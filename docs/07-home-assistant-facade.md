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
| `HOME_ASSISTANT_GARAGE_COVER_ENTITY_ID` | Server-side garage cover entity. |
| `HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID` | Server-side all-lights entity/group. |
| `HOME_ASSISTANT_LIGHT_GROUPS` | Curated light groups in `groupId:Display name:entity_id` comma-separated format. |
| `MOCK_TOTAL_LIGHT_COUNT` | Mock-mode total light count. |

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
| `POST` | `/api/ha/events` | Home Assistant event webhook. |
| `GET` | `/api/events` | Recent event timeline. |

The API rejects arbitrary Home Assistant service/entity payloads from the app. Do not send fields such as `domain`, `service`, `entity_id`, or `target` to `/api/home/actions`.

Device registration is provider-aware:

- Native iOS APNs registrations must include `token`, `platform: "ios"`, `provider: "apns"`, and `environment: "sandbox"` or `"production"`.
- APNs sandbox and production registrations are stored separately even if the raw token value is the same.
- Legacy Expo-style registrations are still accepted with `pushToken` and are treated as `provider: "expo"`.
- Tokens are not returned in registration responses.

Notification preferences are currently in-memory backend state. They can sync from the native app and be fetched for manual verification, but push delivery enforcement begins in a later stage.

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
