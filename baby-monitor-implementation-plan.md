# Baby Monitor Implementation Plan

## Purpose and scope

Add a **Camera** tab to Levy Home for the Kids Room Eufy indoor camera. The tab
will show its live view, pan/tilt controls, volume and talk controls, and a
landscape fullscreen view. It will follow the approved mockups:

- `Camera-Tab-Mockup-Portrait.png` — portrait Camera tab.
- `Camera-Tab-Mockup-Fullscreen-Landscape.png` — landscape fullscreen viewer.

This is a staged implementation plan, not an authorization to implement every
stage at once. Complete and verify each stage before moving to the next.

### Product decisions already made

- Rename the visible **Preferences** tab and screen title to **Settings**.
- Insert **Camera** between **To Do** and **Settings** in the tab bar.
- The portrait Camera tab has a large live-video card, a `Kids Room` label, a
  prominent four-button PTZ pad, and large but secondary speaker and microphone
  controls beside it.
- Tapping the video opens a landscape fullscreen viewer. Its controls are
  compact, translucent overlays; an `xmark` button at upper-right returns to
  the portrait tab.
- The speaker button opens a small popover above it. The popover contains:
  - playback volume;
  - baby-cry sensitivity with exactly five labelled choices: **Lowest**, Low,
    Medium, High, **Highest**.
  Tapping outside the popover dismisses it.
- Tapping the microphone control begins two-way talk and changes its background
  to red. Tapping it again stops talk and restores its default appearance.
- Home Assistant credentials stay on the backend. The iOS app must never know
  the Home Assistant long-lived token or an unprotected stream URL.

## Confirmed current Home Assistant facts (2026-07-20)

- The camera is `camera.kids_room` from `eufy_security` and is enabled.
- Home Assistant has the `camera`, `stream`, `webrtc`, and `eufy_security`
  components loaded. `camera.kids_room` advertises stream support.
- `eufy_security.start_p2p_livestream` successfully started its live view.
- `eufy_security.ptz` with `direction: UP` successfully moved the camera.
  Home Assistant also exposes `DOWN`, `LEFT`, `RIGHT`, `ROTATE360`, and preset
  position actions.
- RTSP is currently off. Do not turn it on merely to implement the app; P2P
  streaming is the proven starting path.
- The current backend has a narrow Home Assistant facade for garage and lights,
  but no camera endpoints. Its arbitrary-service-payload rejection is a
  security boundary to preserve, not bypass.

## Stage 0 implementation record (2026-07-20)

Stage 0 discovery is complete. These results are a source of truth for the
next stages; refresh the live catalog before changing the contract later.

### Verified live contract

| Need | Verified contract | Result |
| --- | --- | --- |
| Camera identity | `camera.kids_room` (`Eufy Security` model `T8410`) | Available and enabled. |
| Start/stop | `POST /api/services/eufy_security/start_p2p_livestream` and `stop_p2p_livestream`, with `entity_id: camera.kids_room` | Start changed the camera from `idle` to `streaming`; cleanup successfully returned it to stopped state. |
| Video proxy | Authenticated `GET /api/camera_proxy_stream/camera.kids_room` while P2P is active | Returned HTTP 200 with `Content-Type: multipart/x-mixed-replace; boundary=ffmpeg` (MJPEG). |
| PTZ | `eufy_security.ptz`, `entity_id: camera.kids_room`, `direction: UP|DOWN|LEFT|RIGHT` | `UP` was physically verified. `ROTATE360` and preset-position services are also available but are not part of the approved initial D-pad. |
| Camera speaker volume | `number.kids_room_speaker_volume`, `number.set_value`, range `0...100`, step `1` | Available; current value was 10. This controls the camera's speaker, not the iPhone's listening volume. |
| Camera microphone/speaker state | `switch.kids_room_microphone` and `switch.kids_room_speaker` | Both currently `on`. These are camera settings, not evidence of an iPhone-to-camera talk session. |
| Cry detection | `binary_sensor.kids_room_crying_detected` plus crying-notification switch | Detection/notification exists. No cry-sensitivity number/select/service was exposed. |

### Audio and transport findings

