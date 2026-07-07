# Lighting Automation Dialog Feature Plan

## Goal

Add a tap interaction to the Home blueprint nodes so each lighting area can expose its relevant Home Assistant lighting actions from inside Levy Home.

Target behavior:

- Tapping `Entry`, `Kitchen`, `Playroom`, `Upstairs`, or `Study` opens a lighting dialog for that area.
- The dialog lists curated lighting automations, scenes, or scripts for that area.
- Tapping one list item triggers that selected Home Assistant action, closes the dialog on success, and refreshes the Home overview so the blueprint connector and node border colors update.
- The bottom of the dialog has side-by-side `All On` and `All Off` buttons for that same area.
- The `Garage` node keeps its existing garage behavior and does not open the lighting dialog.

The important product boundary is that the iOS app should not send arbitrary Home Assistant domains, service names, or entity IDs. The app should ask the Levy Home API to run a stable, curated action ID. The backend should own the mapping from that action ID to Home Assistant.

## Current App Shape

The current code already has most of the right pieces:

- `LevyHome/Views/Home/Blueprint/HomeBlueprintView.swift` owns the foreground blueprint nodes and connector lines.
- `LevyHome/Views/Home/HomeContentView.swift` renders `HomeBlueprintView`, owns the Home screen state, and already handles garage taps.
- `LevyHome/ViewModels/HomeOverviewViewModel.swift` owns the loaded Home overview and already has `apply(overview:)`, which is useful after a lighting action returns a refreshed overview.
- `LevyHome/ViewModels/QuickActionsViewModel.swift` handles garage and light quick actions with busy states, logging, confirmation support, and refreshed overview returns.
- `LevyHome/Services/API/APIClient+Home.swift` already calls:
  - `GET /api/home/overview`
  - `GET /api/home/actions`
  - `POST /api/home/actions`
- `apps/api/src/routes/homeRoutes.ts` already exposes Home overview and quick-action routes.
- `apps/api/src/validation/homeValidation.ts` already rejects arbitrary Home Assistant payload keys such as `domain`, `service`, `entityId`, `target`, and `serviceData`.
- `apps/api/src/integrations/homeAssistant/liveFacade.ts` currently supports garage cover actions and light `turn_off`; it will need a small expansion for scenes, scripts, automations, and room-level `turn_on`.

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
| `Playroom` | Playroom | `light.playroom_lamp` now; future `light.playroom_lights` if more fixtures are added |
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

Add a lighting-action API that is separate from garage quick actions but follows the same safety pattern.

### Read Catalog

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

The response should not need to include Home Assistant entity IDs. The app only needs stable action IDs, display text, icons, and enabled states.

### Perform Action

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

### Stage 1: Define A Curated Lighting Catalog

Add a small backend-owned catalog for the five non-garage blueprint areas.

Recommended first version:

- Keep the catalog in TypeScript, for example `apps/api/src/homeLightingCatalog.ts`.
- Use stable area IDs: `entry`, `kitchen`, `playroom`, `upstairs`, `study`.
- Include `All On` and `All Off` actions as first-class action IDs, even if the UI displays them in the footer.
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

### Stage 2: Add API Contracts And Validation

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

### Stage 3: Extend The Home Assistant Facade

Update:

- `apps/api/src/integrations/homeAssistant/facade.ts`
- `apps/api/src/integrations/homeAssistant/liveFacade.ts`
- `apps/api/src/integrations/homeAssistant/mockFacade.ts`

The live facade currently has a private `callService` helper limited to `cover` and `light`. Expand it so the backend can call these service domains safely:

- `scene.turn_on`
- `script.turn_on`
- `automation.trigger`
- `light.turn_on`
- `light.turn_off`

Keep the public facade method high-level, for example:

```ts
triggerLightingAction(execution: LightingExecution): Promise<void>
```

Do not expose a generic `callService(domain, service, body)` method to routes or validation. The catalog should remain the only place that decides what HA service can run.

### Stage 4: Add HomeService Methods And Routes

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

### Stage 5: Backend Tests

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

### Stage 1: Add Swift Models

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

### Stage 2: Add API Client And Service Methods

Update:

- `LevyHome/Services/API/APIClient+Home.swift`
- `LevyHome/Services/QuickActionService.swift`, or create `LightingActionService.swift`

