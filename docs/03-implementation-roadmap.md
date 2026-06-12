# SwiftUI Implementation Roadmap

This roadmap converts `docs/01-migration-discovery.md` and `docs/02-swiftui-architecture.md` into small, sequential, independently committable implementation stages for the native SwiftUI rebuild.

The first goal is to make the app runnable as early as possible. UI/client parity, native APNs registration, and backend APNs push-provider migration are intentionally separate cut lines. Backend APNs work must not block the first runnable SwiftUI app.

## Roadmap Guardrails

- Do not redo discovery during implementation.
- Do not redesign the architecture unless a concrete contradiction is found and documented.
- Keep each implementation commit focused; target 1-5 files per commit where practical.
- Each stage stops after its own acceptance criteria.
- Do not combine unrelated UI, APNs, backend, and release-readiness work.
- Do not add dark mode, production auth, doorbell integration, local event caching, backend persistence, deep-link routing, widgets, or Home Assistant dashboard features during this roadmap.
- Use SwiftUI, async/await, URLSession, UserDefaults for non-sensitive preferences, and Keychain only when future secrets exist.
- Avoid TCA, Redux, Flux, coordinators, dependency injection frameworks, and enterprise architecture patterns.

## Cut Lines

| Cut line | Completed by | Meaning |
| --- | --- | --- |
| 1. Client parity without native push | Stage 10 | Native app is runnable and matches the current mobile client for tabs, static screens, events timeline, config display, and Debug UI with push marked pending/unavailable. |
| 2. Native APNs registration | Stage 11 | Native app requests notification permission and obtains APNs token on a physical device, independent of backend push delivery. |
| 3. Backend APNs push-provider migration | Stage 14 | Backend accepts provider-aware APNs registrations and sends APNs pushes. |
| 4. End-to-end physical-device garage notification verification | Stage 15 | Fake/real garage events produce APNs notifications and timeline entries on a physical iPhone. |
| 5. Production/TestFlight readiness | Stage 16 | Build/config/release checks are complete for internal distribution. |

## Reasoning Levels

| Level | Use for |
| --- | --- |
| Low | Tiny mechanical changes. |
| Medium | Static SwiftUI screens, simple styling, simple models. |
| High | API client, async state, error handling, APNs setup. |
| Max | Backend APNs migration, provisioning/signing issues, end-to-end push debugging. |

## Stage 0: Native Project Baseline

| Field | Details |
| --- | --- |
| Objective | Create the native SwiftUI iOS project shell in `levy-home` with the agreed app identity and a minimal launchable target. |
| User-visible outcome | The app launches on simulator to a plain placeholder screen. |
| Workstream | Client infrastructure |
| Files/directories likely created | Xcode project/workspace files; `LevyHome/App/LevyHomeApp.swift`; `LevyHome/Resources/Assets.xcassets`; `LevyHome/Resources/Info.plist`; initial test targets if generated. |
| Files/directories likely modified | `README.md` only if adding a one-line build note; otherwise none. |
| Dependencies | Final or temporary bundle identifier decision; Xcode installed; iOS deployment target decision. |
| Risks | Xcode scaffolding can create many generated files in one commit; bundle ID changes later affect APNs and TestFlight. |
| Acceptance criteria | Project opens in Xcode; simulator build succeeds; app launches; no Expo/React Native dependencies are introduced. |
| Manual test plan | Open project in Xcode; select an iPhone simulator; build and run; confirm placeholder screen appears. Stop and verify before adding app architecture files. |
| Suggested commit message | `Create native SwiftUI project shell` |
| Recommended GPT-5.5 reasoning level | High |

## Stage 1: App Composition Root And Config Skeleton

| Field | Details |
| --- | --- |
| Objective | Add the small composition root described in the architecture without implementing network or notification behavior yet. |
| User-visible outcome | The placeholder app still launches; internal structure now has config/environment placeholders. |
| Workstream | Client infrastructure |
| Files/directories likely created | `LevyHome/App/AppConfig.swift`; `LevyHome/App/AppEnvironment.swift`; `LevyHome/App/BuildConfiguration.swift`. |
| Files/directories likely modified | `LevyHome/App/LevyHomeApp.swift`. |
| Dependencies | Stage 0. |
| Risks | Overbuilding environment abstractions too early; accidentally hardcoding production API URL. |
| Acceptance criteria | App compiles; `AppConfig` exposes API base URL through build/default config; no secrets exist in app source; no services perform real work yet. |
| Manual test plan | Build and run on simulator; confirm launch still works; inspect Debug console or placeholder UI only if config value is temporarily displayed. Stop and verify config is not embedded in views. |
| Suggested commit message | `Add app configuration skeleton` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 2: Simulator-Only Tab Shell

