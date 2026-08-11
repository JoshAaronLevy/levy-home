# Home Assistant Facade

Stage 10 adds a narrow backend facade for Home status and selected quick actions. The iOS app should call this API, not Home Assistant directly.

## Run Locally

```sh
npm install
cp apps/api/.env.example apps/api/.env
npm run api:dev
```

The API defaults to mock mode so it can be tested safely without Home Assistant credentials.

## Environment

| Variable | Purpose |
| --- | --- |
| `PORT` | API port, default `4000`. |
| `LEVY_HOME_HA_WEBHOOK_SECRET` | Bearer token required for `/api/ha/events`. |
| `HOME_ASSISTANT_MODE` | `mock` for local safe mode or `live` for Home Assistant REST calls. |
| `HOME_ASSISTANT_BASE_URL` | Home Assistant base URL, required only in live mode. |
| `HOME_ASSISTANT_TOKEN` | Home Assistant long-lived access token, required only in live mode. Do not commit it. |
| `HOME_ASSISTANT_ACTIVITY_ENABLED` | Enables the backend Home Assistant WebSocket activity listener. Defaults to `false`. |
| `HOME_ASSISTANT_WEBSOCKET_URL` | Optional explicit Home Assistant WebSocket URL override. Leave blank to derive `/api/websocket` from `HOME_ASSISTANT_BASE_URL`. |
| `HOME_ASSISTANT_PHONE_ENTITIES` | Exact phone home-presence entity IDs to listen for, in `entity_id:Person:Device name` comma-separated format. |
| `HOME_ASSISTANT_PHONE_ENTITY_PATTERNS` | Explicit glob-style phone entity patterns to listen for, in `entity_id_glob:Person:Device name` comma-separated format. Use `*` as the wildcard; Activity only stores `device_tracker` home transitions. |
| `HOME_ASSISTANT_GARAGE_COVER_ENTITY_ID` | Server-side garage cover entity. |
| `HOME_ASSISTANT_THERMOSTAT_CLIMATE_ENTITY_ID` | Server-side Ecobee climate entity used by the interactive thermostat node. |
| `HOME_ASSISTANT_ROOM_TEMPERATURE_SENSORS` | Optional exact five-sensor override for Temps, in `roomId:Display name:sensor.entity_id` comma-separated format. Leave blank for the verified Levy Home Study, Kitchen/Family, Nursery, Master Bedroom, and Playroom defaults. |
| `HOME_ASSISTANT_OCCUPIED_MEAN_TEMPERATURE_ENTITY_ID` | Home Assistant sensor used for the occupied-only mean in Temps. Defaults to `sensor.occupied_mean_temperature`. |
| `HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID` | Optional server-side all-lights entity/group. Leave blank when curated light entities are the source of truth. |
| `HOME_ASSISTANT_LIGHT_GROUPS` | Curated light groups in `groupId:Display name:entity_id` comma-separated format. Used when `HOME_ASSISTANT_LIGHT_ENTITIES` is blank. |
| `HOME_ASSISTANT_LIGHT_ENTITIES` | Curated individual light entities in `entity_id:Display name` comma-separated format. When set, these are used instead of `HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID` and light groups. |
| `HOME_ASSISTANT_KIDS_ROOM_CAMERA_ENTITY_ID` | Server-side allowlisted camera entity. Defaults to `camera.kids_room`; it must remain a `camera.*` entity. |
| `HOME_ASSISTANT_KIDS_ROOM_SPEAKER_VOLUME_ENTITY_ID` | Server-side allowlisted camera-speaker `number.*` entity. Defaults to `number.kids_room_speaker_volume`. |
| `LEVY_HOME_CAMERA_ACCESS_TOKEN` | Required in live mode. Levy Home API-only bearer credential for camera routes; it is not the Home Assistant token and must not be logged or committed. |
| `MOCK_TOTAL_LIGHT_COUNT` | Mock-mode total light count. |
| `APNS_KEY_ID` | Apple APNs Auth Key ID. Required only for APNs sending. |
| `APNS_TEAM_ID` | Apple Developer Team ID for APNs JWT auth. Required only for APNs sending. |
| `APNS_BUNDLE_ID` | APNs topic/bundle identifier, currently `com.levyhome.app`. |
| `APNS_PRIVATE_KEY_PATH` | Preferred APNs `.p8` private key file path. On Render Secret Files, use `/etc/secrets/<filename>.p8`. When set, this wins over `APNS_PRIVATE_KEY`. |
| `APNS_PRIVATE_KEY` | Fallback APNs `.p8` private key value with newlines escaped as `\n`. Quoting the value is supported. Do not commit it. Ignored when `APNS_PRIVATE_KEY_PATH` is set. |
| `APNS_ENVIRONMENT` | Default APNs endpoint for devices without an environment: `sandbox` or `production`. Native registrations should include their own environment. |

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Basic API health and mode. |
| `GET` | `/api/home/overview` | Garage status, light summary, room temperatures, thermostat status, recent important event, generated time. |
| `GET` | `/api/home/actions` | Curated quick actions and configured light groups. |
| `POST` | `/api/home/actions` | Generic curated action endpoint using `actionId` and optional `groupId`. |
| `POST` | `/api/home/actions/open-garage` | Explicit open-garage action. |
| `POST` | `/api/home/actions/close-garage` | Explicit close-garage action. |
| `POST` | `/api/home/actions/lights-off` | Explicit all-lights-off action. |
| `POST` | `/api/home/actions/light-groups/:groupId/off` | Explicit curated light-group off action. |
| `GET` | `/api/camera/kids-room` | Curated Kids Room camera availability, stream state, and camera-speaker volume. |
| `POST` | `/api/camera/kids-room/sessions` | Starts or reuses a short-lived camera session and returns an opaque, relative brokered stream URL. |
| `DELETE` | `/api/camera/kids-room/sessions/:sessionId` | Stops the active camera session. |
| `GET` | `/api/camera/kids-room/sessions/:sessionId/stream` | Brokered MJPEG response for the active short-lived session. |
| `POST` | `/api/camera/kids-room/ptz` | Moves the configured camera. JSON body is `{ "direction": "UP"|"DOWN"|"LEFT"|"RIGHT" }`. |
| `PUT` | `/api/camera/kids-room/speaker-volume` | Sets only the configured camera speaker volume; JSON body is `{ "value": 0..100 }`. |
| `POST` | `/api/devices/register` | Provider-aware push-device registration for native APNs tokens and legacy Expo push tokens. |
| `GET` | `/api/notification-preferences` | Notification preferences, optionally scoped by `deviceId` or provider-aware device token query params. |
| `PUT` | `/api/notification-preferences` | Sync per-device notification preferences by registered `deviceId` or provider-aware token. |
| `POST` | `/api/debug/send-test-push` | Debug APNs test push to registered APNs devices with provider-neutral counts. |
| `GET` | `/api/debug/home-assistant/phone-entities` | Protected Home Assistant phone-entity discovery helper for Phase 1 activity setup. |
| `POST` | `/api/ha/events` | Home Assistant event webhook. |
| `GET` | `/api/events` | Recent event timeline. Supports optional `limit`, legacy `since`, and explicit `start`/`end` query params. |

