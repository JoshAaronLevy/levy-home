# SwiftUI Implementation Roadmap

This roadmap converts `docs/01-migration-discovery.md`, `docs/02-swiftui-architecture.md`, and `docs/04-product-scope-update.md` into small, sequential, independently committable implementation stages for the native SwiftUI rebuild.

The first goal is still to make the app runnable as early as possible. The revised product goal is broader than the original notification timeline: Levy Home is now a family-focused home notification and lightweight control application. Client product parity, notification history, Preferences, native APNs registration, backend APNs push-provider migration, and production readiness remain separate cut lines.

## Roadmap Guardrails

- Do not redo discovery during implementation.
- Do not redesign the architecture unless a concrete contradiction is found and documented.
- Keep each implementation commit focused; target 1-5 files per commit where practical.
- Each stage stops after its own acceptance criteria.
- Do not combine unrelated UI, Home Assistant facade, APNs, backend push, and release-readiness work.
- Do not add production auth, doorbell integration, local event caching, backend persistence, deep-link routing, widgets, arbitrary device management, camera features, automation builder features, or full Home Assistant dashboard features during this roadmap.
- Dark mode is intentionally deferred until Stage 19 so the APNs, garage notification, and TestFlight readiness path remains focused.
- Use SwiftUI, async/await, URLSession, UserDefaults for non-sensitive preferences, and Keychain only when future secrets exist.
- Route selected controls through the Levy Home API facade. Do not put Home Assistant credentials or arbitrary HA service/entity payloads in the iOS app.
- Keep new implementation work in `levy-home`. Use `levy-home-app` only as conceptual reference unless explicitly directed otherwise.
- Avoid TCA, Redux, Flux, coordinators, dependency injection frameworks, and enterprise architecture patterns.

## Cut Lines

| Cut line | Completed by | Meaning |
| --- | --- | --- |
| 1. Client parity without native push | Stage 12 | Native app is runnable with revised primary navigation, Home command center, Activity timeline, Notifications history, Preferences with local notification preferences, selected quick actions, and Debug moved out of primary navigation. Native APNs is not required. |
| 2. Native APNs registration | Stage 13 | Native app requests notification permission and obtains APNs token on a physical device, independent of backend push delivery. |
| 3. Backend APNs push-provider migration | Stage 16 | Backend accepts provider-aware APNs registrations and sends APNs pushes. |
| 4. End-to-end physical-device garage notification verification | Stage 17 | Garage events produce APNs notifications, Activity entries, and Home overview updates on a physical iPhone. |
| 5. Production/TestFlight readiness | Stage 18 | Build/config/release checks are complete for internal distribution. |
| 6. Theme preference and dark mode | Stage 19 | Preferences includes a Theme setting, and the app supports System, Light, and Dark appearance with polished styling. |

## Reasoning Levels

| Level | Use for |
| --- | --- |
| Low | Tiny mechanical changes. |
| Medium | Static SwiftUI screens, simple styling, simple models. |
| High | API client, async state, error handling, selected control state, APNs setup. |
| Max | Backend APNs migration, Home Assistant action facade safety, provisioning/signing issues, end-to-end push debugging. |

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
| Objective | Add the small composition root described in the architecture without implementing network, controls, preferences, or notification behavior yet. |
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

## Stage 2: Revised Simulator-Only Tab Shell

| Field | Details |
| --- | --- |
| Objective | Create the revised product navigation with Home, Activity, Notifications, and Preferences primary tabs; keep Developer Tools out of primary navigation. This is the first simulator-only milestone. |
| User-visible outcome | The app launches on simulator with a native tab bar and four family-facing tabs. |
| Workstream | Client UI |
| Files/directories likely created | `LevyHome/Views/Root/RootTabView.swift`; `LevyHome/Views/Home/HomeView.swift`; `LevyHome/Views/Activity/ActivityView.swift`; `LevyHome/Views/Notifications/NotificationHubView.swift`; `LevyHome/Views/Preferences/PreferencesView.swift`; `LevyHome/Views/Preferences/NotificationPreferencesView.swift`; `LevyHome/Views/DeveloperTools/DebugView.swift` if build-gated early. |
| Files/directories likely modified | `LevyHome/App/LevyHomeApp.swift`; `LevyHome/App/BuildConfiguration.swift`. |
| Dependencies | Stage 1. |
| Risks | Accidentally preserving Debug as a normal product tab; adding navigation beyond the flat tab shell. |
| Acceptance criteria | Simulator shows Home, Activity, Notifications, and Preferences tabs; Debug is absent from primary tabs; each tab has simple placeholder text; Notifications is framed as history; Preferences is framed as delivery status and preference editing; no networking or push permission prompt occurs. |
| Manual test plan | Run on simulator; tap each primary tab; confirm no crash and no native permission prompts. Stop and verify the first runnable revised tabbed app before visual parity. |
| Suggested commit message | `Add revised SwiftUI tab shell` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 3: Theme And Command-Center UI Primitives

