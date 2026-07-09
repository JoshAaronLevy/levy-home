# Lighting Automation Dialog Feature Plan

## Goal

Build from the current Home blueprint lighting dialog toward a fuller room-level lighting automation picker.

Implemented MVP behavior:

- Tapping `Entry`, `Kitchen`, `Playroom`, `Upstairs`, or `Study` opens a lighting dialog for that area.
- The dialog title is `<Area> Lights`, for example `Kitchen Lights`.
- The dialog body shows `x On | y Off` from the current Home overview light groups.
- The dialog has side-by-side `All On` and `All Off` buttons.
- `All On` is disabled when there are `0` off lights.
- `All Off` is disabled when there are `0` on lights.
- Tapping either button calls the Levy Home API, applies the refreshed Home overview on success, and closes the dialog.
- The `Garage` node keeps its existing garage behavior and does not open the lighting dialog.

Remaining full-feature behavior:

- The dialog can also list curated lighting automations, scenes, or scripts for that area.
- Tapping one list item triggers that selected Home Assistant action, closes the dialog on success, and refreshes the Home overview so the blueprint connector and node border colors update.
- `All On` and `All Off` remain as footer quick actions.

The important product boundary is that the iOS app should not send arbitrary Home Assistant domains, service names, or entity IDs. The app should ask the Levy Home API to run a stable, curated action ID. The backend should own the mapping from that action ID to Home Assistant.

## Current MVP Status

The basic dialog is now implemented. The remaining work in this document is about growing that MVP into a richer per-room automation picker.

Current implementation:

- `LevyHome/Views/Home/Blueprint/HomeBlueprintView.swift` exposes `BlueprintLightingArea` and wraps the five non-garage nodes in plain SwiftUI buttons.
- `LevyHome/Views/Home/HomeContentView.swift` owns `selectedLightingArea`, presents the sheet, computes `x On | y Off`, disables unavailable button states, performs the selected on/off action, applies the refreshed overview, and closes the sheet on success.
- `LevyHome/ViewModels/QuickActionsViewModel.swift` has `performLightGroups(_:turnOn:title:)`, which de-duplicates matching light targets and performs the requested action for each target.
- `LevyHome/Models/API/QuickActionAPIRequests.swift` and `LevyHome/Models/QuickAction.swift` support `turn_on_light_group`.
- `apps/api/src/homeService.ts` lists and performs `turn_on_light_group` and `turn_off_light_group`.
- `apps/api/src/integrations/homeAssistant/liveFacade.ts` maps those curated actions to Home Assistant `light.turn_on` and `light.turn_off`.
- `apps/api/src/validation/homeValidation.ts` still rejects arbitrary Home Assistant payload keys.

What the MVP intentionally does not do yet:

- It does not list room-specific scenes, scripts, or automations.
- It does not have a dedicated `GET /api/home/lighting-actions` catalog.
- It does not have a dedicated `POST /api/home/lighting-actions` endpoint.
- It does not expose per-action icons, subtitles, sort order, or confirmation rules beyond the two footer actions.

## Current App Shape

The current code already has the MVP pieces and several useful building blocks for the full feature:

- `LevyHome/Views/Home/Blueprint/HomeBlueprintView.swift` owns the foreground blueprint nodes and connector lines.
- `BlueprintLightingArea` centralizes the user-facing areas and their matching terms: `entry`, `kitchen`, `playroom`, `upstairs`, and `study`.
- `LevyHome/Views/Home/HomeContentView.swift` renders `HomeBlueprintView`, owns the Home screen state, handles garage taps, and presents the current area lighting sheet.
- `LevyHome/ViewModels/HomeOverviewViewModel.swift` owns the loaded Home overview and already has `apply(overview:)`, which is useful after a lighting action returns a refreshed overview.
- `LevyHome/ViewModels/QuickActionsViewModel.swift` handles garage, whole-home light, and area light quick actions with busy states, logging, confirmation support, and refreshed overview returns.
- `LevyHome/Services/API/APIClient+Home.swift` already calls:
  - `GET /api/home/overview`
  - `GET /api/home/actions`
  - `POST /api/home/actions`
- `apps/api/src/routes/homeRoutes.ts` already exposes Home overview and quick-action routes.
- `apps/api/src/validation/homeValidation.ts` already rejects arbitrary Home Assistant payload keys such as `domain`, `service`, `entityId`, `target`, and `serviceData`.
- `apps/api/src/integrations/homeAssistant/liveFacade.ts` currently supports garage cover actions, `light.turn_on`, and `light.turn_off`; it still needs a small expansion for scenes, scripts, and automations.

