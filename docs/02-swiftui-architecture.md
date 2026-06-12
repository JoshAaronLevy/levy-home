# SwiftUI Target Architecture

This document defines the target architecture for rebuilding the Levy Home mobile app as a native iOS-only SwiftUI application in `levy-home`.

It builds on `docs/01-migration-discovery.md` and does not repeat the full discovery inventory. The current Expo/React Native app in `levy-home-app` remains the product reference. The first native migration replaces only the mobile client. The existing Node/Express API may remain during the first phase.

The architecture intentionally separates three workstreams:

1. UI/client parity work: rebuild the tabs, models, API client, timeline, settings, and debug UI in SwiftUI.
2. Native APNs registration work: replace Expo mobile push-token registration with native iOS notification permission and APNs device-token registration.
3. Backend push-provider migration work: update the API push provider from Expo push tokens to APNs-capable delivery.

These workstreams should not be collapsed into one milestone. Client parity can progress against the existing API before native push delivery is complete.

## 1. Architecture Summary

### Target Shape

The SwiftUI app should be a small native client with a flat tab structure, a tiny service layer, Swift `Codable` models, and simple observable state.

```text
SwiftUI app
-> TabView UI
-> ViewModels for screen state
-> Services for API/config/notifications/settings
-> Existing Node/Express API during initial migration
-> APNs-aware backend after push-provider migration
```

### Primary Responsibilities

| Layer | Responsibilities | Explicitly not responsible for |
| --- | --- | --- |
| SwiftUI views | Render Home, Events, Settings, Debug; route tab selection; show loading/error/empty states | Networking details, APNs credentials, Home Assistant webhook secrets |
| View models | Own screen state, call services, expose display-ready values | Global state frameworks, backend business rules |
| Services | API calls, notification registration, configuration lookup, non-sensitive settings | UI layout, Home Assistant automation logic |
| Models | Decode API responses and represent app domain values | Server-side validation of Home Assistant webhook payloads |
| Backend API | Receive Home Assistant events, store timeline/devices, send push notifications | Native UI state or local iOS storage |

### Migration Boundaries

| Workstream | Goal | Can ship before APNs backend migration? | Notes |
| --- | --- | --- | --- |
| UI/client parity | Native app renders the current mobile experience and reads events from the existing API | Yes | Events timeline, Home, Settings, and much of Debug can work with push status marked pending/unavailable. |
| Native APNs registration | App requests notification permission and obtains APNs device token | Partially | App can obtain token once entitlements/provisioning are ready, but end-to-end pushes require backend support. |
| Backend push-provider migration | API accepts APNs-aware registrations and sends APNs pushes | No, for push parity | This is the core risk and should be tested as its own vertical slice. |

### Non-Goals For Initial Architecture

- No TCA, Redux, Flux, coordinator framework, dependency injection framework, or enterprise layering.
- No production user authentication during the client parity stage.
- No Home Assistant dashboard, camera view, automation builder, or device control UI.
- No client storage of Home Assistant webhook secrets.
- No Core Data, SwiftData, SQLite, Realm, or local event database for MVP parity.
- No mechanical translation of React components into Swift files.

## 2. Final Folder Structure

Recommended project structure after the native SwiftUI project exists:

```text
levy-home/
|-- LevyHome/
|   |-- App/
|   |   |-- LevyHomeApp.swift
|   |   |-- AppEnvironment.swift
|   |   |-- AppConfig.swift
|   |   |-- AppDelegate.swift
|   |   `-- BuildConfiguration.swift
|   |-- Views/
|   |   |-- Root/
|   |   |   `-- RootTabView.swift
|   |   |-- Home/
|   |   |   `-- HomeView.swift
|   |   |-- Events/
|   |   |   |-- EventsView.swift
|   |   |   |-- EventCardView.swift
|   |   |   `-- SeverityBadgeView.swift
|   |   |-- Settings/
|   |   |   `-- SettingsView.swift
|   |   |-- Debug/
|   |   |   `-- DebugView.swift
|   |   `-- Shared/
|   |       |-- InfoPanel.swift
|   |       |-- LoadingStateView.swift
|   |       `-- ErrorBannerView.swift
|   |-- ViewModels/
|   |   |-- PushRegistrationViewModel.swift
|   |   |-- EventsViewModel.swift
|   |   `-- DebugViewModel.swift
|   |-- Models/
|   |   |-- EventType.swift
|   |   |-- EventSeverity.swift
|   |   |-- LevyHomeEvent.swift
|   |   |-- EventDisplayMetadata.swift
|   |   |-- EventPushStatus.swift
|   |   |-- APIResponses.swift
|   |   |-- APIRequests.swift
|   |   `-- APIError.swift
|   |-- Services/
|   |   |-- APIClient.swift
|   |   |-- NotificationService.swift
|   |   |-- SettingsStore.swift
|   |   `-- DateFormattingService.swift
|   |-- Theme/
|   |   |-- AppColors.swift
|   |   |-- AppSpacing.swift
|   |   `-- AppTextStyles.swift
|   |-- Resources/
|   |   |-- Assets.xcassets
|   |   |-- Info.plist
|   |   `-- PrivacyInfo.xcprivacy
|   `-- PreviewSupport/
|       |-- PreviewData.swift
|       `-- MockServices.swift
|-- LevyHomeTests/
|   |-- ModelDecodingTests.swift
|   |-- APIClientTests.swift
|   |-- EventsViewModelTests.swift
|   `-- PushRegistrationViewModelTests.swift
|-- LevyHomeUITests/
|   `-- SmokeUITests.swift
`-- docs/
    |-- 01-migration-discovery.md
    `-- 02-swiftui-architecture.md
