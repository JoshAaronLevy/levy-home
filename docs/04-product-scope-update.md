# Product Scope Update

This document reviews the product direction change for Levy Home and identifies the smallest architecture and roadmap updates needed to support it.

Source documents:

- `docs/01-migration-discovery.md`
- `docs/02-swiftui-architecture.md`
- `docs/03-implementation-roadmap.md`

## Updated Product Definition

Levy Home should now be treated as:

> A family-focused home notification and lightweight control application.

The product exists so Josh and Mallory can use one family app for high-value smart-home notifications and selected actions instead of juggling vendor apps and notification settings across Hue/Lutron, Meross, SmartThings, LG ThinQ, and future integrations such as LIFX or Dreo. Home Assistant Green is the central automation and integration layer; Levy Home should sit on top as a curated family experience for notification routing, status, and common actions.

It is still not:

- a Home Assistant replacement
- a full smart-home dashboard
- an automation builder
- a camera application

The new product center of gravity is the Home screen. The app should help the family answer and act on a small set of household questions:

- Is the garage open?
- Did something important happen recently?
- Did we leave lights on?
- Can we quickly fix the common things we forgot while away from home?
- Which garage notifications do we want this device/family member to receive?
- Are notifications allowed, registered, and configured the way this family member expects?

## 1. Conflicts With Existing Architecture And Roadmap

| Existing assumption | Conflict | Required update |
| --- | --- | --- |
| App is primarily a notification timeline | Product is now notification plus lightweight controls and status visibility | Make Home the primary command center; keep event timeline as supporting activity history. |
| Home screen is static status/copy | Home must show garage status, light summary, recent important event summary, and quick actions | Add Home overview models, services, view model, and UI stages. |
| Events tab is the main dynamic feature | Events remain useful, but no longer define the whole product | Rename conceptually to Activity or keep Events as secondary navigation. |
| Debug tab is a primary tab | Debug should be a developer tool, not primary product experience | Remove Debug from default product navigation; keep build-gated developer access. |
| Service layer only has API, notification, settings, date formatting | The app now needs status queries, command execution, and notification preferences | Add `HomeStatusService`, `QuickActionService`, and `NotificationPreferencesService`/store. |
| Models only cover events/push/API responses | Need domain models for garage status, light summary, quick actions, action results, and notification preferences | Add small `HomeOverview`, `GarageStatus`, `LightSummary`, `QuickAction`, `NotificationPreference` models. |
| Backend contract can stay read-only except push | Quick actions and status visibility require backend or Home Assistant facade APIs | Add backend contract work for selected status/action endpoints; keep HA credentials server-side. |
| Roadmap client parity means static Home, Events, Settings, Debug | Revised MVP includes command-center Home, notification preferences, and selected controls | Update roadmap stages before APNs/backend push migration. |
| Future work excludes device controls | Selected household controls are now MVP | Replace blanket control exclusion with a narrow-control boundary. |

## 2. Recommended Architecture Changes

The existing architecture can stay simple. Do not introduce TCA, Redux, coordinators, dependency injection frameworks, or a broad smart-home domain layer.

### Keep

- SwiftUI-first UI.
- Small view models.
- `URLSession` and `async/await`.
- Existing Node/Express API as an initial backend facade.
- Server-side ownership of Home Assistant credentials/secrets.
- APNs registration separated from backend push-provider migration.
- Backend APNs work not blocking the first runnable SwiftUI app.

### Add

| Area | Minimal addition |
| --- | --- |
| Home overview | `HomeOverviewViewModel`, status cards, recent important event summary, quick-action section. |
| Status models | `GarageStatus`, `LightSummary`, `HomeOverview`, optional `ImportantEventSummary`. |
| Quick actions | `QuickAction`, `QuickActionResult`, `QuickActionService`, confirmation/error UI. |
| Preferences | Product-safe notification delivery status plus `NotificationPreference`, `NotificationPreferencesViewModel`, `NotificationPreferencesService`, and simple persistence. |
| API client | Methods for home overview/status, quick actions, and notification preferences. |
| Backend facade | Selected endpoints that proxy Home Assistant status/actions without exposing HA tokens to the app. |
| Developer tools | Debug view stays build-gated and out of primary navigation. |

