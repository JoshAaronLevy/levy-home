# Siri Implementation Plan

Created: 2026-07-11

Status: Stages 1-5 code implementation completed on 2026-07-11; Stage 1’s required Apple-account signing and physical-device routing validation remain outstanding. Stages 6-9 remain planning only and do not change the API, database, Render service, or Home Assistant configuration.

## What Josh Needs To Do Outside The Codebase

Codex can create the Xcode target, source files, tests, entitlements, plist entries, builds, archives, and exported-IPA checks. The items below require Apple-account access, device interaction, or a product decision from Josh and Mallory.

### Required Before Or During Stage 1

1. Be signed into Xcode with the Apple Developer account for team `45K7QCRX6Y`.
2. Allow Xcode automatic signing to register and sign the proposed Intents extension bundle ID, `com.levyhome.app.intents`.
3. If Xcode cannot manage capabilities automatically, use Apple Developer to:
   - Enable Siri for the `com.levyhome.app` App ID.
   - Register or enable the Intents extension App ID.
   - Create `group.com.levyhome.app` and assign it to the app and extension App IDs.
   - Regenerate affected development and distribution provisioning profiles if signing is managed manually.
   - Use an Apple Developer Account Holder or Admin account for portal changes that the current role cannot perform.
4. Have a physical iPhone available for the Stage 1 routing spike. Simulator and unit tests cannot prove which app Siri will choose for a spoken request.
5. Make sure Siri is enabled on that phone. Enable Siri while locked if locked-phone support is part of the acceptance test.

Apple references:

- [Creating an Intents app extension](https://developer.apple.com/documentation/sirikit/creating-an-intents-app-extension)
- [Requesting authorization to use Siri](https://developer.apple.com/documentation/sirikit/requesting-authorization-to-use-siri)
- [Siri entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.siri)
- [Enabling App ID capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/)

### Required When The First Device Build Is Ready

On Josh's phone, and later on Mallory's phone:

1. Install and open Levy Home once.
2. Confirm that `Device Owner` is set to the correct resident.
3. Open the proposed Siri settings row in Levy Home and approve Siri access.
4. Speak the Stage 1 test phrases and report three separate observations:
   - What Siri transcribed.
   - Which app Siri routed the request to.
   - What Levy Home actually persisted.
5. Test with Levy Home foregrounded, backgrounded, force-quit, and with the phone locked.

Siri controls natural-language routing. Code can make Levy Home eligible and provide vocabulary, but it cannot guarantee that every wording will route correctly. The desired phrase must be proven on the real phones before the app teaches it as a supported phrase.

### Required For TestFlight Acceptance

1. Install the signed TestFlight build on both phones.
2. Repeat the full phrase matrix on both phones; a development build alone is not sufficient release evidence.
3. Confirm whether the preferred public phrase should be:
   - `Using Levy Home, add paper plates to Shopping.`
   - `Add paper plates to Shopping in Levy Home.`
   - `Add paper plates to the Levy Home shopping list.`
4. Upload the signed build through Xcode or Transporter when ready, unless Codex is separately asked to run the repository's complete release/export workflow.

### Not Required For The Initial Implementation

- No Home Assistant changes.
- No Neon/Postgres migration.
- No new Render environment variable or secret.
- No new REST endpoint; the current Shopping and To Do mutation endpoints are sufficient.
- No Apple Reminders permission. Siri will write to Levy Home's backend, not EventKit or the Reminders database.
- No microphone permission specifically for this feature. Siri owns speech capture.
- No Apple Intelligence-capable phone for the stable SiriKit path.
- No manually authored Shortcut for the primary one-sentence SiriKit path.
- No separate app installation for the Intents extension; it is embedded inside Levy Home.

## Goal

Add stable Siri support for the two shared Levy Home lists:

- `Shopping`
- `To Do`

The primary target experience is one spoken request with the app closed:

```text
Using Levy Home, add paper plates to Shopping.
```

The same integration should support To Do:

```text
Using Levy Home, add call the dentist to To Do.
```

The request should persist through the existing Levy Home API, preserve Josh/Mallory attribution, update an already-visible list, and return an honest Siri result only after the backend confirms the mutation.

## Recommended Technical Direction

Use the stable SiriKit Lists and Notes domain for the first release:

- Add an Intents extension that handles `INAddTasksIntent`.
- Expose `Shopping` and `To Do` as the two target task lists.
- Let Siri resolve the open-ended task title and target list.
- Route both lists through one Foundation-only command service.
- Keep all SwiftUI view models and screen state out of the extension.

`INAddTasksIntent` is the strongest stable match because its contract already contains `taskTitles` and `targetTaskList` and does not inherently require an unlocked phone. The system contract can carry several titles, but v1 will deliberately accept one title per invocation so the stock response can remain truthful if a server call fails. Apple also explicitly allows the extension to communicate with the app's server.

References:

- [Lists and Notes](https://developer.apple.com/documentation/sirikit/lists-and-notes)
- [`INAddTasksIntent`](https://developer.apple.com/documentation/intents/inaddtasksintent)
- [`INAddTasksIntentHandling`](https://developer.apple.com/documentation/intents/inaddtasksintenthandling)

Do not make a generalized list framework, add a Siri-specific backend endpoint, or put network logic in `ShoppingListViewModel` or `ToDoViewModel`. This is a two-list household feature and should stay small.

## Pre-Stage 1 Baseline

The following described the repository before the Stage 1 implementation above. It remains the basis for the later-stage design, except where Stages 1-5 have now added extension packaging, Siri authorization UI, vocabulary, entitlement declarations, shared extension-safe foundations, Shopping and To Do command slices, and deterministic Siri resolution/error handling.

### Xcode And Apple Configuration

- `LevyHome.xcodeproj` currently has only the `LevyHome` app and `LevyHomeTests` targets.
- There is no app-extension product, target dependency, or `Embed App Extensions` build phase.
- The app bundle ID is `com.levyhome.app` and the deployment target is iOS 18.
- The current toolchain is Xcode 26.6 with the iOS 26.5 SDK.
- Neither `LevyHome/Resources/LevyHome.entitlements` nor `LevyHome/LevyHomeRelease.entitlements` currently contains Siri or App Group entitlements.
- `LevyHome/Resources/Info.plist` does not yet contain `NSSiriUsageDescription`.
- `NSMicrophoneUsageDescription` and `NSRemindersFullAccessUsageDescription` already exist for unrelated features; neither replaces Siri authorization.

### Existing List Mutations

Shopping already exposes the required operations in `LevyHome/Services/API/APIClient+Shopping.swift`:

- `GET /api/shopping-list`
- `GET /api/shopping-list/items/lookup`
- `POST /api/shopping-list/items`
- `PATCH /api/shopping-list/items/:itemId`

To Do already exposes the required operations in `LevyHome/Services/API/APIClient+ToDo.swift`:

- `GET /api/todo-list`
- `POST /api/todo-list/items`

Resident-to-user mapping can reuse `GET /api/users` from `LevyHome/Services/API/APIClient+System.swift` after the users request is split away from unrelated system-health models.

### Existing Identity And Configuration

- The selected resident is currently stored as `currentResidentName` in ordinary `UserDefaults.standard` through `ResidentPreference`.
- An extension cannot read the app's standard defaults container.
- The app reads `LevyHomeAPIBaseURL` from its own bundle. An Intents extension has a different `Bundle.main`, so the extension needs the same key in its own plist.
- The current Release API URL must be verified in the extension bundle just as it is verified in the main app bundle.

### Existing Live Updates

- Shopping already broadcasts and applies external `item_created` mutations. A Siri-created Shopping item should fit the existing realtime path.
- To Do's websocket currently carries only `hello` and `presence_changed`. It records create sessions for notifications but does not broadcast item mutations to connected iOS clients.
- To Do therefore needs realtime mutation or snapshot parity before an already-open To Do screen can reliably show a Siri addition without manual refresh.

### Existing API Security Boundary

The current Shopping and To Do write routes do not require application-level authorization. Siri does not introduce that condition, but it will reuse it. Do not attempt to "secure" the extension by embedding a shared secret in the app; an embedded secret can be extracted. Proper device/user authentication should be designed separately if the API is hardened.

## Recommended V1 Behavior

| Situation | V1 behavior |
| --- | --- |
| New Shopping item | Create quantity `1`, `purchased: false`, in the real `Miscellaneous` category. |
| Item is already needed | Do not create a duplicate. Treat the requested final state as satisfied, but do not promise custom "already present" speech from the stock SiriKit response. |
| Item exists but was purchased | Restore it using the same semantics as the current `Add Back to Needed` action. |
| New To Do item | Create an `open` item with no date, recurrence, location, notes, alerts, or subtasks. |
| Duplicate To Do title | Allow it. Separate tasks can legitimately have the same title. |
| Several spoken titles | Reject the invocation before mutation and teach one item at a time in v1. The stock response has one overall result code and cannot reliably explain arbitrary per-title partial failure. |
| Missing resident | Require opening Levy Home to choose the Device Owner; never silently attribute the action to Josh. |
| Missing or ambiguous list | Ask the user to choose Shopping or To Do. |
| Unknown list | Decline rather than creating an invented list. |
| Due date, location trigger, or priority | Explicitly unsupported in v1; do not silently discard it. |
| Offline or backend failure | Return failure. Never speak success before persistence is confirmed. |
| Ambiguous network timeout | Do not automatically retry a POST; mutation IDs are correlation IDs today, not proven idempotency keys. |

## Definition Of Done

The initial Siri implementation is complete only when all of the following are true:

1. `INAddTasksIntent` reaches the Levy Home Intents extension on both physical phones.
2. Shopping and To Do items persist through the existing production API.
3. A terminated app is not opened just to perform a normal addition.
4. The locked-phone case works when the user has allowed Siri while locked.
5. The backend receives the correct `actor`; To Do also receives the correct `createdBy` user ID.
6. Shopping duplicate and purchased-item behavior matches the existing app UI.
7. An already-open Shopping or To Do screen receives the committed item without manual refresh.
8. Siri never announces success for a failed mutation; v1 avoids partial multi-item outcomes by accepting one title per invocation.
9. The exported IPA contains the signed extension, correct entitlements, and the production API URL in both bundles.
10. The advertised phrase succeeds three consecutive times per test state on both TestFlight-installed phones.

## Stage 1: Prove Siri Routing And Package The Extension

### Goal

De-risk Apple's phrase routing and extension signing before refactoring list business logic.

### Implementation

1. Add a new Intents extension target named `LevyHomeIntents`.
2. Use bundle ID `com.levyhome.app.intents`, deployment target iOS 18, `APPLICATION_EXTENSION_API_ONLY=YES`, and `SKIP_INSTALL=YES`.
3. Add the extension product to the host app's target dependencies and embed it as:

   ```text
   LevyHome.app/PlugIns/LevyHomeIntents.appex
   ```

4. Create:
   - `LevyHomeIntents/IntentHandler.swift`
   - `LevyHomeIntents/Info.plist`
   - `LevyHomeIntents/LevyHomeIntents.entitlements`
5. Configure the extension plist with:
   - `NSExtensionPointIdentifier = com.apple.intents-service`
   - Principal class `$(PRODUCT_MODULE_NAME).IntentHandler`
   - `IntentsSupported = [INAddTasksIntent]`
   - No locked-device restriction for `INAddTasksIntent`
   - `LevyHomeAPIBaseURL = $(LEVY_HOME_API_BASE_URL)`
6. Set `LEVY_HOME_API_BASE_URL` explicitly for both Debug and Release on the new extension target. The existing value is target-scoped to `LevyHome`, so the extension must not assume it inherits the app target's setting.
7. Add `com.apple.developer.siri` and `group.com.levyhome.app` to the appropriate signed targets while preserving every existing entitlement.
8. Update both app entitlement files; Debug and Release use different files and must not drift.
9. Add `NSSiriUsageDescription` to the main app:

   ```text
   Levy Home uses Siri to add items to your shared Shopping and To Do lists.
   ```

10. Add a localized `AppIntentVocabulary.plist` to the app bundle before evaluating routing. Include:
   - `IntentPhrases` examples for `INAddTasksIntent` using Levy Home.
   - Minimal global parameter vocabulary for `INAddTasksIntent.targetTaskList`.
   - Stable identifiers and synonyms for `Shopping` and `To Do`.
   - List titles as notebook item titles; Apple's `.notebookItemTitle` category covers a note, task, or task-list title, while `.notebookItemGroupName` means a folder containing lists.
11. Wait several minutes after installing a development build before judging vocabulary recognition; Apple notes that development-device ingestion is not instantaneous.
12. Add a Siri row under Preferences that:
   - Shows authorization status.
   - Requests Siri authorization only after a user taps it.
   - Does not repeatedly prompt after denial.
   - Directs the user to Settings when appropriate.
13. Implement a temporary routing-only handler that records a distinct `OSLog` event and returns failure without writing data. It must never pretend that an item was saved.

Vocabulary references:

- [Registering custom vocabulary with SiriKit](https://developer.apple.com/documentation/sirikit/registering-custom-vocabulary-with-sirikit)
- [`INVocabularyStringType.notebookItemTitle`](https://developer.apple.com/documentation/sirikit/invocabularystringtype/invocabularystringtypenotebookitemtitle)

### Verification

1. Build the host app and extension without signing for compile coverage.
2. Build and install a signed Debug build on Josh's phone.
3. Approve Siri access from the app's Preferences screen.
4. Use Xcode's Siri Intent Query tooling and speak:
   - `Using Levy Home, add routing test to Shopping.`
   - `Add routing test to Shopping in Levy Home.`
   - `Add routing test to the Levy Home shopping list.`
5. Confirm the extension receives the parsed target list and task title while the app is foregrounded, backgrounded, terminated, and the phone is locked.
6. Confirm the routing-only build writes no Shopping or To Do row.

### Exit Criteria

- The `.appex` is embedded and signed.
- Siri authorization behaves correctly.
- At least one explicit app-qualified phrase reaches Levy Home reliably on a real phone.
- The exact transcription, selected provider, target list, and task title are recorded.
- If Siri still routes to Apple Reminders after the vocabulary-complete build has had time to ingest, stop for a product decision. Either continue through Stages 2-4 to build the shared command slices and then use Stage 8, or stop the implementation; Stage 8 depends on the shared service and cannot be entered directly from Stage 1.

## Stage 2: Build Extension-Safe Shared Foundations

### Goal

Let the app, Intents extension, and tests share the same list-command behavior without pulling SwiftUI view models into the extension or duplicating endpoint logic. Keep the command, identity, configuration, and resolution core Foundation-only; Siri authorization remains a thin app-only adapter that imports Intents.

### Implementation

1. Add a Siri service group under `LevyHome/Services/Siri/`:
   - `SiriListKind.swift`
   - `SiriListCommandResult.swift`
   - `SiriListCommandService.swift`
   - `SiriIntentResolver.swift`
   - `SiriSharedSettings.swift`
   - `SiriAuthorizationService.swift`
2. Give the required Foundation-only command/settings/API files membership in both the app and extension targets. Keep `SiriAuthorizationService` in the app target because it necessarily imports Intents.
3. Refactor `APIClient`'s concrete `AppLogStore` dependency behind a small Foundation-only logging protocol. Keep `AppLogStore` app-only; the extension can use `OSLog` or no injected logger.
4. Split `fetchUsers` into a focused `APIClient+Users.swift` so the extension does not pull unrelated health-response models into its target.
5. Move small shared response types out of unrelated files where required:
   - Move `PushDeliveryStatus` out of the broader notification response file.
   - Move the explicit resident identity/storage contract out of `HomeOverview.swift` so the extension does not inherit the Home model graph.
   - Keep `UIDevice.current.name` inference app-only. The extension must require an explicitly shared Device Owner rather than guessing from its process or device name.
6. Include only the request/response dependencies needed by Shopping, To Do, users, API errors, JSON values, and nullable API values.
7. Move resident storage to `UserDefaults(suiteName: "group.com.levyhome.app")`.
8. Perform a one-time migration from `UserDefaults.standard` so an existing Josh/Mallory selection survives the upgrade. The migration must run before any group-backed `@AppStorage` wrapper reads its initial value.
9. Update every current `@AppStorage(ResidentPreference.storageKey)` consumer to use the App Group store:
   - `LevyHome/App/LevyHomeApp.swift`
   - `LevyHome/Views/Home/HomeContentView.swift`
   - `LevyHome/Views/Shopping/ShoppingListView.swift`
   - `LevyHome/Views/ToDo/ToDoView.swift`
   - `LevyHome/Views/Preferences/PreferencesView.swift`
10. Read the same shared resident from the Intents extension. Return `failureRequiringAppLaunch` when no resident has been established.
11. Give the extension its own API configuration loader and verify that its `LevyHomeAPIBaseURL` is resolved, not a literal unresolved `$(LEVY_HOME_API_BASE_URL)` placeholder.
12. Update `LevyHome/Resources/PrivacyInfo.xcprivacy` for App Group defaults:
   - Retain `CA92.1` for app-private defaults and legacy migration.
   - Add `1C8F.1` for defaults shared between the app and its extension through the same App Group.
   - Package the revised manifest with both the app and extension.

Privacy reference: [Apple's approved UserDefaults reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).

### Verification

- Unit-test standard-defaults to App Group migration with isolated suites.
- Confirm changing Device Owner is immediately visible to the extension.
- Confirm an unset Device Owner produces a needs-setup result.
- Confirm existing app screens still read the same resident after migration.
- Confirm the extension constructs API URLs using its own bundle.
- Confirm both Debug and Release no-signing builds compile.

### Exit Criteria

- The dual-target command/settings core imports Foundation but not SwiftUI; the thin authorization and intent adapters may import Intents in their owning targets.
- The extension can read the resident and API base URL independently of the running app.
- Existing resident preference and list behavior remain unchanged.
- There is one reusable command boundary for SiriKit and any later App Intent fallback.

## Stage 3: Implement Shopping End To End

### Goal

Make the first real Siri mutation a complete Shopping vertical slice.

### Implementation

1. Add Shopping operations to `SiriListCommandService` using the shared API client.
2. Normalize the spoken title using the same whitespace/case rules used by Shopping duplicate detection.
3. Fetch the Shopping snapshot once per Siri request to:
   - Resolve the real `Miscellaneous` category ID.
   - Avoid creating a client-invented category.
   - Compare against current items.
4. Use the server lookup endpoint before creation so behavior remains correct if the local snapshot races another writer.
5. For the single resolved title:
   - If already needed, return `alreadyPresent` without a mutation.
   - If previously purchased, `PATCH` it back to `purchased: false` using the current Add Back semantics.
   - Otherwise `POST` a new quantity-1, unpurchased item in `Miscellaneous`.
6. Send the selected resident as `actor` and generate a fresh mutation ID for every mutation.
7. If a create loses a race and receives duplicate HTTP `409`, look up the item again and resolve it idempotently instead of returning an incorrect generic failure.
8. Replace the routing-only Stage 1 response for the `Shopping` target with the real command service.
9. Populate `addedTasks` and `modifiedTaskList` with stable backend IDs so Siri can confirm the committed result.
10. If Siri supplies more than one title, reject the invocation before mutation in v1 rather than risking a partially persisted batch with an inaccurate system response.
11. Keep the current Shopping websocket path as the authoritative UI update path.

### Tests

- New item.
- Whitespace-only title.
- Case-insensitive duplicate.
- Already-needed duplicate.
- Previously purchased item.
- Missing `Miscellaneous` category.
- Race-generated `409`.
- Correct actor and unique mutation IDs.
- One title and rejection of several titles before mutation.
- Cancellation and ambiguous timeout with no automatic POST retry.

### Exit Criteria

- A physical-device Siri request adds a Shopping item with the app terminated.
- The correct resident is recorded as actor.
- A visible Shopping screen and a second connected phone receive the committed row once.
- Duplicate handling matches the existing editor instead of creating extra rows.
- Siri returns stock success only after the single requested title reaches an accepted final state.

## Stage 4: Add To Do End To End

### Goal

Route the same Siri contract to Levy Home's To Do list without creating a second business-logic path.

### Implementation

1. Add To Do operations to the same `SiriListCommandService`.
2. Fetch `/api/users` once per Siri request.
3. Match the shared resident to the correct backend user using the same name normalization as `ToDoViewModel`.
4. Do not use a "first user" fallback. If the resident cannot be mapped, return a needs-setup/failure result.
5. Create the task with:
   - `status: open`
   - `locationIds: []`
   - `createdBy: <resolved user ID>`
   - `actor: <selected resident name>`
   - A fresh mutation ID
6. Leave date, recurrence, notes, alerts, and subtasks unset in v1.
7. Allow duplicate To Do titles.
8. Populate Siri's returned task and task-list objects with the committed backend IDs.
9. Reject multi-title input before mutation in v1 for the same truthful-response reason as Shopping.
10. Preserve the existing To Do session-notification behavior by always supplying actor identity.

### Tests

- Josh mapping.
- Mallory mapping.
- Case and whitespace differences in names.
- Resident missing from `/api/users`.
- User lookup failure.
- Single task and multi-title rejection before mutation.
- Duplicate titles.
- Correct `open` default and empty locations.
- Network/server failure without false success.

### Exit Criteria

- Siri adds a To Do item with the app terminated.
- `createdBy` and `actor` identify the correct resident.
- The returned Siri result names only items the backend committed.
- No database, environment, or Home Assistant change was needed.

## Stage 5: Finish Siri Resolution, Vocabulary, And Error UX

### Goal

Turn the working vertical slices into a predictable two-list Siri conversation.

### Implementation

1. Implement `resolveTargetTaskList` with canonical lists and aliases:

   | Canonical list | Accepted aliases |
   | --- | --- |
   | `Shopping` | `shopping list`, `grocery list`, `groceries` |
   | `To Do` | `to-do list`, `todo list`, `task list`, `tasks` |

2. When the list is missing or ambiguous, offer only Shopping and To Do as disambiguation choices.
3. Reject unrelated list names instead of inventing a list or falling through to Shopping.
4. Implement `resolveTaskTitles` after trimming whitespace. Accept exactly one nonempty title in v1; if Siri supplies several titles, mark the request unsupported before mutation and teach one-at-a-time usage in the app's phrase examples.
5. Maintain the localized global `AppIntentVocabulary.plist` introduced in Stage 1. `Shopping` and `To Do` are common to every Levy Home installation, so they belong in bundled global vocabulary rather than runtime user-specific `INVocabulary` registration.
6. Keep app-name synonyms conservative. Add an alternate name only if physical testing shows that Siri consistently mishears `Levy Home` and the alternative is a legitimate name users would say.
7. Treat temporal triggers, spatial triggers, and priority as unsupported for v1. Ask the user to use the app rather than silently losing requested metadata.
8. Use confirmation only for local readiness. Do not make an extra server mutation or promise success during confirmation.
9. Map outcomes carefully within the limits of stock `INAddTasksIntentResponse`:
   - Normal backend success -> `.success` with the committed task and modified list.
   - Already-needed Shopping item -> `.success` only because the requested final state is already satisfied; do not promise Siri will say "already present."
   - Restored Shopping item -> `.success` with the accepted final-state task.
   - Missing resident/setup -> `failureRequiringAppLaunch`.
   - Network/backend error -> failure without app launch unless setup truly requires it.
   - Multi-title input -> reject before mutation, avoiding an outcome the stock response cannot describe accurately.
10. Return `.success` only when the single requested title reaches an accepted final state. Return `.failure` if it does not.
11. Keep structured command results for logs and tests, but do not claim that the stock response can speak arbitrary custom or per-outcome dialog.
12. Add concise phrase examples to the Siri Preferences screen, but advertise only phrases that passed Stage 7 device testing.

### Exit Criteria

- Both canonical lists and all supported aliases have handler tests.
- Missing-list disambiguation works.
- Unsupported metadata is never silently dropped.
- Failed API calls never create Siri success responses.
- The plan does not promise custom "already present" or partial-result speech from `INAddTasksIntentResponse`.
- No exact phrase is treated as guaranteed merely because it appears in source code.

## Stage 6: Make Open Screens And Other Phones Stay Fresh

### Goal

Ensure the user's visible app state matches the server immediately after Siri commits a mutation.

### Shopping Work

1. Verify the existing backend `item_created` broadcast reaches `ShoppingListViewModel.applyLiveMessage` for an extension-created mutation.
2. Verify background/resume behavior; if a websocket disconnects while Siri is active, refresh the snapshot on reconnect before trusting incremental events.
3. Deduplicate by backend item ID so a snapshot and later event cannot create two rows.

### To Do Work

1. Expand `apps/api/src/todoListRealtime.ts` beyond presence-only messages.
2. Add at least:
   - `snapshot_required`
   - `item_created`
   - `item_updated`
   - `item_deleted`
3. Broadcast committed mutations from `apps/api/src/services/todo/todoListMutationService.ts`.
4. Send `snapshot_required` on new/reconnected sockets so mutations missed while the app was suspended are recovered.
5. Decode the new messages in `LevyHome/Services/ToDo/ToDoListLiveMessages.swift`.
6. Inject `APIClient` or an async snapshot-loader closure into the To Do live-update path. `snapshot_required` must perform an authoritative `GET /api/todo-list`; merely decoding the message cannot refresh state.
7. Serialize snapshot and incremental event application on the main actor so a late snapshot cannot overwrite a newer committed mutation.
8. Apply item events by backend ID in `LevyHome/ViewModels/ToDo/ToDoViewModel.swift`.
9. Preserve the current presence and notification-session behavior while adding mutation broadcasts.

### Verification

- Siri-add an item while the matching screen is visible.
- Siri-add while the app is backgrounded, then reopen it.
- Disconnect and reconnect the websocket around the mutation.
- Keep the list open on the second phone while the first phone invokes Siri.
- Confirm each committed item appears once and pull-to-refresh remains a valid fallback.

### Exit Criteria

- Shopping and To Do both update without manual refresh in the normal connected case.
- Reconnect produces an authoritative snapshot before incremental messages resume.
- The second phone sees the new row promptly.
- Presence indicators and To Do session notifications still work.

## Stage 7: Automated, Signed-Artifact, And TestFlight Verification

### Automated Checks

Add focused tests under `LevyHomeTests/Siri/`, including:

- `SiriListCommandServiceTests`
- `SiriResidentStoreTests`
- `SiriIntentResolverTests`
- Extension API configuration tests
- Shopping duplicate/restoration tests
- To Do user-attribution tests
- Multi-title rejection and error-mapping tests

Use the existing `URLProtocol` pattern from `LevyHomeTests/APIClientTests.swift` for client contract tests.

Representative commands:

```sh
git diff --check

xcodebuild test \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath build/DerivedData \
  -only-testing:LevyHomeTests/SiriListCommandServiceTests

xcodebuild \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/ValidationDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

npm run api:typecheck
npm run api:test
npm run api:build
```

The API commands become mandatory when Stage 6 changes To Do realtime contracts.

### Exported IPA Verification

Archive and export a signed build only when a release/export is authorized. Trust the exported IPA rather than the raw archive.

Verify the exact exported artifact contains:

1. `Payload/LevyHome.app/PlugIns/LevyHomeIntents.appex`.
2. `com.apple.developer.siri` in the effective signed entitlements.
3. `group.com.levyhome.app` on both the app and extension.
4. `INAddTasksIntent` in the extension's supported intents.
5. The expected production `LevyHomeAPIBaseURL` in:
   - `Payload/LevyHome.app/Info.plist`
   - `Payload/LevyHome.app/PlugIns/LevyHomeIntents.appex/Info.plist`
6. Valid embedded provisioning profiles for both executables.
7. All pre-existing app entitlements, including push and WeatherKit, remain present.

### Physical And TestFlight Matrix

Test each canonical phrase on both phones with Levy Home:

- Foregrounded on Shopping.
- Foregrounded on To Do.
- Backgrounded.
- Force-quit.
- Phone locked.
- Temporarily offline.
- Siri permission denied, then re-enabled.

Test these content cases:

- New Shopping item.
- Already-needed Shopping item.
- Previously purchased Shopping item.
- New To Do item.
- Several items in one request, which must fail before any mutation in v1.
- Unsupported list.
- Unsupported due date/location request.
- Backend unavailable.

For every attempt, record Siri transcription, selected provider, backend mutation ID, actor, and final database/UI state.

### Exit Criteria

- Each advertised phrase succeeds three consecutive times per supported state on Josh's and Mallory's TestFlight-installed phones.
- Each successful item persists exactly once.
- Offline/server failure never generates false success.
- The other phone receives the item.
- The exported IPA, not just source or archive, proves the extension configuration.

## Stage 8: Add A Modern App Shortcut Fallback Only If Needed

### When To Enter This Stage

Enter this stage if:

- SiriKit routing is inconsistent on either phone.
- The app should expose actions in Spotlight and the Shortcuts app.
- A predictable two-turn interaction is acceptable as a fallback.

Do not add this stage merely because App Intents are newer. The stable App Shortcut trigger-phrase model does not reliably guarantee an arbitrary free-form item in the initial phrase.

### Implementation

1. Add two background App Intents that call the existing shared service:
   - `AddShoppingItemIntent`
   - `AddToDoItemIntent`
2. Add one `AppShortcutsProvider` with app-qualified phrases.
3. Use a deterministic prompt:

   ```text
   User: Add to Levy Home Shopping.
   Siri: What should I add?
   User: Paper plates.
   ```

4. Keep the target list preconfigured so Siri asks only for the item.
5. Add `SiriTipView` or `ShortcutsLink` only after the shortcuts exist.
6. Reuse identical duplicate, category, attribution, and failure behavior. Do not fork the command logic.

References:

- [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)
- [Implement App Shortcuts with App Intents](https://developer.apple.com/videos/play/wwdc2022/10170/)

### Exit Criteria

- Both shortcuts appear without a manual Add to Siri workflow.
- They work from Siri, Spotlight, and Shortcuts.
- Each asks exactly one follow-up question.
- Their persisted results match the SiriKit path exactly.

## Stage 9: Migrate To The Reminders App Schema When iOS 27 Is Final

This is future work. Do not make the production project depend on beta SDK behavior.

The current Xcode 26.6 toolchain cannot compile the new iOS 27 Reminders schema. When a final Xcode 27 SDK is available:

1. Model Shopping and To Do as entities conforming to `.reminders.list`.
2. Model a committed Levy Home list item as a `.reminders.reminder` entity.
3. Add `@AppIntent(schema: .reminders.createReminder)` and map its title/list parameters into `SiriListCommandService`.
4. Gate new code with availability checks while keeping the iOS 18-26 path intact.
5. Run SiriKit and App Schema support side by side initially.
6. Repeat the complete Stage 7 TestFlight matrix on final iOS 27 software.
7. Retire the SiriKit adapter only in a later release after both phones show equal or better routing reliability.

References:

- [Reminders App Schema](https://developer.apple.com/documentation/appintents/app-schema-domain-reminders)
- [`createReminder` schema](https://developer.apple.com/documentation/appintents/appschema/remindersintent/createreminder)

## Proposed File Map

### New Files And Targets

```text
LevyHomeIntents/
  Info.plist
  IntentHandler.swift
  LevyHomeIntents.entitlements

LevyHome/Services/Siri/
  SiriAuthorizationService.swift
  SiriIntentResolver.swift
  SiriListCommandResult.swift
  SiriListCommandService.swift
  SiriListKind.swift
  SiriSharedSettings.swift

LevyHome/Resources/Base.lproj/
  AppIntentVocabulary.plist

LevyHome/Views/Preferences/
  SiriPreferencesView.swift

LevyHomeTests/Siri/
  SiriIntentResolverTests.swift
  SiriListCommandServiceTests.swift
  SiriResidentStoreTests.swift
```

Small shared model/protocol files may be added while extracting extension-safe API dependencies, but avoid a new dynamic framework unless dual-target source membership proves unworkable.

### Existing Files Expected To Change

```text
LevyHome.xcodeproj/project.pbxproj
LevyHome/Resources/Info.plist
LevyHome/Resources/LevyHome.entitlements
LevyHome/LevyHomeRelease.entitlements
LevyHome/Resources/PrivacyInfo.xcprivacy
LevyHome/App/LevyHomeApp.swift
LevyHome/App/AppConfig.swift
LevyHome/Models/HomeOverview.swift
LevyHome/Services/API/APIClient.swift
LevyHome/Services/API/APIClient+Shopping.swift
LevyHome/Services/API/APIClient+ToDo.swift
LevyHome/Services/API/APIClient+System.swift
LevyHome/Views/Home/HomeContentView.swift
LevyHome/Views/Shopping/ShoppingListView.swift
LevyHome/Views/ToDo/ToDoView.swift
LevyHome/Views/Preferences/PreferencesView.swift
LevyHome/Services/ToDo/ToDoListLiveMessages.swift
LevyHome/ViewModels/ToDo/ToDoViewModel.swift
apps/api/src/todoListRealtime.ts
apps/api/src/services/todo/todoListMutationService.ts
```

The thin `IntentHandler.swift` adapter belongs only to the extension target. Put list-name resolution and other testable adapter logic in dual-target `SiriIntentResolver.swift`, which `LevyHomeTests` can import through the host app. Add a separate extension test target only if extension-only behavior later becomes substantial.

The exact file list may shrink after Stage 2 dependency extraction. The important boundaries are that the extension's business layer stays Foundation-only, its thin adapter owns the Intents import, the app keeps its existing SwiftUI ownership, and both Siri routes call one list-command service.

## Cross-Cutting Rules

### Truthful Results

- Persistence must finish before success is returned.
- V1 must reject multi-item input before mutation so a partial result cannot occur.
- A timeout must not be converted into success.
- Never write a row during parameter resolution or confirmation.

### Background Execution

- Keep each request short and cancellation-aware.
- Do not hold a websocket open from the Intents extension.
- Use the normal REST mutations; the backend owns persistence and broadcasts.
- Do not require the main app to launch for routine success.

### Identity

- The App Group holds the selected resident, not an API credential.
- Never default an unset resident to Josh.
- Shopping sends `actor`; To Do sends both `actor` and `createdBy`.
- Changing Device Owner must affect the next Siri invocation.

### Security

- Do not embed a backend secret in either executable.
- Keep the current unauthenticated-route risk documented.
- If authentication is added later, use revocable per-device/user credentials stored in Keychain and shared with the extension through an access group designed for that purpose.

### Privacy And Logging

- Avoid logging full spoken item titles unless explicitly needed for a short-lived debug build.
- Prefer mutation ID, list kind, item count, response status, and normalized error code.
- Never log Apple signing material, tokens, or private API configuration values.

### Scope Control

The initial implementation intentionally does not include:

- Voice listening inside Levy Home.
- A microphone button or custom speech recognizer.
- Creating arbitrary new lists.
- Reading or modifying Apple Reminders.
- Siri support for completing, editing, or deleting items.
- Shopping quantities, brands, notes, stores, or product lookup by voice.
- To Do recurrence, locations, notes, subtasks, alerts, or priority by voice.
- Raising the deployment target for beta App Schema APIs.

Those can be planned after the two basic add-item commands are reliable on both phones.
