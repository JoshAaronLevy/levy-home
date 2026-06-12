# SwiftUI Migration Discovery

This document captures the deprecated Expo/React Native implementation in `levy-home-app` and turns it into migration context for rebuilding the product as an iOS-only native SwiftUI application in `levy-home`.

The React Native app should be treated as a conceptual reference, not as the product specification or a line-by-line implementation template. It was not fully validated because of Expo issues. The SwiftUI rebuild should preserve useful product ideas and backend contract concepts where they still fit, while replacing Expo-specific mobile plumbing with native iOS equivalents.

## Continuity Note

This document is primarily an inventory of the existing Expo/React Native reference app and the original notification-first migration plan. It intentionally preserves the source app's current Home, Events, Settings, and Debug tab shape as historical context.

The target product scope has since changed. Where this document's target-roadmap or SwiftUI-equivalent sections conflict with `docs/04-product-scope-update.md`, `docs/02-swiftui-architecture.md`, `docs/03-implementation-roadmap.md`, or `docs/05-project-continuity-review.md`, treat the newer documents as authoritative for implementation order and target IA. All new implementation work belongs in `levy-home` unless explicitly directed otherwise.

Current superseded assumptions in this discovery document include:

- Home as a mostly static status/copy screen.
- Events as the primary dynamic product surface rather than supporting Activity history.
- Settings as a primary tab.
- Debug as a primary tab rather than build-gated Developer Tools.
- Device controls and light/garage quick actions as entirely out of scope.

These remain accurate descriptions of the current reference app, but they are not the revised SwiftUI target.

## 1. Executive Summary

### What The Application Does

Levy Home is a family-facing iOS notification app for selected Home Assistant events. The current MVP is intentionally narrow: Home Assistant remains the automation brain, a small Node/Express API receives curated Home Assistant events, the API sends push notifications, and the mobile app displays registration status plus a recent event timeline.

The app is explicitly not a full Home Assistant dashboard. It does not control devices, show camera live views, provide automation editing, or replace Home Assistant. Its value is focused notification routing and a simple human-readable event history for important home events.

### Current Feature Set

Current shipped/mobile-visible features:

| Feature | Current behavior |
| --- | --- |
| Home tab | Displays app positioning, push registration status, and current API base URL. |
| Events tab | Loads recent events from the API, supports pull-to-refresh, shows empty/error states, and renders event cards with title, message, entity ID, received time, severity, and push skip reason. |
| Settings tab | Displays API URL, platform label, and current storage model. |
| Debug tab | Displays API URL, push registration status, Expo push token, manual registration action, and test push action. |
| Push registration | Requests notification permission on launch, obtains an Expo push token on physical iOS devices, and registers it with the API. |
| Test push | Calls a debug API endpoint that sends a test push to all registered devices. |
| Home Assistant event ingestion | API accepts authenticated Home Assistant event payloads at `POST /api/ha/events`. |
| Recent event timeline | API stores up to 100 recent events in memory and returns a default page of 50 events. |
| Push dedupe | API dedupes pushes by `type:entityId` for a configurable cooldown window. |
| Garage event docs | Docs define five MVP garage automations and three later doorbell event placeholders. |

Current product scope from docs:

| In scope | Out of scope |
| --- | --- |
| Garage opened/closed notifications | Full Home Assistant dashboard |
| Garage left open alert | Camera live view |
| Garage after-hours alert | Two-way talk |
| Garage still open at 10 PM alert | Hue/Lutron/LIFX controls |
| Doorbell placeholders for later | LG ThinQ / SmartThings |
| Recent event timeline | Android / Apple Watch |
| Push notification pipeline | Automation builder |
| Debug tooling | Production user auth for this stage |

### Current Architecture

The existing repository is an npm workspace with three main parts:

| Package | Role |
| --- | --- |
| `apps/mobile` | Expo Router + React Native iOS app. Handles UI, push permission/token retrieval, API calls, and basic debug tooling. |
| `apps/api` | Node/Express API. Receives Home Assistant events, stores recent events/devices in memory, sends Expo push notifications, and exposes debug/test endpoints. |
| `packages/shared` | Shared TypeScript domain contract. Defines event types, display metadata, event payload models, validation helpers, and dedupe key generation. |

Runtime pipeline:

```text
Home Assistant automation or fake curl event
-> POST /api/ha/events on the Levy Home API
-> API validates payload and applies push dedupe
-> API sends push through Expo push service
-> iOS Expo app receives push
-> app fetches /api/events for timeline display
```

The SwiftUI rewrite should be scoped initially to replacing `apps/mobile`. The API can remain as the backend contract during the first native migration stage, but push delivery will need a deliberate decision because the current backend sends Expo push tokens, while a pure SwiftUI app will receive APNs device tokens.

### Major Dependencies

Mobile dependencies:

| Dependency | Current use | SwiftUI migration implication |
| --- | --- | --- |
| `expo` | App runtime and config system | Remove. Use native iOS app lifecycle. |
| `expo-router` | File-based stack/tab routing | Replace with SwiftUI `TabView` and simple view composition. |
| `expo-notifications` | Notification permission and Expo push token retrieval | Replace with `UserNotifications`, APNs registration, and app delegate callbacks. |
| `expo-constants` | Reads EAS project ID | Remove. No EAS project ID needed for native APNs. |
| `expo-device` | Checks physical device before push token registration | Replace with native runtime handling. Simulator cannot receive remote APNs pushes in the same way as physical devices. |
| `expo-symbols` | SF Symbol rendering in tab icons and buttons | Replace with SwiftUI `Image(systemName:)`. |
| `expo-status-bar` | Status bar style | Replace with native SwiftUI/iOS status bar behavior. |
| `react`, `react-native` | UI/runtime | Replace with SwiftUI. |
| `react-native-reanimated` | Imported but not used by custom app code | Remove. |
| `react-native-safe-area-context`, `react-native-screens` | Navigation/runtime support | Remove. |

API dependencies:

| Dependency | Current use | SwiftUI migration implication |
| --- | --- | --- |
| `express` | HTTP API | Can remain initially. |
| `cors` | Allows browser/dev callers | Not required by native client, but harmless for existing API. |
| `dotenv` | Server environment config | Keep for API while server remains Node. |
| `expo-server-sdk` | Sends Expo push notifications | Must be replaced or supplemented for APNs when the native client no longer uses Expo push tokens. |
| `crypto.randomUUID` | Stored event IDs | Backend concern. Native app only decodes IDs. |

Shared package:

| Dependency | Current use | SwiftUI migration implication |
| --- | --- | --- |
| TypeScript only | Shared domain types and validation | Recreate as Swift `Codable` models and validation helpers where needed. Do not embed TypeScript or generate Swift mechanically unless a schema source is later introduced. |

### Current Maturity Level

The app is MVP/prototype maturity. It has a coherent product direction and working end-to-end plumbing, but several production concerns are intentionally deferred.

Current strengths:

- Small and understandable feature set.
- Clear separation between mobile UI, API, and shared event contract.
- Documented Home Assistant event mapping and local testing flow.
- Simple data models that map cleanly to Swift `Codable` types.
- Minimal client-side state and no complex React state management.

Current limitations:

- API storage is in memory; server restart clears registered devices, dedupe state, and timeline events.
- Mobile app stores no settings or token state locally.
- Push delivery depends on Expo tokens and Expo push service.
- No production user authentication.
- Debug endpoint is unauthenticated.
- Recent events endpoint is unauthenticated.
- No automated tests in the current app/API packages.
- Generated Expo iOS native files exist, but no meaningful custom native iOS implementation exists yet.

## 2. Screen Inventory

### Navigation Structure

Current app navigation is Expo Router based:

```text
Root Stack
`-- (tabs), header hidden
    |-- Home tab: app/(tabs)/index.tsx
    |-- Events tab: app/(tabs)/events.tsx
    |-- Settings tab: app/(tabs)/settings.tsx
    `-- Debug tab: app/(tabs)/debug.tsx

Fallback
`-- +not-found.tsx
```

SwiftUI equivalent:

```text
LevyHomeApp
`-- TabView
    |-- HomeView
    |-- EventsView
    |-- SettingsView
    `-- DebugView
```

A full coordinator layer is unnecessary. `TabView` plus local view models is enough for the current navigation shape.

### Root Layout

| Item | Details |
| --- | --- |
| Current file | `apps/mobile/app/_layout.tsx` |
| Purpose | App shell. Wraps all screens in `PushRegistrationProvider`, configures root stack, sets dark status bar. |
| Inputs | None directly. Indirectly starts push registration through provider side effect. |
| Outputs | Makes push registration state available to all screens. Displays tab stack. |
| Important flows | App launch triggers push registration automatically. |
| SwiftUI equivalent | `@main` app creates shared `PushRegistrationViewModel` or `NotificationService` and injects it through `environment` or as explicit observed state. |

### Tab Layout

| Item | Details |
| --- | --- |
| Current file | `apps/mobile/app/(tabs)/_layout.tsx` |
| Purpose | Defines four tabs and common tab/header styling. |
| Inputs | None. |
| Outputs | Tab bar with Home, Events, Settings, Debug. Uses green active tint `#2f6f5e`. |
| Important flows | User switches among the four primary app areas. |
| SwiftUI equivalent | `TabView` with SF Symbols: `house`, `list.bullet.rectangle`, `gearshape`, `wrench.and.screwdriver`. |

### Home Screen

| Item | Details |
| --- | --- |
| Current file | `apps/mobile/app/(tabs)/index.tsx` |
| Purpose | Landing/status screen. Communicates that Levy Home is for notifications, not a dashboard. Shows push status and API URL. |
| Inputs | `pushRegistration.statusMessage`, `API_BASE_URL`. |
| Outputs | Read-only status panels. |
| User actions | None. |
| Important flows | On app launch, user can immediately see whether push registration ran and which API the app targets. |
| SwiftUI equivalent | `HomeView` with a header and two simple information panels. |

Current display text:

- Eyebrow: `Levy Home`
- Title: `Home notifications, not a dashboard.`
- Subtitle: `Garage events land here first. Doorbell notifications can plug into the same pipeline later.`
- Panels: `Push status`, `API`

### Events Screen

| Item | Details |
| --- | --- |
| Current file | `apps/mobile/app/(tabs)/events.tsx` |
| Purpose | Recent Home Assistant event timeline. |
| Inputs | `fetchRecentEvents()` response, current loading/error state. |
| Outputs | Empty state, error banner, refresh indicator, and event cards. |
| User actions | Pull to refresh. |
| Important flows | Screen loads events on first appearance; user refreshes after sending fake events or real Home Assistant automations. |
| SwiftUI equivalent | `EventsView` backed by `EventsViewModel`, using `.refreshable` and `List` or `ScrollView`/`LazyVStack`. |

Event card fields:

| Field | Current source | Notes |
| --- | --- | --- |
| Title | `event.title ?? event.display.title` | Payload title wins over default metadata. |
| Severity badge | `event.display.severity` | Values: `info`, `warning`, `critical`. |
| Message | `event.message ?? event.display.body` | Payload message wins over default metadata. |
| Entity ID | `event.entityId` | Rendered in monospace. |
| Received time | `event.receivedAt` formatted with `toLocaleString()` | Swift should use `DateFormatter` or `Date.FormatStyle`. |
| Push note | `event.push.reason` when `event.push.skipped` | Mostly dedupe skip messages. |

Screen states:

| State | Current behavior | SwiftUI recommendation |
| --- | --- | --- |
| Initial loading | `isLoading = true` after mount; no explicit full-screen spinner unless refresh control is active | Show a lightweight progress state or retain current quiet behavior. |
| Empty | Shows `No events yet` panel when events are empty and not loading | Preserve. |
| Error | Shows error banner with thrown error message | Preserve but map network/decoding errors to user-readable messages. |
| Refresh | Pull-to-refresh via `RefreshControl` | Use `.refreshable`. |

### Settings Screen

| Item | Details |
| --- | --- |
| Current file | `apps/mobile/app/(tabs)/settings.tsx` |
| Purpose | Read-only runtime/config summary. |
| Inputs | `API_BASE_URL`. |
| Outputs | Three rows: API URL, Platform, Data. |
| User actions | None. |
| Important flows | User or developer can confirm current environment. |
| SwiftUI equivalent | `SettingsView` with static sections. Later this can become editable for development API URL if desired. |

Current rows:

| Label | Value |
| --- | --- |
| API URL | Runtime API base URL. |
| Platform | `iOS development build` |
| Data | `Local API memory only` |

### Debug Screen

| Item | Details |
| --- | --- |
| Current file | `apps/mobile/app/(tabs)/debug.tsx` |
| Purpose | Developer/test tooling for push registration and test pushes. |
| Inputs | `API_BASE_URL`, push registration context, `sendTestPush()` result. |
| Outputs | API URL, push status, error message, Expo push token, buttons, loading spinner, last response text, native alerts. |
| User actions | Register push token, send test push. |
| Important flows | Tester retries push registration manually; tester sends a server-triggered test push after registration. |
| SwiftUI equivalent | `DebugView` backed by `DebugViewModel` or shared push/events view models. Use native alert presentation. |

Current actions:

| Action | API/native work | Success output | Failure output |
| --- | --- | --- | --- |
| Register push token | Request notification permission, obtain Expo token, call `POST /api/devices/register` | Push status updates with registered device count | Status becomes unavailable or error, displays reason |
| Send test push | `POST /api/debug/send-test-push` | Alert and last response: sent ticket count and registered device count | Alert and last response with error message |

### Not Found Screen

| Item | Details |
| --- | --- |
| Current file | `apps/mobile/app/+not-found.tsx` |
| Purpose | Expo Router fallback screen for unknown routes. |
| Inputs | None. |
| Outputs | `Screen not found` and link back home. |
| User actions | Tap Go home. |
| SwiftUI equivalent | Not needed for the initial native app unless deep links/universal links are added. If URL routing is preserved, unknown routes can fall back to Home. |

### Important User Flows

#### First Launch / Push Registration

```text
User launches app
-> Root creates push registration provider
-> app asks for notification permission
-> if granted, app obtains Expo push token
-> app posts token to /api/devices/register with platform ios
-> status is shown on Home and Debug
```

SwiftUI migration impact:

- Replace Expo push token retrieval with APNs token registration.
- Decide whether the backend will accept APNs tokens directly or continue using Expo through an adapter. For a pure native SwiftUI app, direct APNs is the cleaner long-term direction.
- Keep user-visible status messages similar so the debug experience remains useful.

#### Viewing Recent Events

```text
User opens Events tab
-> app calls GET /api/events
-> app stores response events in local screen state
-> app renders cards newest first
-> user can pull to refresh
```

SwiftUI migration impact:

- Model `LevyHomeEvent` as `Codable`.
- Use `URLSession` and `async/await`.
- Keep refresh behavior and empty/error states.

#### Manual Garage Event Test

```text
Developer sends curl POST /api/ha/events with HA webhook secret
-> API validates payload
-> API sends push unless deduped
-> API stores event in recentEvents
-> user sees push notification
-> user opens Events tab and refreshes timeline
```

SwiftUI migration impact:

- Native app behavior remains the same after backend push support is updated.
- The event API contract can remain unchanged.

#### Debug Test Push

```text
User opens Debug tab
-> taps Send test push
-> app calls POST /api/debug/send-test-push
-> API sends push to registered devices
-> app shows alert with result summary
```

SwiftUI migration impact:

- Preserve during development.
- Consider hiding or protecting this in production.
- Update response terminology if the backend moves from Expo tickets to APNs results.

## 3. Component Inventory

### Reusable UI Components

The current mobile app has very little reusable component structure. Most UI is local to screens.

| Component | Current location | Reuse level | Responsibilities | SwiftUI recommendation |
| --- | --- | --- | --- | --- |
| `PushRegistrationProvider` | `apps/mobile/src/push-registration.tsx` | App-wide logic provider | Owns push registration state, auto-registers on launch, exposes retry action | Replace with `PushRegistrationViewModel` or `NotificationRegistrationModel` owned at app level. |
| `usePushRegistration` | `apps/mobile/src/push-registration.tsx` | App-wide hook | Reads push context | Replace with `@Environment`, `@StateObject`, or explicit `@ObservedObject`/`@Observable` injection. |
| `ActionButton` | `apps/mobile/app/(tabs)/debug.tsx` | Local to Debug | Icon + label pressable button with disabled/pressed states | Replace with a small local SwiftUI `Button` style or extracted `PrimaryActionButton` only if reused. |
| Event card markup | `apps/mobile/app/(tabs)/events.tsx` | Local to Events | Displays one `LevyHomeEvent` | Extract `EventCardView` in SwiftUI for readability. |
| Info panels/rows | Home, Settings, Debug | Repeated style but not abstracted | Label/value cards | Consider small `InfoPanel`/`InfoRow` SwiftUI views if repetition grows. Keep simple. |
| Tab icons | `apps/mobile/app/(tabs)/_layout.tsx` | Navigation | SF Symbols through Expo Symbols | Use `Image(systemName:)`. |

### Shared Logic

| Logic | Current location | Details | SwiftUI/native equivalent |
| --- | --- | --- | --- |
| API base URL resolution | `apps/mobile/src/api.ts` | `EXPO_PUBLIC_API_URL` with default `http://localhost:4000`, trailing slash stripped | Build setting, Info.plist config, or debug UserDefaults. Do not hardcode production URLs in views. |
| Generic API request | `apps/mobile/src/api.ts` | Adds JSON headers, parses text as JSON, throws server error message | `APIClient` using `URLSession`, typed request/response methods, JSON decoder/encoder. |
| Device registration | `apps/mobile/src/api.ts` | Posts `pushToken` and `platform: ios` | Same endpoint if backend is adapted to APNs tokens; request field should be renamed or versioned if it becomes APNs-specific. |
| Fetch events | `apps/mobile/src/api.ts` | GET `/api/events` | Preserve endpoint initially. |
| Send test push | `apps/mobile/src/api.ts` | POST `/api/debug/send-test-push` | Preserve for dev, review production exposure. |
| Notification permission/token | `apps/mobile/src/notifications.ts` | Uses Expo Notifications and Expo project ID | Native `UNUserNotificationCenter` authorization and `UIApplication.registerForRemoteNotifications()`. |
| Event validation | `packages/shared/src/index.ts` | Server-side validation for Home Assistant payloads | Native client should not need to validate HA inbound payloads, but should validate/handle decoded API responses defensively. |
| Display metadata | `packages/shared/src/index.ts` | Default title/body/severity per event type | Duplicate in Swift model layer, or expose from backend in each event as it does today. The client should still know severity colors. |
| Dedupe key | `packages/shared/src/index.ts` | `type:entityId` | Backend concern. Only document/display if useful. |
| Time formatting | `events.tsx` | `new Date(value).toLocaleString()` | Use `Date.ISO8601FormatStyle`/`ISO8601DateFormatter` for parsing and `Date.FormatStyle` for display. |

### State Dependencies

| State | Current owner | Initial value | Mutations | Persistence |
| --- | --- | --- | --- | --- |
| Push token | `PushRegistrationProvider` | `null` | Set after Expo token retrieval; cleared on unavailable | Not persisted |
| Push registration status | `PushRegistrationProvider` | `idle` | `registering`, `registered`, `unavailable`, `error` | Not persisted |
| Push status message | `PushRegistrationProvider` | `Push registration has not run yet.` | Updated throughout registration flow | Not persisted |
| Push error | `PushRegistrationProvider` | `null` | Set when permission/device/API registration fails | Not persisted |
| Events list | `EventsScreen` | `[]` | Set from `GET /api/events` | Not persisted |
| Events loading | `EventsScreen` | `false` | True around fetch | Not persisted |
| Events error | `EventsScreen` | `null` | Set on fetch failure | Not persisted |
| Debug sending state | `DebugScreen` | `false` | True around test push call | Not persisted |
| Debug last response | `DebugScreen` | `null` | Set after test push success/failure | Not persisted |

SwiftUI state recommendation:

- Use one app-level notification registration object because Home and Debug both need it.
- Use screen-level view models for events and debug actions.
- Avoid global state containers. The current state surface is tiny.

### Styling And Theme Conventions

The app uses a quiet, utilitarian palette and card-like panels:

| Token purpose | Current color/value |
| --- | --- |
| App background | `#f7faf8` |
| Panel background | `#ffffff` |
| Panel border | `#dde7e1` |
| Primary green / tint | `#2f6f5e` |
| Primary text | `#17211d` |
| Secondary text | `#56645f` |
| Muted label text | `#6b7773` |
| Body text | `#34423d` |
| Info severity background/text | `#e9f2ff` / `#20507e` |
| Warning severity background/text | `#fff4d8` / `#7a5200` |
| Critical/error background/text | `#ffe5e1` / `#8a2418` |
| Error border | `#ffb7ad` |
| Radius | `8` for panels/buttons, `6` for token box, pill radius for severity |
| Spacing | Mostly 12 to 20 points, panels padded 16 points |
| Typography | Bold uppercase labels, 28 point title, 15 to 17 point body/card text |

SwiftUI recommendation:

- Define a small `Theme` enum or constants file for colors and spacing.
- Keep panels simple and compact. This app is operational/status-oriented, not a marketing app.
- Use dynamic type-friendly text styles where possible, but preserve the hierarchy: labels small/bold, title strong, card content readable.
- Consider dark mode only after parity is reached. Current generated native Info.plist forces light style, while Expo config says automatic; product decision is needed.

## 4. Data Model Inventory

### Domain Models

#### `LevyHomeEventType`

Allowed values:

| Type | Current product meaning | Current display severity |
| --- | --- | --- |
| `garage_opened` | Garage door opened during normal hours | `info` |
| `garage_closed` | Garage door closed | `info` |
| `garage_left_open_10_min` | Garage has remained open for 10 minutes | `warning` |
| `garage_opened_after_hours` | Garage changed from closed to open between 10 PM and 7 AM | `warning` |
| `garage_still_open_at_10pm` | Garage was already open at exactly 10 PM | `critical` |
| `doorbell_pressed` | Someone pressed the doorbell | `info` |
| `doorbell_person_detected` | Doorbell detected a person | `warning` |
| `doorbell_motion_detected` | Doorbell detected motion | `info` |

Note: Doorbell event types exist in the shared contract and display metadata, but docs state doorbell/eufy integration is later-stage and should not be wired yet.

#### `EventSeverity`

Client display severity values:

- `info`
- `warning`
- `critical`

These drive badge color and should be modeled as a Swift enum with an unknown fallback strategy for future backend additions.

#### `HomeAssistantEventCategory`

Inbound event category values:

- `garage`
- `doorbell`

Currently optional in payloads and stored events. Swift should decode optional category.

#### `HomeAssistantEventSeverity`

Inbound Home Assistant payload severity values:

- `normal`
- `high`

This is distinct from display severity. The backend maps event type to display severity using metadata. Swift should not conflate `normal/high` with `info/warning/critical`.

#### `EventDisplayMetadata`

Fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `title` | String | Default title for event type. |
| `body` | String | Default notification/event body for event type. |
| `severity` | `EventSeverity` | Client display severity. |

The API embeds this object into each stored event, so the Swift client can render server-provided display metadata. Keeping local metadata too is useful for offline preview/tests, but the API response should remain authoritative for timeline cards.

### API Models

#### `HomeAssistantEventPayload`

Inbound payload accepted by `POST /api/ha/events`:

| Field | Required | Type | Notes |
| --- | --- | --- | --- |
| `type` | Yes | `LevyHomeEventType` | Must be one of the shared event types. |
| `entityId` | Yes | String | Non-empty. Placeholder docs use `cover.main_garage_door`; real ID must come from Home Assistant. |
| `category` | No | `garage` or `doorbell` | Optional. Current garage docs send `garage`. |
| `severity` | No | `normal` or `high` | Optional inbound severity. |
| `source` | No | String | Docs use `home_assistant`. |
| `occurredAt` | No | ISO date string | Defaults to now if omitted. |
| `title` | No | String | Overrides display title when stored/pushed. Empty string becomes absent. |
| `message` | No | String | Overrides display body when stored/pushed. Empty string becomes absent. |
| `metadata` | No | JSON object | Must be a plain object when provided. |

#### `LevyHomeEvent`

Stored event returned to the mobile client:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | String | Server-generated UUID. |
| `type` | `LevyHomeEventType` | Event type. |
| `entityId` | String | Home Assistant entity ID. |
| `category` | Optional category | Optional because payload category is optional. |
| `severity` | Optional HA severity | Optional inbound payload severity. |
| `source` | Optional String | Usually `home_assistant`. |
| `occurredAt` | String | Event occurrence time; defaults server-side to current time. |
| `title` | Optional String | Stored as payload title or default display title. |
| `message` | Optional String | Stored as payload message or default display body. |
| `metadata` | Optional object | Arbitrary JSON object. Swift can model as `[String: JSONValue]` or omit until used. |
| `receivedAt` | String | Server receipt time. Timeline currently formats this. |
| `display` | `EventDisplayMetadata` | Default display metadata for event type. |
| `push` | `EventPushStatus` | Push attempt/skip metadata. |

Swift decoding recommendation:

- Use enums for known string fields, with graceful handling for unknown event types/severities if the backend expands before the app updates.
- Parse dates from ISO strings into `Date` in view models or use custom `Codable` decoding with `ISO8601DateFormatter`.
- Keep raw strings available for display if date parsing fails.
- Model `metadata` conservatively. The app does not currently render it, so it can be decoded as optional unstructured JSON later.

#### `EventPushStatus`

Fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `attempted` | Boolean | Whether the API attempted a push. |
| `skipped` | Boolean | Whether push was skipped. |
| `reason` | Optional String | Dedupe/no-device reason. Events tab displays only when skipped. |
| `ticketCount` | Optional Number | Expo push ticket count. Expo-specific. |
| `invalidTokenCount` | Optional Number | Invalid Expo token count. |

Swift migration note: `ticketCount` is Expo-specific. If backend moves to APNs, rename or supplement this with provider-neutral fields such as `sentCount`, `failedCount`, and `provider`.

#### API Response Models

| Endpoint | Response shape | Current client use |
| --- | --- | --- |
| `GET /health` | `{ ok, service, registeredDeviceCount, recentEventCount, uptimeSeconds }` | Not used by mobile. Useful for diagnostics. |
| `POST /api/devices/register` | `{ ok, registeredDeviceCount, device }` | Mobile uses `registeredDeviceCount`; TypeScript response type omits `device`. |
| `GET /api/events?limit=50` | `{ ok, events }` | Events tab renders `events`. |
| `POST /api/debug/send-test-push` | `{ ok, message, registeredDeviceCount, sentTicketCount, invalidTokenCount, tickets }` | Debug tab uses registered device count and sent ticket count. |
| `POST /api/ha/events` | `{ ok, event, dedupeKey, storedEventCount }` | Not called by mobile. Called by Home Assistant/curl. |

### Configuration Models

#### Mobile App Configuration

| Config | Current source | Notes for SwiftUI |
| --- | --- | --- |
| App name | `apps/mobile/app.json`: `Levy Home` | Use Xcode target display name. Generated iOS `Info.plist` currently says `levy-home-app`, so decide final display name during native setup. |
| Slug | `levy-home` | Expo-only. |
| Scheme | `levyhome` | Preserve only if deep links are needed. Current app has no custom deep-link flow beyond Expo defaults. |
| Platforms | `ios` only | Native rewrite should be iOS-only. |
| Orientation | Portrait | Preserve unless product changes. |
| Tablet support | `supportsTablet: false` | Native target can remain iPhone-only initially. |
| Bundle ID | Expo mobile config: `com.levy.home`; root app config: `com.joshaaronlevy.levyhomeapp`; generated native project uses build settings | Choose one canonical bundle ID for the SwiftUI app. This affects APNs, provisioning, and app identity. |
| EAS project ID | `08eca4d3-53fd-40ab-947c-d8e0db05c8eb` | Expo-only. Remove for pure SwiftUI/APNs. |
| Encryption flag | `ITSAppUsesNonExemptEncryption: false` | Preserve if accurate. |
| User interface style | Expo config says automatic; generated native Info.plist says light | Decide whether native app supports dark mode. Current styling is light-only in practice. |

#### API Runtime Configuration

| Variable | Current default/example | Sensitivity | Notes |
| --- | --- | --- | --- |
| `PORT` | `4000` | Non-secret | API listen port. |
| `LEVY_HOME_HA_WEBHOOK_SECRET` | `dev-secret` in example | Secret | Used only server-side to authenticate Home Assistant webhook. Never ship in the iOS app. |
| `PUSH_DEDUPE_COOLDOWN_MS` | `120000` | Non-secret | Server-side dedupe cooldown by event type/entity ID. |
| `EXPO_ACCESS_TOKEN` | Empty optional | Secret-ish | Expo push provider credential. Remove if moving to APNs. |

#### Mobile Runtime Configuration

| Variable | Current default/example | Sensitivity | Notes |
| --- | --- | --- | --- |
| `EXPO_PUBLIC_API_URL` | `http://localhost:4000` | Non-secret | Client API base URL. In native app, model as build configuration or debug setting. Do not hardcode production API URLs inside views. |

### Persistent Settings

Current app:

- No `AsyncStorage` usage.
- No secure storage usage.
- No local event cache.
- No persisted push registration state.
- API stores registered devices and recent events in process memory only.

SwiftUI recommendation:

- Use `UserDefaults` for non-sensitive local preferences such as selected API environment or debug toggles.
- Use Keychain only for actual secrets or tokens. APNs device tokens are not user secrets in the same sense as auth tokens, but if the app later stores user auth credentials, those must go to Keychain.
- Do not store `LEVY_HOME_HA_WEBHOOK_SECRET` in the app.
- Consider a small local event cache only after network parity is complete. It is not required for MVP parity.

### Implicit Models Inferred From Usage

| Implicit model | Current representation | Suggested Swift model |
| --- | --- | --- |
| Push registration state | Union of `status`, `statusMessage`, `pushToken`, `error` | `PushRegistrationState` with enum status and display message. |
| Device registration request | `{ pushToken, platform: ios }` | `DeviceRegistrationRequest`; rename field later if APNs tokens are accepted. |
| Registered device | API-local `RegisteredDevice` | Backend model, not required in client except optional debug decode. |
| Recent event collection | API-local array capped at 100 | `EventsViewModel.events`. Backend persistence should be solved server-side later. |
| Dedupe cache | API-local `Map<dedupeKey, timestamp>` | Backend concern. |
| Notification payload data | `{ eventType, entityId, dedupeKey }` or `{ source: debug }` | `NotificationPayload` for native notification response handling if deep-linking to Events is added. |
| Theme tokens | Repeated `StyleSheet` constants | `AppTheme` or simple color constants. |
| API error envelope | `{ error: string }` | `APIErrorResponse`. |
| Debug test push result | `registeredDeviceCount`, `sentTicketCount`, etc. | Provider-neutral `PushTestResult` if backend changes. |