| Field | Details |
| --- | --- |
| Objective | Create the four-tab SwiftUI shell with placeholder content for Home, Events, Settings, and Debug. This is the first explicit simulator-only milestone. |
| User-visible outcome | The app launches on simulator with a native tab bar and four selectable tabs. |
| Workstream | Client UI |
| Files/directories likely created | `LevyHome/Views/Root/RootTabView.swift`; `LevyHome/Views/Home/HomeView.swift`; `LevyHome/Views/Events/EventsView.swift`; `LevyHome/Views/Settings/SettingsView.swift`; `LevyHome/Views/Debug/DebugView.swift`. |
| Files/directories likely modified | `LevyHome/App/LevyHomeApp.swift`. |
| Dependencies | Stage 1. |
| Risks | Adding navigation beyond the flat tab shell; starting APNs work too early. |
| Acceptance criteria | Simulator shows Home, Events, Settings, Debug tabs; tab labels/icons are present; each tab has simple placeholder text; no networking or push permission prompt occurs. |
| Manual test plan | Run on simulator; tap each tab; confirm no crash and no native permission prompts. Stop and verify the first runnable tabbed app before adding visual parity. |
| Suggested commit message | `Add SwiftUI tab shell` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 3: Theme And Shared UI Primitives

| Field | Details |
| --- | --- |
| Objective | Add the small visual foundation needed for static parity: colors, spacing, reusable info panel, error banner, and severity badge shell. |
| User-visible outcome | Placeholder screens can use the same quiet green/white panel style as the Expo app. |
| Workstream | Client UI |
| Files/directories likely created | `LevyHome/Theme/AppColors.swift`; `LevyHome/Theme/AppSpacing.swift`; `LevyHome/Views/Shared/InfoPanel.swift`; `LevyHome/Views/Shared/ErrorBannerView.swift`; optionally `LevyHome/Views/Events/SeverityBadgeView.swift`. |
| Files/directories likely modified | Existing placeholder views only as needed to prove the shared components compile. |
| Dependencies | Stage 2. |
| Risks | Over-polishing or adding dark mode; creating a large design system. |
| Acceptance criteria | Shared components compile; colors match the reference palette closely; no dark mode scope added; app still launches on simulator. |
| Manual test plan | Run on simulator; inspect Home placeholder or a preview screen using `InfoPanel`; verify no text clipping in default simulator size. Stop and verify UI primitives before converting screens. |
| Suggested commit message | `Add SwiftUI theme primitives` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 4: Static Home And Settings Parity

| Field | Details |
| --- | --- |
| Objective | Replace Home and Settings placeholders with native SwiftUI equivalents of the current Expo screens, using static/config-driven values only. |
| User-visible outcome | Home shows product copy, push status placeholder, and API URL; Settings shows API URL, platform, and data model rows. |
| Workstream | Client UI |
| Files/directories likely created | None expected, unless extracting `SettingsRow` or `InfoPanel` variant. |
| Files/directories likely modified | `LevyHome/Views/Home/HomeView.swift`; `LevyHome/Views/Settings/SettingsView.swift`; possibly `LevyHome/App/AppEnvironment.swift`. |
| Dependencies | Stage 3. |
| Risks | Accidentally adding editable settings or release behavior decisions too early. |
| Acceptance criteria | Home copy matches the reference intent; Settings rows match API URL, platform, and data concepts; push status clearly says native push is pending/unavailable; simulator build succeeds. |
| Manual test plan | Run on simulator; inspect Home and Settings; verify API URL displays from config; confirm no network call occurs. Stop and verify static parity before adding models. |
| Suggested commit message | `Add Home and Settings parity screens` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 5: Swift Event Models And Decoding Tests

