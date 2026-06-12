# Project Continuity Review

## Executive Summary

Current project state: `levy-home` is documentation-only. It contains `README.md` and the migration/product documents, but no Xcode project, SwiftUI target, Swift source, tests, assets, services, or app implementation scaffolding. The native rebuild has not started. `levy-home` is the working project for all new implementation.

The deprecated reference project, `levy-home-app`, is the existing Expo/React Native + Node/Express implementation. It has four Expo tabs: Home, Events, Settings, and Debug. The backend currently supports event ingestion, in-memory event history, Expo push token registration, Expo push sending, and debug test push. It does not currently expose Home overview/status, quick-action, notification-preference, or APNs endpoints. Because Expo issues prevented full validation, treat it as conceptual reference only, not an absolute source of truth.

Estimated completion percentage: approximately 8% of the overall migration, counting documentation/planning progress only. Native SwiftUI implementation completion is 0%. Documentation alignment is now mostly complete after the updates made alongside this review, with remaining open decisions around final bundle ID, API exposure/auth, APNs provider details, and real Home Assistant entity/action configuration.

Work already completed:

- Current Expo app and Node API have been inventoried in `docs/01-migration-discovery.md`.
- Target SwiftUI architecture exists in `docs/02-swiftui-architecture.md`.
- Staged implementation roadmap exists in `docs/03-implementation-roadmap.md`.
- Revised product scope exists in `docs/04-product-scope-update.md`.
- Product direction has shifted from notification timeline only to family-focused notifications plus lightweight status/control.
- Product north star is a single Josh-and-Mallory family app over Home Assistant that replaces scattered vendor notifications and common control tasks across Hue/Lutron, Meross, SmartThings, LG ThinQ, and future integrations.

Work partially completed:

- Product scope update was mostly propagated into architecture and roadmap before this review.
- Architecture and roadmap now cover Home overview, garage/light status, quick actions, notification preferences, APNs, backend APNs migration, and build-gated Developer Tools.
- Notification hub language was underrepresented before this review; architecture, roadmap, and product-scope docs have now been updated to describe Notifications as a lightweight hub for product-safe delivery status plus preferences.
- Discovery still contains older target-stage content, but now has a continuity note marking those parts as historical/superseded where they conflict with newer docs.

Work unfinished:

- Native SwiftUI project baseline.
- Swift app architecture, models, services, view models, screens, tests, assets, and build settings.
- Backend Home Assistant status/action facade.
- Backend notification preferences.
- Provider-aware APNs registration and APNs sender.
- End-to-end physical-device verification.
- TestFlight/release readiness.
- Any backend/API code needed for status, actions, preferences, or APNs in `levy-home`.

## Documentation Audit

| Document | Complete | Needs revision | Conflicts found | Missing sections |
| --- | --- | --- | --- | --- |
| `docs/01-migration-discovery.md` | Complete as a deprecated reference-app inventory | Yes, if used as target implementation guidance | It describes the old current/reference app scope: notification timeline, Settings tab, Debug tab, no controls. Its later staged roadmap conflicts with the revised product vision. | It does not fully model the revised Home command center, notification hub, quick actions, or preferences because those were not in the reference app. A continuity note now marks those target assumptions as superseded and clarifies `levy-home-app` is conceptual reference only. |
| `docs/02-swiftui-architecture.md` | Mostly complete as target architecture | Minor revisions applied | Before this review, it mostly reflected the scope update but still had a few stale Events/Settings/Debug references and treated Notifications mostly as preferences. | Notification hub status surface is now represented. Real backend contract shapes for status/actions/preferences still need finalization during implementation stages. |
| `docs/03-implementation-roadmap.md` | Mostly complete as staged roadmap | Minor revisions applied | Before this review, the roadmap supported preferences but did not explicitly frame Notifications as a hub. | Exact backend route shapes, APNs credential strategy, real HA entity/action configuration, and release security decisions remain intentionally deferred to their stages. |
| `docs/04-product-scope-update.md` | Complete as product direction update | Minor revisions applied | No material conflict with architecture/roadmap after this review. | Notification hub clarification was added. Broader future categories remain deferred. |

## Product Scope Alignment

| Scope item | Represented? | Notes |
| --- | --- | --- |
| Notification hub vision | Yes, after this review | Notifications is now documented as a lightweight family-facing hub for delivery status plus preferences, distinct from Developer Tools. |
| Home overview/dashboard vision | Yes | Architecture and roadmap make Home the command center with garage status, light summary, recent important event, and quick actions. It remains curated, not a full dashboard. |
| Quick actions | Yes | Close garage, turn off all lights, and curated light-group actions are in architecture, product scope, and roadmap. |
| Notification preferences | Yes | Garage notification preferences are modeled as first-class UI/service/model work, with local persistence first and backend sync later. |
| Debug tooling no longer primary UX | Yes | Architecture, roadmap, and product scope move Debug into build-gated Developer Tools. Discovery still describes the deprecated reference app's Debug tab, with a superseding continuity note. |

