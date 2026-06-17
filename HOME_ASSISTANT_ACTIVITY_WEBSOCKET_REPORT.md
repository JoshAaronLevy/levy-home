# Home Assistant Activity WebSocket Report

## Implementation Status

This document began as a planning/report document. **Phase 1 — Safe Home Assistant entity discovery**, **Phase 2 — Configure tracked phone entities**, **Phase 3 — Backend WebSocket listener**, **Phase 4 — Generic phone activity normalization**, **Phase 5 — Store and expose recent activity**, **Phase 6 — Minimal SwiftUI adjustments**, **Phase 7 — Simulator verification workflow**, temporary **24-hour Home Assistant history backfill**, and **24-hour lazy Activity paging** are now implemented.

The next actual implementation task should be a real Phase 7 run with selected phone entities/patterns configured in the local or deployed environment, then recording the observed phone activity result.

`Phase 0 — Planning report only` is no longer the current state. Phase 1 added a protected backend discovery route that queries Home Assistant REST `/api/states` in live mode and returns sanitized candidate phone entities. Phase 2 added explicit server-side config for activity enablement, tracked phone entity IDs, tracked phone entity patterns, owner/device metadata, and an optional WebSocket URL override. Phase 3 added a backend startup WebSocket listener that connects, authenticates, subscribes to `state_changed`, filters configured phone entities/patterns, and reconnects with backoff. Phase 4 added a generic `phone_state_changed` normalizer that produces Activity-first `LevyHomeEvent` records without push metadata. Phase 5 stores those normalized records in the same in-memory recent activity feed used by webhook events and exposes them through `GET /api/events`. Phase 6 added iOS-side recognition for `phone_state_changed` and `category: "phone"` plus a phone icon in the Activity card. Phase 7 added a repeatable script that starts a known local API process with activity enabled, verifies listener authenticated/subscribed logs, waits for `phone_state_changed` in `/api/events`, and builds/installs/launches the simulator app against `http://localhost:4000`. The temporary backfill added a startup REST history request for the configured phone entities over the last 24 hours. The Activity tab now asks `/api/events` for explicit 24-hour `start`/`end` windows: app open and pull-to-refresh load the newest 24 hours, while scrolling to the bottom fetches the previous 24 hours and appends them. There is still no durable activity storage. A real phone activity observation is pending because this checkout's local `.env` does not yet include `HOME_ASSISTANT_ACTIVITY_ENABLED`, `HOME_ASSISTANT_PHONE_ENTITIES`, or `HOME_ASSISTANT_PHONE_ENTITY_PATTERNS`.

## 1. Current State

### SwiftUI Activity Tab

- The app has an **Activity** tab in `LevyHome/Views/Root/RootTabView.swift`, wired to `ActivityView()`.
- `LevyHome/Views/Activity/ActivityView.swift` creates `ActivityViewModel(apiClient:)`, loads once with `.task`, supports pull-to-refresh, and renders loading, error, empty, and event-list states.
- `LevyHome/ViewModels/ActivityViewModel.swift` fetches up to 500 events per 24-hour window by default through `apiClient.fetchRecentEvents(limit:start:end:)`, refreshes the latest window, and lazy-loads older windows when the user reaches the bottom.
- `LevyHome/Views/Activity/EventCardView.swift` renders `LevyHomeEvent` records with display title/body/severity, occurred time, entity id, source, optional push status, and a phone icon for `phone_state_changed`.
- `LevyHome/Models/LevyHomeEvent.swift` defines the app-side event model with `id`, `type`, `entityId`, `category`, `severity`, `source`, `occurredAt`, `title`, `message`, `receivedAt`, `display`, and optional `push`.
- `LevyHome/Models/EventType.swift` and `LevyHome/Models/EventSeverity.swift` support `phone_state_changed` / `phone` and preserve unknown enum values for future event types.

### API Client

- `LevyHome/Services/APIClient.swift` has `fetchRecentEvents(limit:start:end:)`.
- It sends `GET /api/events`, with optional `limit`, `start`, and `end` query items.
- The response type is `EventsResponse` from `LevyHome/Models/APIResponses.swift`:

```json
{
  "ok": true,
  "events": []
}
```

### Backend Routes

`apps/api/src/server.ts` defines the relevant current routes:

- `GET /health`
- `GET /api/home/overview`
- `GET /api/home/actions`
- `POST /api/home/actions`
- explicit quick-action routes for garage/lights
- `POST /api/devices/register`
- `GET /api/notification-preferences`
- `PUT /api/notification-preferences`
- `POST /api/debug/send-test-push`
- `GET /api/debug/home-assistant/phone-entities`
- `POST /api/ha/events`
- `GET /api/events`