- The Home Assistant camera proxy is a live MJPEG response. It establishes a
  usable backend-authenticated **video** path, but MJPEG carries no audio and
  is not a native `AVPlayer` HLS/WebRTC input. It must not be treated as the
  final audio-capable player path.
- The installed `eufy-security-ws` bridge reports device commands named
  `start_talkback` and `stop_talkback`. Its upstream protocol also accepts
  continuous talkback-audio frames, but those commands are not surfaced as a
  typed Home Assistant talkback service. `eufy_security.send_message` is a raw
  bridge JSON escape hatch and must not be exposed to the app.
- The live catalog contains no Eufy entity/service matching a five-step cry
  sensitivity setting. `number.kids_room_motion_detection_sensitivity` is a
  separate motion setting and must **not** be relabelled or reused as cry
  sensitivity.
- The Home Assistant Eufy integration's own documentation recommends its
  WebRTC/go2rtc path for P2P playback. The WebRTC integration is installed in
  this HA instance, but Stage 0 did not establish a secure programmatic iOS
  playback/talkback endpoint for it.

### Decisions and resulting gates

1. **Stage 1 may proceed**: shell/UI work is independent of the remaining
   transport decision.
2. **Stage 2 cannot claim an audio-capable stream yet**: it must select and
   prove a backend-brokered HLS/WebRTC or equivalent iOS-compatible transport.
   A direct Home Assistant MJPEG proxy is acceptable only for an explicitly
   video-only prototype and must remain backend-authenticated.
3. **Stage 4 volume control is now concrete**: expose the camera speaker
   volume with the `0...100` Home Assistant number entity through a typed
   backend endpoint. Keep iPhone playback volume separate and label it clearly
   if we add it.
4. **Cry sensitivity is deferred**: omit the five-step control unless a
   different documented Eufy capability is discovered and physically verified.
5. **Two-way talk remains a gated, separate transport**: it requires a backend
   adapter for the bridge's talkback WebSocket protocol, authenticated
   short-lived app access, audio-format negotiation/transcoding, and an actual
   iPhone-to-Kids-Room proof. Do not implement it through `send_message`.
6. The Eufy bridge has published a legacy-API deprecation notice. Treat all
   Eufy-specific transport work as version-sensitive and retain explicit
   recovery/error states.

## Important unknowns and gates

Do not promise or expose a finished control until the matching upstream
capability is proven with the actual Kids Room camera.

| Capability | Current state | Gate before UI is made functional |
| --- | --- | --- |
| P2P video + PTZ | Proven manually | Prove backend-managed start, playback, stop, and error recovery. |
| Viewer volume | iOS playback capability, not camera configuration | Prove the selected stream carries audio and AVPlayer volume works. |
| Five-step cry sensitivity | Not yet discovered in the HA catalog | Discover an Eufy entity/service and verify each value changes the real setting. Do not make a local-only slider appear authoritative. |
| Two-way talk | Not yet discovered in the HA catalog | Prove an authenticated end-to-end talkback transport supported by this Eufy/HA setup and iOS. A microphone permission alone is insufficient. |
| Fullscreen/orientation | iOS work | Verify presentation and restoration on a physical iPhone. |

If cry sensitivity or talkback are unavailable through Home Assistant's Eufy
integration, pause that sub-feature and choose an explicit supported route
(for example, a documented Eufy/bridge capability) rather than simulating it.
The video/PTZ feature can still ship independently.

## Architecture boundary

```text
Levy Home iOS
  ├─ typed Camera API calls ─────────────> Levy Home API
  │                                         ├─ allowlisted Eufy PTZ services
  │                                         ├─ stream-session lifecycle
  │                                         └─ signed/short-lived media access
  └─ AVPlayer / approved audio transport <─ secure media/talkback path
                                                └─ Home Assistant + Eufy camera
```

The backend should expose purpose-built camera endpoints and typed request
models such as `move(direction)`, not arbitrary Home Assistant domain/service/
entity values supplied by iOS. Keep stream credentials short-lived, scoped to
the selected camera, redacted from logs, and never persisted in UserDefaults.

## Stages

### Stage 0 — Capability contract and safety discovery

**Goal:** turn the currently proven Home Assistant behavior into a precise,
safe app/backend contract before building UI that controls hardware.