```

### Structure Rules

- Views should remain thin and declarative.
- View models should not import UIKit except where unavoidable through notification bridging; prefer services for UIKit interaction.
- Services should not own visual state.
- Models should be plain Swift value types where possible.
- Preview support and mocks should stay outside production service implementations.
- Do not split by abstract Clean Architecture layers such as Entities/UseCases/Repositories. The app is not complex enough.

## 3. View Hierarchy

### Root Hierarchy

```text
LevyHomeApp
`-- RootTabView
    |-- HomeView
    |-- EventsView
    |-- SettingsView
    `-- DebugView
```

### Home Tab

```text
HomeView
|-- Header
|-- InfoPanel: Push status
`-- InfoPanel: API base URL
```

Responsibilities:

- Show product positioning copy from the Expo app.
- Show current push registration status message.
- Show current API base URL.
- No user actions.

### Events Tab

```text
EventsView
|-- ErrorBannerView, when needed
|-- Empty state, when events are empty and not loading
`-- ScrollView/List of EventCardView
    |-- SeverityBadgeView
    |-- Title/message
    |-- Entity ID
    |-- Received time
    `-- Push skip reason, when present
```

Responsibilities:

- Load events when first shown.
- Refresh with SwiftUI `.refreshable`.
- Preserve current empty and error states.
- Display newest-first events from the API.

### Settings Tab

```text
SettingsView
|-- InfoPanel: API URL
|-- InfoPanel: Platform
`-- InfoPanel: Data
```

Responsibilities:

- Read-only runtime summary for parity.
- Show API URL, platform, and current storage model.
- Later Debug-only API override can live here or Debug, but should not be required for parity.

### Debug Tab

```text
DebugView
|-- InfoPanel: API URL
|-- InfoPanel: Push registration status
|-- Token display panel
|-- Register push token button
|-- Send test push button
|-- Progress indicator, when sending
`-- Last response/error text
```

Responsibilities:

- Retry native push registration.
- Display APNs token or native-pending status.
- Call debug test-push endpoint once backend support exists.
- Show technical errors useful during development.

### View Hierarchy Decision

| Decision | Recommendation |
| --- | --- |
| Navigation | Use a single SwiftUI `TabView` with four tabs. |
| Alternatives considered | `NavigationStack` per tab, coordinator objects, custom router, deep-link-first routing. |
| Tradeoffs | `TabView` is simple and maps directly to the current app. It does not solve future deep-link routing by itself, but current product does not need that. |
| Why this fits | The Expo app has a flat four-tab structure and no nested navigation. Adding routing architecture now would create surface area without solving a current problem. |

## 4. State Management Approach

### Recommended Pattern

Use SwiftUI-native observable state:

- Prefer modern Observation (`@Observable`) if the app targets iOS 17 or newer.
- Use `ObservableObject` with `@StateObject` and `@ObservedObject` if supporting older iOS versions.
- Keep state scoped to the smallest owner that needs it.
- Keep app-wide shared state limited to push registration and app configuration.

### State Ownership

| State | Owner | Lifetime |
| --- | --- | --- |
| Selected tab | `RootTabView` local state, if needed | UI session |
| API base URL/config | `AppConfig` | App lifetime |
| Push status/token/error | `PushRegistrationViewModel` | App lifetime |
| Event list/loading/error | `EventsViewModel` | Events tab lifetime |
| Debug sending/last response | `DebugViewModel` | Debug tab lifetime |
| Debug API override, if added | `SettingsStore` backed by `UserDefaults` | Persistent, non-sensitive |