`POST /api/ha/events` is the current Home Assistant event ingestion path. It requires a bearer token based on `LEVY_HOME_HA_WEBHOOK_SECRET`, validates a narrow event payload, creates a stored event, optionally attempts APNs for garage categories, stores the event in memory, and returns the stored event.

`GET /api/events` returns activity records newest first, clamped to 1-500 records. It supports explicit `start`/`end` activity windows and a legacy `since` filter. For explicit windows, it merges process-local activity with temporary Home Assistant REST history records for configured phone entities. It now includes `POST /api/ha/events` webhook records, normalized Home Assistant WebSocket phone activity records, and temporary startup/on-demand Home Assistant REST history records. `GET /api/debug/home-assistant/phone-entities` is a protected Phase 1 discovery helper for sanitized Home Assistant phone-entity candidates. There is still no route dedicated to raw Home Assistant events or durable activity logs.

### Home Assistant Integration

- `apps/api/src/homeAssistantClient.ts` defines `createHomeAssistantFacade(config)`.
- In mock mode, it returns in-memory garage/light states.
- In live mode, `LiveHomeAssistantFacade` uses Home Assistant REST endpoints:
  - `GET /api/states/:entity_id`
  - `POST /api/services/cover/close_cover`
  - `POST /api/services/light/turn_off`
- The live facade uses `HOME_ASSISTANT_BASE_URL` and `HOME_ASSISTANT_TOKEN`.
- The live facade now includes safe phone-entity discovery through Home Assistant REST `/api/states`.
- The backend now includes a Home Assistant WebSocket listener for live activity ingestion startup, authentication, `subscribe_events`, reconnect/backoff, and runtime phone-entity filtering.

### Environment Variables

From `apps/api/src/config.ts` and `apps/api/.env.example`, the backend expects:

- `PORT`
- `LEVY_HOME_HA_WEBHOOK_SECRET`
- `HOME_ASSISTANT_MODE`
- `HOME_ASSISTANT_BASE_URL`
- `HOME_ASSISTANT_TOKEN`
- `HOME_ASSISTANT_ACTIVITY_ENABLED`
- `HOME_ASSISTANT_WEBSOCKET_URL`
- `HOME_ASSISTANT_PHONE_ENTITIES`
- `HOME_ASSISTANT_PHONE_ENTITY_PATTERNS`
- `HOME_ASSISTANT_GARAGE_COVER_ENTITY_ID`
- `HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID`
- `HOME_ASSISTANT_LIGHT_GROUPS`
- `HOME_ASSISTANT_LIGHT_ENTITIES`
- `MOCK_TOTAL_LIGHT_COUNT`
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY_PATH`
- `APNS_PRIVATE_KEY`
- `APNS_ENVIRONMENT`

The real `apps/api/.env` exists and includes these kinds of keys, plus `HOME_ASSISTANT_LOCAL_URL`, but I only inspected variable names and did not copy values. `HOME_ASSISTANT_LOCAL_URL` is not currently read by `apps/api/src/config.ts`.

### Storage

- I did not find an application database, ORM, migrations directory, SQLite/Postgres/Redis configuration, or durable activity storage.
- `apps/api/src/activityStore.ts` provides a process-local recent activity store capped at 500 events for the temporary inspection phase.
- `apps/api/src/server.ts` shares that store between webhook-created events, Home Assistant WebSocket phone activity, temporary Home Assistant REST history backfill activity, health counts, home overview recent-event lookup, and `GET /api/events`.
- Device registrations and notification preferences are also process-local maps.
- `docs/07-home-assistant-facade.md` explicitly says notification preferences reset when the API restarts. The same limitation applies to current recent activity events.

## 2. Product Concept: Activity Is Not Push Notifications

The app has an **Activity** tab. Activity records are observability/logging records: things the home system saw, such as an iPhone-related Home Assistant entity changing state.

Activity records are not the same thing as push notifications. Push notifications are delivery attempts to a device. Phone-related Home Assistant events should be treated as **Activity-first** records for this milestone.

For this milestone:

- Phone Activity records should not go through APNs delivery logic.
- Phone Activity records should not be described as failed, skipped, or disabled notifications.
- Push notifications for phone activity are a separate future concern.
- Export/email functionality is not part of the milestone.

This matters because the current backend event path is garage/doorbell/push-notification-centric. If phone activity is modeled as `"push": { "skipped": true }`, every normal phone observation starts looking like a notification failure. That is conceptually noisy and misleading. The Activity tab should become a trustworthy log/feed, not a list of notification attempts that did not happen.

### Home Assistant Event Stream Scope

The Home Assistant WebSocket `state_changed` stream gives Home Assistant-observable entity state changes. It does not mean the backend can see every internal iOS event.

The goal is not to capture every iOS internal event. The goal is to capture every relevant Home Assistant-observable state change for the configured Josh/Mallory iPhone entities. Home Assistant Companion App updates may be delayed or throttled by iOS background behavior.

## 3. Current Data Flow

### What the Activity tab currently calls

`ActivityView` creates `ActivityViewModel`, which calls `APIClient.fetchRecentEvents(limit: 500, start: <window-start>, end: <window-end>)`.

### What endpoint it expects

The iOS app expects:

```text
GET {LEVY_HOME_API_BASE_URL}/api/events?limit=500&start=<window-start>&end=<window-end>
```

The app’s default API base URL is `http://localhost:4000`, unless overridden by the `LEVY_HOME_API_BASE_URL` environment/build setting or the `LevyHomeAPIBaseURL` Info.plist value.

