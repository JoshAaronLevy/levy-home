# Project Continuity Review

## Executive Summary

Current project state: `levy-home` now contains the native SwiftUI iOS project, core app composition, primary tab shell, theme primitives, live Home overview plumbing, live Home quick actions, typed models/API client, live Activity timeline plumbing, local notification preference UI, native APNs permission/token plumbing, client-side APNs API registration/preference-sync adapters, the Stage 10 backend Home status/action facade, Stage 15 backend provider-aware device registration plus per-device garage notification preference sync, Stage 16 backend APNs sender/debug push support, a Stage 17 manual QA evidence guide, a Stage 18 TestFlight readiness guide, and the Stage 19 Theme preference plus dark-mode styling pass. `levy-home` remains the working project for all new implementation.

The deprecated reference project, `levy-home-app`, is the existing Expo/React Native + Node/Express implementation. It has four Expo tabs: Home, Events, Settings, and Debug. The backend currently supports event ingestion, in-memory event history, Expo push token registration, Expo push sending, and debug test push. It does not currently expose Home overview/status, quick-action, notification-preference, or APNs endpoints. Because Expo issues prevented full validation, treat it as conceptual reference only, not an absolute source of truth.

Estimated completion percentage: approximately 95% by staged roadmap count, or roughly 80% by remaining risk. The biggest remaining work is physical-device garage notification/control verification, completing production/TestFlight readiness with real signing/backend/APNs inputs, and durable persistence/security hardening if needed.

Work already completed:

- Current Expo app and Node API have been inventoried in `docs/01-migration-discovery.md`.
- Target SwiftUI architecture exists in `docs/02-swiftui-architecture.md`.
- Staged implementation roadmap exists in `docs/03-implementation-roadmap.md`.
- Revised product scope exists in `docs/04-product-scope-update.md`.
- Native SwiftUI project baseline, app environment/config skeleton, and root `TabView` exist.
- Home is wired to the backend overview facade for live garage status, light status, recent important events, loading, refresh, partial, stale, and error states.
- Models, API request/response/error types, and `APIClient` exist with unit coverage.
- Activity is wired through `ActivityViewModel` for live event data and tested states.
- Preferences now contains product-safe delivery status plus a clean notification category list; Garage notification toggles live on a pushed detail screen and persist locally.
- Notifications is now focused on notification history only.
- Stage 10 backend facade exists in `apps/api`, with mock/live Home Assistant modes, `/api/home/overview`, curated quick-action routes, and event timeline endpoints.
- Home quick actions are wired through the backend facade with confirmation, progress, success/failure messaging, duplicate-tap protection, and post-action overview refresh.
- Native APNs permission and token plumbing exists in the iOS app, including `AppDelegate`, `NotificationService`, `PushRegistrationViewModel`, product-safe Preferences status, debug-only Developer Tools access, and Push Notifications entitlements.
- Client-side API registration and preference-sync adapters exist for APNs device registration and garage notification preferences, with technical failure reporting in Developer Tools and product-safe degraded status in Preferences.
- Backend provider-aware device registration exists for native APNs tokens, with APNs sandbox/production separation and legacy Expo push-token compatibility.
- Backend garage notification preferences can be synced and fetched per device by provider-aware token or registered device ID.
- Backend APNs sending exists through an environment-configured APNs provider, with provider-neutral debug/test push response counts.
- Garage Home Assistant events now attempt APNs delivery for mapped garage preference categories and honor per-device garage preferences.
- Stage 17 manual QA guidance exists in `docs/manual-qa-garage-notifications.md`.
- Stage 18 TestFlight readiness guidance exists in `docs/08-testflight-readiness.md`.
- The app privacy manifest now declares app-specific `UserDefaults` usage.
- Preferences now includes a Theme row and focused Theme detail screen with System, Light, and Dark choices.
- Theme preference persists locally, defaults to System, and applies app-wide through SwiftUI `preferredColorScheme`.
- App color tokens and shared UI components now render intentionally in light and dark appearances.
- Product direction has shifted from notification timeline only to family-focused notifications plus lightweight status/control.
- Product north star is a single Josh-and-Mallory family app over Home Assistant that replaces scattered vendor notifications and common control tasks across Hue/Lutron, Meross, SmartThings, LG ThinQ, and future integrations.

Work partially completed:

- Product scope update has been propagated into architecture and roadmap, including the newer split between Notifications history and Preferences.
- Architecture and roadmap now cover Home overview, garage/light status, quick actions, notification preferences, APNs, backend APNs migration, and build-gated Developer Tools.
- Preferences is now the product surface for delivery status and notification preference editing; Notifications is the read-only history surface.
- Discovery still contains older target-stage content, but now has a continuity note marking those parts as historical/superseded where they conflict with newer docs.

Work unfinished:

- Physical-device APNs delivery verification with real credentials and a real iPhone.
- Stage 17 evidence checklist execution.
- Stage 18 archive/TestFlight execution with Apple Developer signing, a non-localhost release API URL, production APNs, and a safe production Home Assistant facade.
- Durable backend persistence for events, devices, and preferences if/when required for production.
- End-to-end physical-device verification.
- Backend/API hardening still needed for production exposure, persistence, and protected debug/action endpoints.