### Backend Facade Principle

The app should not call Home Assistant directly in the MVP unless a future security review explicitly chooses that path. The existing API should evolve into a narrow Levy Home facade:

```text
SwiftUI app
-> Levy Home API
-> selected Home Assistant status/action integration
```

This keeps Home Assistant tokens and webhook secrets off-device and preserves the app as a curated family experience rather than a generic HA client.

## 3. Recommended Roadmap Changes

The roadmap should shift from event-timeline parity first to command-center parity first.

Recommended changes:

1. Keep the early runnable simulator milestone.
2. Build the revised tab shell with Home, Activity/Events, Notifications history, Preferences, and developer Debug hidden or build-gated.
3. Build static Home command-center UI before live API integration.
4. Add models/API client support for home overview, selected quick actions, and preferences.
5. Add backend status/action facade stages before APNs backend push migration.
6. Keep native APNs registration and backend APNs push-provider migration as separate cut lines.
7. Keep production/TestFlight readiness after end-to-end garage notification/control verification.

Do not add these to the implementation roadmap except as future work:

- dark mode
- production auth
- doorbell/person/motion implementation
- local event caching
- backend persistence
- deep-link routing
- widgets
- Home Assistant dashboard features
- camera features
- automation builder

## 4. Revised MVP

### In Scope

| Capability | MVP behavior |
| --- | --- |
| Home overview | Primary screen shows garage status, light status summary, recent important event summary, and quick actions. |
| Garage status | Shows whether garage is open/closed/unknown, with last updated timestamp when available. |
| Light summary | Shows whether lights are on/off and optionally a count/group summary. |
| Recent important events | Shows the latest high-signal garage events; full history remains available in Activity/Events. |
| Close garage quick action | User can close the garage door through a selected Home Assistant action. |
| Turn off all lights quick action | User can turn off all lights through a selected Home Assistant action. |
| Turn off selected light groups | User can turn off curated groups, not arbitrary devices. |
| Notification history | User can see recent delivered notification history once native push delivery and backend notification records exist. |
| Notification preferences | User can enable/disable garage notification categories: opened, closed, left open, after-hours, still open at 10 PM. |
| Preferences status | User can see plain-language notification permission/registration/sync status without raw token details. |
| Events/activity timeline | Continues to show recent events and pull-to-refresh. |
| Native APNs | Still required for notification delivery, separated from UI/control parity. |
| Developer diagnostics | Available as a build-gated developer tool, not a primary tab in production. |

### Out Of Scope

| Capability | Reason |
| --- | --- |
| Full Home Assistant dashboard | Product is curated and family-focused. |
| Arbitrary device management | MVP only supports selected household actions. |
| Automation builder | Home Assistant remains the automation brain. |
| Camera live view/two-way talk | Explicitly not a camera application. |
| Doorbell/person/motion implementation | Future notification categories only. |
| Production auth | Future work unless API exposure demands it before release. |
| Local event cache | Backend/API should remain source of truth for MVP. |
| Backend persistence | Important hardening, but not required to define the revised client MVP. |

## 5. Revised Information Architecture

### Recommended IA

```text
Home
- Garage status
- Light status summary
- Recent important event summary
- Quick actions

Activity
- Recent event timeline
- Pull to refresh
- Event severity and push metadata

Notifications
- Notification history
- Delivered notification status/history once backend records exist

Preferences
- Product-safe delivery status
- Garage notification preferences
- Future doorbell/person/motion categories disabled or hidden until implemented

Developer Tools
- Build-gated Debug view
- API URL/status
- APNs token/status
- Test push
```

### Product Hierarchy