1. Refresh the live HA catalog after any Eufy configuration change.
2. Read the current states and service schemas for `camera.kids_room`, P2P
   actions, PTZ, camera stream support, audio/talkback, and cry-sensitivity
   candidates.
3. In Home Assistant Developer Tools, verify start -> visible video -> stop;
   verify every planned PTZ direction. Record exact entity/service IDs only
   after confirming they work.
4. Determine the media strategy from a real backend deployment:
   - whether HA provides a playable HLS/WebRTC path after P2P start;
   - how the backend can provide authenticated, short-lived playback access to
     iOS without exposing its HA token;
   - expected start latency, stop behavior, and reconnect behavior.
5. Prove or reject the two-way-talk and cry-sensitivity capabilities. For the
   five-step sensitivity setting, record the exact upstream values that map to
   `Lowest`, `Low`, `Medium`, `High`, and `Highest`.
6. Write the resulting contract, unavailable capabilities, and test steps into
   this document before implementation moves past the relevant gate.

**Exit criteria:** all discoverable live capabilities have been recorded;
allowlisted routes/services and remaining transport decisions are explicit; the
two uncertain audio features are either proven or explicitly deferred. This
exit criterion is satisfied by the Stage 0 implementation record above.

### Stage 1 — Shell navigation and design primitives

**Goal:** add the new information architecture without camera network calls.

1. Update `LevyHome/Views/Root/RootTabView.swift`:
   - add `RootTab.camera` between `.todo` and the renamed `.settings`;
   - use the `video` SF Symbol for Camera and `gearshape` for Settings;
   - change the visible tab label from `Preferences` to `Settings`.
2. Rename the visible header in `LevyHome/Views/Preferences/PreferencesView.swift`
   to `Settings`. Preserve its current navigation hierarchy and existing
   notification/Siri/developer behavior; source type/file renames are optional
   and should be a separate mechanical change if desired.
3. Add `LevyHome/Views/Camera/` and a previewable `CameraView` using local
   placeholder state only. Do not bake mockup PNGs into the product UI.
4. Define small view-state models and protocols for camera status, PTZ, stream
   session, audio menu state, and talk state. Make view models testable without
   a real camera.
5. Add unit/UI coverage confirming tab order, Settings naming, and that Camera
   is selectable.

**Exit criteria:** the app navigates Home → List → To Do → Camera → Settings;
the existing Settings content still works; Camera compiles and previews without
network dependencies.

#### Stage 1 implementation record (2026-07-20)

- Completed the tab order `Home`, `List`, `To Do`, `Camera`, `Settings` in
  `RootTabView`; Settings retains the existing `PreferencesView` content.
- Renamed the visible Settings header and relevant release-note copy without
  renaming the established Preferences source hierarchy.
- Added a non-networked `CameraView` placeholder for `Kids Room`, deliberately
  without embedding a mockup image or attempting a live connection.
- Added local session/PTZ/audio/talk state models and protocol seams for later
  stages, plus focused tab-order/label tests.
- Verified with `RootTabTests` on the iPhone 17 Pro simulator: 2 tests passed.

### Stage 2 — Backend camera facade and stream-session lifecycle

**Goal:** provide the minimum secure API that lets the app start, observe, and
stop the selected camera stream.

1. Extend backend config with a curated camera definition (initially exactly
   `camera.kids_room`, display name `Kids Room`). Validate it at startup in live
   mode; do not accept an entity ID from the app.
2. Add a camera-specific integration/facade rather than broadening the existing
   garage/light facade into an arbitrary executor.
3. Add typed API contracts/routes for:
   - camera availability/status;
   - start session;
   - stop session;
   - playable-session descriptor or brokered media endpoint;
   - read/set camera speaker volume (`0...100` only, never an arbitrary number
     entity);
   - precise safe error codes for unavailable camera, starting, expired session,
     and upstream failure.
4. Make backend start/stop idempotent, serialize conflicting session changes,
   and always attempt cleanup when the client abandons playback.
5. Use the chosen secure media strategy from Stage 0. Do not return a permanent
   HA URL, access token, RTSP URL, or Eufy credentials to the iOS client.
6. Add route, contract, and facade tests in mock mode plus guarded live
   verification against `camera.kids_room`.

**Exit criteria:** a simulator can receive a valid, non-secret playback
descriptor from the deployed API; a real camera session starts and stops
reliably through the backend.