### App Environment

Create a small `AppEnvironment` object or value that groups long-lived dependencies:

```text
AppEnvironment
|-- config: AppConfig
|-- apiClient: APIClient
|-- notificationService: NotificationService
|-- settingsStore: SettingsStore
|-- dateFormatter: DateFormattingService
```

This is not a dependency injection framework. It is a simple composition root so views and view models do not construct services ad hoc.

### State Decision

| Decision | Recommendation |
| --- | --- |
| State management | Use SwiftUI Observation or `ObservableObject`; app-level push registration state plus screen-level view models. |
| Alternatives considered | TCA, Redux-style store, Flux, global singleton state, coordinators with state ownership. |
| Tradeoffs | Simple observable objects are less rigid than reducer-based systems, but much faster to understand and maintain for a four-screen app. They rely on discipline to avoid view model sprawl. |
| Why this fits | The current app has minimal React state: push registration, events loading/error/list, and debug sending state. Native SwiftUI state primitives cover this cleanly. |

## 5. Service Layer Design

### Service Boundaries

| Service | Responsibilities | Not responsible for |
| --- | --- | --- |
| `APIClient` | HTTP requests, JSON encode/decode, API errors | Push permission, UI alerts, persistence policy |
| `NotificationService` | Permission checks, APNs registration, foreground presentation policy, token callbacks | Sending push notifications from server, storing APNs credentials |
| `SettingsStore` | Non-sensitive local settings via `UserDefaults` | Auth tokens, Home Assistant secrets, event database |
| `DateFormattingService` | Parse API ISO dates and format display strings | Business rules, storage |
| `AppConfig` | API base URL, build flavor, debug/release flags | Mutable runtime state beyond config |

### Service Construction

Services should be created once at app startup and passed into view models. Avoid global mutable singletons for app-specific services. System singletons such as `UNUserNotificationCenter.current()` are acceptable inside `NotificationService` because they are Apple APIs, but wrap them enough to test view model behavior.

### Service Decision

| Decision | Recommendation |
| --- | --- |
| Service layer | Use a small hand-written service layer with explicit dependencies passed at initialization. |
| Alternatives considered | Dependency injection framework, service locator, global singletons, no service layer. |
| Tradeoffs | Explicit construction is a little more setup than global singletons, but testable and still small. A framework would add unnecessary ceremony. |
| Why this fits | The app needs only API, notifications, settings, and formatting services. These are stable seams without needing enterprise architecture. |

## 6. Swift Model Design

### Model Groups

| Model | Purpose | Notes |
| --- | --- | --- |
| `EventType` | Known event type enum | Include all current garage and doorbell placeholder values. Consider unknown fallback. |
| `DisplaySeverity` | `info`, `warning`, `critical` | Drives badge color. Distinct from Home Assistant payload severity. |
| `HomeAssistantCategory` | `garage`, `doorbell` | Optional on decoded events. |
| `HomeAssistantPayloadSeverity` | `normal`, `high` | Optional, separate from display severity. |
| `EventDisplayMetadata` | Default title/body/severity | Decoded from API response. Local fallback constants optional. |
| `EventPushStatus` | Push attempt/skip metadata | Keep Expo-specific fields optional during transition. |
| `LevyHomeEvent` | Timeline event | `Codable`, `Identifiable`, display helpers where useful. |
| `RegisterDeviceRequest` | Device token registration body | Should evolve to provider-aware APNs contract. |
| `RegisterDeviceResponse` | Device registration response | Keep `registeredDeviceCount`. Device details optional. |
| `EventsResponse` | Recent events response | Contains `[LevyHomeEvent]`. |
| `TestPushResponse` | Debug push result | Initially mirror current fields, then provider-neutral. |
| `APIErrorResponse` | Server error envelope | `{ error: String }`. |

### Date Handling

API dates are strings today. The app should:

- Decode raw date strings without crashing.
- Parse ISO date strings in a controlled place.
- Show a fallback display string if parsing fails.
- Avoid scattering `DateFormatter` setup across views.

### Enum Forward Compatibility

For event/severity fields, use one of these approaches:

| Approach | Use when |
| --- | --- |
| Strict enum decoding | Backend and app deploy together, unknown values should fail loudly in tests. |
| Enum with `.unknown(String)` | Backend may add event types before app update, and timeline should still render. |