That means this feature should be an extension of the existing Home action boundary, not a new direct app-to-Home-Assistant path.

## Recommended Home Assistant Setup

### 1. Choose The Right HA Object Type

For manually selected lighting presets, prefer this order:

| HA type | Best for | Notes |
| --- | --- | --- |
| `scene.*` | Static lighting looks, such as evening, cooking, dim, bright, movie | Cleanest for "set these lights to this state." |
| `script.*` | Multi-step actions or condition-aware routines | Best when the action does more than set a static light state. |
| `automation.*` | Existing HA automations that already contain the desired action sequence | Usable, but less ideal for manual app controls if the automation depends on trigger context. |
| `light.*` | `All On` and `All Off` quick actions | Best for simple area-wide on/off controls. |

Existing automations can be used, but if any automation depends on a real trigger, trigger variables, time conditions, person state, or other context, convert that logic into a script or scene before exposing it in the app.

### 2. Use Stable Entity IDs

The backend catalog should point at stable HA entity IDs. Good naming examples:

```text
scene.kitchen_cooking
scene.kitchen_evening
script.kitchen_cleanup
scene.foyer_welcome
scene.playroom_bright
script.study_focus
scene.upstairs_night
```

Avoid exposing generated or unclear entity IDs to the app. If HA creates an awkward entity ID, rename it in Home Assistant before adding it to the Levy Home catalog.

### 3. Make Area Light Targets Match The Blueprint

The `All On` and `All Off` buttons should control the same logical room targets that drive the blueprint status colors. If these drift apart, the app can trigger an action successfully but the node color may not reflect what the user expected.

Recommended app-facing targets from the current lights-by-area audit:

| Blueprint node | HA area or room | Recommended light target |
| --- | --- | --- |
| `Entry` | Foyer / Entry | `light.foyer_lights` |
| `Kitchen` | Kitchen | `light.kitchen_cans`, `light.kitchen_nook`, or one HA group such as `light.kitchen` |
| `Playroom` | Playroom | `light.playroom` |
| `Upstairs` | Upstairs Hallway | `light.upstairs_hallway` |
| `Study` | Study | `light.study_lamp_1`, `light.study_lamp_2`, `light.study_lamp_3`, or a cleaner `light.study_lights` group |

If an area has multiple individual light entities, a Home Assistant group/helper is cleaner for the API and app. For example, creating `light.study_lights` would make Study easier to reason about than three separate lamp targets.

### 4. Test Each HA Action Before Wiring The App

Before adding an action to the backend catalog:

1. Run it from Home Assistant Developer Tools.
2. Confirm the correct lights change.
3. Confirm it does not rely on a trigger-only variable.
4. Confirm it is safe to run repeatedly.
5. Confirm it works when some lights are already on or already off.
6. Confirm the long-lived access token used by the Levy Home API can call the required service.

For automations specifically, decide deliberately whether the manual trigger should honor or skip automation conditions. The backend should set that behavior explicitly in the Home Assistant service data instead of relying on Home Assistant defaults.

## Recommended API Design

The MVP currently reuses the existing quick-action API. The fuller automation-picker feature should add a dedicated lighting-action API that is separate from garage quick actions but follows the same safety pattern.

### Current MVP API

The current area quick actions use:

```http
GET /api/home/actions
POST /api/home/actions
```

Current request examples:

```json
{
  "actionId": "turn_on_light_group",
  "groupId": "kitchen_cans"
}
```

```json
{
  "actionId": "turn_off_light_group",
  "groupId": "kitchen_nook"
}
```

This works for the simple dialog because the app can derive the matching light group IDs from `/api/home/overview` and the backend can safely map those IDs to configured Home Assistant light entities or groups.

Keep this MVP path for `All On` and `All Off` unless the richer catalog needs a different result shape.

### Future Automation Catalog

Read catalog:

```http
GET /api/home/lighting-actions
```

Suggested response shape:

```json
{
  "ok": true,
  "areas": [
    {
      "id": "kitchen",
      "title": "Kitchen",
      "subtitle": "Kitchen lighting",
      "actions": [
        {
          "id": "kitchen.cooking",
          "title": "Cooking",
          "subtitle": "Bright cans and nook lights",
          "systemImage": "fork.knife",
          "isEnabled": true,
          "requiresConfirmation": false
        }
      ],
      "allOnActionId": "kitchen.all_on",
      "allOffActionId": "kitchen.all_off"
    }
  ]
}
```