#### Stage 2 implementation record (2026-07-20)

- Added a camera-specific backend facade and the fixed, server-side Kids Room
  allowlist (`camera.kids_room` and `number.kids_room_speaker_volume`). The app
  cannot provide Home Assistant entity IDs, services, URLs, or credentials.
- Added status, idempotent session start/stop, brokered MJPEG stream, and bounded
  camera-speaker volume routes. Live camera routes require a distinct Levy Home
  API bearer credential (never the Home Assistant token); sessions use an opaque
  UUID, expire after five minutes, serialize concurrent starts, and attempt
  cleanup when stream clients disconnect.
- Added mock-mode route/config coverage for the curated camera contract,
  opaque-session checks, brokered-stream response, and `0...100` volume bound.
- This is source and mock-API proof only. It has not been deployed or verified
  against the physical camera in this stage; those live checks remain required
  before the Stage 2 exit criteria can be claimed.

### Stage 3 — Portrait live viewer and PTZ

**Goal:** implement the approved portrait Camera-tab experience with real
video and controls.

1. Add `CameraService` and `CameraViewModel` to the iOS app, injected through
   `AppEnvironment` and backed by typed `APIClient` extensions. Send the
   distinct camera API bearer credential from build configuration for every
   camera request; never use or embed the Home Assistant token.
2. In `CameraView`, match the portrait mockup:
   - `Camera` header;
   - rounded live-video card with loading, connecting, live, unavailable, and
     recoverable-error states;
   - `Kids Room` label;
   - large four-direction PTZ control;
   - substantial speaker and microphone buttons beside it.
3. Start video only while the Camera tab/view is visible; stop or release its
   session when leaving the tab, entering background, or receiving an error.
   Avoid background video/audio claims until specifically designed and tested.
4. Implement `UP`, `DOWN`, `LEFT`, and `RIGHT` as typed backend actions. Disable
   or debounce repeated taps while an action is in flight, surface a concise
   failure message, and preserve the live feed on a PTZ failure.
5. Prefer an accessible control label such as “Move camera up”; support Dynamic
   Type, VoiceOver, and iPad-safe layout even though the approved design is
   iPhone portrait.
6. Add unit tests for view-model transitions and API payloads; defer manual
   simulator/device testing until the agreed final physical-device pass.
   Perform live PTZ proof only when
   the room/camera movement is safe.

**Exit criteria:** portrait video, error/retry, start/stop, and all four PTZ
directions work against the actual camera without exposing HA secrets.

#### Stage 3 implementation record (2026-07-20)

- Replaced the Camera-tab placeholder with the approved portrait viewer: a
  rounded Kids Room video card, connection/unavailable/retry states, a
  prominent accessible four-direction PTZ pad, and the speaker/talk controls
  reserved for their later functional stages.
- Implemented the current video-only transport faithfully. The iOS app starts
  an authenticated brokered session, decodes the MJPEG response into rendered
  JPEG frames, and stops the session when the tab disappears or the app leaves
  the active scene. It does not claim AVPlayer or audio support.
- Added a server-allowlisted `POST /api/camera/kids-room/ptz` route that accepts
  only `UP`, `DOWN`, `LEFT`, and `RIGHT`; Home Assistant entity/service details
  remain server-side.
- Added the camera API-only credential build setting. It must be supplied for
  the eventual physical-device build and must not be the Home Assistant token.
- Source/build and mock-route proof is complete. Deployment, real MJPEG
  playback, and physical camera movement remain required before the exit
  criteria can be claimed.

### Stage 4 — Camera speaker volume and cry-sensitivity popover

**Goal:** make the speaker control useful without overstating what it controls.

1. Tapping the speaker icon presents an anchored popover above the button.
   Tapping the dimmed/outside area dismisses it; selecting a control should not
   accidentally dismiss before the value is applied.
2. Add a labelled **Camera speaker volume** slider bound to the typed backend
   read/set API for `number.kids_room_speaker_volume` (`0...100`). Read its
   real value when the menu opens; apply a changed value through the backend;
   reconcile to the returned/read-back camera value after success. Clarify in
   UI/accessibility that it controls the camera speaker, not the iPhone's
   listening volume or the camera's microphone sensitivity.