Recommendation: use unknown fallback for API-decoded event type and severity values. The product is notification-focused; failing an entire timeline because one future event type is unknown is too brittle.

### Model Decision

| Decision | Recommendation |
| --- | --- |
| Model style | Use manually written Swift `Codable` value types with lightweight enum fallbacks. |
| Alternatives considered | Generated Swift from TypeScript, dynamic dictionaries everywhere, shared schema generation, server-driven display only. |
| Tradeoffs | Manual models must be kept in sync with backend contracts, but they are easy to read and test. Code generation would need a schema pipeline the project does not yet have. Dynamic dictionaries would hide errors. |
| Why this fits | The event contract is small, stable, and already well understood from the shared TypeScript package. Manual Swift models are the lowest-friction reliable choice. |

## 7. API Client Design

### Current Mobile Endpoints

| Method | Path | Initial SwiftUI use |
| --- | --- | --- |
| `GET` | `/api/events` | Events timeline. |
| `POST` | `/api/devices/register` | Native token registration, after backend contract is decided. |
| `POST` | `/api/debug/send-test-push` | Debug screen. |
| `GET` | `/health` | Optional diagnostics. |

The SwiftUI app should not call `POST /api/ha/events`; Home Assistant owns that integration.

### Client Responsibilities

`APIClient` should:

- Normalize the base URL once.
- Build URLs safely from paths and query items.
- Set JSON headers for JSON requests.
- Use `URLSession` and `async/await`.
- Decode success responses into typed models.
- Decode `{ error: string }` for non-2xx responses when possible.
- Produce typed `APIError` values for invalid URL, transport, status, server message, and decoding failures.
- Avoid automatic retries at first. Push/event actions are simple enough for manual retry UI.

### Error Surface

| Error | View behavior |
| --- | --- |
| Invalid config/base URL | Settings/Debug should show clear configuration issue. |
| Network unreachable | Events shows error banner; Debug shows technical detail. |
| Non-2xx with error envelope | Display server-provided message where safe. |
| Non-2xx without envelope | Display status-based fallback. |
| Decoding failure | Display `The API returned an unexpected response.` and log detail in debug builds. |

### API Client Decision

| Decision | Recommendation |
| --- | --- |
| Networking | Use `URLSession` with `async/await` and a small typed `APIClient`. |
| Alternatives considered | Alamofire, generated OpenAPI client, raw `URLSession` calls inside view models, callback-based networking. |
| Tradeoffs | A hand-written client means contract changes require manual updates, but the surface is only a few endpoints. Third-party networking would be heavier than the app needs. |
| Why this fits | Current mobile networking is a tiny `fetch` wrapper. Native parity needs the same simplicity with better typed errors. |

## 8. Configuration Strategy

### Configuration Sources

| Configuration | Recommended source | Secret? |
| --- | --- | --- |
| API base URL | Build setting or Info.plist value, optionally Debug override in UserDefaults | No |
| Build flavor | Xcode scheme/build configuration | No |
| Debug tab enabled | Compile-time flag or build configuration | No |
| Bundle identifier | Xcode target setting | No, but important |
| APNs environment | Entitlements/provisioning and backend registration payload | No on client; credentials are server-side |
| Home Assistant webhook secret | Server/Home Assistant only | Yes |
| APNs signing key/certificate | Backend secret store only | Yes |
| Future user auth tokens | Keychain | Yes |

### Environment Model

Use a small `AppConfig` value that contains:

- `apiBaseURL`
- `buildFlavor`
- `isDebugBuild`
- `isDebugTabEnabled`
- optional `apnsEnvironment` if the app needs to tell the backend sandbox vs production

### Local Development

For local development against the existing Node API:

- Use a Debug build API base URL such as a LAN URL, not a source-code edit.
- Allow HTTP/local networking only in Debug if needed.
- Prefer HTTPS for any production or internet-accessible API.

### Configuration Decision

| Decision | Recommendation |
| --- | --- |
| Config | Use build settings/Info.plist plus optional Debug `UserDefaults` override for API base URL. |
| Alternatives considered | Hardcoded constants, environment files parsed at runtime, remote config service, user-editable production settings. |
| Tradeoffs | Build settings require scheme discipline, but keep release config explicit. A Debug override is practical for LAN testing. Remote config is unnecessary. |
| Why this fits | The current app has one client runtime variable: API URL. The native app needs configurability without adding a configuration platform. |

## 9. Persistence Strategy

### Initial Client Persistence

Initial native client persistence should be minimal:

| Data | Store? | Store where | Notes |
| --- | --- | --- | --- |
| API base URL debug override | Optional | `UserDefaults` | Debug builds only. |
| Last selected environment | Optional | `UserDefaults` | Only if multiple environments exist. |
| APNs token | Optional | Memory or `UserDefaults` for display/debug | APNs token can change; always treat callbacks as authoritative. |
| Events timeline | No | None | Fetch from API for parity. |
| Home Assistant secret | Never | Nowhere in app | Server-side only. |
| Future user auth tokens | Future work | Keychain | Only if production auth is added. |

### Backend Persistence Is Separate

The existing API stores devices, events, and dedupe state in memory. That is a backend maturity issue, not a SwiftUI client architecture issue. The SwiftUI app should not compensate with a client-side database during initial migration.

### Persistence Decision

| Decision | Recommendation |
| --- | --- |
| Persistence | Use `UserDefaults` only for non-sensitive debug/config preferences; defer event caching and Keychain until needed. |
| Alternatives considered | Core Data, SwiftData, SQLite, Realm, local JSON event cache, storing all app state in UserDefaults. |
| Tradeoffs | Minimal persistence means no offline timeline, but avoids stale local data and unnecessary storage logic. Backend persistence remains the correct place to solve timeline/device durability. |
| Why this fits | The current Expo app persists nothing locally. Parity does not require a database, and the product is not an offline-first app. |

## 10. Notification/APNs Strategy

### Workstream Separation

Notification migration has three separate parts:

| Workstream | Owner | Output |
| --- | --- | --- |
| UI/client parity | SwiftUI app | Shows push status and Debug controls, even if native push is pending. |
| Native APNs registration | SwiftUI app + Apple provisioning | App requests permission and receives APNs device token. |
| Backend push-provider migration | API/backend | API stores APNs-aware registrations and sends APNs notifications. |

### Native APNs Registration Flow

Target native flow:

```text
App launch or Debug retry
-> NotificationService checks current notification settings
-> if needed, request authorization for alert/sound/list/banner behavior
-> register for remote notifications
-> AppDelegate receives APNs device token or failure
-> PushRegistrationViewModel updates state
-> APIClient registers provider-aware device token with backend
-> Home and Debug show resulting status
```

### Foreground Presentation

Current Expo behavior:

- Play sound.
- Show alert/banner/list.
- Do not set badge.

Native target should match this unless product decisions change.

### Token Registration Contract

Current request:

```json
{
  "pushToken": "ExpoPushToken[...]",
  "platform": "ios"
}
```

Recommended future request:

```json
{
  "token": "<apns-device-token>",
  "platform": "ios",
  "provider": "apns",
  "environment": "sandbox"
}
```

The exact backend route can be either the existing `/api/devices/register` with a versioned/provider-aware body or a new endpoint such as `/api/devices/register-native`. Prefer preserving the route and evolving the request body if backward compatibility is manageable.

### Notification Routing

Initial native app should not add complex notification deep-link routing. If the user taps a notification, opening the app to the Events tab is enough future behavior. Highlighting a specific event requires the notification payload to include a stable event ID and the client to fetch/locate it; that is future work.

### Notification Decision

| Decision | Recommendation |
| --- | --- |
| Push migration | Implement native APNs registration in the app and migrate backend sending to APNs as a separate backend workstream. |
| Alternatives considered | Keep Expo push, bridge Expo tokens from native app, use local notifications only, defer all notification UI until backend is ready. |
| Tradeoffs | APNs requires entitlements, provisioning, physical-device testing, and backend changes. It is more work than client UI parity, but it is the correct native architecture. Keeping Expo would undermine the pure SwiftUI/iOS-only goal. |
| Why this fits | Push is the core product promise. A pure native app cannot rely on Expo push tokens, so APNs must be treated as first-class architecture rather than screen-level glue. |

## 11. Debug/Release Behavior Strategy

### Debug Tab Policy

The Debug tab is useful during migration, but it exposes internal implementation details such as tokens, API URLs, registration errors, and test push actions.

Recommended behavior:

| Build | Debug tab | Token visibility | Test push |
| --- | --- | --- | --- |
| Debug/local | Enabled | Full token visible/copyable if needed | Enabled |
| Internal/TestFlight | Enabled or hidden by build flag | Masked by default, reveal optional | Enabled only if backend endpoint is safe |
| Release/App Store | Hidden unless intentionally productized | Hidden or masked | Disabled unless authenticated/protected |

### Debug Endpoint Risk