| Field | Details |
| --- | --- |
| Objective | Add the small visual foundation for a polished family command center: colors, spacing, cards, buttons, banners, status badges, and action progress states. |
| User-visible outcome | Placeholder screens can use the quiet family-friendly panel/card style for Home and Activity. |
| Workstream | Client UI |
| Files/directories likely created | `LevyHome/Theme/AppColors.swift`; `LevyHome/Theme/AppSpacing.swift`; `LevyHome/Views/Shared/InfoPanel.swift`; `LevyHome/Views/Shared/ErrorBannerView.swift`; `LevyHome/Views/Shared/PrimaryActionButton.swift`; `LevyHome/Views/Shared/StatusBadgeView.swift`. |
| Files/directories likely modified | Existing placeholder views only as needed to prove the shared components compile. |
| Dependencies | Stage 2. |
| Risks | Over-polishing or adding dark mode; creating a large design system. |
| Acceptance criteria | Shared components compile; styling supports Home status cards and quick actions; no dark mode scope added; app still launches on simulator. |
| Manual test plan | Run on simulator; inspect a placeholder Home screen using status/action components; verify no text clipping in default simulator size. Stop and verify UI primitives before building real Home sections. |
| Suggested commit message | `Add command center UI primitives` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 4: Static Home Command Center

| Field | Details |
| --- | --- |
| Objective | Replace the passive Home placeholder with static/sample command-center UI: garage status, light summary, recent important event summary, and quick actions. |
| User-visible outcome | Home feels like the primary family command center, even before live data exists. |
| Workstream | Client UI |
| Files/directories likely created | `LevyHome/Views/Home/GarageStatusCard.swift`; `LevyHome/Views/Home/LightSummaryCard.swift`; `LevyHome/Views/Home/RecentImportantEventView.swift`; `LevyHome/Views/Home/QuickActionsView.swift`; `LevyHome/PreviewSupport/PreviewData.swift`. |
| Files/directories likely modified | `LevyHome/Views/Home/HomeView.swift`. |
| Dependencies | Stage 3. |
| Risks | Turning Home into a generic dashboard; adding live controls before contracts exist. |
| Acceptance criteria | Home shows sample garage state, sample light summary, sample recent important event, and disabled/sample quick actions; no network calls occur; UI is scannable in the first viewport. |
| Manual test plan | Run on simulator; inspect Home; verify quick actions are present but safe/inert; verify the screen does not expose Home Assistant entity IDs. Stop and verify Home direction before adding models. |
| Suggested commit message | `Add static Home command center` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 5: Domain Models For Events, Status, Actions, And Preferences

| Field | Details |
| --- | --- |
| Objective | Add Swift models for the revised MVP: events, garage status, light summary, Home overview, quick actions, action results, and notification preferences. |
| User-visible outcome | No UI change; the app gains typed models for Home, Activity, Notifications, and Preferences. |
| Workstream | Client infrastructure |
| Files/directories likely created | `LevyHome/Models/EventType.swift`; `LevyHome/Models/EventSeverity.swift`; `LevyHome/Models/LevyHomeEvent.swift`; `LevyHome/Models/HomeOverview.swift`; `LevyHome/Models/GarageStatus.swift`; `LevyHome/Models/LightSummary.swift`; `LevyHome/Models/QuickAction.swift`; `LevyHome/Models/NotificationPreference.swift`; `LevyHomeTests/ModelDecodingTests.swift`. |
| Files/directories likely modified | Test target configuration if needed. |
| Dependencies | Stage 1; contracts from architecture and product-scope docs. |
| Risks | Strict enum decoding could break forward compatibility; models may drift into generic HA device models. |
| Acceptance criteria | Tests decode all five garage event types, garage status variants, light summary examples, quick action results, notification preferences, optional fields, and unknown enum fallback where appropriate. |
| Manual test plan | Run unit tests; confirm app still builds on simulator. Stop and verify the domain boundary remains curated. |
| Suggested commit message | `Add revised MVP domain models` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 6: API Error, Request, And Response Models