| Priority | Surface | Purpose |
| --- | --- | --- |
| 1 | Home | Command center for status and action. |
| 2 | Activity | Event history and troubleshooting context. |
| 3 | Notifications | Family-facing notification history. |
| 4 | Preferences | Family-facing notification delivery status and preference editing. |
| 5 | Developer Tools | Diagnostics for development and TestFlight only. |

## 6. Revised Navigation Structure

### Recommended Primary Navigation

Use `TabView`, but revise the primary tabs:

```text
RootTabView
|-- Home
|-- Activity
|-- Notifications
`-- Preferences
```

Other product settings can be reached from a toolbar/menu later if needed. Debug should not be a normal production tab.

### Debug Access

Recommended Debug behavior:

| Build | Access |
| --- | --- |
| Debug/local | Developer Tools available through build flag, hidden tab, toolbar item, or debug-only menu. |
| Internal/TestFlight | Available only if needed for APNs rollout; consider hiding behind build flag. |
| Release | Hidden unless intentionally productized and backend debug endpoints are protected. |

### Navigation Impact

This is a small architecture change: keep `TabView`, but change tab membership and move Debug out of primary IA. A coordinator or custom router is still unnecessary.

## 7. Revised Home Screen Experience

The Home screen should feel like a polished family command center.

### Home Screen Sections

| Section | Purpose | Initial data source |
| --- | --- | --- |
| Garage status | Shows current garage state and whether action is needed | Backend status endpoint or placeholder until backend facade exists. |
| Light summary | Shows whether lights are on, off, or partially on | Backend status endpoint or curated summary endpoint. |
| Recent important event | Shows latest high-priority/relevant event without requiring timeline navigation | Existing `/api/events` filtered client-side at first, or backend overview endpoint. |
| Quick actions | Provides curated actions for forgotten-away-from-home tasks | Backend action endpoint. |
| System/status footnote | Optional compact API/sync status | Debug/internal only or subtle product-safe copy. |

### Home States

| State | Behavior |
| --- | --- |
| Loading | Show compact loading placeholders for status cards. |
| Partial data | Show known sections and mark unknown sections clearly. |
| Error | Show a concise error and allow retry. |
| Action in progress | Disable the active action, show progress, avoid duplicate submissions. |
| Action success | Show short confirmation and refresh overview. |
| Action failure | Show actionable error without exposing backend secrets. |

### Home Design Direction

- Family-friendly, calm, polished, and direct.
- Primary information should be scannable in the first viewport.
- Avoid dense dashboard grids of arbitrary devices.
- Quick actions should be few, obvious, and confirmation-aware for garage closure.
- Status should answer practical questions, not expose Home Assistant internals.

## 8. Revised Notification History And Preferences Experience

Notifications and Preferences should be separate family-facing surfaces. Notifications is the read-only notification history. Preferences answers two editable/configuration questions:

- Are notifications currently allowed and registered?
- Which garage notification categories does this device/family member want?

Developer details such as raw APNs tokens, provider names, debug push responses, and server errors belong in Developer Tools, not in the family-facing Preferences tab.

The Preferences root should list configurable notification categories, devices, or groups cleanly. It should not show every toggle at the top level. Tapping a row such as Garage should open a detail screen where that category's notification settings can be edited, matching the shape of iOS Settings notification preferences.

### Initial Preferences

| Preference | Default recommendation | Notes |
| --- | --- | --- |
| Garage opened | On or configurable by family preference | May be noisy for some users. |
| Garage closed | On initially for parity; could become timeline-only later | Existing MVP pushes it. |
| Garage left open | On | High-value safety notification. |
| Garage after-hours | On | High-value security notification. |
| Garage still open at 10 PM | On | High-value bedtime notification. |

### Future Categories

- Doorbell pressed
- Person detected
- Motion detected

These should appear only when reliable backend/Home Assistant integration exists, or appear disabled with clear future labeling if product wants visibility.

### Preference Architecture

Recommended initial architecture:

```text
NotificationHubView
-> notification history list/placeholder

PreferencesView
-> NotificationDeliveryStatusView
-> notification category list
   -> GarageNotificationPreferencesView