3. If we add a local listening-volume control later, keep it separate from the
   camera speaker setting and label it **Phone playback volume**.
4. Add the five-step cry-sensitivity control only after Stage 0 proves the
   upstream mapping. Use discrete, labeled choices in this exact order:
   `Lowest`, `Low`, `Medium`, `High`, `Highest`. Only labels for lowest and Highest are needed. The intermediate ones do not need labels. They can just have the icons along the slider indicating the level selected. NOTE: To be clear, this should look like a slider but with distinctive stops for each level. The user can slide to the desired level and it should stop at the closest level. The user should not be able to select a value between the levels. There's no need to show text for the current selected level. They should be able to just tell based on where the active point of the slider is.
5. Persist/show the confirmed setting only if the backend can read it back from
   the camera or has an intentional durable preference model. Handle a failed
   set by reverting the selection and explaining that the camera setting was
   not updated.
6. If Stage 0 finds no usable Eufy/HA sensitivity integration, omit this section
   from the shipped popover and document the limitation rather than presenting a
   nonfunctional control.

**Exit criteria:** camera speaker volume changes are read back successfully; the
popover dismisses correctly; cry sensitivity is either end-to-end verified or
intentionally not shown.

#### Stage 4 implementation record (2026-07-20)

- Added an anchored Camera speaker volume popover above the speaker control.
  Its dimmed outside area and close button dismiss it; slider interaction does
  not dismiss the menu.
- The popover reads the current value when opened, applies only final slider
  changes through the typed `0...100` backend route, then uses the returned
  camera value as the confirmed UI value. Failed updates revert to the last
  confirmed value and show a clear message.
- The copy and accessibility labels distinguish the camera speaker from phone
  playback volume and microphone sensitivity.
- Cry sensitivity is intentionally omitted: no verified Eufy/Home Assistant
  read/write mapping exists, so a five-step local-only slider would be
  misleading.
- Source, mock-route, and compile proof is complete. A deployed API and
  physical-camera read/write check remain required before the exit criteria can
  be claimed.

### Stage 5 — Two-way talk

#### Deferred to [`stretch-goals.md`](stretch-goals.md) until a secure, physical-device talkback transport is proven.

**Goal:** add a trustworthy, clearly active talk state only after the complete
transport is proven.

1. Before code changes, prove the real chain: iPhone microphone capture →
approved authenticated transport → Kids Room camera speaker, plus stop and
failure behavior. Verify it on a physical iPhone, not only the simulator.
2. If supported, add a dedicated talkback session contract/endpoint. It must
not reuse an unauthenticated media URL or expose HA credentials.
3. Request microphone permission only when the user first enables talk. The
existing `NSMicrophoneUsageDescription` is present, but verify its wording and
denial/retry experience. Configure `AVAudioSession` deliberately for recording
and playback, including route changes and interruptions.
4. On microphone tap: begin connection/capture, then change the control to a
red active background only once talk is actually live. While starting, show a
neutral in-progress state. On second tap, leaving the screen, app background,
route loss, error, or timeout: stop capture/session and return to the default
background.
5. Make talk push-to-talk or latched-toggle behavior explicit during design
review; this plan currently reflects the requested **latched toggle**.
6. Test permission denied, headset/Bluetooth route changes, phone call/audio
interruption, network loss, camera unavailable, and cleanup after force-close.

**Exit criteria:** on a real iPhone, a user can start/stop talk safely, Grayson
can hear the phone, and every termination path removes the red active state.

### Stage 6 — Landscape fullscreen viewer

**Goal:** implement the approved immersive viewer without losing session or
control state.

1. Opening the portrait video presents a dedicated fullscreen landscape
experience. Lock/prefer landscape only while this presentation is active, then
restore normal portrait-capable behavior when it is dismissed.
2. Keep the same stream session where possible; do not stop/restart video just
because the user enters fullscreen. Handle rotation and playback-surface
recreation without leaking sessions.
3. Match the landscape mockup: edge-to-edge video, compact translucent PTZ pad
at lower-left, translucent speaker/microphone controls at lower-right, and an
upper-right `xmark` close button. No tab bar or normal screen header.
4. Reuse the same PTZ, volume-menu, and talkback view models so active volume,
cry-sensitivity, and talk state remain coherent between portrait/fullscreen.
5. Ensure the red talk state remains obvious against bright or dark footage,
and make all overlay controls accessible and safely inset.
6. Test enter/exit, rotation, playback continuity, controls, outside-popover
dismissal, and returning to the same portrait view state.