| Field | Details |
| --- | --- |
| Objective | Add typed request/response/error models for events, Home overview, quick actions, notification preferences, device registration, and debug push. |
| User-visible outcome | No visible UI change. |
| Workstream | Client infrastructure |
| Files/directories likely created | `LevyHome/Models/APIResponses.swift`; `LevyHome/Models/APIRequests.swift`; `LevyHome/Models/APIError.swift`. |
| Files/directories likely modified | `LevyHomeTests/ModelDecodingTests.swift` or a small response decoding test file. |
| Dependencies | Stage 5. |
| Risks | Baking in arbitrary HA command payloads; baking in Expo-specific test-push terminology too deeply. |
| Acceptance criteria | Response models compile; sample `HomeOverviewResponse`, `QuickActionResponse`, `NotificationPreferencesResponse`, `EventsResponse`, `RegisterDeviceResponse`, `TestPushResponse`, and `APIErrorResponse` decode; action requests use curated action IDs or explicit request types only. |
| Manual test plan | Run unit tests; confirm app still builds on simulator. Stop and verify response/request models before URLSession work. |
| Suggested commit message | `Add revised API models` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 7: Expanded URLSession API Client

| Field | Details |
| --- | --- |
| Objective | Implement typed `APIClient` methods for events, Home overview, selected quick actions, notification preferences, device registration, and debug push using async/await. |
| User-visible outcome | No direct UI change yet; services can call the future backend facade. |
| Workstream | Client infrastructure |
| Files/directories likely created | `LevyHome/Services/APIClient.swift`; `LevyHomeTests/APIClientTests.swift`. |
| Files/directories likely modified | `LevyHome/App/AppEnvironment.swift`; possibly `LevyHome/App/AppConfig.swift`. |
| Dependencies | Stage 6. |
| Risks | Async error handling bugs; malformed URL handling; accidentally calling real network in unit tests; allowing arbitrary HA actions. |
| Acceptance criteria | API client supports current `/api/events`, future `/api/home/overview`, selected quick actions, preferences, registration, debug push, and optional health; tests cover success, server error envelope, HTTP error, transport failure, invalid base URL, and decoding failure. |
| Manual test plan | Run unit tests; do not require live backend facade yet. Stop and verify API client behavior before wiring UI. |
| Suggested commit message | `Add expanded API client` |
| Recommended GPT-5.5 reasoning level | High |

## Stage 8: Activity Timeline With Sample And Live Event Data

| Field | Details |
| --- | --- |
| Objective | Build Activity UI and wire it to the existing events API, including empty, loading, refresh, and error states. |
| User-visible outcome | Activity tab displays real recent events from the existing Node/Express API. |
| Workstream | Client UI, Client infrastructure |
| Files/directories likely created | `LevyHome/Views/Activity/EventCardView.swift`; `LevyHome/Views/Activity/SeverityBadgeView.swift`; `LevyHome/ViewModels/ActivityViewModel.swift`; `LevyHomeTests/ActivityViewModelTests.swift`; optionally `LevyHome/Services/DateFormattingService.swift`. |
| Files/directories likely modified | `LevyHome/Views/Activity/ActivityView.swift`; `LevyHome/App/AppEnvironment.swift`. |
| Dependencies | Stage 7; local API available for manual testing. |
| Risks | Async state races; repeated load calls; poor error messages; local API URL mismatch on simulator. |
| Acceptance criteria | Activity loads from `GET /api/events`; pull-to-refresh reloads; empty/error states work; unit tests cover success/failure/empty refresh; app remains runnable without APNs. |
| Manual test plan | Start existing Node API; run app on simulator; open Activity; verify empty state; send fake garage event with curl; refresh Activity; verify event card appears. Stop and verify event history before Home live data. |
| Suggested commit message | `Wire Activity timeline to API` |
| Recommended GPT-5.5 reasoning level | High |