| Field | Details |
| --- | --- |
| Objective | Add Swift models for the existing event contract and tests that decode representative event JSON. |
| User-visible outcome | No UI change; the app gains typed event models for the upcoming Events timeline. |
| Workstream | Client infrastructure |
| Files/directories likely created | `LevyHome/Models/EventType.swift`; `LevyHome/Models/EventSeverity.swift`; `LevyHome/Models/EventDisplayMetadata.swift`; `LevyHome/Models/EventPushStatus.swift`; `LevyHome/Models/LevyHomeEvent.swift`; `LevyHomeTests/ModelDecodingTests.swift`. |
| Files/directories likely modified | Test target configuration if needed. |
| Dependencies | Stage 1; event contract from discovery document. |
| Risks | Strict enum decoding could break forward compatibility; date parsing could be too brittle. |
| Acceptance criteria | Tests decode all five garage event types, one doorbell placeholder, a skipped push event, optional fields, and an unknown enum fallback if implemented. |
| Manual test plan | Run unit tests; no simulator UI verification required beyond app still compiling. Stop and verify model contract before networking. |
| Suggested commit message | `Add event models and decoding tests` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 6: API Error And Response Models

| Field | Details |
| --- | --- |
| Objective | Add typed request/response/error models used by the API client, without implementing HTTP calls yet. |
| User-visible outcome | No visible UI change. |
| Workstream | Client infrastructure |
| Files/directories likely created | `LevyHome/Models/APIResponses.swift`; `LevyHome/Models/APIRequests.swift`; `LevyHome/Models/APIError.swift`. |
| Files/directories likely modified | `LevyHomeTests/ModelDecodingTests.swift` or a small new response decoding test file. |
| Dependencies | Stage 5. |
| Risks | Baking in Expo-specific test-push terminology too deeply; losing provider-neutral migration path. |
| Acceptance criteria | Response models compile; sample `EventsResponse`, `RegisterDeviceResponse`, `TestPushResponse`, and `APIErrorResponse` decode; Expo-specific fields are optional where appropriate. |
| Manual test plan | Run unit tests; confirm app still builds on simulator. Stop and verify response models before adding URLSession. |
| Suggested commit message | `Add API response models` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 7: URLSession API Client

| Field | Details |
| --- | --- |
| Objective | Implement the typed `APIClient` with async/await for current mobile endpoints, plus unit tests using stubs. |
| User-visible outcome | No direct UI change yet; app can now fetch recent events through a service. |
| Workstream | Client infrastructure |
| Files/directories likely created | `LevyHome/Services/APIClient.swift`; `LevyHomeTests/APIClientTests.swift`. |
| Files/directories likely modified | `LevyHome/App/AppEnvironment.swift`; possibly `LevyHome/App/AppConfig.swift`. |
| Dependencies | Stage 6. |
| Risks | Async error handling bugs; malformed URL handling; accidentally calling real network in unit tests. |
| Acceptance criteria | API client supports `fetchRecentEvents`, `registerDevice` placeholder/current contract, `sendTestPush`, and optional `health`; tests cover success, server error envelope, HTTP error, transport failure, invalid base URL, and decoding failure. |
| Manual test plan | Run unit tests; optionally point Debug build to local API and exercise a temporary health/fetch call only if already exposed through a safe test harness. Stop and verify API client behavior before wiring UI. |
| Suggested commit message | `Add typed API client` |
| Recommended GPT-5.5 reasoning level | High |

## Stage 8: Events Timeline UI With Sample Data

| Field | Details |
| --- | --- |
| Objective | Build the Events card UI, empty state, error banner, and severity badges against preview/sample data before introducing live async state. |
| User-visible outcome | Events tab shows native event cards from local sample data or preview mode. |
| Workstream | Client UI |
| Files/directories likely created | `LevyHome/Views/Events/EventCardView.swift`; `LevyHome/PreviewSupport/PreviewData.swift`; optionally `LevyHome/Services/DateFormattingService.swift`. |
| Files/directories likely modified | `LevyHome/Views/Events/EventsView.swift`; `LevyHome/Views/Events/SeverityBadgeView.swift`. |
| Dependencies | Stage 5 and Stage 3. |
| Risks | Mixing sample data with production state; overbuilding layout; adding event detail navigation. |
| Acceptance criteria | Events tab can display sample garage events; empty state and error banner are available; severity colors match reference; no network call occurs in this stage. |
| Manual test plan | Run on simulator; inspect Events tab with sample data state; use previews if available; verify card layout for long entity IDs. Stop and verify visual timeline before async integration. |
| Suggested commit message | `Add Events timeline UI` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 9: Events ViewModel And Live API Integration