### What response shape it expects today

The app currently expects `EventsResponse` containing `[LevyHomeEvent]`. Example of the current garage-style shape:

```json
{
  "ok": true,
  "events": [
    {
      "id": "string",
      "type": "garage_opened",
      "entityId": "cover.main_garage_door",
      "category": "garage",
      "severity": "normal",
      "source": "home_assistant",
      "occurredAt": "2026-06-15T22:30:00Z",
      "title": "Garage opened",
      "message": "The garage door opened.",
      "receivedAt": "2026-06-15T22:30:01Z",
      "display": {
        "title": "Garage opened",
        "body": "The garage door opened.",
        "severity": "info"
      },
      "push": {
        "attempted": false,
        "skipped": true,
        "reason": "No APNs notification preference category is configured for this event type."
      }
    }
  ]
}
```

Important contract note: the Swift model makes `push` optional, and Phase 4 made backend `LevyHomeEvent.push` optional too. Phone Activity records should omit `push`; they should not include a fake `"push skipped"` object.

### Does the API currently return real Home Assistant activity?

- `GET /api/events` returns webhook-created events, normalized Home Assistant WebSocket phone activity, and temporary Home Assistant REST history records stored or fetched during the current API process lifetime.
- Fresh process with live activity configured: startup requests the last 24 hours of Home Assistant history for the configured phone entities and stores matching records in memory. Explicit `start`/`end` requests can also fetch older 24-hour windows directly from Home Assistant while persistence is deferred.
- Fresh process without live activity config, no webhook posts, and no matching WebSocket phone activity yet: returns `events: []`.
- Manual webhook posts: returns those stored in-memory events.
- Live Home Assistant activity ingestion subscribes to `state_changed` over `/api/websocket` when `HOME_ASSISTANT_MODE=live` and `HOME_ASSISTANT_ACTIVITY_ENABLED=true`.
- It also pulls a temporary 24-hour Home Assistant history backfill at API startup while durable activity storage is deferred.
- Existing Home Assistant live mode still uses REST for Home overview and quick actions.

### Is Home Assistant wired to the API?

Yes for the backend MVP, with durable storage still deferred.

- There is a protected webhook endpoint, `/api/ha/events`, intended for Home Assistant or manual event posting.
- The backend can connect to Home Assistant's WebSocket event stream at startup when live activity ingestion is enabled.
- The backend filters configured phone entities and explicit phone-entity patterns before normalization/storage.

### Is the API wired to the app?

Yes. The app’s Activity tab calls `/api/events`, and the backend serves `/api/events`. The backend Home Assistant WebSocket listener now stores normalized Josh/Mallory iPhone activity in that same recent feed. The remaining proof step is to verify real Home Assistant phone activity appears in the simulator Activity tab.

## 4. Gap Analysis

| Capability | Current status |
| --- | --- |
| Home Assistant WebSocket client | Present for `/api/websocket` connection, auth handshake, and `subscribe_events`. |
| Home Assistant REST client | Present for states, service calls, and Phase 1 safe phone-entity discovery; not used for activity ingestion. |
| Persistent backend listener process | Present in `startServer()` when `HOME_ASSISTANT_MODE=live` and `HOME_ASSISTANT_ACTIVITY_ENABLED=true`. |
| Reconnect/backoff logic | Present with bounded backoff delays. |
| Phone entity filtering | Present for configured exact entity IDs and explicit glob-style patterns. |
| Activity/event persistence model | Present for the MVP. `LevyHomeEvent` supports Activity-only phone records without `push`, and the shared in-memory recent activity store includes WebSocket phone records. Durable storage is still pending. |
| API endpoint SwiftUI can call | Present: `GET /api/events`; reusable only if the contract can support Activity-only phone records cleanly. |
| Working SwiftUI Activity UI | Present for the MVP. It renders `LevyHomeEvent` records, recognizes phone activity, and uses a phone icon for `phone_state_changed`. |
| Error/loading/empty states | Present in `ActivityView` and `ActivityViewModel`. |
| Simulator API config | Present for local Phase 7 runs through `scripts/verify-home-assistant-activity-simulator.sh`, which builds the simulator app with `LEVY_HOME_API_BASE_URL=http://localhost:4000`. Physical iPhones still need LAN/deployed URL. |