The response should not need to include Home Assistant entity IDs. The app only needs stable action IDs, display text, icons, grouping, and enabled states.

Perform action:

```http
POST /api/home/lighting-actions
```

Suggested request:

```json
{
  "areaId": "kitchen",
  "actionId": "kitchen.cooking"
}
```

Suggested response:

```json
{
  "ok": true,
  "result": {
    "areaId": "kitchen",
    "actionId": "kitchen.cooking",
    "status": "success",
    "message": "Kitchen Cooking requested.",
    "refreshedHomeOverview": {}
  }
}
```

This mirrors the existing `QuickActionResult` pattern so the iOS app can immediately apply the refreshed overview and update the blueprint colors.

## Backend Implementation Stages

### Completed MVP Backend Stage

Already done:

- Added `turn_on_light_group` to the curated quick-action contract.
- Kept `turn_off_light_group` as the existing off path.
- Updated validation so the new action ID is accepted while arbitrary Home Assistant payloads are still rejected.
- Updated the live Home Assistant facade to call `light.turn_on`.
- Updated the mock facade and API tests.

### Remaining Stage 1: Define A Curated Automation Catalog

Add a small backend-owned catalog for room-specific automations, scenes, and scripts for the five non-garage blueprint areas.

Recommended first version:

- Keep the catalog in TypeScript, for example `apps/api/src/homeLightingCatalog.ts`.
- Use stable area IDs: `entry`, `kitchen`, `playroom`, `upstairs`, `study`.
- Keep `All On` and `All Off` on the current quick-action path unless there is a strong reason to migrate them into the new catalog.
- Store private HA execution details only on the backend.

Example internal shape:

```ts
type LightingExecution =
  | { kind: 'scene'; entityId: string }
  | { kind: 'script'; entityId: string }
  | { kind: 'automation'; entityId: string; skipCondition: boolean }
  | { kind: 'light_on'; entityIds: string[]; brightnessPct?: number }
  | { kind: 'light_off'; entityIds: string[] };
```

Why code-owned first:

- It is easy to review.
- It avoids a large fragile JSON environment variable.
- It keeps the first implementation simple.
- It still allows changes with a backend deploy, without an iOS release.

If the catalog changes often later, move it to a JSON file, database table, or admin-editable config.

### Remaining Stage 2: Add API Contracts And Validation

Update:

- `apps/api/src/contracts/home.ts`
- `apps/api/src/validation/homeValidation.ts`

New contract types should cover:

- `LightingAreaId`
- `LightingAction`
- `LightingActionArea`
- `LightingActionRequest`
- `LightingActionResult`

Validation should:

- Require a JSON object.
- Accept only `areaId` and `actionId`.
- Reject arbitrary HA fields like the quick-action validator already does.
- Confirm the `areaId` exists in the backend catalog.
- Confirm the `actionId` belongs to that area.

This keeps the security posture consistent with the existing quick-action endpoint.

### Remaining Stage 3: Extend The Home Assistant Facade

Update:

- `apps/api/src/integrations/homeAssistant/facade.ts`
- `apps/api/src/integrations/homeAssistant/liveFacade.ts`
- `apps/api/src/integrations/homeAssistant/mockFacade.ts`

The live facade currently handles `cover` and `light` services. Expand it so the backend can also call these service domains safely:

- `scene.turn_on`
- `script.turn_on`
- `automation.trigger`

Keep the public facade method high-level, for example:

```ts
triggerLightingAction(execution: LightingExecution): Promise<void>
```

Do not expose a generic `callService(domain, service, body)` method to routes or validation. The catalog should remain the only place that decides what HA service can run.

### Remaining Stage 4: Add HomeService Methods And Routes

Update:

- `apps/api/src/homeService.ts`
- `apps/api/src/routes/homeRoutes.ts`

Add:

- `homeService.listLightingActions()`
- `homeService.performLightingAction(areaId, actionId)`
- `GET /api/home/lighting-actions`
- `POST /api/home/lighting-actions`

`performLightingAction` should:

1. Look up the area and action in the catalog.
2. Throw `404` for unknown area/action combinations.
3. Throw `400` or `409` for disabled actions.
4. Call the HA facade.
5. Return a result with `refreshedHomeOverview: await this.getOverview()`.

### Remaining Stage 5: Backend Tests

Add or update tests around:

- Catalog listing shape.
- Request validation rejects arbitrary HA payloads.
- Unknown area/action returns an API error.
- Disabled action returns an API error.
- Scene/script/automation/light executions call the expected facade method.
- `POST /api/home/lighting-actions` returns a refreshed overview.