`POST /api/debug/send-test-push` is unauthenticated today. This can be acceptable during local MVP development, but it should not be exposed broadly in a production release without a deliberate backend policy.

### Release Behavior Decision

| Decision | Recommendation |
| --- | --- |
| Debug/release | Keep Debug tooling in Debug builds; hide or restrict it in Release until endpoints are protected. |
| Alternatives considered | Always ship Debug tab, remove Debug entirely, put Debug behind a secret gesture, require production auth now. |
| Tradeoffs | Debug-only gating keeps migration efficient but requires build configuration discipline. Shipping Debug always is risky. Adding auth now would expand scope. |
| Why this fits | Debug tools are valuable for APNs migration, but the app is family-facing and should not expose raw diagnostics in production by default. |

## 12. Backend Contract Implications

### Contracts That Can Remain Initially

| Contract | Initial status |
| --- | --- |
| `GET /api/events` response shape | Keep. SwiftUI app can decode current `LevyHomeEvent` models. |
| Event display metadata embedded in events | Keep. Client can render from server response. |
| Home Assistant webhook payload | Keep. Native app does not call it. |
| Push dedupe semantics | Keep server-side. Client only displays skip reasons. |
| Debug test push endpoint | Keep for local/debug, but revisit release exposure. |

### Contracts That Need Push Migration Work

| Contract | Current Expo behavior | Native/APNs implication |
| --- | --- | --- |
| Device registration request | `pushToken` is Expo token | Needs provider-aware APNs token body. |
| Device validation | `Expo.isExpoPushToken` | Needs APNs token validation/normalization appropriate to provider. |
| Push send result | Expo tickets and invalid Expo token count | Needs provider-neutral send result fields. |
| Server push provider | `expo-server-sdk` | Needs APNs provider implementation. |
| Token environment | Implied by Expo/EAS | Must distinguish sandbox/production APNs. |

### Recommended Provider-Aware Device Model

Backend storage should evolve from:

```text
pushToken, platform, registeredAt, lastSeenAt
```

to:

```text
deviceToken, platform, provider, environment, registeredAt, lastSeenAt, appVersion?, deviceName?
```

Optional fields can wait. The important additions are `provider` and `environment`.

### Backend Contract Decision

| Decision | Recommendation |
| --- | --- |
| Backend contract | Keep read-only event/timeline contracts stable; evolve device registration and push send responses to provider-aware APNs-capable contracts. |
| Alternatives considered | Rewrite backend before client parity, keep Expo-only backend, create a separate native-only API, add production auth immediately. |
| Tradeoffs | Evolving the existing API minimizes client migration risk, but requires careful transitional naming around `pushToken`. A backend rewrite would delay native UI parity. Keeping Expo-only blocks native push parity. |
| Why this fits | The API already matches the product model. Only the push-provider boundary is architecturally wrong for a pure native app. |

## 13. Testing Strategy

### Test Pyramid

| Layer | Recommended coverage |
| --- | --- |
| Unit tests | Models, API client, view models, date formatting, push state transitions. |
| Integration/manual tests | Local API event fetching, APNs registration on physical device, debug test push. |
| UI smoke tests | App launches, tabs exist, Events empty/list/error states render. |
| Backend contract tests | Future backend APNs route behavior and provider-neutral push result shape. |

### Client Tests

| Area | Test examples |
| --- | --- |
| Model decoding | Decode all five garage events, doorbell placeholder event, skipped push event, unknown event type fallback. |
| Date formatting | Valid ISO date, missing optional date, malformed date fallback. |
| API client | Success, server error envelope, non-JSON error, 500 without envelope, invalid base URL, decoding failure. |
| Events view model | Initial load success, load failure, refresh success after prior error, empty response. |
| Push view model | Permission denied, APNs token success, APNs failure, API registration success, API registration failure. |
| Debug view model | Test push success, test push failure, duplicate tap while sending. |

### Manual APNs Tests

APNs cannot be fully proven on simulator. Manual acceptance should include:

1. Physical iPhone installs Debug build.
2. App requests notification permission.
3. APNs token is received and displayed in Debug.
4. Token registration reaches backend.
5. Fake garage event triggers push.
6. Foreground and background notification presentation behave as expected.
7. Event appears in the timeline after refresh.
8. Sandbox and production APNs environments are not mixed.

### Testing Decision

