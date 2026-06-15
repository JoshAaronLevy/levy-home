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
| `HOME_ASSISTANT_PHONE_ENTITIES` | Exact phone-related entity IDs to listen for, in `entity_id:Person:Device name` comma-separated format. |
| `HOME_ASSISTANT_PHONE_ENTITY_PATTERNS` | Explicit glob-style phone entity patterns to listen for, in `entity_id_glob:Person:Device name` comma-separated format. Use `*` as the wildcard. |
| `HOME_ASSISTANT_GARAGE_COVER_ENTITY_ID` | Server-side garage cover entity. |
| `HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID` | Server-side all-lights entity/group. |
| `HOME_ASSISTANT_LIGHT_GROUPS` | Curated light groups in `groupId:Display name:entity_id` comma-separated format. |
| `MOCK_TOTAL_LIGHT_COUNT` | Mock-mode total light count. |
| `APNS_KEY_ID` | Apple APNs Auth Key ID. Required only for APNs sending. |
| `APNS_TEAM_ID` | Apple Developer Team ID for APNs JWT auth. Required only for APNs sending. |
| `APNS_BUNDLE_ID` | APNs topic/bundle identifier, currently `com.levy.home`. |
| `APNS_PRIVATE_KEY_PATH` | Local path to the APNs `.p8` private key file. Do not commit the key. |
| `APNS_PRIVATE_KEY` | Alternative APNs private key value with newlines escaped as `\n`. Do not commit it. |
| `APNS_ENVIRONMENT` | Default APNs endpoint for devices without an environment: `sandbox` or `production`. Native registrations should include their own environment. |

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Basic API health and mode. |
| `GET` | `/api/home/overview` | Garage status, light summary, recent important event, generated time. |
| `GET` | `/api/home/actions` | Curated quick actions and configured light groups. |
| `POST` | `/api/home/actions` | Generic curated action endpoint using `actionId` and optional `groupId`. |
| `POST` | `/api/home/actions/close-garage` | Explicit close-garage action. |
| `POST` | `/api/home/actions/lights-off` | Explicit all-lights-off action. |
| `POST` | `/api/home/actions/light-groups/:groupId/off` | Explicit curated light-group off action. |
| `POST` | `/api/devices/register` | Provider-aware push-device registration for native APNs tokens and legacy Expo push tokens. |
| `GET` | `/api/notification-preferences` | Garage notification preferences, optionally scoped by `deviceId` or provider-aware device token query params. |
| `PUT` | `/api/notification-preferences` | Sync per-device garage notification preferences by registered `deviceId` or provider-aware token. |
| `POST` | `/api/debug/send-test-push` | Debug APNs test push to registered APNs devices with provider-neutral counts. |
| `GET` | `/api/debug/home-assistant/phone-entities` | Protected Home Assistant phone-entity discovery helper for Phase 1 activity setup. |
| `POST` | `/api/ha/events` | Home Assistant event webhook. |
| `GET` | `/api/events` | Recent event timeline. |

The API rejects arbitrary Home Assistant service/entity payloads from the app. Do not send fields such as `domain`, `service`, `entity_id`, or `target` to `/api/home/actions`.

Device registration is provider-aware:

- Native iOS APNs registrations must include `token`, `platform: "ios"`, `provider: "apns"`, and `environment: "sandbox"` or `"production"`.
- APNs sandbox and production registrations are stored separately even if the raw token value is the same.
- Legacy Expo-style registrations are still accepted with `pushToken` and are treated as `provider: "expo"`.
- Tokens are not returned in registration responses.

Notification preferences are currently in-memory backend state. They can sync from the native app, be fetched for manual verification, and are used for garage APNs push filtering while the API process is running. They reset when the API restarts until durable backend persistence is added.

Stage 16 APNs behavior:

- Debug test pushes use registered APNs devices and return provider-neutral counts such as `sentNotificationCount`, `failedNotificationCount`, and `invalidTokenCount`.
- Debug test pushes are diagnostics and do not apply garage notification category preferences.
- Garage Home Assistant events map to the five garage preference categories and only send APNs pushes to devices where that category is enabled.
- If APNs credentials are missing, `/api/debug/send-test-push` returns a readable `503` error instead of crashing. Garage event ingestion still stores the event and records the missing-credentials reason in `event.push`.
- Expo-style device registrations remain accepted for compatibility, but this backend stage does not send Expo pushes.

## Manual Checks

```sh
curl http://localhost:4000/api/home/overview
curl http://localhost:4000/api/home/actions

curl -X POST http://localhost:4000/api/home/actions \
  -H "Content-Type: application/json" \
  -d '{"actionId":"close_garage"}'

curl -X POST http://localhost:4000/api/home/actions \
  -H "Content-Type: application/json" \
  -d '{"actionId":"turn_off_light_group","groupId":"downstairs"}'

curl -X POST http://localhost:4000/api/home/actions/light-groups/downstairs/off
```

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
      { "category": "garage_after_hours", "isEnabled": true }
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

After reviewing discovery output, configure only the exact entities and explicit patterns you want the backend to ingest:

```sh
HOME_ASSISTANT_ACTIVITY_ENABLED=true
HOME_ASSISTANT_PHONE_ENTITIES=sensor.joshs_iphone_battery_level:Josh:Josh's iPhone,device_tracker.mallorys_iphone:Mallory:Mallory's iPhone
HOME_ASSISTANT_PHONE_ENTITY_PATTERNS=sensor.joshs_iphone_*:Josh:Josh's iPhone,sensor.mallorys_iphone_*:Mallory:Mallory's iPhone
```

`HOME_ASSISTANT_WEBSOCKET_URL` is optional. Leave it blank unless the WebSocket listener needs to connect to a different URL than the one derived from `HOME_ASSISTANT_BASE_URL`. These values stay server-side and are not returned to the iOS app.

When `HOME_ASSISTANT_MODE=live` and `HOME_ASSISTANT_ACTIVITY_ENABLED=true`, the API process starts a background Home Assistant WebSocket listener at startup. It authenticates with `HOME_ASSISTANT_TOKEN`, subscribes to `state_changed`, filters to the configured exact entities and patterns, and reconnects with backoff after unexpected disconnects. The listener does not log tokens, request headers, raw Home Assistant events, or Home Assistant URLs.

Matching phone state changes are normalized into generic `phone_state_changed` Activity records with `category: "phone"`, `source: "home_assistant"`, safe Home Assistant metadata, and no `push` object. Phone activity is not sent through APNs and is not represented as skipped notification delivery.

Matching phone activity is stored in the same process-local recent activity feed as webhook-created events and returned from `GET /api/events`. This storage is temporary for the simulator proof and resets when the API process restarts or redeploys.

The iOS Activity tab decodes `phone_state_changed` and `category: "phone"` directly and renders those records with phone-specific iconography.

To run the full local simulator verification workflow after selecting tracked phone entities, use:

```sh
scripts/verify-home-assistant-activity-simulator.sh
```

The script checks live activity env configuration, starts the local API with activity ingestion enabled, waits for phone activity in `/api/events`, then builds, installs, and launches the simulator app against `http://localhost:4000`.