Additional gaps:

- Backend `LEVY_HOME_EVENT_TYPES` now includes `phone_state_changed`.
- Swift `EventType` now includes `phoneStateChanged`.
- Swift `HomeAssistantCategory` now includes `phone`.
- Backend `HomeAssistantEventCategory` now allows `garage`, `doorbell`, and `phone`.
- `createStoredEvent()` still handles garage push behavior, but Activity-only phone records omit `push`.
- Phase 1 code discovers sanitized Home Assistant phone-entity candidates through `GET /api/debug/home-assistant/phone-entities`.
- Phase 2 code parses tracked phone entity config, and Phase 3 consumes it for WebSocket filtering.
- Phase 3 uses the runtime WebSocket implementation. No `ws` package dependency was added.
- Phase 5 stores matching normalized phone state changes in the shared recent activity store and exposes them through `GET /api/events`.
- Phase 7 local preflight confirmed Home Assistant REST was reachable with the local `.env`, but tracked phone activity env keys were not configured yet.

## 5. Recommended Architecture

Recommended first-milestone flow:

```text
Home Assistant WebSocket
  -> backend-owned listener
  -> configured phone entity filter
  -> activity normalizer
  -> temporary recent activity store
  -> existing Activity API endpoint if compatible
  -> SwiftUI Activity tab
```

The backend should own the Home Assistant connection and token. The SwiftUI app should never talk directly to Home Assistant and should never receive `HOME_ASSISTANT_TOKEN`, the Nabu Casa URL value, webhook secrets, APNs credentials, or APNs tokens.

The WebSocket listener should run as a backend startup/background process, not inside a request handler. Request handlers should only query already-normalized activity records.

Recommended behavior:

1. Discover candidate iPhone entities safely using backend-side REST `/api/states`.
2. Manually choose explicit tracked entity IDs and/or patterns.
3. On API startup, if `HOME_ASSISTANT_MODE=live` and activity ingestion is enabled, connect to Home Assistant at `/api/websocket`.
4. For an HTTPS `HOME_ASSISTANT_BASE_URL`, derive a `wss://.../api/websocket` URL unless an explicit WebSocket URL override is added.
5. Authenticate with the server-side long-lived access token from `HOME_ASSISTANT_TOKEN`.
6. Subscribe to `state_changed` events.
7. Filter to configured phone-related entities or patterns for Josh’s iPhone and Mallory’s iPhone.
8. Normalize all matching MVP events into generic `phone_state_changed` Activity records.
9. Store the normalized records in a temporary recent activity store.
10. Expose them through the selected endpoint.
11. Let the SwiftUI Activity tab fetch that endpoint and render records.

### Deployment Caveats

- A long-running Node/Express process can support this listener locally and in the included Dockerfile model.
- A request/response-only or serverless-style host may not support a persistent listener. Functions can freeze, timeout, or scale horizontally.
- Multiple backend instances can each open a WebSocket and duplicate ingestion unless there is a leader lock, queue, durable idempotency, or single worker process.
- The listener should not start during test runs unless explicitly enabled or mocked.

## 6. First Working Milestone

The first working milestone is intentionally narrow:

- Backend can safely discover Home Assistant entities related to Josh/Mallory iPhones.
- Backend can connect to Home Assistant WebSocket.
- Backend can subscribe to `state_changed`.
- Backend can filter to explicitly configured phone entities.
- Backend can normalize matching events as `phone_state_changed`.
- Backend can store those records in the existing recent activity/events feed.
- `GET /api/events?limit=500&start=<window-start>&end=<window-end>` returns real phone activity records when live activity config and/or Home Assistant history are available.
- The SwiftUI simulator Activity tab displays those records.

The first milestone does **not** require:

- durable database storage
- export/email
- APNs
- polished icons
- perfect categorization
- historical backfill
- full Home Assistant log replication
- every possible iPhone-internal event
- every possible Home Assistant iPhone-related entity

## 7. Key Decisions Before Implementation

### Endpoint Decision