## Stage 9: Preferences UI With Local Notification Preferences

| Field | Details |
| --- | --- |
| Objective | Implement the Preferences tab with product-safe delivery status and garage notification preferences using local `UserDefaults` persistence. Keep Notifications focused on notification history. Backend enforcement can come later. |
| User-visible outcome | User can open Preferences to see whether notifications are allowed/registered in plain language, choose a notification category such as Garage, toggle that category's notification settings on a detail screen, and see preferences persist across app launches; Notifications remains a simple history surface. |
| Workstream | Client UI, Client infrastructure |
| Files/directories likely created | `LevyHome/Views/Preferences/PreferencesView.swift`; `LevyHome/Views/Preferences/NotificationDeliveryStatusView.swift`; `LevyHome/Services/NotificationPreferencesService.swift`; `LevyHome/ViewModels/NotificationPreferencesViewModel.swift`; `LevyHomeTests/NotificationPreferencesViewModelTests.swift`. |
| Files/directories likely modified | `LevyHome/Views/Root/RootTabView.swift`; `LevyHome/Views/Notifications/NotificationHubView.swift`; `LevyHome/Views/Preferences/NotificationPreferencesView.swift`; `LevyHome/App/AppEnvironment.swift`; `LevyHome/Services/SettingsStore.swift` if used. |
| Dependencies | Stage 5 and Stage 3. |
| Risks | Implying preferences already affect server push delivery; exposing developer-only token details in family-facing Preferences; burying future categories in UI too early. |
| Acceptance criteria | Preferences shows product-safe notification delivery status without raw tokens; Preferences root lists Garage as a clean category row instead of showing all toggles; tapping Garage opens a detail screen with five garage preferences; toggles persist locally; Notifications is history-only; UI clearly remains simple; future doorbell/person/motion categories are hidden or disabled until implemented; no backend sync required yet. |
| Manual test plan | Run on simulator; inspect Preferences notification status copy; tap Garage; toggle each preference; quit/relaunch app; verify values persist; confirm Notifications shows history only and no APNs permission prompt occurs. Stop and verify preference architecture before backend enforcement. |
| Suggested commit message | `Add notification preferences UI` |
| Recommended GPT-5.5 reasoning level | Medium |

## Stage 10: Backend Home Status And Action Facade

| Field | Details |
| --- | --- |
| Objective | Add narrow backend endpoints for Home overview status and selected quick actions, without adding backend persistence, production auth, or arbitrary HA control. |
| User-visible outcome | The API can provide garage/light summary and execute curated actions for the native app. |
| Workstream | Backend |
| Files/directories likely created | New or ported backend/API helper/service modules under `levy-home`; backend docs for required HA configuration if needed. |
| Files/directories likely modified | Backend/API files in `levy-home`; `.env.example` or equivalent in `levy-home`; possibly a new docs note for status/action facade. Do not modify `levy-home-app` unless explicitly directed. |
| Dependencies | Confirmed Home Assistant reachable API strategy; server-side HA token/config available outside source control; curated entity/group IDs known or placeholder-configured safely. |
| Risks | Accidentally exposing arbitrary HA service calls; committing HA credentials; implementing controls before status can verify result; expanding into dashboard scope. |
| Acceptance criteria | API exposes a narrow Home overview/status endpoint; API exposes selected actions for close garage, turn off all lights, and curated light groups; HA credentials stay server-side; arbitrary service/entity payloads from the app are rejected/not supported. |
| Manual test plan | Run API locally; call overview endpoint with curl; call each selected action against safe/test HA setup or mocked mode; verify errors are readable; verify event webhook and `/api/events` still work. Stop and verify backend facade safety before live Home integration. |
| Suggested commit message | `Add Home status and action facade` |
| Recommended GPT-5.5 reasoning level | Max |

## Stage 11: Live Home Overview Integration