**Exit criteria:** fullscreen opens in landscape, closes predictably back to
portrait Camera, preserves a healthy session, and matches the intended visual
hierarchy.

#### Stage 6 implementation record (2026-07-20)

- Added a dedicated fullscreen Camera view opened by tapping the portrait video.
  It uses the existing `CameraViewModel`, so it preserves the active video
  session, current speaker-volume state, and PTZ in-flight state rather than
  starting a second session.
- Added a landscape-only fullscreen orientation policy and restored portrait
  orientation on dismissal. The fullscreen layout has edge-to-edge video,
  compact translucent lower-corner controls, and an accessible upper-right
  close button.
- Reused the Camera speaker popover in fullscreen. The microphone control
  remains visibly unavailable because Stage 5 talkback is deferred.
- Source/compile proof is complete. Actual rotation, playback continuity, safe
  insets, and fullscreen control behavior remain physical-device checks before
  the exit criteria can be claimed.

### Stage 7 — End-to-end QA, privacy review, and release

**Goal:** prove the complete household feature before release.

1. Run backend typecheck/tests and iOS unit/UI tests. Re-run the live HA catalog
and verify the configured camera/action IDs have not changed.
2. Test on the simulator for layout, empty/loading/error states, and tab naming;
test a physical iPhone for real video latency, audio, talkback, rotation, and
hardware volume behavior.
3. Confirm no secrets, full stream URLs, raw Home Assistant responses, room
audio, or microphone data appear in app/API logs, crash reports, analytics, or
persisted state.
4. Verify lifecycle cleanup: switch tabs, background/foreground, lock/unlock,
network changes, server restart, and camera offline/recovery.
5. Manually validate the actual Kids Room camera after every live PTZ/talkback
test, returning it to a safe position and stopping the stream/session.
6. Update API docs, privacy text if needed, and this plan with the final
capability decisions. Then follow the normal fresh build, simulator install,
physical-device proof, and release workflow.

**Exit criteria:** all shipped controls have physical-device proof; unsupported
ones are absent or clearly deferred; the release contains no client-side Home
Assistant secrets.

#### Stage 7 implementation record (2026-07-20)

- Added the camera API, privacy, and safe smoke-check documentation to
  `docs/07-home-assistant-facade.md`. It explicitly documents the brokered
  session boundary, the separate Levy Home camera credential, the absence of
  microphone/talkback/cry-sensitivity functionality, and the prohibition on
  persisting or logging camera media and Home Assistant credentials.
- Added `docs/manual-qa-camera.md` as the physical-device release checklist,
  including lifecycle, recovery, PTZ safe-position, fullscreen, and log-review
  checks. It intentionally excludes the deferred Stage 5 talkback capability.
- The source review confirms the app makes camera API calls only through the
  curated backend contract; stream requests do not use `AppLogStore`, and the
  general API client records request paths/statuses rather than headers, bodies,
  or response data. Backend logging redacts bearer credentials. The app privacy
  manifest still declares no collected data, and the shipped camera feature
  requests no microphone access.
- `npm --prefix apps/api run typecheck` and `npm --prefix apps/api test` pass.
  `xcodebuild build-for-testing` compiled the iOS app and unit-test bundle
  successfully without launching a simulator. A refreshed 2026-07-20 Home
  Assistant catalog confirms `camera.kids_room` and
  `number.kids_room_speaker_volume` are enabled, and the
  `eufy_security.start_p2p_livestream`, `stop_p2p_livestream`, and `ptz`
  actions remain available.
- Per the requested workflow, simulator boot and physical-device QA remain
  pending until the final phone-testing pass; therefore Stage 7 exit criteria
  and release approval are not yet claimed.

## Suggested implementation order for future prompts

Start with **Stage 0**, then implement one numbered stage per prompt. For any
stage that modifies the backend contract, finish its backend tests before
building the dependent SwiftUI behavior. Do not combine Stage 5 talkback with a
general UI polish change: it needs separate real-device audio proof.