The API rejects arbitrary Home Assistant service/entity payloads from the app. Do not send fields such as `domain`, `service`, `entity_id`, or `target` to `/api/home/actions`.

Camera routes are deliberately limited to the configured Kids Room camera and
require the `Authorization: Bearer <LEVY_HOME_CAMERA_ACCESS_TOKEN>` header in
live mode. The session URL is an opaque, five-minute, in-memory capability and
is relative to the Levy Home API; the app never receives a Home Assistant URL,
token, RTSP address, or Eufy credential. Stream connection closure attempts to
stop the session. Camera speaker volume is separate from iPhone playback volume
and cry sensitivity.

### Camera privacy and logging

Camera video is proxied only for an active, authenticated in-memory session. It
is not written to the API filesystem, database, event timeline, or analytics.
The camera endpoints accept only the curated Kids Room actions and do not expose
raw Home Assistant responses to the app. API logging redacts bearer credentials;
the iOS camera stream client does not log request headers, stream URLs, MJPEG
frames, or response bodies. The current release does not request microphone
permission or provide two-way talkback, and no cry-sensitivity control is
shown. The Levy Home camera bearer credential is distinct from the Home
Assistant token; it must be stored in release build configuration, never source
control, and is not a substitute for a Home Assistant credential.

Device registration is provider-aware:

- Native iOS APNs registrations must include `token`, `platform: "ios"`, `provider: "apns"`, and `environment: "sandbox"` or `"production"`.
- APNs sandbox and production registrations are stored separately even if the raw token value is the same.
- Legacy Expo-style registrations are still accepted with `pushToken` and are treated as `provider: "expo"`.
- Tokens are not returned in registration responses.

Notification preferences are database-backed when `DATABASE_URL` is configured and fall back to in-memory state for local no-database development. They can sync from the native app, be fetched for manual verification, and are used for APNs push filtering.

APNs behavior:

- Debug test pushes use registered APNs devices and return provider-neutral counts such as `sentNotificationCount`, `failedNotificationCount`, and `invalidTokenCount`.
- Debug test pushes are diagnostics and do not apply notification category preferences.
- Startup logs whether `APNS_PRIVATE_KEY_PATH` loaded successfully when the path is configured. The log includes the file path but never the private key contents.
- Garage Home Assistant events map to the five garage preference categories and only send APNs pushes to devices where that category is enabled.
- Partner presence Home Assistant events map to the `partner_presence` category and only send APNs pushes to devices where that category is enabled.
- Partner presence events with `metadata.recipient` only send APNs pushes to registered Levy Home devices whose stored device owner/name matches that recipient.
- Selected lighting automation Home Assistant events map to the `lighting_automation` category and only send APNs pushes to devices where that category is enabled.
- If APNs credentials are missing, `/api/debug/send-test-push` returns a readable `503` error instead of crashing. Notification-capable event ingestion still stores the event and records the missing-credentials reason in `event.push`.
- Expo-style device registrations remain accepted for compatibility, but this backend stage does not send Expo pushes.

## Manual Checks

```sh
curl http://localhost:4000/api/home/overview
curl http://localhost:4000/api/home/actions

curl -X POST http://localhost:4000/api/home/actions \
  -H "Content-Type: application/json" \
  -d '{"actionId":"open_garage"}'

curl -X POST http://localhost:4000/api/home/actions \
  -H "Content-Type: application/json" \
  -d '{"actionId":"turn_off_light_group","groupId":"upstairs_hallway"}'

curl -X POST http://localhost:4000/api/home/actions/light-groups/upstairs_hallway/off
```

Camera route smoke checks require the separate Levy Home camera access token.
They use only the brokered API path; do not substitute a Home Assistant token or
call the Home Assistant stream proxy from a phone:

```sh
export CAMERA_ACCESS_TOKEN='your-levy-home-camera-access-token'

curl -H "Authorization: Bearer $CAMERA_ACCESS_TOKEN" \
  http://localhost:4000/api/camera/kids-room

curl -X POST -H "Authorization: Bearer $CAMERA_ACCESS_TOKEN" \
  http://localhost:4000/api/camera/kids-room/sessions

curl -X POST \
  -H "Authorization: Bearer $CAMERA_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"direction":"UP"}' \
  http://localhost:4000/api/camera/kids-room/ptz

curl -X PUT \
  -H "Authorization: Bearer $CAMERA_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"value":10}' \
  http://localhost:4000/api/camera/kids-room/speaker-volume
```

After any live PTZ check, visually return the Kids Room camera to its safe
position. Stop the session using the opaque `id` returned by the session-create
response; never record or share the stream bytes or authorization header.

As of the current Home Assistant catalog, the Levy Home live configuration uses exact `HOME_ASSISTANT_LIGHT_ENTITIES` and leaves both `HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID` and `HOME_ASSISTANT_LIGHT_GROUPS` blank. The Temps default sensor map is Study `sensor.study_thermometer_temperature`, Kitchen/Family `sensor.family_room_thermometer_temperature`, Nursery `sensor.nursery_thermometer_temperature`, Master Bedroom `sensor.master_bedroom_thermometer_temperature`, and Playroom `sensor.playroom_thermometer_temperature`. The older `downstairs`, `bedrooms`, and `light.all_lights` examples were demo/fallback values and do not exist in the live catalog.

To verify arbitrary Home Assistant payloads are rejected:

```sh
curl -i -X POST http://localhost:4000/api/home/actions \
  -H "Content-Type: application/json" \
  -d '{"domain":"light","service":"turn_on","entity_id":"light.everything"}'
```

To verify provider-aware APNs registration and per-device garage preferences:

```sh
curl -X POST http://localhost:4000/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "token": "sample-apns-token",
    "platform": "ios",
    "provider": "apns",
    "environment": "sandbox",
    "appVersion": "0.1.0",
    "deviceName": "Josh iPhone"
  }'

curl -X PUT http://localhost:4000/api/notification-preferences \
  -H "Content-Type: application/json" \
  -d '{
    "deviceToken": "sample-apns-token",
    "provider": "apns",
    "environment": "sandbox",
    "preferences": [
      { "category": "garage_opened", "isEnabled": false },
      { "category": "garage_left_open", "isEnabled": true },
      { "category": "garage_after_hours", "isEnabled": true },
      { "category": "partner_presence", "isEnabled": true },
      { "category": "lighting_automation", "isEnabled": true }
    ]
  }'

curl 'http://localhost:4000/api/notification-preferences?deviceToken=sample-apns-token&provider=apns&environment=sandbox'
```

To verify the debug APNs endpoint shape without credentials, first register a sample APNs token and then call:

```sh
curl -i -X POST http://localhost:4000/api/debug/send-test-push \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Levy Home test",
    "body": "Testing backend APNs delivery."
  }'
```

Without APNs credentials, this should return `503` with `code: "apns_credentials_not_configured"`. With valid APNs credentials and a real physical-device token for the matching environment, it should return `ok: true` and increment `sentNotificationCount`.

To verify the event webhook and timeline:

```sh
curl -X POST http://localhost:4000/api/ha/events \
  -H "Authorization: Bearer dev-secret" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "garage_opened",
    "category": "garage",
    "severity": "normal",
    "entityId": "cover.main_garage_door",
    "source": "home_assistant"
  }'

curl http://localhost:4000/api/events
```

To trigger the Levy Home garage-left-open notification from Home Assistant, use the same reusable `rest_command.levy_home_event` shown below, then add an automation that fires when the garage has stayed open for 10 minutes. Keep the `entity_id` aligned with `HOME_ASSISTANT_GARAGE_COVER_ENTITY_ID`; this example uses the live Meross cover entity.

```yaml
alias: Garage - Left Open for 10 Minutes
description: ""
triggers:
  - entity_id: cover.meross_garage_door
    to: "open"
    for: "00:10:00"
    trigger: state
conditions:
  - condition: state
    entity_id: cover.meross_garage_door
    state: "open"
actions:
  - action: rest_command.levy_home_event
    data:
      payload_json: |-
        {{
          {
            "type": "garage_left_open_10_min",
            "category": "garage",
            "severity": "normal",
            "entityId": "cover.meross_garage_door",
            "source": "home_assistant",
            "occurredAt": now().isoformat(),
            "title": "Garage left open",
            "message": "The garage has been open for 10 minutes"
          } | to_json
        }}
mode: single
```

To trigger Levy Home partner-presence notifications from Home Assistant, configure a reusable `rest_command` and replace the old Home Assistant mobile-app notification action with the REST call. Keep the existing automation triggers and Josh-is-home condition; remove or replace the `notify.mobile_app_josh_iphone` action so Home Assistant does not also send its own push.

`rest_command.levy_home_event` will not appear in the Home Assistant action picker until the `rest_command:` YAML exists in Home Assistant configuration and Home Assistant has restarted. If you search for `rest` before that configuration is loaded, there may be no matching action to select.

Add secrets in Home Assistant `secrets.yaml`:

```yaml
levy_home_api_events_url: https://levy-home.onrender.com/api/ha/events
levy_home_ha_authorization_header: Bearer YOUR_LEVY_HOME_HA_WEBHOOK_SECRET
```

Add this command in Home Assistant configuration:

```yaml
rest_command:
  levy_home_event:
    url: !secret levy_home_api_events_url
    method: POST
    headers:
      Authorization: !secret levy_home_ha_authorization_header
      Content-Type: application/json
    payload: "{{ payload_json }}"
```

Use this action for `Mallory Left Home - Notify Josh`:

```yaml
actions:
  - action: rest_command.levy_home_event
    data:
      payload_json: >-
        {{
          {
            "type": "partner_left_home",
            "category": "presence",
            "severity": "normal",
            "entityId": "device_tracker.mallorys_iphone",
            "source": "home_assistant",
            "occurredAt": trigger.to_state.last_changed.isoformat(),
            "title": "Mallory left home",
            "message": "Mallory left home.",
            "metadata": {
              "actor": "Mallory",
              "recipient": "Josh",
              "oldState": trigger.from_state.state,
              "newState": trigger.to_state.state,
              "automation": "Mallory Left Home - Notify Josh"
            }
          } | to_json
        }}
mode: single
```