Remaining product gaps:

- Product-safe notification delivery wording and exact hub UI content still need implementation-stage copy/design.
- Preferences do not affect push delivery until backend per-device preference sync and enforcement exist.
- Home overview is documented, but actual status/action backend contracts are not implemented or finalized.

## Architecture Alignment

| Capability | Architecture support | Missing pieces |
| --- | --- | --- |
| Garage status | Yes | `GarageStatus`, `HomeOverview`, `HomeStatusService`, `HomeOverviewViewModel`, `GarageStatusCard`, and backend `/api/home/overview` facade are planned but not implemented. |
| Light status | Yes | `LightSummary`, `LightSummaryCard`, `HomeStatusService`, and backend overview/facade support are planned but not implemented. |
| Quick actions | Yes | `QuickAction`, `QuickActionResult`, `QuickActionService`, `QuickActionsViewModel`, confirmation/progress/error states, and backend action endpoints are planned but not implemented. |
| Notification preferences | Yes | `NotificationPreference`, `NotificationPreferencesService`, `NotificationPreferencesViewModel`, local `UserDefaults`, and later backend sync are planned but not implemented. |
| Event timeline | Yes | `ActivityView`, `ActivityViewModel`, event models, `APIClient.fetchRecentEvents`, event cards, empty/error/refresh states are planned but not implemented. |
| APNs migration | Yes | `NotificationService`, `AppDelegate`, provider-aware device registration, APNs backend migration, physical-device test stages are planned but not implemented. |

Missing architecture details to settle during future stages:

- Final backend contract shape for Home overview and actions.
- Final backend contract shape for notification preference sync/enforcement.
- Final backend/API location and runtime inside `levy-home`.
- Whether Developer Tools access is hidden tab, toolbar item, menu, or build-only route.
- Final bundle identifier and APNs sandbox/production handling.
- Security posture for any internet-accessible API, especially debug/action endpoints.

## Roadmap Alignment

The roadmap now supports the revised product vision. It includes:

- Early native project baseline.
- Revised Home/Activity/Notifications primary navigation.
- Static Home command center before live data.
- Expanded models and API client for status, actions, preferences, events, registration, and debug push.
- Activity timeline integration.
- Notifications hub with local preferences.
- Backend Home status/action facade.
- Live Home overview and quick actions.
- Native APNs registration.
- Provider-aware registration and preference sync.
- Backend APNs sender.
- End-to-end garage notification/control verification.
- Production/TestFlight readiness.
- Guardrails that keep all new implementation in `levy-home` and use `levy-home-app` only as conceptual reference.

Stages that must be added:

- None after this review. The notification hub is now incorporated into existing Stage 2, Stage 9, Stage 13, Stage 14, and Stage 17.

Stages that must be modified:

- Stage 2: revised to name Notifications as a hub.
- Stage 9: revised from a preferences-only screen to a Notifications hub with delivery status and local preferences.
- Stage 13/14: revised so APNs state feeds both Developer Tools and product-safe hub status.
- Stage 17: revised to verify Notifications hub status in end-to-end QA.

Stages that should be removed:

- None from the current roadmap. The old discovery-document roadmap is superseded and should not be used as the implementation sequence.

## Recommended Next Action

Create Stage 0: the native SwiftUI iOS project baseline in `levy-home`, with no feature implementation beyond a minimal launchable placeholder and agreed app identity/build settings.

Stop condition for the next step: simulator build succeeds and no Expo/React Native dependencies are introduced.

## Documentation Updates Made

- Added a continuity note to `docs/01-migration-discovery.md` clarifying that its old target assumptions are historical/superseded where they conflict with newer docs.
- Updated `docs/02-swiftui-architecture.md` to represent the Notifications hub, fix stale Activity/Developer Tools wording, include `docs/05-project-continuity-review.md` in the doc tree, and align persistence/debug terminology.
- Updated `docs/03-implementation-roadmap.md` to include the Notifications hub in the relevant stages and acceptance criteria.
- Updated `docs/04-product-scope-update.md` to clarify the notification hub vision.
- Updated docs to clarify that `levy-home-app` is deprecated, unvalidated conceptual reference, and that new implementation belongs in `levy-home`.

No application code was implemented.