| Field | Details |
| --- | --- |
| Objective | Wire Home to live overview/status data through `HomeOverviewViewModel` and `HomeStatusService`, including loading, partial, stale, and error states. |
| User-visible outcome | Home shows real garage status, real light summary, and recent important event summary from the API facade. |
| Workstream | Client UI, Client infrastructure |
| Files/directories likely created | `LevyHome/Services/HomeStatusService.swift`; `LevyHome/ViewModels/HomeOverviewViewModel.swift`; `LevyHomeTests/HomeOverviewViewModelTests.swift`. |
| Files/directories likely modified | `LevyHome/Views/Home/HomeView.swift`; Home section views; `LevyHome/App/AppEnvironment.swift`. |
| Dependencies | Stage 10; Stage 7. |
| Risks | Poor partial-data handling; making Home unusable when one status source fails; confusing stale status with real-time guarantee. |
| Acceptance criteria | Home loads overview data; supports retry/refresh; handles unknown garage status and partial light summary gracefully; recent important event summary uses backend or event data; tests cover success, partial, and failure states. |
| Manual test plan | Run API and simulator app; open Home; verify real/placeholder configured statuses; stop API and verify error state; restart API and refresh. Stop and verify Home status before enabling actions. |
| Suggested commit message | `Wire Home overview to API` |
| Recommended GPT-5.5 reasoning level | High |

## Stage 12: Live Quick Actions Integration

| Field | Details |
| --- | --- |
| Objective | Wire selected Home quick actions to the backend facade with confirmation, progress, success/failure, duplicate-tap protection, and post-action overview refresh. |
| User-visible outcome | User can close garage and turn off curated lights from Home when backend facade is configured. |
| Workstream | Client UI, Client infrastructure |
| Files/directories likely created | `LevyHome/Services/QuickActionService.swift`; `LevyHome/ViewModels/QuickActionsViewModel.swift`; `LevyHomeTests/QuickActionsViewModelTests.swift`. |
| Files/directories likely modified | `LevyHome/Views/Home/QuickActionsView.swift`; `LevyHome/Views/Home/HomeView.swift`; `LevyHome/App/AppEnvironment.swift`; API request/response tests if needed. |
| Dependencies | Stage 10 and Stage 11. |
| Risks | Accidental garage closure; duplicate action submissions; unclear failure messages; app drifting toward generic controls. |
| Acceptance criteria | Close garage requires confirmation; all quick actions disable while in progress; success/failure is visible; Home overview refreshes after action; only curated action IDs/endpoints are used; tests cover success, failure, cancellation, and duplicate taps. |
| Manual test plan | Run API and simulator app; trigger each action against safe/test setup; confirm progress/result states; verify status refresh; cancel garage confirmation; simulate API failure. Stop and verify Cut Line 1: client parity without native push. |
| Suggested commit message | `Wire Home quick actions to API` |
| Recommended GPT-5.5 reasoning level | High |

## Stage 13: Native APNs Permission And Token Milestone

| Field | Details |
| --- | --- |
| Objective | Add native notification permission flow, APNs registration, app delegate callback handling, and app-level push registration state without requiring backend APNs sending. This is the physical-device-only APNs milestone. |
| User-visible outcome | On a physical iPhone, Developer Tools can request notification permission and show an APNs token or error, while Preferences shows product-safe registration status. Simulator shows a clear unavailable state. |
| Workstream | Native APNs |
| Files/directories likely created | `LevyHome/Services/NotificationService.swift`; `LevyHome/App/AppDelegate.swift`; `LevyHome/ViewModels/PushRegistrationViewModel.swift`; `LevyHomeTests/PushRegistrationViewModelTests.swift`. |
| Files/directories likely modified | `LevyHome/App/LevyHomeApp.swift`; `LevyHome/App/AppEnvironment.swift`; `LevyHome/Views/Preferences/NotificationDeliveryStatusView.swift`; `LevyHome/Views/DeveloperTools/DebugView.swift`; entitlement/project capability files. |
| Dependencies | Stage 12; Apple developer team/provisioning access; physical iPhone; Push Notifications capability. |
| Risks | Provisioning/signing failures; simulator behavior differs from device; permission denial edge cases; APNs token callback timing. |
| Acceptance criteria | Physical device receives APNs token; Developer Tools shows registered/native-token status; Preferences shows product-safe allowed/registered status; permission denied and APNs failure states are visible; simulator does not crash and reports unavailable. |
| Manual test plan | Build to physical iPhone; launch app; open Developer Tools; tap Register; accept permission; verify APNs token appears; delete/reinstall and test permission-denied path if practical; run simulator and verify unavailable state. Stop and verify Cut Line 2: native APNs registration. |
| Suggested commit message | `Add native APNs registration` |
| Recommended GPT-5.5 reasoning level | Max |