Use this action for `Mallory Arrived Home - Notify Josh`:

```yaml
actions:
  - action: rest_command.levy_home_event
    data:
      payload_json: >-
        {{
          {
            "type": "partner_arrived_home",
            "category": "presence",
            "severity": "normal",
            "entityId": "device_tracker.mallorys_iphone",
            "source": "home_assistant",
            "occurredAt": trigger.to_state.last_changed.isoformat(),
            "title": "Mallory is home",
            "message": "Mallory is home.",
            "metadata": {
              "actor": "Mallory",
              "recipient": "Josh",
              "oldState": trigger.from_state.state,
              "newState": trigger.to_state.state,
              "automation": "Mallory Arrived Home - Notify Josh"
            }
          } | to_json
        }}
mode: single
```

Use this full automation for `Josh Left Home - Notify Mallory`:

```yaml
alias: Josh Left Home - Notify Mallory
description: ""
triggers:
  - trigger: state
    entity_id: device_tracker.josh_iphone
    from: home
conditions:
  - condition: state
    entity_id: device_tracker.mallorys_iphone
    state: home
actions:
  - action: rest_command.levy_home_event
    data:
      payload_json: >-
        {{
          {
            "type": "partner_left_home",
            "category": "presence",
            "severity": "normal",
            "entityId": "device_tracker.josh_iphone",
            "source": "home_assistant",
            "occurredAt": trigger.to_state.last_changed.isoformat(),
            "title": "Josh left home",
            "message": "Josh left. But don't worry. He loves you too much to be gone for long",
            "metadata": {
              "actor": "Josh",
              "recipient": "Mallory",
              "oldState": trigger.from_state.state if trigger.from_state else none,
              "newState": trigger.to_state.state if trigger.to_state else none,
              "automation": "Josh Left Home - Notify Mallory"
            }
          } | to_json
        }}
mode: single
```

Use this full automation for `Josh Arrived Home - Notify Mallory`:

```yaml
alias: Josh Arrived Home - Notify Mallory
description: ""
triggers:
  - trigger: state
    entity_id: device_tracker.josh_iphone
    to: home
conditions:
  - condition: state
    entity_id: device_tracker.mallorys_iphone
    state: home
actions:
  - action: rest_command.levy_home_event
    data:
      payload_json: >-
        {{
          {
            "type": "partner_arrived_home",
            "category": "presence",
            "severity": "normal",
            "entityId": "device_tracker.josh_iphone",
            "source": "home_assistant",
            "occurredAt": trigger.to_state.last_changed.isoformat(),
            "title": "Josh arrived home",
            "message": "Prepare to be loved on... Josh arrived home.",
            "metadata": {
              "actor": "Josh",
              "recipient": "Mallory",
              "oldState": trigger.from_state.state if trigger.from_state else none,
              "newState": trigger.to_state.state if trigger.to_state else none,
              "automation": "Josh Arrived Home - Notify Mallory"
            }
          } | to_json
        }}
mode: single
```

Use this full automation for `Study On Bright` when the lights should still turn on exactly as before and then send a Levy Home app notification:

```yaml
alias: Study On Bright
description: ""
triggers:
  - device_id: 12d671f1d1064ff9df53625dbfd0d434
    domain: lutron_caseta
    type: press
    subtype: "on"
    trigger: device
conditions: []
actions:
  - action: light.turn_on
    metadata: {}
    target:
      entity_id:
        - light.study_lamp_1
        - light.study_lamp_2
        - light.study_lamp_3
    data:
      transition: 1
      color_temp_kelvin: 4500
      brightness_pct: 75
  - delay:
      seconds: 1
  - action: rest_command.levy_home_event
    data:
      payload_json: >-
        {{
          {
            "type": "study_lights_on",
            "category": "lighting",
            "severity": "normal",
            "entityId": "automation.study_on_bright",
            "source": "home_assistant",
            "occurredAt": now().isoformat(),
            "message": "Study: Let there be light!",
            "metadata": {
              "automation": "Study On Bright",
              "trigger": "lutron_caseta_on_press",
              "lights": [
                "light.study_lamp_1",
                "light.study_lamp_2",
                "light.study_lamp_3"
              ]
            }
          } | to_json
        }}
mode: single
```