-> NotificationPreferencesViewModel
-> NotificationPreferencesService
-> local UserDefaults and/or backend device preference endpoint
```

Preference storage decision:

| Option | Recommendation |
| --- | --- |
| Local-only UserDefaults | Acceptable for first UI slice and simulator testing. Does not control server push delivery by itself. |
| Backend per-device preferences | Required before preferences can reliably affect APNs delivery. Should be tied to registered device token/device ID. |
| User account preferences | Future work with production auth. Not needed for MVP. |

The UI and model should be designed now so local preferences can later sync to backend without changing the view.

## 9. Revised Quick Actions Experience

### Initial Quick Actions

| Action | Behavior | Risk level |
| --- | --- | --- |
| Close garage door | Sends selected Home Assistant close-cover command through backend facade | High; should require confirmation and status refresh. |
| Turn off all lights | Sends selected Home Assistant turn-off command for curated all-lights group | Moderate; should show confirmation/result. |
| Turn off selected light groups | Sends turn-off command for curated groups only | Moderate; group list should be backend/config curated. |

### Quick Action Principles

- Only include actions that match the product goal: things we forgot while away from home.
- Do not expose arbitrary Home Assistant devices or entities.
- Do not let the app become a control dashboard.
- Keep Home Assistant entity IDs and service details out of the UI.
- Route actions through backend so Home Assistant credentials remain server-side.
- Confirm risky actions, especially garage closure.
- Refresh status after action completion.

### Suggested Backend Action Contract

Exact routes can be decided during backend implementation, but the client should expect a narrow action API such as:

```text
GET /api/home/overview
POST /api/home/actions/close-garage
POST /api/home/actions/lights-off
POST /api/home/actions/light-groups/{groupId}/off
```

or a provider-neutral command endpoint:

```text
POST /api/home/actions
{
  "action": "close_garage"
}
```

Recommendation: prefer explicit curated endpoints or curated action IDs. Do not accept arbitrary Home Assistant service/entity payloads from the app.

## 10. Migration Impact Estimate

### Overall Impact

| Area | Impact | Notes |
| --- | --- | --- |
| SwiftUI navigation | Moderate | Primary tabs change; Debug moves out of product navigation. |
| Home screen | High | Becomes primary dynamic experience, not static copy/status. |
| Models | Moderate | Add status, action, and preference models. |
| API client | High | Add overview/status/action/preference methods. |
| Backend API | High | Need narrow Home Assistant facade for status and actions. |
| APNs architecture | Moderate | Still required, but not conceptually changed by product update. Preferences later affect push filtering. |
| Roadmap | High | Client parity cut line shifts to include command-center Home and preferences. |
| Testing | High | Must test status, actions, action failure, and preference persistence in addition to notifications. |
| Production readiness | Moderate | Controls increase safety/security review needs. |

### Risk Changes

| New or increased risk | Mitigation |
| --- | --- |
| Garage close action could be triggered accidentally | Require confirmation, show current state, disable duplicate taps, refresh status. |
| Backend may expose overly broad HA control | Use curated action IDs/endpoints only; never accept arbitrary HA service payloads from app. |
| Preferences UI may not match server push behavior initially | Clearly separate local UI slice from backend preference enforcement stage. |
| App drifts toward dashboard | Keep IA limited: Home command center, Activity, Notifications, and Preferences. No arbitrary device list. |
| Debug remains visible in product | Build-gate Developer Tools and remove Debug from normal tabs. |

## Recommended Change Summary

1. Preserve the simple SwiftUI architecture.
2. Revise primary navigation to Home, Activity, Notifications, and Preferences.
3. Move Debug to build-gated Developer Tools.
4. Add Home overview/status/action models and services.
5. Add a Preferences tab with product-safe delivery status, preference models, and view model now, with backend sync later; keep Notifications focused on history.
6. Add backend Home Assistant facade stages for selected status/actions.
7. Keep APNs registration and backend push-provider migration separate.
8. Update the roadmap so the revised MVP is achieved before TestFlight readiness.