## Stage 14: Client Device Registration And Preference Sync Adapter

| Field | Details |
| --- | --- |
| Objective | Prepare the native client for provider-aware device registration and future backend notification preference sync once backend contracts exist. |
| User-visible outcome | Developer Tools can show whether APNs token registration with the API is pending, skipped, successful, or failed; Preferences can show product-safe sync status and later sync preferences without UI redesign. |
| Workstream | Client infrastructure, Native APNs |
| Files/directories likely created | None expected unless adding `DeviceRegistrationState.swift`. |
| Files/directories likely modified | `LevyHome/Models/APIRequests.swift`; `LevyHome/Models/APIResponses.swift`; `LevyHome/Services/APIClient.swift`; `LevyHome/ViewModels/PushRegistrationViewModel.swift`; `LevyHome/Services/NotificationPreferencesService.swift`; related tests. |
| Dependencies | Stage 13; agreed backend registration/preference request shape. |
| Risks | Overloading current `pushToken` semantics; implying local preferences already control server push delivery; breaking client parity against existing API. |
| Acceptance criteria | Client can build provider-aware APNs registration and preference sync requests; if backend is unavailable, Developer Tools reports technical API registration/sync failure while Preferences reports product-safe degraded status without losing local state; tests cover success/failure with stubbed API. |
| Manual test plan | Run unit tests; on physical device, obtain APNs token; attempt API registration against current backend if configured; verify graceful failure or success. Stop and verify client APNs state is separate from server push delivery. |
| Suggested commit message | `Prepare APNs registration and preference sync` |
| Recommended GPT-5.5 reasoning level | High |

## Stage 15: Backend Provider-Aware Device Registration And Preferences

| Field | Details |
| --- | --- |
| Objective | Update the existing Node/Express API to accept provider-aware APNs device registrations and per-device garage notification preferences without changing Home Assistant event ingestion or timeline contracts. |
| User-visible outcome | Native app can register its APNs token and sync garage notification preferences with the API; no push delivery is guaranteed yet. |
| Workstream | Backend |
| Files/directories likely created | Backend tests if test structure exists in `levy-home`; provider-aware registration/preference helper if useful. |
| Files/directories likely modified | Backend/API files and shared request models in `levy-home`; API docs if needed. Do not modify `levy-home-app` unless explicitly directed. |
| Dependencies | Stage 14; backend development environment. |
| Risks | Breaking Expo development clients if still used; storing sandbox/production tokens ambiguously; preference enforcement without persistence; expanding backend scope into production auth. |
| Acceptance criteria | API accepts provider-aware APNs registration body; API accepts/surfaces garage notification preferences by device token or device ID; preserves or deliberately versions current Expo token behavior; does not alter `/api/events` or `/api/ha/events` behavior. |
| Manual test plan | Run API locally; register sample APNs token with curl; sync sample preferences; register/sync from physical native app; verify response and server log/device count; run existing manual event curl and verify timeline still works. Stop and verify backend registration/preferences before APNs sending. |
| Suggested commit message | `Add provider-aware registration and preferences` |
| Recommended GPT-5.5 reasoning level | Max |

## Stage 16: Backend APNs Sender And Debug Push

| Field | Details |
| --- | --- |
| Objective | Add APNs push sending on the backend and adapt debug/test push behavior to provider-neutral results. This completes backend APNs push-provider migration. |
| User-visible outcome | Registered native devices can receive backend-sent APNs test pushes, honoring preferences where implemented. |
| Workstream | Backend |
| Files/directories likely created | APNs service module in `levy-home`; APNs environment/config docs; backend tests if available. |
| Files/directories likely modified | Backend/API files and `.env.example` or equivalent in `levy-home`; backend-specific docs if documenting APNs setup; native `TestPushResponse` model if response shape changes. Do not modify `levy-home-app` unless explicitly directed. |
| Dependencies | Stage 15; APNs key/certificate decision; APNs credentials available to backend environment; physical iPhone registered from Stage 13/14. |
| Risks | APNs credential handling; sandbox/production mismatch; invalid token cleanup; accidentally committing secrets; preference filtering bugs; breaking Expo push path before native push is proven. |
| Acceptance criteria | Debug endpoint can send APNs notification to a registered native device; response uses provider-neutral counts; APNs credentials are loaded from environment and never committed; Expo-specific response fields are optional or deprecated safely; preference handling is documented. |
| Manual test plan | Configure APNs credentials locally or in test backend; register physical device; call debug test-push endpoint; confirm notification arrives; toggle a garage preference if backend enforcement exists and verify behavior; verify invalid/missing credential errors are readable and do not crash API. Stop and verify Cut Line 3: backend APNs push-provider migration. |
| Suggested commit message | `Add APNs push sender` |
| Recommended GPT-5.5 reasoning level | Max |

