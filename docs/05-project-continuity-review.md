# Project Continuity Review

## Executive Summary

Current project state: `levy-home` now contains the native SwiftUI iOS project, core app composition, primary tab shell, theme primitives, live Home overview plumbing, live Home quick actions, typed models/API client, live Activity timeline plumbing, local notification preference UI, native APNs permission/token plumbing, and the Stage 10 backend Home status/action facade. `levy-home` remains the working project for all new implementation.

The deprecated reference project, `levy-home-app`, is the existing Expo/React Native + Node/Express implementation. It has four Expo tabs: Home, Events, Settings, and Debug. The backend currently supports event ingestion, in-memory event history, Expo push token registration, Expo push sending, and debug test push. It does not currently expose Home overview/status, quick-action, notification-preference, or APNs endpoints. Because Expo issues prevented full validation, treat it as conceptual reference only, not an absolute source of truth.

Estimated completion percentage: approximately 65% by staged roadmap count, or roughly 55-60% by remaining risk. The biggest remaining work is backend device registration, backend APNs sending, physical-device verification, preference sync/enforcement, and TestFlight readiness.

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
- Product direction has shifted from notification timeline only to family-focused notifications plus lightweight status/control.
- Product north star is a single Josh-and-Mallory family app over Home Assistant that replaces scattered vendor notifications and common control tasks across Hue/Lutron, Meross, SmartThings, LG ThinQ, and future integrations.

Work partially completed:

- Product scope update has been propagated into architecture and roadmap, including the newer split between Notifications history and Preferences.
- Architecture and roadmap now cover Home overview, garage/light status, quick actions, notification preferences, APNs, backend APNs migration, and build-gated Developer Tools.
- Preferences is now the product surface for delivery status and notification preference editing; Notifications is the read-only history surface.
- Discovery still contains older target-stage content, but now has a continuity note marking those parts as historical/superseded where they conflict with newer docs.

Work unfinished:

- Backend notification preferences and preference enforcement.
- Backend device registration and APNs sender.
- End-to-end physical-device verification.
- TestFlight/release readiness.
- Backend/API code needed for notification preferences, preference enforcement, and APNs in `levy-home`.

## Documentation Audit

| Document | Complete | Needs revision | Conflicts found | Missing sections |
| --- | --- | --- | --- | --- |
| `docs/01-migration-discovery.md` | Complete as a deprecated reference-app inventory | Yes, if used as target implementation guidance | It describes the old current/reference app scope: notification timeline, Settings tab, Debug tab, no controls. Its later staged roadmap conflicts with the revised product vision. | It does not fully model the revised Home command center, notification hub, quick actions, or preferences because those were not in the reference app. A continuity note now marks those target assumptions as superseded and clarifies `levy-home-app` is conceptual reference only. |
| `docs/02-swiftui-architecture.md` | Mostly complete as target architecture | Minor revisions applied | Earlier versions had stale Events/Settings/Debug references and treated Notifications as the place for preferences. | Notifications history and Preferences are now separate. Real backend contract shapes for status/actions/preferences still need finalization during implementation stages. |
| `docs/03-implementation-roadmap.md` | Mostly complete as staged roadmap | Minor revisions applied | Earlier versions supported preferences inside Notifications. | Stage 2 and Stage 9 now reflect a four-tab product shell. Exact backend route shapes, APNs credential strategy, real HA entity/action configuration, and release security decisions remain intentionally deferred to their stages. |
| `docs/04-product-scope-update.md` | Complete as product direction update | Minor revisions applied | No material conflict with architecture/roadmap after this update. | Notification history and Preferences clarification was added. Broader future categories remain deferred. |

## Product Scope Alignment

| Scope item | Represented? | Notes |
| --- | --- | --- |
| Notification history and Preferences vision | Revised | The product now separates notification history from preference editing: Notifications is history-only, while Preferences owns delivery status and lists editable notification categories such as Garage. |
| Home overview/dashboard vision | Yes | Architecture and roadmap make Home the command center with garage status, light summary, recent important event, and quick actions. It remains curated, not a full dashboard. |
| Quick actions | Yes | Close garage, turn off all lights, and curated light-group actions are in architecture, product scope, and roadmap. |
| Notification preferences | Yes | Garage notification preferences are modeled as first-class UI/service/model work, with a Preferences category row, a Garage detail screen, local persistence first, and backend sync later. |
| Debug tooling no longer primary UX | Yes | Architecture, roadmap, and product scope move Debug into build-gated Developer Tools. Discovery still describes the deprecated reference app's Debug tab, with a superseding continuity note. |

Remaining product gaps:

- Product-safe notification delivery wording and exact Preferences status states still need later APNs-stage refinement.
- Preferences do not affect push delivery until backend per-device preference sync and enforcement exist.
- Home overview and action facade contracts now exist, but real Home Assistant entity/action configuration still needs household-specific validation.

## Architecture Alignment

| Capability | Architecture support | Missing pieces |
| --- | --- | --- |
| Garage status | Yes | Backend `/api/home/overview` exists with garage status; iOS `HomeStatusService` and `HomeOverviewViewModel` now load and display live Home overview data. |
| Light status | Yes | Backend overview/facade support exists with light summary; iOS live Home wiring now displays live/partial/unknown light status. |
| Quick actions | Yes | Backend curated quick-action endpoints exist; iOS `QuickActionService`, `QuickActionsViewModel`, confirmation/progress/error states, duplicate-tap protection, and post-action overview refresh are implemented. |
| Notification preferences | Yes | `NotificationPreference`, `NotificationPreferencesService`, `NotificationPreferencesViewModel`, local `UserDefaults`, and Preferences UI are implemented; later backend sync/enforcement is still planned. |
| Event timeline | Yes | `ActivityView`, `ActivityViewModel`, event models, `APIClient.fetchRecentEvents`, event cards, empty/error/refresh states are implemented. |
| APNs migration | Yes | Native `NotificationService`, `AppDelegate`, `PushRegistrationViewModel`, debug registration controls, simulator unavailable handling, and entitlements are implemented. Backend device registration, backend APNs sending, and physical-device end-to-end verification remain planned. |

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
- Guardrails that keep all new implementation in `levy-home` and use `levy-home-app` only as conceptual reference.

Stages that must be added:

- None after this update. The Notifications/Preferences split is incorporated into existing Stage 2, Stage 9, Stage 13, Stage 14, and Stage 17.

Stages that must be modified:

- Stage 2: revised to use four product tabs: Home, Activity, Notifications, and Preferences.
- Stage 9: revised so Preferences owns delivery status and local preferences while Notifications remains history-only.
- Stage 13/14: revised so APNs state feeds Developer Tools and product-safe Preferences status.
- Stage 17: revised to verify Preferences status and Notifications history in end-to-end QA.

Stages that should be removed:

- None from the current roadmap. The old discovery-document roadmap is superseded and should not be used as the implementation sequence.

## Recommended Next Action

Implement Stage 14: client device registration and preference sync adapter.

Stop condition for the next step: the client can represent whether API device registration is skipped, pending, successful, or failed without requiring backend APNs delivery yet.

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

Application code has since been implemented through the Stage 13 native APNs permission/token milestone.