## 5. Integration Inventory

### Home Assistant Integrations

Current integration point:

```text
POST /api/ha/events
Authorization: Bearer <LEVY_HOME_HA_WEBHOOK_SECRET>
Content-Type: application/json
```

The current docs define five MVP garage automations:

| Levy event type | Trigger | Conditions | Notes |
| --- | --- | --- | --- |
| `garage_opened` | Garage changes closed to open | Normal hours only when avoiding duplicate after-hours alerts | Push during MVP. |
| `garage_closed` | Garage changes open to closed | None | Push during MVP; may become timeline-only later. |
| `garage_left_open_10_min` | Garage remains open for 10 minutes | None | High-priority alert. |
| `garage_opened_after_hours` | Garage changes closed to open | Between 10 PM and 7 AM | Distinct from the 10 PM still-open check. |
| `garage_still_open_at_10pm` | Time is 10:00 PM | Garage is open | Catches garage already open at bedtime. |

Important assumptions from docs:

- `cover.main_garage_door` is a placeholder only.
- The real Meross garage entity ID must be discovered in Home Assistant Developer Tools > States.
- Expected cover states are `open` and `closed`, but they must be confirmed before live wiring.
- The after-hours window is 10 PM through 7 AM in Home Assistant local time.
- `garage_opened_after_hours` and `garage_still_open_at_10pm` are intentionally separate automations.
- Eufy/doorbell events are placeholders only and should not be wired yet.

SwiftUI migration implication:

- The SwiftUI client does not call the Home Assistant webhook directly.
- The Home Assistant secret must remain server-side.
- The event types and display behavior must be preserved in Swift models/UI.

### Notifications

Current notification flow:

```text
Expo app asks for permission
-> Expo app obtains Expo push token
-> Expo app posts token to /api/devices/register
-> API validates token with Expo.isExpoPushToken
-> API sends push with expo-server-sdk
```

Current notification behavior:

- Requires a physical iOS device with an EAS development build.
- Requests notification permission if not already granted.
- Shows alert/banner/list and plays sound.
- Does not set badge.
- Push data for HA events includes `eventType`, `entityId`, and `dedupeKey`.
- Push data for debug events includes `source: debug`.
- No notification tap routing is implemented in the current app.

SwiftUI migration implication:

- Native app should use `UNUserNotificationCenter` for permission and presentation options.
- Native app should use APNs token registration through `UIApplication.registerForRemoteNotifications()`.
- Backend must be updated to accept and send to APNs device tokens, or an interim push gateway must translate/bridge. Expo push tokens will not exist in a pure SwiftUI app.
- If keeping the current API route temporarily, define whether `pushToken` means Expo token, APNs token, or a provider-neutral device token. Prefer a versioned/provider-aware device registration model before production.

### Networking

Current mobile networking:

- `fetch` against `API_BASE_URL`.
- JSON `Accept` and `Content-Type` headers on all requests.
- Parses response text as JSON when present.
- Throws an `Error` with `data.error` or HTTP status fallback.
- No retries, timeout handling, request cancellation, auth headers, or offline cache.

Endpoints used by the mobile app:

| Method | Path | Used by | Auth |
| --- | --- | --- | --- |
| `POST` | `/api/devices/register` | Push registration | None |
| `GET` | `/api/events` | Events timeline | None |
| `POST` | `/api/debug/send-test-push` | Debug tab | None |

Endpoints not used by the mobile app but relevant:

| Method | Path | Used by | Auth |
| --- | --- | --- | --- |
| `POST` | `/api/ha/events` | Home Assistant/curl | Bearer `LEVY_HOME_HA_WEBHOOK_SECRET` |
| `GET` | `/health` | Operations/debug | None |

SwiftUI migration implication:

- Use `URLSession` with `async/await`.
- Keep a tiny `APIClient` with typed methods.
- Add timeout and better error classification if useful, but avoid a large networking framework.
- Keep authentication out of the app for now unless product scope changes.

### Authentication And Authorization

Current state:

- Only `POST /api/ha/events` is protected.
- The Home Assistant webhook uses a static bearer secret from server environment.
- There is no user login.
- There is no per-device/user identity beyond the registered push token.
- `/api/events`, `/api/devices/register`, `/api/debug/send-test-push`, and `/health` are unauthenticated.

SwiftUI migration implication:

- Do not introduce user auth in the native client during parity migration unless the product scope changes.
- Never include the Home Assistant webhook secret in the app.
- For production readiness, consider protecting debug endpoints or excluding Debug from release builds.
- If the API becomes internet-accessible, revisit `/api/events` exposure before shipping broadly.

### Local Storage

Current state:

- Mobile: no local storage.
- API: registered devices, recent events, and dedupe timestamps are in memory.
- API restart loses device registrations, event timeline, and dedupe history.

SwiftUI migration implication:

- MVP parity does not require local persistence.
- Use `UserDefaults` for non-sensitive preferences only.
- Use Keychain for future auth tokens/secrets.
- Server-side persistence is more important than client-side persistence for registered devices and recent timeline durability.

### Native Capabilities

Current Expo/native capabilities:

| Capability | Current state | SwiftUI migration action |
| --- | --- | --- |
| Push notifications | Via `expo-notifications`; no custom entitlement file entries visible in generated entitlement file | Add Push Notifications capability and APNs provisioning in Xcode. |
| Physical device push testing | Required for meaningful push token | Still required for APNs end-to-end testing. |
| Local network access | Generated Info.plist allows local networking for Expo dev launcher | Native debug builds may need local network allowance if calling a LAN API over HTTP. Production should use HTTPS. |
| URL schemes | Expo-generated schemes present | Preserve `levyhome` only if app links/deep links are part of product. |
| Status bar | Dark style | Use native app styling. |
| Splash/icon assets | `icon.png` and `splash-icon.png` | Reuse or recreate in native asset catalog. |
| Orientation | Portrait in Expo config, generated native project supports all orientations | Choose native target orientations intentionally, likely portrait-only at first. |
| Tablet | `supportsTablet: false` | iPhone-only initially. |
| Privacy manifest | Generated Expo manifest declares UserDefaults, file timestamp, boot time access | Native app needs a fresh privacy manifest based on actual APIs used. |

## 6. Environment Configuration

### Environment Variables

| Name | Current owner | Example/default | Must not be hardcoded in SwiftUI app? | Notes |
| --- | --- | --- | --- | --- |
| `EXPO_PUBLIC_API_URL` | Mobile | `http://localhost:4000` | Yes, avoid hardcoding in views | Replace with build setting, Info.plist value, or debug setting. It is not secret, but should be configurable by environment. |
| `PORT` | API | `4000` | Not applicable | Server runtime config. |
| `LEVY_HOME_HA_WEBHOOK_SECRET` | API/Home Assistant | `dev-secret` in example | Absolutely must not be in app | Server-only secret for Home Assistant webhook. |
| `PUSH_DEDUPE_COOLDOWN_MS` | API | `120000` | Not applicable | Server-side dedupe behavior. |
| `EXPO_ACCESS_TOKEN` | API | Empty optional | Must not be in app | Remove when moving off Expo push service. |

### Secrets

Secrets that must remain out of the SwiftUI app:

- `LEVY_HOME_HA_WEBHOOK_SECRET`
- Any production Home Assistant token/credential
- `EXPO_ACCESS_TOKEN` while Expo push exists
- Future APNs signing key/private key, if APNs is implemented server-side using token auth
- Future user auth refresh tokens, unless stored in Keychain on-device

### Runtime Configuration