## Stage 17: End-To-End Garage Notification And Control Verification

| Field | Details |
| --- | --- |
| Objective | Verify the real product pipeline: Home overview, selected controls, fake or real Home Assistant garage event, backend APNs push, Activity timeline, and notification preferences. |
| User-visible outcome | A physical iPhone can view home status, run selected quick actions, receive garage notifications, and see events in Activity. |
| Workstream | QA |
| Files/directories likely created | `levy-home/docs/manual-qa-garage-notifications.md` only if capturing QA evidence is desired. |
| Files/directories likely modified | Existing docs only if manual QA findings require clarifying steps; no app source changes unless a bug fix is split into its own commit. |
| Dependencies | Stage 16; physical iPhone; local or deployed API; Home Assistant webhook secret for fake curl tests; safe configured HA entities/groups; dedupe cooldown awareness. |
| Risks | APNs sandbox/production mismatch; dedupe causing false negatives; Home Assistant entity/timezone assumptions; unsafe garage action testing; physical-device network reachability. |
| Acceptance criteria | Home overview loads; close garage confirmation/cancel path works; light-off actions work against safe curated groups; all five MVP garage event types can be sent; expected pushes arrive according to preferences; Activity shows newest-first entries; Preferences shows correct product-safe status; Notifications remains history-focused; Debug/Developer Tools show correct environment and technical push status. |
| Manual test plan | On physical iPhone, register APNs token; load Home; run safe quick actions; send `garage_opened`, `garage_closed`, `garage_left_open_10_min`, `garage_opened_after_hours`, and `garage_still_open_at_10pm` curl events; confirm push and Activity for each; toggle one preference and verify expected behavior if backend enforcement exists; repeat one event within cooldown and verify skip reason if applicable. Stop and verify Cut Line 4: end-to-end physical-device garage notification verification. |
| Suggested commit message | `Verify garage notification and control flow` |
| Recommended GPT-5.5 reasoning level | Max |

## Stage 18: Production/TestFlight Readiness

| Field | Details |
| --- | --- |
| Objective | Prepare the native app and backend configuration for internal TestFlight distribution without adding deferred product scope. |
| User-visible outcome | Internal testers can install a correctly configured build and verify Home overview, selected controls, preferences, and notifications against the intended backend. |
| Workstream | Production |
| Files/directories likely created | Release checklist doc if needed; export/archive notes. |
| Files/directories likely modified | Xcode project signing/build settings; `LevyHome/App/BuildConfiguration.swift`; `LevyHome/Resources/Info.plist`; `LevyHome/Resources/PrivacyInfo.xcprivacy`; docs for release/testflight steps. |
| Dependencies | Stage 17; Apple developer/TestFlight access; final bundle ID; release API URL; APNs production environment configured; safe production HA facade configuration. |
| Risks | Signing/provisioning drift; Developer Tools accidentally shipping broadly; production API still exposing unauthenticated debug/action endpoints; privacy manifest mismatch; selected controls increase safety/security review needs. |
| Acceptance criteria | Archive succeeds; build uses release API URL; APNs production environment is configured; Developer Tools behavior follows policy; no secrets are in app source; privacy manifest reflects actual APIs used; internal TestFlight install launches; selected controls are confirmed safe or disabled for the build. |
| Manual test plan | Archive Release/Internal build; install via TestFlight or direct internal distribution; launch app; verify API URL/environment; load Home; verify controls are safe/enabled as intended; register for notifications on physical device; send one test garage event through intended backend. Stop and verify Cut Line 5: Production/TestFlight readiness. |
| Suggested commit message | `Prepare internal TestFlight build` |
| Recommended GPT-5.5 reasoning level | Max |