Recommended default:

1. First attempt to reuse `GET /api/events` because the SwiftUI Activity tab already calls it.
2. To reuse it cleanly, the backend event contract must allow Activity-only records without requiring `push`.
3. If removing/omitting `push` from phone Activity records becomes invasive, create `GET /api/activity` with a cleaner `ActivityEvent` contract.
4. Do not create both endpoints for the same MVP unless there is a clear reason.

Decision rule:

```text
Use /api/events if phone Activity can be represented cleanly as LevyHomeEvent without fake push metadata.
Use /api/activity if LevyHomeEvent remains too tied to garage/doorbell/push semantics.
```

Tradeoff:

- Reusing `/api/events` and `LevyHomeEvent` is fastest because the SwiftUI Activity tab already calls and renders it.
- Creating `/api/activity` with an `ActivityEvent` model is cleaner conceptually, but it requires more backend and Swift model/UI work.

### MVP Event-Type Decision

Recommended MVP default: normalize all matching Home Assistant phone `state_changed` events as `phone_state_changed`.

Do not classify MVP events into `phone_battery_changed`, `phone_location_changed`, or `phone_connection_changed` yet.

Why:

- We do not yet know the exact Home Assistant entity IDs and payload shapes.
- Premature categorization could add bugs before the ingestion pipeline works.
- A generic `phone_state_changed` event is enough to prove the end-to-end path.
- Specific event types can be added later as a display/normalization improvement after real payloads are observed.

Future refinement candidates:

- `phone_battery_changed`
- `phone_location_changed`
- `phone_connection_changed`

### Storage Decision

Should the first milestone use in-memory storage or durable storage?

Recommended default: in-memory is acceptable for the first simulator proof, but label it temporary. Durable storage will be needed later so activity survives API restarts, deploys, and multi-device use.

### Entity Matching Decision

Discovery and runtime matching should be separate:

1. Discover candidate phone entities with Home Assistant REST `/api/states`.
2. Review the list manually.
3. Add chosen entity IDs/patterns to backend config.
4. WebSocket listener filters against that explicit config.

Discovery is a one-time or occasional developer tool/helper. It should not be the runtime matching strategy for the MVP.

Runtime ingestion should use explicit configured entity IDs and/or explicit patterns. Fuzzy matching is acceptable for discovery only, not as the primary long-term ingestion filter.

Current Home Assistant catalog note: the phone display names are now `Joshs iPhone` and `Mallorys iPhone`, but the underlying IDs did not all change after the rename. The current key IDs are `device_tracker.josh_iphone`, `device_tracker.mallorys_iphone`, `notify.josh_iphone`, `notify.mallorys_iphone`, Josh's `sensor.josh_iphone_*` sensors, and Mallory's mostly generic `sensor.iphone_*` sensors. Re-run discovery before changing the backend env values again.

### WebSocket Worker Decision

Should the listener live inside the main API process or as a separate worker?

Recommended default: main API process is acceptable for local/dev MVP if deployment is a long-running Node process. A separate worker is cleaner later if deployment, uptime, or scale requires it.

### Push-Notification Decision

Should phone activity trigger APNs?

Recommended default: no. Not for this milestone.

## 8. MVP Normalizer Strategy

Start with a generic normalizer:

- Use the configured owner/entity map to determine `person`.
- Use the configured entity metadata and Home Assistant `attributes.friendly_name` as display helpers.
- Do not use `friendly_name` as the only identity mechanism.
- Normalize every matching MVP event as `type: "phone_state_changed"`.
- Keep richer phrasing for later once real payloads are known.

Simple title formats are enough:

- `Joshs iPhone changed`
- `{friendlyName} changed`

Simple message format is enough:

```text
{oldState} -> {newState}
```

This keeps the first implementation focused on proving the pipeline rather than polishing display copy before real payloads are known.

## 9. Implementation Plan

### Phase 1 — Safe Home Assistant entity discovery

Status: implemented.

Goal: identify Home Assistant entities related to Josh’s iPhone and Mallory’s iPhone.

Implemented files/areas:

- `apps/api/src/homeAssistantClient.ts`
- `apps/api/src/server.ts`
- `apps/api/src/server.test.ts`
- `docs/07-home-assistant-facade.md`

Steps:

1. Uses backend-side REST `/api/states`.
2. Filters candidates by entity id/friendly name/device class containing `iphone`, `josh`, `mallory`, `mobile_app`, or known Companion App sensor patterns.
3. Produces safe output only: entity IDs, friendly names, domains, bounded current state summaries, timestamps, and matched terms.
4. Does not print or return tokens, Nabu Casa URL values, headers, raw secrets, raw attributes, or full state dumps.
5. Exposes discovery through protected `GET /api/debug/home-assistant/phone-entities`, using the existing `LEVY_HOME_HA_WEBHOOK_SECRET` bearer check.