Native app should have a small runtime/build config model:

| Config | Recommendation |
| --- | --- |
| API base URL | Read from build settings/Info.plist for production and optionally allow a Debug-only override in UserDefaults. |
| Build flavor | Use Debug/Release or explicit schemes such as Local, Staging, Production if needed. |
| Push provider | Avoid exposing provider details in views. The app should register for native push; backend handles provider-specific delivery. |
| Debug tab availability | Keep in Debug builds. Consider hiding in Release unless intentionally available to family users. |
| Display strings for event metadata | Prefer server response for timeline; keep local fallback constants for resilience/tests. |

### Values Not To Hardcode In SwiftUI

Do not hardcode these inside SwiftUI views or source files that would need code edits per environment:

- Production API base URL
- Home Assistant webhook secret
- Home Assistant entity IDs such as the real garage door entity
- APNs credentials
- Future user credentials or tokens
- Family-specific device names or assumptions
- Dedupe cooldown values that should remain server-configurable

It is acceptable to include non-secret placeholder values in docs and test data, such as `cover.main_garage_door`, as long as they are clearly marked as placeholders.

## 7. Migration Complexity Assessment

Classification scale:

| Level | Meaning |
| --- | --- |
| Trivial | Static UI or direct SwiftUI equivalent with no meaningful behavior. |
| Easy | Small feature with one service call or local state, low risk. |
| Moderate | Multiple states, async work, model decoding, or small backend coordination. |
| Complex | Requires native capability work, backend contract changes, or production hardening. |
| High Risk | Core delivery path or ambiguous external integration where mistakes can break notifications/security. |

### Feature Complexity Table

| Feature | Complexity | Why |
| --- | --- | --- |
| Tab navigation | Trivial | Current app has four flat tabs and no nested navigation. SwiftUI `TabView` maps cleanly. |
| Home status screen | Trivial | Static header plus two status panels. Depends only on shared push registration state and API config. |
| Settings read-only screen | Trivial | Static rows. No editing or persistence today. |
| Not found fallback | Trivial | Not required unless native deep-link routing is added. |
| Theme/color parity | Easy | Colors and spacing are repeated but simple. A small theme file is enough. |
| Event card UI | Easy | Straightforward rendering of decoded event fields and severity badge. |
| Events empty/error states | Easy | Local view model state maps to SwiftUI conditional UI. |
| Pull-to-refresh events | Easy | SwiftUI `.refreshable` maps directly to current behavior. |
| API client for `/api/events` | Easy | One unauthenticated JSON GET with small response model. |
| API client for test push | Easy | One unauthenticated POST with small response model. |
| API error handling | Moderate | Current JS throws plain strings. Swift should classify URL, HTTP, decoding, and server-envelope errors. |
| Date parsing/formatting | Moderate | Current JS accepts loose Date parsing. Swift should parse ISO strings deliberately and handle malformed dates gracefully. |
| Push registration UI state | Moderate | Shared app-level state, launch side effect, retry behavior, permission denial, and API registration errors. |
| Native notification permission | Moderate | `UNUserNotificationCenter` is straightforward, but requires careful user messaging and app lifecycle integration. |
| APNs device token registration | Complex | Requires app delegate bridging in SwiftUI, provisioning, entitlements, physical device testing, token refresh handling, and backend support. |
| Backend push provider migration | High Risk | Current backend only understands Expo push tokens and uses `expo-server-sdk`. Pure SwiftUI needs APNs support or a push-provider transition strategy. This is the main migration risk. |
| Home Assistant event API contract | Easy | Client only reads stored events. Existing server validation can remain unchanged. |
| Home Assistant automation behavior | Moderate | Not implemented in app, but product correctness depends on event mapping, real entity ID, and timezone/state verification. |
| Push dedupe display | Easy | Client only displays skip reason if server marks event as skipped. Backend remains owner. |
| Recent event timeline durability | Complex if changed, Easy if not | Current parity is easy because events stay server-memory only. Production persistence would require backend storage design. |
| Device registration persistence | Complex if productionized | Current in-memory server device map is prototype-grade. Native migration can preserve behavior, but production needs server persistence and token invalidation. |
| Debug tab parity | Moderate | UI is simple, but test push semantics change when leaving Expo tickets for APNs results. |
| Production auth | High Risk if added | Current scope excludes auth. Adding it would affect API, app security, storage, and UX. Do not combine with initial migration. |
| Release build configuration | Moderate | Need canonical bundle ID, Info.plist values, APNs capability, HTTPS API URL, and Debug tab decision. |
| Local development over LAN | Moderate | Native app needs configurable API URL and possibly local network/ATS allowances for HTTP LAN testing. |
| Doorbell placeholders | Easy for model support, Complex when real integration starts | Event types already exist, but reliable eufy/Home Assistant signals are explicitly deferred. |

### Highest-Risk Areas

1. Push provider transition from Expo to APNs.
2. Backend persistence for device registrations and event timeline if the app is expected to survive API restarts.
3. Public exposure of unauthenticated event/debug endpoints if the API moves beyond local/private use.
4. Correct Home Assistant garage entity/state/timezone configuration.
5. Choosing and preserving the final iOS bundle ID before APNs provisioning and TestFlight/App Store setup.

## 8. SwiftUI Migration Recommendations

### Recommended Architecture

Keep the SwiftUI app small and direct:

```text
LevyHomeApp
|-- AppEnvironment
|   |-- APIClient
|   |-- NotificationService
|   `-- AppConfig
|-- Views
|   |-- HomeView
|   |-- EventsView
|   |-- SettingsView
|   `-- DebugView
|-- ViewModels
|   |-- PushRegistrationViewModel
|   |-- EventsViewModel
|   `-- DebugViewModel
|-- Models
|   |-- LevyHomeEvent
|   |-- EventDisplayMetadata
|   |-- EventPushStatus
|   |-- EventType
|   `-- API response/request models
`-- Services
    |-- APIClient
    |-- NotificationService
    `-- SettingsStore
```

This is enough. Do not add Redux, Flux, coordinators, dependency injection frameworks, TCA, or enterprise patterns. The current app does not justify them.

### App State And Observation

Use one of these two native patterns:

| Pattern | When to use |
| --- | --- |
| `ObservableObject` with `@StateObject`/`@ObservedObject` | Safe choice for broad iOS version compatibility and familiar SwiftUI behavior. |
| Modern Observation (`@Observable`) | Good choice if the new app targets iOS 17+ and the team wants the current SwiftUI observation model. |

Recommended state ownership:

| State | Owner |
| --- | --- |
| Push registration status/token/error | App-level `PushRegistrationViewModel`. |
| Events list/loading/error | `EventsViewModel` owned by `EventsView`. |
| Test push sending/last result | `DebugViewModel` or local state in `DebugView`. |
| API base URL/config | `AppConfig` injected into services, displayed by Home/Settings/Debug. |
| Non-sensitive debug settings | `SettingsStore` backed by `UserDefaults`. |

### View Models

#### `PushRegistrationViewModel`

Responsibilities:

- Request notification permission.
- Register with APNs.
- Receive APNs device token from native app delegate bridge.
- Register device token with API.
- Expose status, message, token display string, error, and retry action.
- Avoid repeatedly spamming permission prompts or registration calls.

Status enum should preserve current user-facing states:

- `idle`
- `registering`
- `registered`
- `unavailable`
- `error`

#### `EventsViewModel`

Responsibilities:

- Load recent events on first view appearance.
- Refresh on pull-to-refresh.
- Track loading and error states.
- Decode `LevyHomeEvent` models.
- Format event timestamps for display, or expose parsed dates to views.

Keep this view model small. It only needs an `APIClient` and perhaps a date formatter.

#### `DebugViewModel`

Responsibilities:

- Trigger manual push registration through `PushRegistrationViewModel` or `NotificationService`.
- Call test push endpoint.
- Track sending state and last response/error.
- Provide alert content for success/failure.

If Debug remains development-only, guard it by build configuration rather than building complex permissions around it.

### Services

#### `APIClient`

Use `URLSession` with `async/await`.

Recommended responsibilities:

- Hold base URL from `AppConfig`.
- Build URL requests.
- Encode request bodies.
- Decode typed responses.
- Decode server error envelope `{ error: string }` when present.
- Surface clean `APIError` cases: invalid URL, transport error, non-2xx status, server error message, decoding error.

Initial methods:

| Method | Endpoint |
| --- | --- |
| Register device | `POST /api/devices/register` |
| Fetch recent events | `GET /api/events` |
| Send test push | `POST /api/debug/send-test-push` |
| Optional health check | `GET /health` |

#### `NotificationService`

Use native iOS APIs:

- `UNUserNotificationCenter.current().getNotificationSettings()`
- `UNUserNotificationCenter.current().requestAuthorization(options:)`
- `UIApplication.shared.registerForRemoteNotifications()` through an app lifecycle bridge
- App delegate callbacks for successful/failed APNs registration
- Foreground notification presentation policy matching current behavior: alert/banner/list and sound, no badge by default

Keep notification routing minimal initially. Current app does not deep-link from notifications. If notification taps are added later, route to Events tab and optionally highlight/filter by event ID/type if the backend sends enough data.

#### `SettingsStore`

Use `UserDefaults` for:

- Debug API base URL override, if desired.
- Last selected environment, if multiple environments exist.
- Non-sensitive UI preferences, if added later.

Use Keychain for:

- Future user auth tokens.
- Future API secrets that truly need local storage.

Do not store the Home Assistant webhook secret in the app.

### Models

Create Swift models manually from the shared TypeScript contract:

| Swift model | Source concept |
| --- | --- |
| `LevyHomeEvent` | `LevyHomeEvent` |
| `EventType` | `LevyHomeEventType` |
| `EventDisplayMetadata` | `EventDisplayMetadata` |
| `DisplaySeverity` | `EventSeverity` |
| `HomeAssistantCategory` | `HomeAssistantEventCategory` |
| `HomeAssistantPayloadSeverity` | `HomeAssistantEventSeverity` |
| `EventPushStatus` | `EventPushStatus` |
| `RegisterDeviceResponse` | Mobile API response type |
| `EventsResponse` | Mobile API response type |
| `TestPushResponse` | Mobile API response type, later provider-neutral |
| `APIErrorResponse` | Server error envelope |

Modeling guidance:

- Conform response models to `Codable`.
- Conform UI-facing event models to `Identifiable` where useful.
- Keep raw string fallback for unknown enum values if forward compatibility matters.
- Do not model arbitrary `metadata` deeply until the UI uses it.

### Persistence Strategy

For MVP parity:

- Do not add Core Data, SwiftData, SQLite, or Realm.
- Fetch events from the API when the Events view loads or refreshes.
- Keep app-level push registration state in memory.
- Store only non-sensitive settings in `UserDefaults` if needed.
- Store secrets/tokens in Keychain only when actual user auth or sensitive credentials are introduced.

For production hardening, prioritize backend persistence:

| Backend data | Current storage | Recommended production direction |
| --- | --- | --- |
| Registered devices | In-memory `Map` | Durable database table keyed by token/device ID, with last seen and provider. |
| Recent events | In-memory array capped at 100 | Durable event table with retention policy. |
| Push dedupe timestamps | In-memory `Map` | Durable/cache-backed dedupe store if dedupe must survive restarts. |

### Notification Strategy

Recommended native direction:

1. Add native APNs registration to the SwiftUI app.
2. Update backend device registration to store provider-aware tokens, for example provider `apns` with device token and environment `sandbox`/`production`.
3. Replace or supplement `expo-server-sdk` with APNs sending on the server.
4. Keep current notification title/body/data semantics.
5. Keep push dedupe server-side.
6. Keep foreground presentation equivalent: sound and visible alert/list/banner, no badge unless product requests badges.

Transitional options:

| Option | Pros | Cons | Recommendation |
| --- | --- | --- | --- |
| Keep Expo push service | Least backend change if using Expo runtime | Not compatible with pure SwiftUI APNs tokens without an Expo client/runtime | Not recommended for pure native. |
| Add APNs while keeping old Expo endpoint fields | Fastest native path | Ambiguous `pushToken` semantics | Acceptable only as short-lived migration. |
| Version device registration/provider model | Clean contract and future-proofing | Small backend change required | Recommended. |

### Error-Handling Strategy

User-facing principles:

- Keep messages actionable and short.
- Preserve server error messages for debug screens.
- Avoid leaking secrets or raw credentials.
- Distinguish permission denied, simulator/unavailable push, network failure, server failure, and decoding failure.

Recommended error categories:

| Category | Example UI message |
| --- | --- |
| Notification permission denied | `Push notification permission was not granted.` |
| Remote notification unavailable | `Push notifications require a physical device and a valid APNs setup.` |
| API unreachable | `Unable to reach the Levy Home API.` |
| Server error envelope | Use server-provided `error` when safe. |
| Decoding error | `The API returned an unexpected response.` |
| Test push failed | `Unable to send test push.` plus debug detail in Debug. |

Events screen can keep the current error banner pattern. Debug can show more technical details because it is a diagnostic screen.

### Testing Strategy

Keep testing focused and proportional.

Recommended initial tests:

| Layer | Tests |
| --- | --- |
| Model decoding | Decode representative `LevyHomeEvent` JSON for each garage event type and one doorbell placeholder. |
| API client | Use `URLProtocol` stubs to test success, server error envelope, HTTP error, invalid JSON, and empty responses where applicable. |
| View models | Test push registration state transitions with mocked notification/API services; test events load success/error/refresh behavior. |
| Date formatting | Test valid ISO string and malformed date fallback. |
| Notification service | Unit test wrapper state where possible; manual/device testing for APNs callbacks. |
| UI smoke | Optional SwiftUI previews for Home, Events empty/error/list, Settings, Debug. |
| End-to-end manual | Physical iPhone APNs registration, fake garage curl event, push receipt, timeline refresh. |

Do not overbuild UI automation at the beginning. The riskiest behavior is push delivery, which needs real-device manual verification even with unit coverage.

## 9. Staged Migration Roadmap

### Stage 0: Decisions And Native Project Baseline

| Field | Details |
| --- | --- |
| Goal | Establish the SwiftUI project identity and migration constraints before writing feature code. |
| Deliverables | Native SwiftUI project in `levy-home`; canonical bundle ID; deployment target; app display name; portrait/iPhone support decision; Debug/Release config; initial asset catalog using current icon/splash assets or approved replacements. |
| Dependencies | Apple developer account/provisioning access; decision on final bundle ID (`com.levy.home` vs existing generated/root alternatives). |
| Risks | Changing bundle ID later will complicate APNs, installed app identity, TestFlight, and future releases. |
| Estimated difficulty | Moderate |
| Acceptance criteria | App launches to a placeholder SwiftUI tab shell on simulator/device; project has no Expo/React Native dependencies; config values are not hardcoded in views. |

### Stage 1: Domain Models And API Client

| Field | Details |
| --- | --- |
| Goal | Recreate the event/API contract natively. |
| Deliverables | Swift `Codable` models for events, display metadata, push status, responses, and errors; `APIClient` with `fetchRecentEvents`, `registerDevice`, and `sendTestPush`; basic config model for API base URL. |
| Dependencies | Existing `packages/shared` contract; current API routes. |
| Risks | Enum/date decoding mismatches can break the timeline. Current JS date parsing is permissive; Swift should be stricter but user-friendly on failure. |
| Estimated difficulty | Easy to Moderate |
| Acceptance criteria | Unit tests or local stubs decode representative API JSON; API client can call local `/api/events`; server error envelopes surface readable messages. |