## Stage 19: Theme Preference And Dark Mode Styling

| Field | Details |
| --- | --- |
| Objective | Add a family-facing Theme setting in Preferences and complete dark theme styling across the app. |
| User-visible outcome | User can choose System, Light, or Dark appearance from Preferences. The default is System when iOS exposes the system color scheme, otherwise Light. Home, Activity, Notifications, Preferences, Developer Tools, status badges, banners, buttons, and cards all look intentional in light and dark appearances. |
| Workstream | Client UI, Client infrastructure |
| Files/directories likely created | `LevyHome/Models/ThemePreference.swift`; `LevyHome/Services/ThemePreferenceService.swift`; `LevyHome/ViewModels/ThemePreferenceViewModel.swift`; `LevyHome/Views/Preferences/ThemePreferenceView.swift`; `LevyHomeTests/ThemePreferenceViewModelTests.swift`. |
| Files/directories likely modified | `LevyHome/App/AppEnvironment.swift`; `LevyHome/App/LevyHomeApp.swift` or `LevyHome/Views/Root/RootTabView.swift`; `LevyHome/Theme/AppColors.swift`; shared components and feature views that use fixed colors; `LevyHome/Views/Preferences/PreferencesView.swift`; simulator testing guide if the manual appearance check flow changes. |
| Dependencies | Stage 18, or explicit decision to pull theme work earlier after push/release risk is handled. |
| Risks | Fixed colors that look fine in Light but fail in Dark; overriding system appearance too aggressively; adding a top-level tab instead of a Preferences row; changing the app's product IA while touching styling. |
| Acceptance criteria | Default theme preference is System when identifiable and Light as fallback; Preferences root includes a clean Theme row; tapping Theme opens a detail screen with System, Light, and Dark options; selection persists across launches; System follows iOS appearance changes; Light and Dark force the selected appearance app-wide; all existing product screens and Developer Tools are legible and polished in Light and Dark; no new product tabs or unrelated settings are added. |
| Manual test plan | Run app in simulator; open Preferences; confirm Theme row appears; open Theme detail and select System, Light, and Dark; quit/relaunch after each forced selection; verify Home, Activity, Notifications, Preferences, Garage notification detail, Developer Tools, loading/error/empty states, action progress/result states, and tab/navigation bars in both appearances; toggle simulator/system appearance and verify System mode follows it. |
| Suggested commit message | `Add theme preference and dark mode` |
| Recommended GPT-5.5 reasoning level | Medium |

## Future Work Not In This Roadmap

These items are intentionally deferred. They should become separate discovery/architecture/roadmap updates before implementation.

| Future item | Why deferred |
| --- | --- |
| Production user authentication | Current scope excludes auth; adding it affects backend, storage, UX, and security model. Revisit before broad internet exposure. |
| Doorbell/eufy/person/motion integration | Event types exist as placeholders, but reliability and Home Assistant mapping are not yet validated. |
| Local event caching/offline timeline | Existing Expo app has no local persistence; backend persistence should be solved first if durability is needed. |
| Backend event/device persistence | Important production hardening, but separate from native client parity, controls, and APNs provider migration. |
| Notification deep-link routing | Current app does not route notification taps; Activity opening/highlighting can be added later. |
| Widgets, Apple Watch, Android | Explicitly out of current product scope. |
| Full Home Assistant dashboard or arbitrary device management | Revised MVP includes only curated household status/actions. |
| Camera live view/two-way talk | Explicitly out of scope. |
| Automation builder | Home Assistant remains the automation brain. |
| Additional smart-home controls | Require separate product review to avoid dashboard creep. |

## Implementation Notes For Future Agents

- Start each stage by reading the acceptance criteria and stop after they pass.
- Keep commits focused even if nearby cleanup is tempting.
- If a stage reveals a contradiction in the architecture, document it before redesigning.
- Prefer manual physical-device checks for APNs over simulator assumptions.
- Never commit APNs keys, Home Assistant secrets, production credentials, or real HA tokens.
- Do not let backend APNs work block the first simulator-runnable SwiftUI app.
- Do not let selected controls expand into arbitrary Home Assistant device management.
