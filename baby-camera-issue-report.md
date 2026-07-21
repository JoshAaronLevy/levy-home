# Baby Camera Investigation Report

## Purpose and current status

Levy Home has a Kids Room camera feature backed by Home Assistant and a Eufy
indoor security camera. The intended experience is a live camera view in the
Camera tab, portrait and fullscreen-landscape layouts, pan/tilt controls, and
camera speaker-volume controls.

The feature is **not release-ready**. It previously streamed successfully on
Josh's physical iPhone, but pan/tilt commands were severely delayed. The most
recent blocking issue is more basic: the installed iPhone build displays
`Camera access has not been configured for this build.` whenever Camera starts
or the user taps **Try Again**. The phone was unplugged for the night before
the latest build could be further diagnosed.

This report intentionally does not include any Home Assistant token, Levy Home
camera bearer token, stream URL, camera imagery, or audio.

## Architecture

### Home Assistant / Eufy capabilities already verified

Home Assistant has discovered the indoor camera as `camera.kids_room`. The
following capability checks were performed successfully in Home Assistant's
Developer Tools:

- Starting the P2P livestream worked.
- `eufy_security.ptz` with `direction: UP` physically moved the camera.
- The dedicated action `eufy_security.ptz_up` also physically moved it
  immediately while the Levy Home stream was open.
- The camera exposes `number.kids_room_speaker_volume`.

The Eufy / Home Assistant integration did not expose a verified two-way
talkback service or cry-sensitivity control. Those remain intentionally out of
scope in `stretch-goals.md`; the microphone control is currently an unavailable
state rather than a shipped talkback implementation.

### API path

The Express API owns Home Assistant access and exposes only Levy Home camera
routes:

| Concern | Implementation |
| --- | --- |
| Camera authentication | `Authorization: Bearer <Levy Home camera token>` |
| API configuration | `LEVY_HOME_CAMERA_ACCESS_TOKEN` in the deployed API environment |
| Status | `GET /api/camera/kids-room` |
| Start session | `POST /api/camera/kids-room/sessions` |
| Stop session | `DELETE /api/camera/kids-room/sessions/:id` |
| Stream | API-proxied MJPEG session URL |
| Pan / tilt | `POST /api/camera/kids-room/ptz` |
| Speaker volume | `PUT /api/camera/kids-room/speaker-volume` |

The phone must have the **separate Levy Home camera bearer token**. It must not
contain the Home Assistant long-lived access token. Render configuration only
sets the server-side API value; it does not automatically configure an iOS app
that has already been built.

### iOS configuration path

`LevyHome/App/AppConfig.swift` resolves the iOS camera token in this order:

1. `LEVY_HOME_CAMERA_ACCESS_TOKEN` from the app process environment, when it
   is non-empty.
2. `LevyHomeCameraAccessToken` from the built app's `Info.plist`.

`LevyHome/Resources/Info.plist` uses the build substitution
`$(LEVY_HOME_CAMERA_ACCESS_TOKEN)`. The committed Debug and Release build
settings in `LevyHome.xcodeproj/project.pbxproj` intentionally contain an empty
value. This avoids committing a credential, but it means a locally installed
debug build needs a secure build-time override.

`CameraService.requiredAccessToken()` is the only code path that produces the
exact current user-facing message. Therefore, the running `CameraService`
instance is receiving `nil`, an empty string, or an unresolved `$(...)` value.

## Chronological investigation

### 1. Initial implementation and capability validation

- Created the Camera tab between To Do and Settings, and renamed Preferences to
  Settings.
- Added portrait and fullscreen-landscape camera layouts based on the approved
  mockups.
- Implemented API-backed session creation, MJPEG streaming, pan/tilt, speaker
  volume, fullscreen orientation behavior, and cleanup.
- Completed staged implementation through stage 7, leaving stage 5's unverified
  Eufy capabilities in `stretch-goals.md`.

### 2. First physical-device test: stream / fullscreen failures

Josh reported the following on the physical iPhone:

- Camera changed from Connecting to Live but rendered a black view.
- Fullscreen remained Connecting.
- Exiting fullscreen did not reliably return to portrait when orientation lock
  was enabled.
- Camera cleanup generated a `DELETE` 404 and later the UI said the camera
  session was not found.

Evidence gathered during that investigation:

- The deployed API returned a valid multipart MJPEG response, with 45 JPEG
  frame markers and approximately 5.7 MB over 15 seconds.
- The `DELETE` 404 was a race caused by the broker closing a session when the
  stream connection ended.

Repairs made:

- Replaced the original byte-stream reader with a `URLSessionDataDelegate`
  MJPEG frame parser running off the main thread and retaining only the latest
  frame.
- Added a no-frame watchdog.
- Treated a cleanup 404 as successful local cleanup.
- Improved fullscreen orientation coordination.
- Updated the portrait pan/tilt control visuals toward the approved mockup.

Result: Josh subsequently confirmed that camera video worked in both portrait
and landscape.

### 3. Physical-device pan / tilt latency

Once video worked, Josh found camera direction controls extremely delayed:

- One app tap could take roughly a minute before physical movement.
- A manual Home Assistant action was effectively instant.
- A backend camera speaker request using the same Home Assistant REST
  credentials took about 1.2 seconds, so the basic server-to-Home-Assistant
  connection was healthy.