Recommended choice: create a separate `LightingActionService` and `LightingActionsViewModel`. The feature is related to quick actions, but it has area-specific catalog state and a dialog-specific UI. Keeping it separate will keep `QuickActionsViewModel` from becoming a catch-all.

API methods:

```swift
func fetchLightingActions() async throws -> LightingActionsResponse
func performLightingAction(_ request: LightingActionRequest) async throws -> LightingActionResponse
```

### Stage 3: Add A LightingActionsViewModel

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

### Stage 4: Make Non-Garage Blueprint Nodes Tappable

Update:

- `LevyHome/Views/Home/Blueprint/HomeBlueprintView.swift`

Add a small app-facing enum, for example:

```swift
enum BlueprintLightingAreaID: String, CaseIterable, Identifiable {
    case entry
    case kitchen
    case playroom
    case upstairs
    case study
}
```

Then add a callback to `HomeBlueprintView`:

```swift
let onLightingAreaTapped: (BlueprintLightingAreaID) -> Void
```

Wrap the five non-garage nodes in plain buttons. Keep Garage as its own existing button.

Accessibility should be explicit:

- Label: `Kitchen lighting`
- Hint: `Shows Kitchen lighting actions.`

### Stage 5: Add The Dialog View

Create a focused SwiftUI view, for example:

- `LevyHome/Views/Home/Lighting/LightingActionDialog.swift`

Recommended UI:

- Title: area title, such as `Kitchen`.
- Optional subtitle: small status or count of actions.
- List rows for curated actions.
- Bottom action bar with `All On` and `All Off`.
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

### Stage 6: Wire HomeContentView

Update:

- `LevyHome/Views/Home/HomeContentView.swift`
- `LevyHome/App/AppEnvironment.swift`
- `LevyHome/App/LevyHomeApp.swift` if dependency wiring requires it.
- Preview support for `HomeContentView`.

`HomeContentView` should:

1. Own `@StateObject private var lightingActionsViewModel`.
2. Load lighting actions alongside home overview, weather, and quick actions.
3. Set `selectedLightingArea` when a blueprint node is tapped.
4. Present the dialog for non-garage nodes.
5. Apply the refreshed overview after a successful action.

The existing garage tap flow should remain unchanged.

### Stage 7: iOS Tests

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

Before calling the feature TestFlight-ready:

1. Start the API in live Home Assistant mode.
2. Confirm `GET /api/home/lighting-actions` returns all five non-garage areas.
3. Confirm each area has `All On` and `All Off`.
4. Confirm each listed action succeeds from the API.
5. Confirm each listed action changes the expected HA lights.
6. Confirm the response includes `refreshedHomeOverview`.
7. Confirm the iOS sheet opens for Entry, Kitchen, Playroom, Upstairs, and Study.
8. Confirm the Garage node still performs the garage action and does not show a lighting dialog.
9. Confirm the dialog closes after successful action selection.
10. Confirm the dialog stays open and shows an error if the API fails.
11. Confirm the node connector and border color refresh after `All On` and `All Off`.
12. Confirm the app does not expose raw HA entity IDs in the UI.
13. Confirm VoiceOver labels and hints make the tappable nodes understandable.

## Open Decisions

These are the decisions to settle before implementation:

1. Which existing HA automations should appear in each room dialog?
2. Should we convert any of those automations into scenes or scripts first?
3. Should `All On` preserve HA defaults, or force a default brightness/color temperature?
4. Should an action close the dialog immediately on request, or only after the API confirms success? Recommendation: close only after success.
5. Should actions require confirmation? Recommendation: no confirmation for lighting actions unless an action affects more than the tapped room.
6. Should the catalog live in TypeScript first, or should we jump straight to JSON/env-backed config? Recommendation: TypeScript first.

## Preferred Build Order

1. Confirm/create the HA scenes, scripts, automations, and light groups.
2. Add the backend catalog and read-only `GET /api/home/lighting-actions`.
3. Add backend perform route and HA facade execution.
4. Add API tests.
5. Add Swift models, service, and view model.
6. Make blueprint nodes tappable.
7. Add the SwiftUI dialog.
8. Wire success refresh into `HomeOverviewViewModel.apply(overview:)`.
9. Run backend and iOS tests.
10. Install on device and manually QA against live Home Assistant.
