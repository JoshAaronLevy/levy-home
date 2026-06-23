# Manual QA: Garage Notifications And Controls

This guide captures the Stage 17 physical-device verification pass for Levy Home.

Stage 17 cannot be fully completed on Simulator. It requires:

- A physical iPhone signed for `com.levyhome.app`.
- Backend APNs credentials for the same bundle ID and environment.
- A reachable local or deployed Levy Home API.
- Safe Home Assistant garage/light entities or mock mode for control checks.

## Current Status

Status: prepared, not physically verified.

During the Stage 17 preflight, the connected iPhone appeared offline and `apps/api/.env` was not present, so APNs delivery could not be verified from this workspace session. Local backend contract checks can still run without credentials, but expected push delivery requires the physical prerequisites above.

## Safety Notes

- Do not test `close_garage` against the real garage unless someone has confirmed the doorway is clear.
- Prefer `HOME_ASSISTANT_MODE=mock` until the API, app, APNs, and preference flow are proven.
- Keep APNs `.p8` files outside the repo and never commit `apps/api/.env`.
- Use APNs `sandbox` for Debug/device builds unless the iOS build is signed for production push.

## Backend Setup

From repo root:

```sh
cp apps/api/.env.example apps/api/.env
```

Edit `apps/api/.env`:

```sh
PORT=4000
LEVY_HOME_HA_WEBHOOK_SECRET=dev-secret
HOME_ASSISTANT_MODE=mock

APNS_KEY_ID=YOUR_KEY_ID
APNS_TEAM_ID=YOUR_TEAM_ID
APNS_BUNDLE_ID=com.levyhome.app
APNS_PRIVATE_KEY_PATH=/absolute/path/to/AuthKey_YOUR_KEY_ID.p8
APNS_ENVIRONMENT=sandbox
```

For real Home Assistant control verification, switch to `HOME_ASSISTANT_MODE=live` and set:

```sh
HOME_ASSISTANT_BASE_URL=http://homeassistant.local:8123
HOME_ASSISTANT_TOKEN=YOUR_LONG_LIVED_TOKEN
HOME_ASSISTANT_GARAGE_COVER_ENTITY_ID=cover.main_garage_door
HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID=light.all_lights
HOME_ASSISTANT_LIGHT_GROUPS=
HOME_ASSISTANT_LIGHT_ENTITIES=light.foyer_lights: Foyer, light.kitchen_cans: Kitchen Cans, light.kitchen_nook: Kitchen Nook, light.upstairs_hallway: Upstairs Hallway, light.study_lamp_3: Study, light.playroom_lamp: Playroom
```

Start the API:

```sh
npm run api:dev
```

Confirm the API is reachable from the Mac:

```sh
curl http://localhost:4000/health
```

## Physical iPhone API URL

The app defaults to `http://localhost:4000`, which only works in Simulator. A physical iPhone needs a URL it can reach.

Find the Mac LAN IP:

```sh
ipconfig getifaddr en0 || ipconfig getifaddr en1
```

During preflight, the Mac LAN IP was `192.168.1.143`. Regenerate this value before QA because it can change.

Set the app's API base URL for the physical-device run to:

```text
http://YOUR_MAC_LAN_IP:4000
```

In Xcode, set the `LEVY_HOME_API_BASE_URL` build setting for the `LevyHome` app target or use a temporary Debug scheme/environment override if preferred. Do not commit a personal LAN IP.

## Physical iPhone Registration

1. Connect the physical iPhone by USB or ensure it is available to Xcode.
2. Select the `LevyHome` scheme and the physical iPhone destination.
3. Confirm Push Notifications capability is enabled and the signing team is valid.
4. Run the app on the phone.
5. Open Preferences.
6. Open Developer.
7. Tap `Register And Sync Device`.
8. Accept the iOS notification permission prompt.

Expected:

- Developer shows notification permission as allowed.
- Developer shows APNs token as registered.
- API registration shows synced.
- `/health` shows `registeredDeviceCount` at least `1`.

## Debug APNs Test Push

From repo root, with the API running:

```sh
curl -X POST http://localhost:4000/api/debug/send-test-push \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Levy Home test",
    "body": "Testing backend APNs delivery."
  }'
```