### Phase 2 — Configure tracked phone entities

Status: implemented.

Goal: add explicit server-side config for what should be ingested.

Implemented concepts:

- activity ingestion enabled flag
- tracked entity IDs
- explicit entity ID patterns
- owner/person mapping
- optional WebSocket URL override

Implemented files:

- `apps/api/src/config.ts`
- `apps/api/.env.example`
- `apps/api/src/config.test.ts`
- `apps/api/src/server.test.ts`
- `docs/07-home-assistant-facade.md`

Environment variables:

- `HOME_ASSISTANT_ACTIVITY_ENABLED`
- `HOME_ASSISTANT_WEBSOCKET_URL`
- `HOME_ASSISTANT_PHONE_ENTITIES`
- `HOME_ASSISTANT_PHONE_ENTITY_PATTERNS`

This phase intentionally does not start the WebSocket listener. The configured entity IDs and patterns are the safe allowlist that Phase 3 should consume.

### Phase 3 — Backend WebSocket listener

Status: implemented.

Goal: connect, authenticate, subscribe, filter, and reconnect safely.

Implemented files:

- `apps/api/src/homeAssistantActivityClient.ts`
- `apps/api/src/homeAssistantActivityClient.test.ts`
- `apps/api/src/server.ts`

Steps:

1. Connects to Home Assistant `/api/websocket`, deriving the URL from `HOME_ASSISTANT_BASE_URL` or honoring `HOME_ASSISTANT_WEBSOCKET_URL`.
2. Authenticates with the server-side token.
3. Subscribes to `state_changed`.
4. Filters to configured phone entities/patterns.
5. Handles reconnect/backoff.
6. Avoids logging tokens, headers, raw events, or Home Assistant URLs.
7. Starts the listener from backend startup, not from route handlers.
8. Avoids starting the listener in route tests because `createApp()` remains side-effect-free; listener startup lives in `startServer()`.

This phase intentionally did not store phone activity records. Phase 4 added normalization, and Phase 5 should wire normalized records into the activity feed.

### Phase 4 — Generic phone activity normalization

Status: implemented.

Goal: normalize matching configured phone entity events into generic `phone_state_changed` records.

Implemented files:

- `apps/api/src/activityNormalizer.ts`
- `apps/api/src/activityNormalizer.test.ts`
- `apps/api/src/contracts.ts`
- `apps/api/src/homeAssistantActivityClient.ts`
- `apps/api/src/server.ts`
- `apps/api/src/server.test.ts`

Steps:

1. Extracts entity id, old state, new state, timestamps, friendly name, context id, and safe bounded attributes.
2. Applies configured entity/person/device mapping from the Phase 3 listener event.
3. Creates a simple title and message.
4. Omits `push`.
5. Does not classify battery/location/connection-specific event types yet.

This phase intentionally did not store normalized phone events in the recent activity feed. Phase 5 replaced the listener's log-only callback with storage.

### Phase 5 — Store and expose recent activity

Goal: make normalized records queryable by the app.

Status: implemented.

Implemented MVP:

- Reuses `GET /api/events`; no parallel `/api/activity` endpoint was needed.
- Adds a shared in-memory recent activity store capped at 500 events for the temporary inspection phase.
- Stores webhook-created events, normalized Home Assistant WebSocket phone activity, and temporary Home Assistant REST history backfill activity in that store.
- Keeps phone activity as Activity-only records with no `push` object and no APNs attempt.

Files changed:

- `apps/api/src/activityStore.ts`
- `apps/api/src/activityStore.test.ts`
- `apps/api/src/server.ts`
- `apps/api/src/server.test.ts`
- `docs/07-home-assistant-facade.md`

Temporary limitation: storage is still process-local and resets on API restart or deploy.

### Phase 6 — Minimal SwiftUI adjustments only if needed

Goal: keep SwiftUI changes minimal.

Status: implemented.

Implemented MVP:

- Did not rebuild the Activity UI.
- Kept `ActivityViewModel` and `APIClient.fetchRecentEvents(limit:start:end:)` on the existing `/api/events` path.
- Added `phoneStateChanged` to Swift `EventType`.
- Added `phone` to Swift `HomeAssistantCategory`.
- Added a phone icon for `phone_state_changed` Activity cards.
- Added model decoding coverage for phone activity records that omit `push`.

Files changed:

- `LevyHome/Models/EventType.swift`
- `LevyHome/Models/EventSeverity.swift`
- `LevyHome/Views/Activity/EventCardView.swift`
- `LevyHome/Views/Activity/ActivityView.swift`
- `LevyHomeTests/ModelDecodingTests.swift`

### Phase 7 — Simulator verification

Goal: prove real Home Assistant phone activity appears in the simulator Activity tab.

Status: verification workflow implemented; real phone activity observation pending selected phone entity config.

Use the dedicated runner:

```sh
scripts/verify-home-assistant-activity-simulator.sh
```

The script:

1. Loads env from `apps/api/.env` without printing secret values.
2. Requires live Home Assistant mode, base URL, token, webhook secret, and at least one selected exact phone entity or explicit phone entity pattern.
3. Starts a known local API process with `HOME_ASSISTANT_ACTIVITY_ENABLED=true`.
4. Confirms listener logs show authenticated and subscribed.
5. Waits for `phone_state_changed` records in `GET /api/events?limit=500`.
6. Builds, installs, and launches the simulator app with `LEVY_HOME_API_BASE_URL=http://localhost:4000`.

Useful options:

```sh
PHASE7_EVENT_WAIT_SECONDS=300 scripts/verify-home-assistant-activity-simulator.sh
SIMULATOR_NAME='iPhone 17 Pro' scripts/verify-home-assistant-activity-simulator.sh
PHASE7_DRY_RUN=true PHASE7_SKIP_HA_PREFLIGHT=true scripts/verify-home-assistant-activity-simulator.sh
```

Manual endpoint check:

```sh
curl 'http://localhost:4000/api/events?limit=500&start=2026-06-14T17:00:00.000Z&end=2026-06-15T17:00:00.000Z'
```

Then open Activity and confirm phone records render newest first.

Current local preflight:

- Home Assistant REST was reachable from this checkout.
- Candidate phone-like Home Assistant entities were present.
- `HOME_ASSISTANT_ACTIVITY_ENABLED`, `HOME_ASSISTANT_PHONE_ENTITIES`, and `HOME_ASSISTANT_PHONE_ENTITY_PATTERNS` were not present in the local `.env`, so the real phone-event wait was not run to completion.

## 10. Proposed Data Shapes

### MVP-compatible `/api/events` shape

This keeps compatibility with the existing SwiftUI Activity tab while treating phone events as Activity records rather than notification records.

```json
{
  "ok": true,
  "events": [
    {
      "id": "01HZPHONEEVENTEXAMPLE",
      "type": "phone_state_changed",
      "entityId": "sensor.josh_iphone_battery_level",
      "category": "phone",
      "severity": "normal",
      "source": "home_assistant",
      "occurredAt": "2026-06-15T22:30:00Z",
      "receivedAt": "2026-06-15T22:30:01Z",
      "title": "Joshs iPhone changed",
      "message": "82 -> 81",
      "display": {
        "title": "Joshs iPhone changed",
        "body": "82 -> 81",
        "severity": "info"
      },
      "metadata": {
        "homeAssistantEventType": "state_changed",
        "person": "Josh",
        "deviceName": "Joshs iPhone",
        "friendlyName": "Joshs iPhone Battery Level",
        "oldState": "82",
        "newState": "81",
        "oldAttributes": {},
        "newAttributes": {},
        "homeAssistantContextId": "context-id-if-available"
      }
    }
  ]
}
```

Contract status: the Swift model allows `push` to be absent, and the backend `LevyHomeEvent` type now allows it too. Phone Activity records omit `push`; they do not include a fake `"push skipped"` object.

Raw Home Assistant event storage can be useful for debugging, but full raw events may include more home data than expected. If `metadata.raw` is added, it should be deliberate, server-side only, and safely redacted or bounded.

### Cleaner later `/api/activity` shape

If `/api/events` remains too tied to push/garage semantics, a dedicated activity contract would be cleaner:

```json
{
  "ok": true,
  "activity": [
    {
      "id": "string",
      "source": "home_assistant",
      "eventType": "state_changed",
      "activityType": "phone_state_changed",
      "entityId": "sensor.josh_iphone_battery_level",
      "deviceName": "Joshs iPhone",
      "person": "Josh",
      "friendlyName": "Joshs iPhone Battery Level",
      "oldState": "82",
      "newState": "81",
      "summary": "Joshs iPhone changed: 82 -> 81.",
      "occurredAt": "2026-06-15T22:30:00Z",
      "receivedAt": "2026-06-15T22:30:01Z",
      "metadata": {
        "oldAttributes": {},
        "newAttributes": {},
        "homeAssistantContextId": "context-id-if-available"
      }
    }
  ]
}
```