| Field | Details |
| --- | --- |
| Objective | Wire Events tab to `EventsViewModel` and `APIClient`, including load-on-appear, refresh, loading, empty, and error states. |
| User-visible outcome | Native app fetches and displays real recent events from the existing Node/Express API; pull-to-refresh works. |
| Workstream | Client UI, Client infrastructure |
| Files/directories likely created | `LevyHome/ViewModels/EventsViewModel.swift`; `LevyHomeTests/EventsViewModelTests.swift`. |
| Files/directories likely modified | `LevyHome/Views/Events/EventsView.swift`; `LevyHome/App/AppEnvironment.swift`; possibly `LevyHome/Services/DateFormattingService.swift`. |
| Dependencies | Stage 7; local API available for manual testing. |
| Risks | Async state races; repeated load calls; poor error messages; local API URL mismatch on simulator. |
| Acceptance criteria | Events loads from `GET /api/events`; pull-to-refresh reloads; empty/error states work; unit tests cover success/failure/empty refresh; app remains runnable without APNs. |
| Manual test plan | Start existing Node API; run app on simulator; open Events; verify empty state; send fake garage event with curl; refresh Events; verify event card appears. Stop and verify live timeline behavior before Debug parity. |
| Suggested commit message | `Wire Events screen to API` |
| Recommended GPT-5.5 reasoning level | High |

## Stage 10: Debug Screen Parity Without Native Push

| Field | Details |
| --- | --- |
| Objective | Implement the Debug screen UI and test-push request path while keeping native push registration clearly marked as pending/unavailable. |
| User-visible outcome | Debug shows API URL, native push status placeholder, token placeholder, Register action disabled or explanatory, Send test push action if safe against current API. |
| Workstream | Client UI, Client infrastructure |
| Files/directories likely created | `LevyHome/ViewModels/DebugViewModel.swift`; `LevyHomeTests/DebugViewModelTests.swift`. |
| Files/directories likely modified | `LevyHome/Views/Debug/DebugView.swift`; `LevyHome/App/AppEnvironment.swift`; maybe `LevyHome/Views/Shared/InfoPanel.swift`. |
| Dependencies | Stage 7 and Stage 4. |
| Risks | Confusing users by implying push is fully supported; exposing unauthenticated debug test push in release builds. |
| Acceptance criteria | Debug UI matches current diagnostic intent; status clearly says native APNs registration is not implemented yet; test push call handles success/failure if enabled; Release hiding policy is at least represented by config flag. |
| Manual test plan | Run on simulator; open Debug; verify API URL and native-pending push status; optionally call existing test-push endpoint and verify response handling. Stop and verify Cut Line 1: client parity without native push remains independent of APNs. |
| Suggested commit message | `Add Debug screen parity without push` |
| Recommended GPT-5.5 reasoning level | High |

## Stage 11: Native APNs Permission And Token Milestone

| Field | Details |
| --- | --- |
| Objective | Add native notification permission flow, APNs registration, app delegate callback handling, and app-level push registration state without requiring backend APNs sending. This is the physical-device-only APNs milestone. |
| User-visible outcome | On a physical iPhone, Debug can request notification permission and show an APNs token or error. Simulator shows a clear unavailable state. |
| Workstream | Native APNs |
| Files/directories likely created | `LevyHome/Services/NotificationService.swift`; `LevyHome/App/AppDelegate.swift`; `LevyHome/ViewModels/PushRegistrationViewModel.swift`; `LevyHomeTests/PushRegistrationViewModelTests.swift`. |
| Files/directories likely modified | `LevyHome/App/LevyHomeApp.swift`; `LevyHome/App/AppEnvironment.swift`; `LevyHome/Views/Home/HomeView.swift`; `LevyHome/Views/Debug/DebugView.swift`; entitlement/project capability files. |
| Dependencies | Stage 10; Apple developer team/provisioning access; physical iPhone; Push Notifications capability. |
| Risks | Provisioning/signing failures; simulator behavior differs from device; permission denial edge cases; APNs token callback timing. |
| Acceptance criteria | Physical device receives APNs token; Home and Debug show registered/native-token status; permission denied and APNs failure states are visible; simulator does not crash and reports unavailable. |
| Manual test plan | Build to physical iPhone; launch app; tap Register in Debug; accept permission; verify APNs token appears; delete/reinstall and test permission-denied path if practical; run simulator and verify unavailable state. Stop and verify Cut Line 2: native APNs registration. |
| Suggested commit message | `Add native APNs registration` |
| Recommended GPT-5.5 reasoning level | Max |

## Stage 12: Client Device Registration Contract Adapter