Expected:

- Response has `ok: true`.
- `provider` is `apns`.
- `sentNotificationCount` is at least `1`.
- `invalidTokenCount` is `0`.
- Physical iPhone receives the notification.

If response is `503` with `apns_credentials_not_configured`, APNs credentials are missing or unreadable.

## Garage Event Matrix

Use this helper from repo root:

```sh
send_garage_event() {
  event_type="$1"
  curl -X POST http://localhost:4000/api/ha/events \
    -H "Authorization: Bearer dev-secret" \
    -H "Content-Type: application/json" \
    -d "{
      \"type\": \"${event_type}\",
      \"category\": \"garage\",
      \"severity\": \"normal\",
      \"entityId\": \"cover.main_garage_door\",
      \"source\": \"manual_stage_17_qa\"
    }"
}
```

Send all five MVP garage events:

```sh
send_garage_event garage_opened
send_garage_event garage_closed
send_garage_event garage_left_open_10_min
send_garage_event garage_opened_after_hours
send_garage_event garage_still_open_at_10pm
```

Expected for each enabled preference:

- Response has `ok: true`.
- Response event has `push.attempted: true`.
- Response event has `push.skipped: false`.
- `sentNotificationCount` is at least `1`.
- Physical iPhone receives the notification.
- Activity shows the newest event after refresh.
- Home recent important event updates where applicable.

Confirm timeline ordering:

```sh
curl 'http://localhost:4000/api/events?limit=5'
```

Expected:

- Events are newest first.
- All five event types are present after the matrix.

## Preference Enforcement Check

1. On the iPhone, open Preferences.
2. Open Garage.
3. Turn off `Garage opened`.
4. Sync preferences from Developer if needed.
5. Send:

```sh
send_garage_event garage_opened
```

Expected:

- No push arrives for `garage_opened`.
- The event is still stored in Activity.
- The response or timeline event shows push skipped because the preference is disabled.

Turn `Garage opened` back on and repeat:

```sh
send_garage_event garage_opened
```

Expected:

- Push arrives again.
- Event is stored in Activity.

## Home And Controls Check

With `HOME_ASSISTANT_MODE=mock`, verify safely:

```sh
curl http://localhost:4000/api/home/overview
curl -X POST http://localhost:4000/api/home/actions \
  -H "Content-Type: application/json" \
  -d '{"actionId":"turn_off_all_lights"}'
curl -X POST http://localhost:4000/api/home/actions \
  -H "Content-Type: application/json" \
  -d '{"actionId":"turn_off_light_group","groupId":"upstairs_hallway"}'
```

On the iPhone:

- Home loads.
- Light actions show progress and success/failure state.
- Home refreshes after each action.
- Close garage shows confirmation and can be cancelled.

Only after confirming the real garage area is safe, test live `close_garage` against Home Assistant.

## Evidence Checklist

Record results here during the physical pass:

| Check | Result | Notes |
| --- | --- | --- |
| Physical iPhone connected and signed | Pending |  |
| App API URL points to reachable API | Pending |  |
| API has APNs credentials | Pending |  |
| APNs token received on device | Pending |  |
| Device registration synced to API | Pending |  |
| Debug APNs test push received | Pending |  |
| `garage_opened` push received when enabled | Pending |  |
| `garage_closed` push received when enabled | Pending |  |
| `garage_left_open_10_min` push received when enabled | Pending |  |
| `garage_opened_after_hours` push received when enabled | Pending |  |
| `garage_still_open_at_10pm` push received when enabled | Pending |  |
| Disabled `garage_opened` preference suppresses push | Pending |  |
| Activity shows newest-first entries | Pending |  |
| Home overview loads and refreshes | Pending |  |
| Close garage confirmation cancel path works | Pending |  |
| Curated light actions work safely | Pending |  |
| Notifications remains history-focused | Pending |  |
| Developer shows environment and technical status | Pending |  |

## Stage 17 Completion Rule

Stage 17 is complete only after the evidence checklist is filled with passing physical-device results or specific bugs are filed/fixed. Local backend tests alone are not enough for this stage.