Likely test files:

- `apps/api/test/integration/routes/homeRoutes.test.ts`
- `apps/api/test/unit/integrations/homeAssistant/facade.test.ts`
- `apps/api/test/unit/validation/domainValidation.test.ts` or a new focused home validation test.

Run:

```sh
npm run api:typecheck
npm run api:build
npm run api:test
```

## iOS Implementation Stages

### Completed MVP iOS Stage

Already done:

- Added `BlueprintLightingArea`.
- Made non-garage blueprint nodes tappable.
- Added the current sheet in `HomeContentView`.
- Added `x On | y Off` calculation from the current `HomeOverview.lightSummary.groups`.
- Added disabled-state rules for `All On` and `All Off`.
- Added `turn_on_light_group` to `QuickActionID` and `QuickActionRequest`.
- Added `QuickActionsViewModel.performLightGroups(_:turnOn:title:)`.
- Kept Garage on the existing garage action path.
- Added focused Swift tests for request encoding and the multi-target light action helper.

### Remaining Stage 1: Add Swift Models For Automation Catalog

Add API models for the catalog and result. Good locations:

- `LevyHome/Models/API/QuickActionAPIResponses.swift`, or a new `LightingActionAPIResponses.swift`
- `LevyHome/Models/API/QuickActionAPIRequests.swift`, or a new `LightingActionAPIRequests.swift`
- `LevyHome/Models/QuickAction.swift`, or a new `LightingAction.swift`

Suggested Swift concepts:

- `LightingAreaID`
- `LightingAction`
- `LightingActionArea`
- `LightingActionRequest`
- `LightingActionResult`

The app should tolerate unknown IDs so a backend deploy cannot break decoding. Follow the existing `QuickActionID.unknown(String)` pattern.

### Remaining Stage 2: Add API Client And Service Methods

Update:

- `LevyHome/Services/API/APIClient+Home.swift`
- `LevyHome/Services/QuickActionService.swift`, or create `LightingActionService.swift`

Recommended choice: create a separate `LightingActionService` and `LightingActionsViewModel` for the future automation list. The current `QuickActionsViewModel` is acceptable for the MVP because it only performs area on/off actions, but the richer catalog will have enough state to deserve its own view model.

API methods:

```swift
func fetchLightingActions() async throws -> LightingActionsResponse
func performLightingAction(_ request: LightingActionRequest) async throws -> LightingActionResponse
```

### Remaining Stage 3: Add A LightingActionsViewModel

The view model should own:

- Loaded area catalog.
- Loading state.
- Performing state.
- `performingActionID`.
- Error/message state.
- A helper to find the area for a tapped blueprint node.

It should return `HomeOverview?` after performing an action, just like `QuickActionsViewModel` does today. Then `HomeContentView` can call:

```swift
if let refreshedOverview = await lightingActionsViewModel.perform(action) {
    homeViewModel.apply(overview: refreshedOverview)
    selectedLightingArea = nil
}
```

Close the dialog on success. Keep it open on failure so the error is visible and the user can try another action.

### Remaining Stage 4: Extend The Existing Dialog

Update the existing MVP sheet instead of replacing it.

Current state:

- `HomeContentView` already presents a sheet when `selectedLightingArea` is set.
- The sheet already has the correct title, count body, footer buttons, disabled states, and success-close behavior.
- `HomeBlueprintView` already keeps Garage separate from the lighting nodes.

Future change:

- `LevyHome/Views/Home/Lighting/LightingActionDialog.swift`

Possible next UI:

- Title: area title, such as `Kitchen`.
- Keep the existing `x On | y Off` body.
- List rows for curated actions.
- Keep the existing bottom action bar with `All On` and `All Off`.
- Disabled state while an action is running.
- Inline error banner if an action fails.

Use a sheet from `HomeContentView`:

```swift
.sheet(item: $selectedLightingArea) { area in
    LightingActionDialog(...)
        .presentationDetents([.medium])
}
```

If the area has no configured actions, show a quiet empty state but still show `All On` and `All Off` if those are available.

### Remaining Stage 5: Wire HomeContentView To The Automation Catalog

Update:

- `LevyHome/Views/Home/HomeContentView.swift`
- `LevyHome/App/AppEnvironment.swift`
- `LevyHome/App/LevyHomeApp.swift` if dependency wiring requires it.
- Preview support for `HomeContentView`.

`HomeContentView` should:

1. Own `@StateObject private var lightingActionsViewModel`.
2. Load lighting actions alongside home overview, weather, and quick actions.
3. Pass the selected area's automation list into the existing dialog.
4. Keep the current footer on/off controls wired to the existing quick-action MVP path unless the backend API is intentionally changed.
5. Apply the refreshed overview after any successful automation or on/off action.

The existing garage tap flow should remain unchanged.

### Remaining Stage 6: iOS Tests

Add or update tests around:

- API decoding for lighting catalog and result payloads.
- Unknown lighting action IDs do not break decoding.
- `LightingActionsViewModel` loads catalog successfully.
- Performing an action returns refreshed overview.
- Failed action leaves an error message.
- `HomeContentView` can still build with previews.

Likely test files:

- `LevyHomeTests/APIModelDecodingTests.swift`
- A new `LevyHomeTests/LightingActionsViewModelTests.swift`
- Potentially `LevyHomeTests/HomeOverviewViewModelTests.swift` if overview application behavior changes.

Run:

```sh
xcodebuild -project LevyHome.xcodeproj -scheme LevyHome -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

For focused tests, use the same destination pattern already used in this repo for existing view model tests.

## Suggested First Catalog

Start with a small catalog that proves the full path before adding every possible lighting preset.

Example:

| Area | First actions |
| --- | --- |
| Entry | `All On`, `All Off`, maybe `Welcome` |
| Kitchen | `All On`, `All Off`, `Cooking`, `Evening` |
| Playroom | `All On`, `All Off`, maybe `Bright` |
| Upstairs | `All On`, `All Off`, `Night` |
| Study | `All On`, `All Off`, `Focus`, `Evening` |

The first implementation does not need to solve global lighting scenes or presence automations. Keep it room-scoped so the tap behavior is predictable.

## Manual QA Checklist

MVP checks that apply now:

1. Start the API in live Home Assistant mode.
2. Confirm `GET /api/home/actions` includes `turn_on_light_group` and `turn_off_light_group`.
3. Confirm `POST /api/home/actions` works for representative `turn_on_light_group` and `turn_off_light_group` requests.
4. Confirm the iOS sheet opens for Entry, Kitchen, Playroom, Upstairs, and Study.
5. Confirm the title is `<Area> Lights`.
6. Confirm the body shows `x On | y Off`.
7. Confirm `All On` is disabled when `0` lights are off.
8. Confirm `All Off` is disabled when `0` lights are on.
9. Confirm both buttons are enabled when at least one light is on and at least one light is off.
10. Confirm `All On` and `All Off` change the expected HA lights.
11. Confirm the dialog closes after a successful action.
12. Confirm the dialog stays open and shows an error if the API fails.
13. Confirm the node connector and border color refresh after `All On` and `All Off`.
14. Confirm the Garage node still performs the garage action and does not show a lighting dialog.
15. Confirm VoiceOver labels and hints make the tappable nodes understandable.

Future full automation checks:

1. Confirm `GET /api/home/lighting-actions` returns all five non-garage areas.
2. Confirm each listed automation/scene/script succeeds from the API.
3. Confirm each listed automation/scene/script changes the expected HA lights.
4. Confirm the response includes `refreshedHomeOverview`.
5. Confirm the app does not expose raw HA entity IDs in the UI.

## Open Decisions

These are the decisions to settle before implementation:

1. Which existing HA automations should appear in each room dialog?
2. Should we convert any of those automations into scenes or scripts first?
3. Should `All On` preserve HA defaults, or force a default brightness/color temperature?
4. Should all automation actions close the dialog only after API-confirmed success, matching the current MVP behavior?
5. Should automation actions require confirmation? Recommendation: no confirmation unless an action affects more than the tapped room.
6. Should the future catalog live in TypeScript first, or should we jump straight to JSON/env-backed config? Recommendation: TypeScript first.

## Preferred Remaining Build Order

1. Manually QA the current MVP on a device against live Home Assistant.
2. Confirm/create the HA scenes, scripts, and automations that should appear in each room.
3. Add the backend automation catalog and read-only `GET /api/home/lighting-actions`.
4. Add backend perform route and HA facade execution for scenes, scripts, and automations.
5. Add API tests.
6. Add Swift models, service, and view model for the automation catalog.
7. Extend the existing SwiftUI dialog with automation rows above the current footer buttons.
8. Wire automation success refresh into `HomeOverviewViewModel.apply(overview:)`.
9. Run backend and iOS tests.
10. Install on device and manually QA against live Home Assistant.