The MVP should prefer the lowest-churn path that gets real Home Assistant phone activity into the simulator Activity tab without polluting records with notification metadata.

## 11. Acceptance Criteria for the First Working Milestone

- API starts without exposing secrets.
- Backend logs show Home Assistant WebSocket connected, authenticated, and subscribed.
- Backend filters only explicitly configured Josh/Mallory phone-related entities.
- At least one real Home Assistant phone state change appears in the backend activity feed.
- Matching records are normalized as `phone_state_changed`.
- `GET /api/events?limit=500&start=<window-start>&end=<window-end>` returns real phone activity records.
- SwiftUI simulator Activity tab displays those records.
- Phone activity does not attempt APNs/push notification delivery.
- Phone activity records do not contain misleading skipped-notification metadata.
- Activity still shows useful loading, error, and empty states.
- Token values, Nabu Casa URL values, webhook secrets, APNs credentials, and APNs tokens are not exposed to the client app or committed to docs.

## 12. Implementation Guardrails

- Do not implement all phases in one pass unless explicitly asked.
- Prefer one narrow phase per Codex task.
- Do not start with the WebSocket listener before discovering entity IDs.
- Do not create a parallel Activity UI.
- Do not introduce durable database infrastructure in the first pass unless the existing in-memory store cannot support the simulator proof.
- Do not expose secrets.
- Do not log tokens or headers.
- Do not classify events into battery/location/connection types until real data has been observed.
- Do not wire phone Activity into APNs.

## 13. Risks / Red Flags

- Secret exposure: `HOME_ASSISTANT_TOKEN`, Nabu Casa URL values, webhook secrets, APNs keys, and APNs tokens must stay server-side and out of SwiftUI, reports, logs, tests, and git history.
- Token logging: WebSocket auth failures and REST errors must not log request headers or token values.
- WebSocket hosting: a long-running Node/Docker process can support the listener; a serverless-only deployment may not.
- Duplicate ingestion: multiple backend instances could each open a WebSocket and duplicate records.
- Reconnect duplicates: reconnects could potentially create duplicate nearby events, depending on timing and Home Assistant behavior.
- MVP dedupe: a simple in-memory dedupe key may be useful even for the first proof, such as entity id + old state + new state + event timestamp.
- Durable idempotency: later durable storage should consider a stable unique key to prevent duplicates across restarts or multiple instances.
- No durable storage: the current in-memory recent activity store loses activity when the API restarts.
- Current event contract began garage/doorbell-centric; backend types now support phone activity, but future categories may still need careful contract expansion.
- Current Activity UI recognizes `phone_state_changed`; truly unknown future event types still use generic icons.
- Entity IDs are unknown and may be unstable. Home Assistant Companion App entities can change with device rename/reintegration.
- One phone may simply be named `iPhone`, so discovery and config should not rely only on friendly name.
- iOS/Home Assistant Companion background updates are opportunistic. Battery/location/sensor updates may be delayed by iOS background execution rules and Companion App settings.
- Nabu Casa URL vs local URL: `HOME_ASSISTANT_BASE_URL` is what code reads today; `HOME_ASSISTANT_LOCAL_URL` exists in the local env but is unused.
- Simulator networking: `http://localhost:4000` is appropriate for iOS Simulator. A physical iPhone needs a LAN or deployed API URL.
- Naming confusion: current backend names are `events`, `HomeAssistantEventPayload`, and `LevyHomeEvent`; UI calls it Activity; notification code is interwoven for garage events.

## 14. What Not To Do Yet

- Do not implement export/email functionality.
- Do not wire APNs for phone activity.
- Do not expose the Home Assistant token to the app.
- Do not build a new Activity UI from scratch unless the current one truly cannot support the data.
- Do not add complex database infrastructure unless necessary for the first simulator proof.
- Do not rely only on fuzzy matching of friendly names long-term.
- Do not start the WebSocket listener in test runs unless explicitly enabled or mocked.
- Do not create a parallel event system that duplicates the existing Activity tab without explaining why.

## Bottom Line

Phases 1-7 are complete as an implementation workflow. The SwiftUI Activity tab and `/api/events` endpoint are already connected, and the backend can now discover candidate phone entities, read explicit phone tracking config, connect to Home Assistant WebSocket, filter configured phone entities, normalize matching state changes as generic `phone_state_changed` Activity records without push metadata, store those records in the shared in-memory recent activity feed, render them in the Activity tab with phone-specific decoding and iconography, and run a repeatable simulator verification script. The remaining milestone proof is to add selected phone entity config to the environment and capture a real `phone_state_changed` event in the simulator Activity tab.