## Documentation Audit

| Document | Complete | Needs revision | Conflicts found | Missing sections |
| --- | --- | --- | --- | --- |
| `docs/01-migration-discovery.md` | Complete as a deprecated reference-app inventory | Yes, if used as target implementation guidance | It describes the old current/reference app scope: notification timeline, Settings tab, Debug tab, no controls. Its later staged roadmap conflicts with the revised product vision. | It does not fully model the revised Home command center, notification hub, quick actions, or preferences because those were not in the reference app. A continuity note now marks those target assumptions as superseded and clarifies `levy-home-app` is conceptual reference only. |
| `docs/02-swiftui-architecture.md` | Mostly complete as target architecture | Minor revisions applied | Earlier versions had stale Events/Settings/Debug references and treated Notifications as the place for preferences. | Notifications history and Preferences are now separate. Theme preference architecture has been added for a later post-readiness implementation. Real backend contract shapes for status/actions/preferences still need finalization during implementation stages. |
| `docs/03-implementation-roadmap.md` | Mostly complete as staged roadmap | Minor revisions applied | Earlier versions supported preferences inside Notifications and explicitly deferred dark mode. | Stage 2 and Stage 9 now reflect a four-tab product shell. Stage 19 now covers theme preference and dark mode styling. Exact backend route shapes, APNs credential strategy, real HA entity/action configuration, and release security decisions remain intentionally deferred to their stages. |
| `docs/04-product-scope-update.md` | Complete as product direction update | Minor revisions applied | No material conflict with architecture/roadmap after this update. | Notification history and Preferences clarification was added. Theme preference is now planned after production/TestFlight readiness. Broader future categories remain deferred. |
| `docs/08-testflight-readiness.md` | Complete as a Stage 18 readiness checklist | No | No conflicts found | It intentionally records external blockers instead of claiming archive/TestFlight completion without signing, release API, production APNs, and physical-device validation. |

## Product Scope Alignment

| Scope item | Represented? | Notes |
| --- | --- | --- |
| Notification history and Preferences vision | Revised | The product now separates notification history from preference editing: Notifications is history-only, while Preferences owns delivery status and lists editable notification categories such as Garage. |
| Home overview/dashboard vision | Yes | Architecture and roadmap make Home the command center with garage status, light summary, recent important event, and quick actions. It remains curated, not a full dashboard. |
| Quick actions | Yes | Close garage, turn off all lights, and curated light-group actions are in architecture, product scope, and roadmap. |
| Notification preferences | Yes | Garage notification preferences are modeled as first-class UI/service/model work, with a Preferences category row, a Garage detail screen, local persistence first, and backend sync later. |
| Theme preference and dark mode | Yes | Stage 19 adds a Preferences Theme row, focused Theme detail screen, persisted System/Light/Dark choices, app-wide appearance override, and light/dark styling updates. |
| Debug tooling no longer primary UX | Yes | Architecture, roadmap, and product scope move Debug into build-gated Developer Tools. Discovery still describes the deprecated reference app's Debug tab, with a superseding continuity note. |

Remaining product gaps:

- Product-safe notification delivery wording and exact Preferences status states still need later APNs-stage refinement.
- Preferences can now sync to the backend per device, but they do not affect push delivery until Stage 16 or a later enforcement pass wires them into sending.
- Home overview and action facade contracts now exist, but real Home Assistant entity/action configuration still needs household-specific validation.

## Architecture Alignment

| Capability | Architecture support | Missing pieces |
| --- | --- | --- |
| Garage status | Yes | Backend `/api/home/overview` exists with garage status; iOS `HomeStatusService` and `HomeOverviewViewModel` now load and display live Home overview data. |
| Light status | Yes | Backend overview/facade support exists with light summary; iOS live Home wiring now displays live/partial/unknown light status. |
| Quick actions | Yes | Backend curated quick-action endpoints exist; iOS `QuickActionService`, `QuickActionsViewModel`, confirmation/progress/error states, duplicate-tap protection, and post-action overview refresh are implemented. |
| Notification preferences | Yes | `NotificationPreference`, `NotificationPreferencesService`, `NotificationPreferencesViewModel`, local `UserDefaults`, Preferences UI, provider-aware sync request construction, product-safe sync status, backend per-device preference sync, and garage event push filtering are implemented. |
| Theme preference | Yes | `ThemePreference`, `ThemePreferenceService`, `ThemePreferenceViewModel`, `ThemePreferenceView`, Preferences row/detail navigation, app-wide preferred color scheme binding, adaptive color tokens, and unit coverage are implemented. |
| Event timeline | Yes | `ActivityView`, `ActivityViewModel`, event models, `APIClient.fetchRecentEvents`, event cards, empty/error/refresh states are implemented. |
| APNs migration | Yes | Native `NotificationService`, `AppDelegate`, `PushRegistrationViewModel`, debug registration controls, simulator unavailable handling, entitlements, client API registration adapter, backend provider-aware device registration, APNs sender, and provider-neutral debug push endpoint are implemented. Physical-device end-to-end verification remains planned. |