### Stage 2: SwiftUI Tab Shell And Static Screens

| Field | Details |
| --- | --- |
| Goal | Match the current navigation and low-risk read-only UI. |
| Deliverables | `TabView` with Home, Events, Settings, Debug; theme constants; Home and Settings parity UI; SF Symbol tab icons. |
| Dependencies | Stage 0 config and Stage 1 app config. |
| Risks | Low. Need to preserve compact operational style and avoid accidental product expansion. |
| Estimated difficulty | Trivial to Easy |
| Acceptance criteria | Home shows app copy, push status placeholder, and API URL; Settings shows API URL, platform, and data model; tab labels/icons match current app. |

### Stage 3: Events Timeline

| Field | Details |
| --- | --- |
| Goal | Ship read-only timeline parity. |
| Deliverables | `EventsViewModel`; Events screen load-on-appear; pull-to-refresh; empty state; error banner; event card UI with severity badges, entity ID, received time, and push skip reason. |
| Dependencies | Stage 1 API client/models; Stage 2 theme/UI shell; local API running. |
| Risks | Date formatting and decoding optional/unexpected fields. Backend still has in-memory data only. |
| Estimated difficulty | Easy |
| Acceptance criteria | Sending fake garage events to the API appears in the native Events tab after load/refresh; empty and error states can be reproduced; all severity styles are legible. |

### Stage 4: Native Push Registration

| Field | Details |
| --- | --- |
| Goal | Replace Expo push token registration with APNs registration in the SwiftUI app. |
| Deliverables | `NotificationService`; app delegate bridge for APNs callbacks; permission request flow; push registration state model; Home/Debug status integration; manual retry action. |
| Dependencies | Apple developer provisioning; Push Notifications capability; physical device; backend contract decision for APNs tokens. |
| Risks | Complex native lifecycle and provisioning work. This is not just a UI migration because Expo tokens disappear. |
| Estimated difficulty | Complex |
| Acceptance criteria | On a physical iPhone, the app requests notification permission, receives an APNs device token, registers it with the API or APNs-aware registration endpoint, and shows registered status. Permission denied and registration failure states are visible and recoverable. |

### Stage 5: Backend Push Provider Transition

| Field | Details |
| --- | --- |
| Goal | Ensure Home Assistant events can push native SwiftUI clients. |
| Deliverables | API update for provider-aware device registration; APNs sending implementation; sandbox/production environment handling; provider-neutral push send result model; invalid token cleanup strategy; debug test push adapted to APNs. |
| Dependencies | APNs key/certificate choice; server deployment environment; Stage 4 app token registration. |
| Risks | High. Mistakes break the core notification promise. APNs credentials must remain server-side. Expo-specific response fields need migration. |
| Estimated difficulty | High Risk |
| Acceptance criteria | Fake garage event triggers an APNs push on a physical device; debug test push works; invalid token behavior is logged/handled; Expo dependencies are no longer required for native push delivery. |

### Stage 6: Debug Screen Parity

| Field | Details |
| --- | --- |
| Goal | Restore developer diagnostics in native UI. |
| Deliverables | Debug screen showing API URL, push registration status/error, APNs token display, register action, send test push action, loading state, last response, and alerts. |
| Dependencies | Stages 4 and 5. |
| Risks | Debug UI can leak too much provider/token detail if shipped to family users. Decide Debug availability per build. |
| Estimated difficulty | Moderate |
| Acceptance criteria | Debug screen can retry registration and send test push; success/failure messages are clear; Release behavior is decided and implemented. |

### Stage 7: End-To-End Garage Flow Verification

| Field | Details |
| --- | --- |
| Goal | Validate the native app against the actual MVP product flow. |
| Deliverables | Manual QA checklist; curl scripts or documented commands; verified handling for all five garage event types; screenshots or notes for empty/error/list states. |
| Dependencies | Local or deployed API; physical iPhone; Stage 5 push support; Home Assistant entity/state assumptions if testing real automations. |
| Risks | Home Assistant entity ID/timezone/state assumptions can produce false negatives. Dedupe cooldown can make repeated tests look broken. |
| Estimated difficulty | Moderate |
| Acceptance criteria | Each garage event type can be sent manually; push arrives when expected; dedupe skip reason appears when expected; timeline shows newest-first events; Home/Settings/Debug reflect the correct environment. |

### Stage 8: Production Readiness Pass

| Field | Details |
| --- | --- |
| Goal | Decide which MVP prototype limitations must be fixed before real family use. |
| Deliverables | API HTTPS requirement; release API URL config; Debug tab release policy; backend persistence decision; endpoint exposure/auth review; privacy manifest; notification copy review; TestFlight build. |
| Dependencies | Product decision on deployment scope and who can access the API. |
| Risks | Shipping with unauthenticated timeline/debug endpoints or in-memory device storage may be acceptable for local-only testing but weak for internet-facing production. |
| Estimated difficulty | Moderate to Complex depending on scope |
| Acceptance criteria | Release build points at the intended API; secrets are absent from the app; APNs works from production environment; app survives API restart according to agreed expectations or documents limitations clearly. |

### Stage 9: Later Doorbell/Event Expansion

| Field | Details |
| --- | --- |
| Goal | Add later event types only after the garage MVP is stable. |
| Deliverables | Confirmed Home Assistant/eufy signals; updated event docs; UI handling for doorbell event category; any notification copy changes. |
| Dependencies | Reliable doorbell integration in Home Assistant. |
| Risks | Doorbell/eufy reliability is unknown and explicitly out of current scope. Avoid mixing this into the native parity migration. |
| Estimated difficulty | Easy for UI/model support, Complex for real integration reliability |
| Acceptance criteria | Doorbell events are generated reliably by Home Assistant, delivered through the API, pushed to native devices, and displayed in the timeline without degrading garage flows. |

## Recommended Initial Cut Line

The first SwiftUI milestone should be:

1. Native project identity is settled.
2. Home, Settings, and Events tabs are functional.
3. Events tab reads from the existing API.
4. Push registration is stubbed or shows a clear unavailable/native-pending status.

The second milestone should tackle APNs and backend push migration as a focused vertical slice. That keeps the UI/model migration separate from the highest-risk infrastructure change.

## Open Questions Before Implementation

| Question | Why it matters |
| --- | --- |
| What is the final bundle ID for the native SwiftUI app? | APNs provisioning and installed app identity depend on it. |
| Should the Debug tab ship in Release builds? | Current debug actions are useful but expose internals and unauthenticated test push behavior. |
| Will the API remain local/private or become internet-accessible? | Determines urgency of HTTPS, auth, event endpoint exposure, and persistence hardening. |
| Should the backend be migrated off Expo push during the SwiftUI rebuild or in a separate backend stage? | Pure native push requires APNs support; this is the main cross-cutting dependency. |
| Does the app need dark mode parity? | Current Expo config says automatic, but implemented styles and generated Info.plist are effectively light. |
| Should event timeline persist locally for offline reading? | Not required for MVP parity, but could improve UX once backend persistence exists. |
| What is the real Home Assistant garage entity ID and state vocabulary? | Docs intentionally use `cover.main_garage_door` as a placeholder only. |

## Summary Recommendation

Rebuild the mobile client as a small native SwiftUI app with `TabView`, simple observable view models, `URLSession` networking, native APNs registration, and a tiny settings/config layer. Keep the event timeline contract and Home Assistant event semantics intact. Do not introduce a broad architecture framework or production auth during the first UI migration.

Treat push delivery as the central architectural migration, not as a screen-level detail. The current app registers Expo push tokens; the SwiftUI app will register APNs tokens. Plan backend APNs support as its own stage with real-device acceptance criteria before claiming parity with the Expo implementation.