| Decision | Recommendation |
| --- | --- |
| Testing | Unit-test models/API/view models; use physical-device manual tests for APNs; keep UI automation to smoke coverage initially. |
| Alternatives considered | Heavy UI automation first, no tests until app complete, snapshot testing everything, relying only on manual QA. |
| Tradeoffs | Focused tests catch contract and state bugs without slowing UI iteration. APNs still needs manual real-device testing. Full UI automation would be expensive before the UI stabilizes. |
| Why this fits | The riskiest code is model/network/push state, not complex navigation. The app has only four tabs and little interaction depth. |

## 14. Architecture Decision Records

### ADR 001: Replace Only The Mobile App Initially

| Field | Decision |
| --- | --- |
| Recommendation | Rebuild the native SwiftUI client while allowing the existing Node/Express API to remain during the first phase. |
| Alternatives considered | Rewrite the API first, rebuild mobile and backend simultaneously, keep Expo mobile app and only harden backend. |
| Tradeoffs | Keeping the API reduces migration scope and lets UI parity progress quickly. Some backend limitations remain visible, especially in-memory storage and Expo push. |
| Why this fits this app | The request is an iOS-only SwiftUI rebuild, and the existing API already models the core event timeline well enough for client parity. |

### ADR 002: Keep Architecture SwiftUI-Native And Small

| Field | Decision |
| --- | --- |
| Recommendation | Use SwiftUI views, observable view models, small services, and plain `Codable` models. |
| Alternatives considered | TCA, Redux, Flux, coordinator architecture, dependency injection framework, Clean Architecture-style use cases/repositories. |
| Tradeoffs | Small architecture relies on discipline, but avoids boilerplate. Heavy patterns offer consistency at scale but are premature here. |
| Why this fits this app | The product has four tabs, a few API calls, and one central native capability. Complexity should be spent on APNs, not architecture scaffolding. |

### ADR 003: Use `TabView` For Navigation

| Field | Decision |
| --- | --- |
| Recommendation | Use a single `TabView` with Home, Events, Settings, and Debug. |
| Alternatives considered | Custom router, coordinator, nested navigation stacks from day one. |
| Tradeoffs | `TabView` does not solve future deep links alone, but current app has no nested navigation. |
| Why this fits this app | It directly mirrors the Expo Router tab structure and minimizes migration risk. |

### ADR 004: Use Screen-Level View Models

| Field | Decision |
| --- | --- |
| Recommendation | Use `EventsViewModel` and `DebugViewModel` for screen-specific async state, plus an app-level `PushRegistrationViewModel`. |
| Alternatives considered | One global app store, views owning all async state, one view model per tiny subview. |
| Tradeoffs | Screen view models are easy to test and reason about. They can become bloated if responsibilities are not kept narrow. |
| Why this fits this app | Current state naturally divides into app-wide push registration and per-screen event/debug state. |

### ADR 005: Use `URLSession` And `async/await`

| Field | Decision |
| --- | --- |
| Recommendation | Implement a small `APIClient` on top of `URLSession` and `async/await`. |
| Alternatives considered | Alamofire, generated client, callbacks, raw networking in views. |
| Tradeoffs | Manual client code must be maintained, but endpoint count is low. Third-party networking adds dependency weight without enough benefit. |
| Why this fits this app | The Expo app currently has a tiny fetch wrapper; native parity should be just as direct while gaining typed errors. |

### ADR 006: Use Manual Swift Models

| Field | Decision |
| --- | --- |
| Recommendation | Write Swift `Codable` models manually from the shared TypeScript contract. |
| Alternatives considered | Code generation from TypeScript, schema-first OpenAPI/JSON Schema, untyped dictionaries. |
| Tradeoffs | Manual models require sync discipline. Generation would require a schema pipeline not present today. Untyped dictionaries reduce safety. |
| Why this fits this app | The event contract is small and stable enough for clear hand-written models and tests. |

### ADR 007: Keep Client Persistence Minimal

| Field | Decision |
| --- | --- |
| Recommendation | Use `UserDefaults` only for non-sensitive debug/config preferences; avoid local event persistence initially. |
| Alternatives considered | SwiftData, Core Data, SQLite, Realm, JSON file cache. |
| Tradeoffs | No offline timeline at first. Avoids stale cache behavior and storage complexity. |
| Why this fits this app | The Expo app has no local persistence. Backend persistence is the right place to solve durable event/device state. |

### ADR 008: Use Keychain Only When Secrets Exist

| Field | Decision |
| --- | --- |
| Recommendation | Do not introduce Keychain until the app stores true secrets such as future auth tokens. |
| Alternatives considered | Store APNs token in Keychain, store all preferences in Keychain, avoid Keychain forever. |
| Tradeoffs | APNs token is sensitive-ish operational data but not a user auth secret; storing it in Keychain adds little value. Future auth will require Keychain. |
| Why this fits this app | Current app has no user auth and must never store Home Assistant webhook secrets. |