To safely discover candidate Josh/Mallory iPhone entities from Home Assistant live mode:

```sh
curl 'http://localhost:4000/api/debug/home-assistant/phone-entities' \
  -H "Authorization: Bearer dev-secret"
```

The discovery response is intentionally sanitized. It includes entity IDs, domains, friendly names, bounded state summaries, timestamps, and matched search terms; it does not return Home Assistant tokens, headers, raw attributes, or full state dumps. Optional comma-separated `keywords` can narrow a one-off search:

```sh
curl 'http://localhost:4000/api/debug/home-assistant/phone-entities?keywords=josh,mallory,iphone' \
  -H "Authorization: Bearer dev-secret"
```

After reviewing discovery output, configure the exact home-presence tracker entities you want the Activity tab to ingest:

```sh
HOME_ASSISTANT_ACTIVITY_ENABLED=true
HOME_ASSISTANT_PHONE_ENTITIES=device_tracker.josh_iphone:Josh:Joshs iPhone,device_tracker.mallorys_iphone:Mallory:Mallorys iPhone
HOME_ASSISTANT_PHONE_ENTITY_PATTERNS=
```

As of the current Home Assistant catalog, the display names are `Joshs iPhone` and `Mallorys iPhone`, but several underlying IDs did not change after the rename. Josh's phone still uses `josh_iphone` IDs, Mallory's tracker/notify IDs use `mallorys_iphone`, and Mallory's Companion App sensors still use generic `sensor.iphone_*` IDs. The Levy Home Activity feed intentionally keeps only `device_tracker` transitions involving `home`, because the Home Assistant automations use those presence changes. Battery, activity, focus, last-update-trigger, geocoded location, SSID/BSSID, pressure, storage, and step counter sensors are too noisy for the user-facing Activity timeline. Re-run discovery after future HA renames before changing these values.

`HOME_ASSISTANT_WEBSOCKET_URL` is optional. Leave it blank unless the WebSocket listener needs to connect to a different URL than the one derived from `HOME_ASSISTANT_BASE_URL`. These values stay server-side and are not returned to the iOS app.

When `HOME_ASSISTANT_MODE=live` and `HOME_ASSISTANT_ACTIVITY_ENABLED=true`, the API process starts a background Home Assistant WebSocket listener at startup. It authenticates with `HOME_ASSISTANT_TOKEN`, subscribes to `state_changed`, filters to the configured exact entities and patterns, and reconnects with backoff after unexpected disconnects. The listener does not log tokens, request headers, raw Home Assistant events, or Home Assistant URLs.

At startup, the API also performs a temporary 24-hour Home Assistant REST history backfill for the configured phone entities. Exact `HOME_ASSISTANT_PHONE_ENTITIES` are requested directly; `HOME_ASSISTANT_PHONE_ENTITY_PATTERNS` are first resolved through `/api/states`, then requested through `/api/history/period/<timestamp>` with `filter_entity_id`. The backfill narrows that set to `device_tracker` entities before requesting history. This is an inspection aid for the simulator phase and is not durable storage.

Matching phone home-presence changes are normalized into `phone_state_changed` Activity records with clear display titles such as `Josh arrived home` or `Mallory left home`, `category: "phone"`, `source: "home_assistant"`, safe Home Assistant metadata, and no `push` object. Phone activity is not sent through APNs and is not represented as skipped notification delivery.

Matching phone activity is stored in the same process-local recent activity feed as webhook-created events and returned from `GET /api/events`. The temporary feed is capped at 500 process-local records, sorted newest first by `occurredAt`, and resets when the API process restarts or redeploys. The iOS Activity tab requests `GET /api/events?limit=500&start=<window-start>&end=<window-end>`: app open and pull-to-refresh load the newest 24-hour window, and the explicit `Load Earlier Activity` control requests the previous 24-hour window. Home Assistant history enrichment is best-effort; if history is unavailable, `/api/events` still returns process-local activity records.

The iOS Activity tab decodes `phone_state_changed` and `category: "phone"` directly and renders those records with phone-specific iconography.

To run the full local simulator verification workflow after selecting tracked phone entities, use:

```sh
scripts/verify-home-assistant-activity-simulator.sh
```

The script checks live activity env configuration, starts the local API with activity ingestion enabled, waits for phone activity in `/api/events`, then builds, installs, and launches the simulator app against `http://localhost:4000`.