Missing architecture details to settle during future stages:

- Final household-specific Home Assistant entity IDs and curated action groups.
- Final backend contract shape for notification preference sync/enforcement.
- Final backend/API location and runtime inside `levy-home`.
- Whether Developer Tools access is hidden tab, toolbar item, menu, or build-only route.
- Final bundle identifier and APNs sandbox/production handling.
- Security posture for any internet-accessible API, especially debug/action endpoints.

## Roadmap Alignment

The roadmap now supports the revised product vision. It includes:

- Early native project baseline.
- Revised Home/Activity/Notifications/Preferences primary navigation.
- Static Home command center before live data.
- Expanded models and API client for status, actions, preferences, events, registration, and debug push.
- Activity timeline integration.
- Notifications history plus Preferences with local notification preferences.
- Backend Home status/action facade.
- Live Home overview and quick actions.
- Native APNs registration.
- Provider-aware registration and preference sync.
- Backend APNs sender.
- End-to-end garage notification/control verification.
- Production/TestFlight readiness.
- Post-readiness theme preference and dark mode styling.
- Guardrails that keep all new implementation in `levy-home` and use `levy-home-app` only as conceptual reference.

Stages that must be added:

- Stage 19 has been added for theme preference and dark mode styling. The Notifications/Preferences split remains incorporated into existing Stage 2, Stage 9, Stage 13, Stage 14, and Stage 17.

Stages that must be modified:

- Stage 2: revised to use four product tabs: Home, Activity, Notifications, and Preferences.
- Stage 9: revised so Preferences owns delivery status and local preferences while Notifications remains history-only.
- Stage 13/14: revised so APNs state feeds Developer Tools and product-safe Preferences status.
- Stage 17: revised to verify Preferences status and Notifications history in end-to-end QA.
- Guardrails and future-work sections: revised so dark mode is no longer treated as indefinitely deferred and is instead planned for Stage 19.

Stages that should be removed:

- None from the current roadmap. The old discovery-document roadmap is superseded and should not be used as the implementation sequence.

## Recommended Next Action

Run Stage 17 physical-device end-to-end garage notification and control verification using `docs/manual-qa-garage-notifications.md`, then execute the Stage 18 archive/TestFlight checklist in `docs/08-testflight-readiness.md`.

Stop condition for the next step: a physical iPhone can register, receive expected APNs garage/debug notifications according to preferences, load Activity/Home updates, and safely verify curated controls.

## Documentation Updates Made

- Added a continuity note to `docs/01-migration-discovery.md` clarifying that its old target assumptions are historical/superseded where they conflict with newer docs.
- Updated `docs/02-swiftui-architecture.md` to represent Notifications history and Preferences, fix stale Activity/Developer Tools wording, include `docs/05-project-continuity-review.md` in the doc tree, and align persistence/debug terminology.
- Updated `docs/03-implementation-roadmap.md` to include Notifications history and Preferences in the relevant stages and acceptance criteria.
- Updated `docs/04-product-scope-update.md` to clarify the notification history and Preferences vision.
- Updated docs to clarify that `levy-home-app` is deprecated, unvalidated conceptual reference, and that new implementation belongs in `levy-home`.
- Updated docs again after Stage 9 to split Notifications history from the Preferences tab.
- Updated docs after Stage 11 to mark live Home overview integration complete and move the recommended next action to Stage 12.
- Updated docs after Stage 12 to mark live Home quick-action integration complete and move the recommended next action to Stage 13.
- Updated docs after Stage 13 to mark native APNs permission/token plumbing complete and move the recommended next action to Stage 14.
- Updated docs after Stage 14 to mark client API registration/preference-sync adapters complete and move the recommended next action to Stage 15.
- Updated docs after Stage 15 to mark backend provider-aware device registration and per-device garage preference sync complete and move the recommended next action to Stage 16.
- Updated docs to add Stage 19 for a Preferences Theme setting and dark mode styling, including architecture and product-scope alignment.
- Updated docs after Stage 16 to mark backend APNs sender/debug push support complete and move the recommended next action to Stage 17.
- Added `docs/manual-qa-garage-notifications.md` to prepare Stage 17 physical-device verification and record evidence.
- Added `docs/08-testflight-readiness.md` to prepare Stage 18 internal TestFlight readiness checks and record the external blockers.
- Updated `LevyHome/Resources/PrivacyInfo.xcprivacy` to declare app-specific `UserDefaults` usage.
- Implemented Stage 19 Theme preference and dark-mode styling, including app-wide appearance selection and focused Preferences UI.
- Updated `docs/06-ios-simulator-testing-guide.md` with a manual Theme preference check flow.

Application code has since been implemented through the Stage 19 Theme preference and dark-mode styling milestone. Stage 17 physical-device verification is prepared but not yet completed. Stage 18 release-readiness documentation is prepared, but archive/TestFlight acceptance is not complete until signing, release API URL, production APNs, safe Home Assistant facade configuration, and physical-device validation are supplied and verified.