### ADR 009: Treat APNs As A Separate Workstream

| Field | Decision |
| --- | --- |
| Recommendation | Separate native APNs registration from UI parity and backend push-provider migration. |
| Alternatives considered | Implement push at the same time as every screen, defer all push UI, keep Expo push forever. |
| Tradeoffs | Users may see native-pending push status during early client parity. The benefit is lower risk and clearer acceptance criteria. |
| Why this fits this app | Push is the central architectural risk. Separating it prevents UI migration from being blocked by provisioning/backend work. |

### ADR 010: Move Backend Push To Provider-Aware APNs Contracts

| Field | Decision |
| --- | --- |
| Recommendation | Evolve device registration and push send responses to include provider and environment. |
| Alternatives considered | Keep `pushToken` as an overloaded field, create a separate native-only backend, keep Expo SDK. |
| Tradeoffs | Provider-aware contracts require backend changes, but avoid ambiguity and support sandbox/production APNs cleanly. |
| Why this fits this app | A pure SwiftUI app will receive APNs device tokens, not Expo push tokens. The backend must model that reality. |

### ADR 011: Keep Production Auth As Future Work

| Field | Decision |
| --- | --- |
| Recommendation | Do not introduce production user auth during the initial SwiftUI architecture; document endpoint exposure as production-readiness work. |
| Alternatives considered | Add login immediately, protect every endpoint now, embed static app secret, leave all endpoints public without review. |
| Tradeoffs | Deferring auth keeps migration focused but leaves production exposure questions unresolved. Embedding app secrets would be insecure. |
| Why this fits this app | The current product scope explicitly excludes production auth, and adding it would reshape backend, storage, and UX. |

### ADR 012: Keep Debug Tooling Build-Gated

| Field | Decision |
| --- | --- |
| Recommendation | Keep Debug tab enabled for Debug/internal builds and hide or restrict it for Release unless intentionally productized. |
| Alternatives considered | Always ship Debug, remove Debug, hide behind gesture, require auth immediately. |
| Tradeoffs | Build gating is simple but needs release discipline. Always shipping Debug risks exposing internals. |
| Why this fits this app | Debug tooling is essential for APNs migration but not necessarily part of the family-facing product. |

### ADR 013: Defer Notification Deep Linking

| Field | Decision |
| --- | --- |
| Recommendation | Initially open the app normally after notification tap; consider routing to Events later. |
| Alternatives considered | Full deep-link routing now, event-detail screen, notification-specific navigation stack. |
| Tradeoffs | Less polished notification tap behavior at first, but avoids building navigation that the current app does not have. |
| Why this fits this app | The reference app does not implement notification tap routing or event detail screens. Parity should stay lean. |

### ADR 014: Keep Doorbell As Later Expansion

| Field | Decision |
| --- | --- |
| Recommendation | Include doorbell event types in models for contract completeness, but do not add doorbell-specific UI or integrations initially. |
| Alternatives considered | Remove doorbell models, build doorbell UI now, integrate eufy during migration. |
| Tradeoffs | Keeping model support is harmless, but UI/integration work would expand scope. |
| Why this fits this app | Doorbell events exist as placeholders in the contract, while docs explicitly defer eufy/doorbell reliability work. |

## Implementation Cut Lines

### Cut Line A: Client Parity Without Native Push

Deliver:

- Project baseline.
- `TabView` with Home, Events, Settings, Debug.
- Models and `APIClient`.
- Events timeline from existing API.
- Push status shown as native-pending/unavailable.

Do not block this on APNs or backend push migration.

### Cut Line B: Native APNs Registration

Deliver:

- Push Notifications capability/provisioning.
- Permission request and APNs token callback handling.
- App-level push registration state.
- Debug token visibility in Debug builds.

This proves native device registration, not server push delivery.

### Cut Line C: Backend Push Provider Migration

Deliver:

- Provider-aware device registration contract.
- APNs sender on backend.
- Provider-neutral debug test push result.
- End-to-end garage event push on physical device.

This is the point where native notification parity is achieved.

## Final Recommendation

Build the native SwiftUI app as a small, direct client first. Keep screens, models, networking, and settings simple. Treat APNs as a native capability workstream and backend push migration as a backend contract workstream. The architecture should make those seams explicit without importing a heavyweight app framework.