Changes attempted:

1. Changed the backend from generic PTZ calls to the integration's dedicated
   services (`ptz_up`, `ptz_down`, `ptz_left`, and `ptz_right`). This is in
   commit `026b699` (`Fixed camera actions`).
2. Changed PTZ dispatch to Home Assistant's authenticated WebSocket
   `call_service` flow, matching the Home Assistant Developer Tools action
   model more closely. Read-only WebSocket authentication was separately
   validated before this change.
3. Discovered that the iOS view model discarded every tap while a previous PTZ
   request was still running. This explains why a second action could appear to
   do nothing indefinitely. The view model was changed to retain the latest
   requested direction and dispatch it after the current request finishes.
4. Added API timing logs for each PTZ request:
   - `Camera PTZ action requested.`
   - `Camera PTZ action dispatched to Home Assistant.`
   - `Camera PTZ action completed by Home Assistant.`

These logs report only service names, elapsed time, and success state. They do
not log tokens, frames, stream URLs, or Home Assistant payloads. They are needed
to distinguish a slow API-to-Home-Assistant WebSocket connection from a slow
Home Assistant/Eufy command completion.

The queued-control / timing work was included in the subsequently pushed work
(current HEAD is `dc2d940`, `Camera update`). However, a conclusive post-change
latency test has not happened because the camera-access configuration message
now prevents a session from starting.

## Current blocking issue: iPhone says access is not configured

### What was observed

After the most recent server changes were pushed and a new device build was
installed, Josh reported:

> Camera access hasn't been configured for the build.

Tapping **Try Again** repeatedly showed the same message.

### What was checked and attempted

1. The physical iPhone was detected as an iPhone 16 Pro and a signed Debug
   build was produced and installed using `xcrun devicectl`.
2. The built app was confirmed to use bundle ID `com.levyhome.app`, version
   `12.1.1` build `34`, and the production API base URL
   `https://levy-home.onrender.com`.
3. The project build setting was confirmed blank in source, as expected for a
   secret that must not be committed.
4. A local API environment file contained a camera token. A second signed
   device build used that value only as a build-time override. The built
   `Info.plist` was checked privately to confirm the camera credential field was
   populated; the credential value was not added to Git or this report.
5. Josh still received the same message.
6. A defensive code fix was then made in `LevyHome/App/AppConfig.swift`:
   empty process-environment values no longer override a non-empty value in the
   built `Info.plist`. That corrected build was installed and launched.
7. Josh again reported the same message.

### Current source state

The AppConfig fallback repair is currently a local, uncommitted change:

- `LevyHome/App/AppConfig.swift`

It should **not** be discarded, but it also has not solved the issue according
to the latest physical-device report.

All other camera changes are committed at current HEAD:

```text
dc2d940 Camera update
d79d78c Baby cam fix
9ab219d Fixed baby cam controls bug
026b699 Fixed camera actions
24254bd Baby cam fixes
876efff Finished baby monitor implementation
```

## Verification already completed

- API typecheck passed.
- API automated tests passed: 156 tests.
- iOS test build passed for the queued-control implementation.
- Signed iPhone Debug builds succeeded and were installed/launch-requested.
- API MJPEG proxy response was independently observed to carry JPEG frames.
- Physical-device streaming was confirmed by Josh in portrait and fullscreen
  landscape before the current credential-blocking state.

These are useful engineering checks but do not replace the remaining physical
device verification.

## Most useful next diagnostic step

When the phone is connected again, do not make another speculative token or
backend change first. Add temporary, non-sensitive app diagnostics at the
configuration boundary and install one build. The diagnostic should report
only:

- whether the process environment has a token key,
- whether its value is empty,
- whether the bundle `Info.plist` has a token key,
- whether its value is empty or unresolved (`$(...)`), and
- whether the `CameraService` was initialized with an available token.

It must never log the token value, token length, request `Authorization`
header, stream URL, frames, or audio. The existing in-app Developer Logs is the
best place to surface this data on a physical phone.

That evidence will determine whether the failure is:

1. a configuration-read problem,
2. a SwiftUI environment / `CameraService` construction problem,
3. the wrong installed app/process still running, or
4. an unexpected build-time substitution behavior.

Only after that is resolved should we resume PTZ latency testing. Once camera
startup works again, test one movement at a time and compare the three Render
PTZ timing logs described above. If dispatch is slow, investigate persistent
Home Assistant WebSocket reuse; if dispatch is fast but completion is slow,
investigate Eufy/Home Assistant command queuing while the stream is active.

## Recommended release gate

Do not release until the following are verified on the physical iPhone:

1. Camera opens without a configuration error.
2. Portrait video starts and renders live frames.
3. Fullscreen opens in landscape and returns to portrait correctly.
4. Each pan/tilt action moves correctly with acceptable latency, including two
   quick successive taps.
5. Speaker-volume menu reads and updates the Home Assistant number entity.
6. Leaving camera and locking/backgrounding the phone cleanly stops the
   session without user-visible 404 errors.
7. Device and server logs contain no secrets, imagery, audio, full stream URLs,
   or raw Home Assistant payloads.