| Field | Details |
| --- | --- |
| Objective | Prepare the native client for provider-aware device registration once the backend contract exists, while keeping current app runnable if backend work is not complete. |
| User-visible outcome | Debug can show whether APNs token registration with the API is pending, skipped, successful, or failed. |
| Workstream | Client infrastructure, Native APNs |
| Files/directories likely created | None expected unless adding `DeviceRegistrationState.swift`. |
| Files/directories likely modified | `LevyHome/Models/APIRequests.swift`; `LevyHome/Models/APIResponses.swift`; `LevyHome/Services/APIClient.swift`; `LevyHome/ViewModels/PushRegistrationViewModel.swift`; related tests. |
| Dependencies | Stage 11; agreed backend registration request shape. |
| Risks | Overloading current `pushToken` semantics; breaking client parity against existing API; making backend APNs work seem complete when only client request shape is ready. |
| Acceptance criteria | Client can build a provider-aware APNs registration request; if backend is unavailable, UI reports API registration failure without losing APNs token state; tests cover success/failure with stubbed API. |
| Manual test plan | Run unit tests; on physical device, obtain APNs token; attempt API registration against current backend if configured; verify graceful failure or success depending on backend readiness. Stop and verify client APNs state is separate from server push delivery. |
| Suggested commit message | `Prepare APNs device registration contract` |
| Recommended GPT-5.5 reasoning level | High |

## Stage 13: Backend Provider-Aware Device Registration

| Field | Details |
| --- | --- |
| Objective | Update the existing Node/Express API to accept and store provider-aware APNs device registrations without changing Home Assistant event ingestion or timeline contracts. |
| User-visible outcome | Native app can register its APNs token with the API; no push delivery is guaranteed yet. |
| Workstream | Backend |
| Files/directories likely created | Backend tests if test structure exists; provider-aware registration helper if useful. |
| Files/directories likely modified | `levy-home-app/apps/api/src/server.ts`; `levy-home-app/packages/shared/src/index.ts` only if shared request types are added; API docs if needed. |
| Dependencies | Stage 12; backend development environment. |
| Risks | Breaking Expo development clients if still used; storing sandbox/production tokens ambiguously; expanding backend scope into persistence/auth. |
| Acceptance criteria | API accepts provider-aware APNs registration body; preserves or deliberately versions current Expo token behavior; returns registered device count; does not alter `/api/events` or `/api/ha/events` behavior. |
| Manual test plan | Run API locally; register sample APNs token with curl; register from physical native app; verify response and server log/device count; run existing manual event curl and verify timeline still works. Stop and verify backend registration before APNs sending. |
| Suggested commit message | `Add provider-aware device registration` |
| Recommended GPT-5.5 reasoning level | Max |

## Stage 14: Backend APNs Sender And Debug Push

| Field | Details |
| --- | --- |
| Objective | Add APNs push sending on the backend and adapt debug/test push behavior to provider-neutral results. This completes backend APNs push-provider migration. |
| User-visible outcome | Registered native devices can receive backend-sent APNs test pushes. |
| Workstream | Backend |
| Files/directories likely created | APNs service module if extracting from `server.ts`; APNs environment/config docs; backend tests if available. |
| Files/directories likely modified | `levy-home-app/apps/api/src/server.ts`; `levy-home-app/apps/api/.env.example`; `levy-home-app/docs/local-dev.md` or backend-specific docs if documenting APNs setup; native `TestPushResponse` model if response shape changes. |
| Dependencies | Stage 13; APNs key/certificate decision; APNs credentials available to backend environment; physical iPhone registered from Stage 11/12. |
| Risks | APNs credential handling; sandbox/production mismatch; invalid token cleanup; accidentally committing secrets; breaking Expo push path before native push is proven. |
| Acceptance criteria | Debug endpoint can send APNs notification to a registered native device; response uses provider-neutral counts; APNs credentials are loaded from environment and never committed; Expo-specific response fields are either optional or deprecated safely. |
| Manual test plan | Configure APNs credentials locally or in test backend; register physical device; call debug test-push endpoint; confirm notification arrives; verify invalid/missing credential errors are readable and do not crash API. Stop and verify Cut Line 3: backend APNs push-provider migration. |
| Suggested commit message | `Add APNs push sender` |
| Recommended GPT-5.5 reasoning level | Max |

## Stage 15: End-To-End Garage Notification Verification

| Field | Details |
| --- | --- |
| Objective | Verify the real product pipeline from fake or real Home Assistant garage event through backend APNs push and native timeline display. |
| User-visible outcome | A physical iPhone receives garage event notifications and shows the events in the native timeline. |
| Workstream | QA |
| Files/directories likely created | `levy-home/docs/manual-qa-garage-notifications.md` only if capturing QA evidence is desired. |
| Files/directories likely modified | Existing docs only if manual QA findings require clarifying steps; no app source changes unless a bug fix is split into its own commit. |
| Dependencies | Stage 14; physical iPhone; local or deployed API; Home Assistant webhook secret for fake curl tests; dedupe cooldown awareness. |
| Risks | APNs sandbox/production mismatch; dedupe causing false negatives; Home Assistant entity/timezone assumptions; physical-device network reachability. |
| Acceptance criteria | All five MVP garage event types can be sent; expected pushes arrive; dedupe skip behavior is understood; Events timeline shows newest-first entries; Home/Settings/Debug show correct environment and push status. |
| Manual test plan | On physical iPhone, register APNs token; send `garage_opened`, `garage_closed`, `garage_left_open_10_min`, `garage_opened_after_hours`, and `garage_still_open_at_10pm` curl events; confirm push and timeline for each; repeat one event within cooldown and verify skip reason if applicable. Stop and verify Cut Line 4: end-to-end physical-device garage notification verification. |
| Suggested commit message | `Verify garage APNs notification flow` |
| Recommended GPT-5.5 reasoning level | Max |

## Stage 16: Production/TestFlight Readiness

| Field | Details |
| --- | --- |
| Objective | Prepare the native app and backend configuration for internal TestFlight distribution without adding deferred product scope. |
| User-visible outcome | Internal testers can install a correctly configured build and verify notifications against the intended backend. |
| Workstream | Production |
| Files/directories likely created | Release checklist doc if needed; export/archive notes. |
| Files/directories likely modified | Xcode project signing/build settings; `LevyHome/App/BuildConfiguration.swift`; `LevyHome/Resources/Info.plist`; `LevyHome/Resources/PrivacyInfo.xcprivacy`; docs for release/testflight steps. |
| Dependencies | Stage 15; Apple developer/TestFlight access; final bundle ID; release API URL; APNs production environment configured. |
| Risks | Signing/provisioning drift; Debug tab accidentally shipping broadly; production API still exposing unauthenticated debug endpoint; privacy manifest mismatch. |
| Acceptance criteria | Archive succeeds; build uses release API URL; APNs production environment is configured; Debug tab behavior follows policy; no secrets are in app source; privacy manifest reflects actual APIs used; internal TestFlight install launches. |
| Manual test plan | Archive Release/Internal build; install via TestFlight or direct internal distribution; launch app; verify API URL/environment; register for notifications on physical device; send one test garage event through intended backend. Stop and verify Cut Line 5: Production/TestFlight readiness. |
| Suggested commit message | `Prepare internal TestFlight build` |
| Recommended GPT-5.5 reasoning level | Max |

## Future Work Not In This Roadmap

These items are intentionally deferred. They should become separate discovery/architecture/roadmap updates before implementation.

| Future item | Why deferred |
| --- | --- |
| Dark mode | Current reference UI is effectively light-only; parity comes first. |
| Production user authentication | Current product scope excludes auth; adding it affects backend, storage, UX, and security model. |
| Doorbell/eufy integration | Event types exist as placeholders, but reliability and Home Assistant mapping are not yet validated. |
| Local event caching/offline timeline | Existing Expo app has no local persistence; backend persistence should be solved first if durability is needed. |
| Backend event/device persistence | Important production hardening, but separate from native client parity and APNs provider migration. |
| Notification deep-link routing | Current app does not route notification taps; Events tab opening/highlighting can be added later. |
| Widgets, Apple Watch, Android | Explicitly out of current product scope. |
| Home Assistant dashboard or device controls | Levy Home is a notification layer, not a Home Assistant replacement. |
| Camera live view/two-way talk | Explicitly out of scope for MVP and native parity. |
| Automation builder | Home Assistant remains the automation brain. |

## Implementation Notes For Future Agents

- Start each stage by reading the acceptance criteria and stop after they pass.
- Keep commits focused even if nearby cleanup is tempting.
- If a stage reveals a contradiction in the architecture, document it before redesigning.
- Prefer manual physical-device checks for APNs over simulator assumptions.
- Never commit APNs keys, Home Assistant secrets, or production credentials.
- Do not let backend APNs work block the first simulator-runnable SwiftUI app.
