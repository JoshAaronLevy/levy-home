# Swift Codebase Refactor Plan

## Purpose

This document lays out a staged, behavior-preserving plan for refactoring the Swift codebase. The goal is not to redesign the app or change user-facing behavior. The goal is to make the SwiftUI app easier to understand, safer to change, easier to test, and less dependent on very large single-file feature implementations.

The current project already has useful architecture boundaries:

- `LevyHome/App`: app bootstrap, environment, configuration, delegate.
- `LevyHome/Models`: app models and API request/response DTOs.
- `LevyHome/Services`: API, live updates, WeatherKit/Open-Meteo/NWS, notifications, preferences, and other integration services.
- `LevyHome/ViewModels`: several feature view models already live outside views.
- `LevyHome/Views`: feature views, shared UI components, and app shell.
- `LevyHomeTests`: unit tests for models, API client behavior, view models, and policies.

The refactor should build on that shape rather than replacing it wholesale.

## Current Hot Spots

Swift files by approximate size at the time this plan was written:

| File | Lines | Notes |
| --- | ---: | --- |
| `LevyHome/Views/ToDo/ToDoView.swift` | 3,633 | Main screen, shared to-do UI, Family Calendar UI, Personal Reminders UI, editor UI, view models, EventKit services, models, preview data. |
| `LevyHome/Views/Shopping/ShoppingListMockupView.swift` | 3,527 | Entry view, live shopping view model, editor, filters, product search, rows, display models, formatting helpers. |
| `LevyHome/Views/Home/HomeView.swift` | 1,853 | Home screen composition, weather cards/charts, blueprint UI, shortcut UI, recent activity ribbon, policy/helpers, previews. |
| `LevyHome/Services/HomeWeatherService.swift` | 938 | Multi-provider weather service, provider implementations, provider DTOs, parsing helpers. |
| `LevyHome/Models/APIResponses.swift` | 636 | Response DTOs for many domains in one file. |
| `LevyHome/Services/ShoppingListLiveService.swift` | 634 | WebSocket service plus message models and connection state. |
| `LevyHome/Services/APIClient.swift` | 420 | Cross-domain HTTP client endpoints. |

The biggest issue is not line count by itself. The issue is mixed responsibilities: views, view models, services, domain models, formatting, preview data, and integration logic are sometimes colocated in the same file.

## Refactor Principles

1. Preserve behavior first.
   Every stage should compile and pass tests before moving on.

2. Prefer move-only changes at first.
   Start by moving existing declarations into better files with minimal edits. Avoid rewriting logic while moving it.

3. Refactor by feature boundary, not by arbitrary file length.
   Split along responsibilities users and developers can understand: Family Calendar, Personal Reminders, shared to-dos, shopping item editor, product search, weather charts, etc.

4. Keep Swift access control intentional.
   Many current declarations are `private` because they live in one file. Moving them will require changing some to default internal access. Do this deliberately and avoid making things `public` unless needed.

5. Keep services out of views.
   SwiftUI views should compose UI and trigger actions. EventKit, live WebSocket handling, API calls, and domain transforms should live in services or view models.

6. Keep previews useful.
   Moving code should not make SwiftUI previews harder to run. Preview fixtures should move to `PreviewSupport` or feature-local preview files.

7. Update Xcode project membership carefully.
   This project uses explicit `.pbxproj` file references. New Swift files must be added to the `LevyHome` target and test files to the `LevyHomeTests` target.

8. Use tests as migration rails.
   For any moved view model, service, or domain mapper, add or preserve tests before doing deeper cleanup.

## Proposed End-State Shape

This is a target direction, not a mandate to create every file immediately.

```text
LevyHome/
  App/
  Models/
    API/
    Activity/
    Home/
    Notifications/
    Shopping/
    ToDo/
    Weather/
  Services/
    API/
    EventKit/
    Notifications/
    Shopping/
    Weather/
  ViewModels/
    Activity/
    Home/
    Notifications/
    Preferences/
    Shopping/
    ToDo/
  Views/
    Activity/
    DeveloperTools/
    Home/
      Components/
      Weather/
      Blueprint/
    Notifications/
    Preferences/
    Root/
    Shared/
    Shopping/
      Components/
      Filters/
      Editor/
      ProductSearch/
    ToDo/
      Calendar/
      Reminders/
      SharedList/
      Editor/
      Components/
  PreviewSupport/
    Activity/
    Home/
    Shopping/
    ToDo/
LevyHomeTests/
  API/
  Home/
  Notifications/
  Shopping/
  ToDo/
  Weather/
```

It is fine if Xcode groups remain flatter than the filesystem at first. The important part is that each feature becomes understandable without scrolling through thousands of lines.

## Stage 0: Baseline And Guardrails

### Objective

Create a known-good baseline before moving code.

### Tasks

1. Confirm the worktree and protect unrelated changes.
   - Run `git status --short`.
   - Identify any unrelated user changes and leave them alone.

2. Capture current file-size inventory.
   - Run `wc -l $(rg --files -g '*.swift') | sort -nr | head -40`.
   - Keep the inventory in the refactor PR/commit notes so progress is visible.

3. Establish the verification command.
   - Primary verification:
     `xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'`
   - Also run `git diff --check` after every stage.

4. Decide whether the refactor is split across multiple commits.
   - Recommended: one commit per stage or per major feature extraction.
   - Avoid one huge "move everything" commit.

### Exit Criteria

- Baseline tests pass.
- No unrelated files are touched.
- The first refactor stage can be reviewed independently.

### Stage 0 Baseline Results

Captured on 2026-07-05 before any structural Swift refactor work.

#### Worktree Status

Command:

```bash
git status --short
```

Result:

```text
 M LevyHome/App/LevyHomeApp.swift
 M LevyHome/Views/ToDo/ToDoView.swift
?? refactor-plan.md
```

Notes:

- `LevyHome/App/LevyHomeApp.swift` and `LevyHome/Views/ToDo/ToDoView.swift` were already modified before Stage 0 for the calendar/reminders permission and To Do updates.
- Stage 0 does not refactor or otherwise touch Swift source.
- `refactor-plan.md` is the planning/baseline artifact.

#### File-Size Inventory

Command:

```bash
wc -l $(rg --files -g '*.swift') | sort -nr | head -40
```

Result:

```text
   22293 total
    3633 LevyHome/Views/ToDo/ToDoView.swift
    3527 LevyHome/Views/Shopping/ShoppingListMockupView.swift
    1853 LevyHome/Views/Home/HomeView.swift
     938 LevyHome/Services/HomeWeatherService.swift
     756 LevyHomeTests/APIClientTests.swift
     671 LevyHomeTests/HomeWeatherViewModelTests.swift
     636 LevyHome/Models/APIResponses.swift
     634 LevyHome/Services/ShoppingListLiveService.swift
     529 LevyHomeTests/PushRegistrationViewModelTests.swift
     485 LevyHomeTests/APIModelDecodingTests.swift
     478 LevyHome/ViewModels/HomeWeatherViewModel.swift
     441 LevyHome/Views/DeveloperTools/DebugView.swift
     420 LevyHome/Services/APIClient.swift
     375 LevyHomeTests/ModelDecodingTests.swift
     367 LevyHome/ViewModels/HomeOverviewViewModel.swift
     346 LevyHome/ViewModels/QuickActionsViewModel.swift
     322 LevyHome/ViewModels/PushRegistrationViewModel.swift
     321 LevyHome/Views/Preferences/PreferencesView.swift
     308 LevyHomeTests/QuickActionsViewModelTests.swift
     306 LevyHome/Views/Preferences/NotificationDeliveryStatusView.swift
     261 LevyHome/Models/APIRequests.swift
     251 LevyHome/Services/NotificationService.swift
     222 LevyHomeTests/HomeOverviewViewModelTests.swift
     221 LevyHome/Views/Home/QuickActionsView.swift
     220 LevyHomeTests/ActivityViewModelTests.swift
     194 LevyHome/Views/Activity/ActivityView.swift
     191 LevyHome/Views/Notifications/NotificationHubView.swift
     180 LevyHomeTests/NotificationPreferencesViewModelTests.swift
     170 LevyHome/App/AppEnvironment.swift
     162 LevyHome/Views/Activity/EventCardView.swift
     158 LevyHome/ViewModels/ActivityViewModel.swift
     137 LevyHome/Models/EventSeverity.swift
     121 LevyHome/Views/Shared/AppScreenChrome.swift
     119 LevyHome/Services/NotificationPreferencesService.swift
     116 LevyHome/Views/Preferences/ThemePreferenceView.swift
     111 LevyHome/Views/Preferences/NotificationPreferencesView.swift
     109 LevyHome/Models/HomeOverview.swift
     108 LevyHome/Models/QuickAction.swift
      96 LevyHome/Services/QuickActionService.swift
```

#### Verification

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

Full test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

The run emitted simulator/system noise, including Network framework messages, a duplicate `UIAccessibilityLoaderWebShared` runtime warning, and WeatherKit auth-service logs. These did not fail the test run.

#### Commit Strategy

Use small, reviewable commits from here forward:

1. Commit the current feature fixes and `refactor-plan.md` separately from structural refactor work if possible.
2. Stage 1 should be a tiny project-file organization proof.
3. Stage 2 should be split into To Do models, EventKit services/view models, Calendar/Reminders UI, shared-list UI, and editor UI.
4. Avoid combining To Do, Shopping, Home, services, and model-file splits into one commit.

## Stage 1: Project And File Organization Helpers

### Objective

Make it safe and repeatable to add many Swift files.

### Tasks

1. Confirm how new Swift files are added.
   - The current project uses explicit `PBXFileReference` / `PBXBuildFile` entries.
   - New files must be added to `LevyHome.xcodeproj/project.pbxproj`.

2. Use Xcode when practical for file creation.
   - Creating files through Xcode reduces `.pbxproj` mistakes.
   - If editing manually, verify each new file appears in the correct target sources build phase.

3. Create feature folders incrementally.
   - Start with `Views/ToDo`, `ViewModels/ToDo`, `Services/EventKit`, `Models/ToDo`, and `PreviewSupport/ToDo`.
   - Do not create the entire target tree unless files are actually moved there.

4. Agree on naming conventions.
   - View files: `ToDoSummaryCard.swift`, `ToDoTaskRow.swift`, `ShoppingItemRow.swift`.
   - View models: `ToDoViewModel.swift`, `ShoppingListViewModel.swift`.
   - Services: `FamilyCalendarService.swift`, `PersonalRemindersService.swift`.
   - Models: `ToDoTask.swift`, `ToDoReminder.swift`, `ToDoCalendarEvent.swift`.

### Exit Criteria

- At least one small file move proves the `.pbxproj` process.
- Build/test still passes.

### Stage 1 Results

Completed on 2026-07-05 as a small project-file organization proof.

#### Moved File

Moved the self-contained To Do flow layout helper out of the large To Do screen file:

```text
LevyHome/Views/ToDo/Components/FlowLayout.swift
```

The implementation was moved without behavior changes. `FlowLayout` is now an internal app-target type instead of a `private` type nested in `ToDoView.swift`, which proves the access-control adjustment that future file splits will need.

Line-count check after the move:

```text
3544 LevyHome/Views/ToDo/ToDoView.swift
  90 LevyHome/Views/ToDo/Components/FlowLayout.swift
3634 total
```

#### Xcode Project Wiring

Updated `LevyHome.xcodeproj/project.pbxproj` manually with:

- one `PBXBuildFile` entry for `FlowLayout.swift`
- one `PBXFileReference` entry for `FlowLayout.swift`
- one `Components` `PBXGroup` under `Views/ToDo`
- one app-target `PBXSourcesBuildPhase` entry

The test build output confirmed Xcode compiled:

```text
LevyHome/Views/ToDo/Components/FlowLayout.swift
```

#### Verification

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

Full test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

Simulator/system logs appeared during the run, including CA event messages, Network framework connection logs, and the duplicate `UIAccessibilityLoaderWebShared` warning. They did not fail the test run.

#### Pattern For Future Stages

For each new Swift file in later stages:

1. Create the feature subfolder only when the first file moves into it.
2. Move one declaration group at a time.
3. Change `private` to internal only when cross-file access requires it.
4. Add the new file to the matching Xcode group.
5. Add the new file to the app target's sources build phase.
6. Run `git diff --check` and the full `xcodebuild test` command.

## Stage 2: To Do Feature Refactor

### Why First

`ToDoView.swift` is currently the largest and most mixed file. It is also actively changing because it now combines shared Neon to-dos, Family Calendar EventKit reads, and Personal Reminders EventKit reads.

### Target Responsibilities

After this stage, `ToDoView.swift` should mainly:

- Own page-level state such as selected sheets and pending deletion.
- Compose the summary, Family Calendar, Personal Reminders, and shared list sections.
- Trigger view model actions.
- Avoid containing service implementations, row components, editor implementation details, and model definitions.

### Proposed File Split

```text
LevyHome/Views/ToDo/
  ToDoView.swift
  Components/
    ToDoErrorBanner.swift
    ToDoSummaryCard.swift
    ToDoMetricPill.swift
    ToDoStatusPill.swift
    ToDoInlineBadge.swift
    ToDoDueBadge.swift
    ToDoIconBadge.swift
    FlowLayout.swift
  Calendar/
    ToDoCalendarPanel.swift
    ToDoCalendarEventRow.swift
    ToDoCalendarEventDetailSheet.swift
    ToDoCalendarDetailRow.swift
  Reminders/
    ToDoRemindersPanel.swift
    ToDoReminderRow.swift
    ToDoReminderMetadataRow.swift
    ToDoReminderDetailSheet.swift
  SharedList/
    ToDoTaskSectionView.swift
    ToDoTaskRow.swift
    ToDoAvatarStack.swift
    ToDoAssigneeStack.swift
    ToDoLocationRow.swift
  Editor/
    ToDoEditorSheet.swift
    ToDoFormPanel.swift
    ToDoTextFieldRow.swift
    ToDoLocationSearchField.swift
    ToDoCreatedByRow.swift
    ToDoDueDatePicker.swift
    ToDoRecurringPicker.swift
    ToDoToggleRow.swift
    ToDoCheckboxRow.swift
    ToDoFormRowHeader.swift

LevyHome/ViewModels/ToDo/
  ToDoViewModel.swift
  ToDoFamilyCalendarViewModel.swift
  ToDoPersonalRemindersViewModel.swift
  ToDoLocationSearchViewModel.swift

LevyHome/Services/EventKit/
  FamilyCalendarService.swift
  PersonalRemindersService.swift

LevyHome/Models/ToDo/
  ToDoTask.swift
  ToDoTaskSection.swift
  ToDoDraft.swift
  ToDoEditorMode.swift
  ToDoStatus.swift
  ToDoRecurring.swift
  ToDoDueDateOption.swift
  ToDoTone.swift
  ToDoCalendarEvent.swift
  ToDoReminder.swift
  ToDoFamilyCalendarState.swift
  ToDoPersonalRemindersState.swift
  ToDoLocationSearchSuggestion.swift

LevyHome/PreviewSupport/ToDo/
  ToDoPreviewData.swift
```

### Implementation Steps

1. Extract pure models first.
   - Move `ToDoTaskSection`, `ToDoTask`, `ToDoDraft`, `ToDoEditorMode`, `ToDoStatus`, `ToDoRecurring`, `ToDoDueDateOption`, `ToDoTone`, `ToDoCalendarEvent`, `ToDoReminder`, and state enums.
   - Keep names unchanged.
   - Change `private` to internal where needed.
   - Run tests.

2. Extract EventKit services.
   - Move `FamilyCalendarService` and `PersonalRemindersService`.
   - Keep EventKit imports in service files, not in `ToDoView.swift`, unless the view still directly uses EventKit types.
   - Add protocols only if needed for tests or preview injection.
   - Run tests.

3. Extract view models.
   - Move `ToDoViewModel`, `ToDoFamilyCalendarViewModel`, `ToDoPersonalRemindersViewModel`, and `ToDoLocationSearchViewModel`.
   - Confirm `@MainActor` boundaries are explicit where async UI state is mutated.
   - Add or expand unit tests for loading, cancellation handling, empty states, and completion toggles.
   - Run tests.

4. Extract Family Calendar UI.
   - Move `ToDoCalendarPanel`, event row, detail sheet, and detail row.
   - Preserve the new behavior:
     - Count badge shows events today.
     - Zero events does not render the bulky "Nothing found" empty-state body.
     - Calendar permission is requested only from the To Do page load path.
   - Run tests and perform a simulator smoke check if practical.

5. Extract Personal Reminders UI.
   - Move reminders panel, row, metadata row, and detail sheet.
   - Preserve permission sequencing with Family Calendar before Reminders.
   - Preserve zero-reminders compact state.
   - Run tests.

6. Extract shared to-do list UI.
   - Move task section, task row, avatar/assignee stack, location row, and status/due badges.
   - Keep row actions injected as closures.
   - Run tests.

7. Extract editor UI.
   - Move editor sheet and form controls.
   - Keep `ToDoDraft` as the single handoff object back to `ToDoViewModel`.
   - Consider adding focused tests for draft-to-request mapping if not already covered.
   - Run tests.

8. Extract preview data.
   - Move `ToDoPreviewData` to `PreviewSupport/ToDo`.
   - Ensure previews still compile.

### Exit Criteria

- `ToDoView.swift` is reduced to page composition and orchestration.
- EventKit service code no longer lives in the view file.
- To Do feature files build cleanly.
- Full test suite passes.

### Stage 2A Results

Completed on 2026-07-05 as the first To Do feature extraction after the Stage 1 project-file proof.

#### Moved Files

Moved To Do data/state declarations into feature model files:

```text
LevyHome/Models/ToDo/ToDoModels.swift
LevyHome/Models/ToDo/ToDoEventKitModels.swift
```

Moved To Do sample/fallback data into preview support:

```text
LevyHome/PreviewSupport/ToDo/ToDoPreviewData.swift
```

The move included:

- `ToDoTaskSection`
- `ToDoTask`
- `ToDoDraft`
- `ToDoEditorMode`
- `ToDoStatus`
- `ToDoRecurring`
- `ToDoDueDateOption`
- `ToDoTone`
- `ToDoLocationSearchSuggestion`
- `ToDoLocation` display helpers
- `FamilyCalendarLoadResult`
- `ToDoFamilyCalendarState`
- `PersonalRemindersLoadResult`
- `ToDoPersonalRemindersState`
- `ToDoReminder`
- `ToDoCalendarEvent`
- `ToDoPreviewData`

`ToDoDraft` no longer depends directly on `ToDoPreviewData`; both now share `ToDoDateDefaults` so production model defaults and preview data keep the same date behavior without coupling the model to preview fixtures.

#### Xcode Project Wiring

Updated `LevyHome.xcodeproj/project.pbxproj` manually with:

- a `Models/ToDo` group containing `ToDoModels.swift` and `ToDoEventKitModels.swift`
- a `PreviewSupport/ToDo` group containing `ToDoPreviewData.swift`
- app-target source entries for all three new files

The test build output confirmed Xcode compiled:

```text
LevyHome/Models/ToDo/ToDoModels.swift
LevyHome/Models/ToDo/ToDoEventKitModels.swift
LevyHome/PreviewSupport/ToDo/ToDoPreviewData.swift
```

#### Line-Count Impact

After Stage 2A:

```text
2649 LevyHome/Views/ToDo/ToDoView.swift
 271 LevyHome/Models/ToDo/ToDoModels.swift
 439 LevyHome/Models/ToDo/ToDoEventKitModels.swift
 197 LevyHome/PreviewSupport/ToDo/ToDoPreviewData.swift
3556 total
```

For comparison:

- Stage 0 baseline `ToDoView.swift`: 3,633 lines
- After Stage 1 `ToDoView.swift`: 3,544 lines
- After Stage 2A `ToDoView.swift`: 2,649 lines

#### Verification

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

Full test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

Simulator/system logs appeared during the run, including Network framework messages and the duplicate `UIAccessibilityLoaderWebShared` warning. They did not fail the test run.

#### Remaining Stage 2 Work After Stage 2A

Stage 2B should move the EventKit services and To Do view models next. `ToDoView.swift` still contains `FamilyCalendarService`, `PersonalRemindersService`, `ToDoViewModel`, `ToDoFamilyCalendarViewModel`, `ToDoPersonalRemindersViewModel`, `ToDoLocationSearchViewModel`, and the screen UI components.

### Stage 2B Results

Completed on 2026-07-05 as the service/view-model extraction for the To Do feature.

#### Moved Files

Moved To Do API and location-search view models into:

```text
LevyHome/ViewModels/ToDo/ToDoViewModel.swift
LevyHome/ViewModels/ToDo/ToDoLocationSearchViewModel.swift
```

Moved EventKit-backed view models into:

```text
LevyHome/ViewModels/ToDo/ToDoFamilyCalendarViewModel.swift
LevyHome/ViewModels/ToDo/ToDoPersonalRemindersViewModel.swift
```

Moved EventKit services into:

```text
LevyHome/Services/EventKit/FamilyCalendarService.swift
LevyHome/Services/EventKit/PersonalRemindersService.swift
```

The move included:

- `ToDoViewModel`
- `ToDoLocationSearchViewModel`
- `FamilyCalendarService`
- `PersonalRemindersService`
- `PersonalRemindersServiceError`
- `ToDoFamilyCalendarViewModel`
- `ToDoPersonalRemindersViewModel`

Access-control changes were limited to what cross-file references required. For example, moved view models and services are now internal app-target types, while implementation-only helpers such as `PersonalRemindersServiceError` remain private to their file.

#### Xcode Project Wiring

Updated `LevyHome.xcodeproj/project.pbxproj` manually with:

- a `Services/EventKit` group containing `FamilyCalendarService.swift` and `PersonalRemindersService.swift`
- a `ViewModels/ToDo` group containing the four To Do view model files
- app-target source entries for all six new files

The test build output confirmed Xcode compiled:

```text
LevyHome/Services/EventKit/FamilyCalendarService.swift
LevyHome/Services/EventKit/PersonalRemindersService.swift
LevyHome/ViewModels/ToDo/ToDoViewModel.swift
LevyHome/ViewModels/ToDo/ToDoLocationSearchViewModel.swift
LevyHome/ViewModels/ToDo/ToDoFamilyCalendarViewModel.swift
LevyHome/ViewModels/ToDo/ToDoPersonalRemindersViewModel.swift
```

#### Line-Count Impact

After Stage 2B:

```text
1938 LevyHome/Views/ToDo/ToDoView.swift
 276 LevyHome/ViewModels/ToDo/ToDoViewModel.swift
  96 LevyHome/ViewModels/ToDo/ToDoFamilyCalendarViewModel.swift
  96 LevyHome/ViewModels/ToDo/ToDoLocationSearchViewModel.swift
  93 LevyHome/ViewModels/ToDo/ToDoPersonalRemindersViewModel.swift
  75 LevyHome/Services/EventKit/FamilyCalendarService.swift
  89 LevyHome/Services/EventKit/PersonalRemindersService.swift
```

For comparison:

- Stage 0 baseline `ToDoView.swift`: 3,633 lines
- After Stage 1 `ToDoView.swift`: 3,544 lines
- After Stage 2A `ToDoView.swift`: 2,649 lines
- After Stage 2B `ToDoView.swift`: 1,938 lines

#### Verification

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

The first full test run compiled the moved files but hit one unrelated timing-style failure in `QuickActionsViewModelTests.testDuplicateTapsAreIgnoredWhileActionIsInProgress`. The isolated rerun of that test passed, and a subsequent full-suite rerun passed.

Full test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Final result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

Simulator/system logs appeared during the runs, including Network framework messages, WeatherKit auth-service messages, and the duplicate `UIAccessibilityLoaderWebShared` warning. They did not fail the final test run.

### Stage 2C Results

Completed on 2026-07-05 as the Family Calendar and Personal Reminders UI extraction.

#### Moved Files

Moved the Family Calendar card, event row, event detail sheet, and detail row into:

```text
LevyHome/Views/ToDo/Components/ToDoCalendarPanel.swift
```

Moved the Personal Reminders card, reminder row, metadata row, and reminder detail sheet into:

```text
LevyHome/Views/ToDo/Components/ToDoRemindersPanel.swift
```

The move preserved the current To Do page behavior:

- the Family Calendar badge still shows today's event count
- synced zero-event and zero-reminder states remain compact
- calendar and reminder retry/completion/select actions are still injected from `ToDoView`
- the existing EventKit permission/load orchestration remains in `ToDoView`

Access-control changes were limited to shared To Do UI primitives that the extracted files now reference:

- `ToDoStatusPill`
- `ToDoInlineBadge`
- `ToDoIconBadge`
- `ToDoLocationRow`
- `ToDoFormPanel`

#### Xcode Project Wiring

Updated `LevyHome.xcodeproj/project.pbxproj` manually with:

- `ToDoCalendarPanel.swift` and `ToDoRemindersPanel.swift` in the existing To Do `Components` group
- app-target source entries for both new files

The test build output confirmed Xcode compiled:

```text
LevyHome/Views/ToDo/Components/ToDoCalendarPanel.swift
LevyHome/Views/ToDo/Components/ToDoRemindersPanel.swift
```

#### Line-Count Impact

After Stage 2C:

```text
1361 LevyHome/Views/ToDo/ToDoView.swift
 298 LevyHome/Views/ToDo/Components/ToDoCalendarPanel.swift
 281 LevyHome/Views/ToDo/Components/ToDoRemindersPanel.swift
  90 LevyHome/Views/ToDo/Components/FlowLayout.swift
```

For comparison:

- Stage 0 baseline `ToDoView.swift`: 3,633 lines
- After Stage 1 `ToDoView.swift`: 3,544 lines
- After Stage 2A `ToDoView.swift`: 2,649 lines
- After Stage 2B `ToDoView.swift`: 1,938 lines
- After Stage 2C `ToDoView.swift`: 1,361 lines

#### Verification

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

Full test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Final result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

Simulator/system logs appeared during the run, including Network framework messages, WeatherKit auth-service messages, CoreAnimation launch metric messages, and the duplicate `UIAccessibilityLoaderWebShared` warning. They did not fail the test run.

### Stage 2D Results

Completed on 2026-07-05 as the shared to-do list UI and primitive extraction.

#### Moved Files

Moved the shared task-list section and swipe row into:

```text
LevyHome/Views/ToDo/Components/ToDoTaskListView.swift
```

Moved shared To Do visual primitives into:

```text
LevyHome/Views/ToDo/Components/ToDoSharedComponents.swift
```

The move included:

- `ToDoTaskSectionView`
- `ToDoTaskRow`
- `ToDoAvatarStack`
- `ToDoAssigneeStack`
- `ToDoStatusPill`
- `ToDoInlineBadge`
- `ToDoDueBadge`
- `ToDoIconBadge`
- `ToDoLocationRow`

The task row remains closure-driven for complete, edit, and delete behavior. `ToDoTaskRow` is private to the task-list component file; shared primitives remain internal because the summary card, editor sheet, calendar panel, reminders panel, and task-list row all reuse them.

#### Xcode Project Wiring

Updated `LevyHome.xcodeproj/project.pbxproj` manually with:

- `ToDoTaskListView.swift` and `ToDoSharedComponents.swift` in the existing To Do `Components` group
- app-target source entries for both new files

The test build output confirmed Xcode compiled:

```text
LevyHome/Views/ToDo/Components/ToDoSharedComponents.swift
LevyHome/Views/ToDo/Components/ToDoTaskListView.swift
```

#### Line-Count Impact

After Stage 2D:

```text
1097 LevyHome/Views/ToDo/ToDoView.swift
 136 LevyHome/Views/ToDo/Components/ToDoSharedComponents.swift
 130 LevyHome/Views/ToDo/Components/ToDoTaskListView.swift
 298 LevyHome/Views/ToDo/Components/ToDoCalendarPanel.swift
 281 LevyHome/Views/ToDo/Components/ToDoRemindersPanel.swift
  90 LevyHome/Views/ToDo/Components/FlowLayout.swift
```

For comparison:

- Stage 0 baseline `ToDoView.swift`: 3,633 lines
- After Stage 1 `ToDoView.swift`: 3,544 lines
- After Stage 2A `ToDoView.swift`: 2,649 lines
- After Stage 2B `ToDoView.swift`: 1,938 lines
- After Stage 2C `ToDoView.swift`: 1,361 lines
- After Stage 2D `ToDoView.swift`: 1,097 lines

#### Verification

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

Full test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Final result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

Simulator/system logs appeared during the run, including Network framework messages and the duplicate `UIAccessibilityLoaderWebShared` warning. They did not fail the test run.

#### Remaining Stage 2 Work After Stage 2D

Stage 2E should move the editor sheet and form controls next: `ToDoEditorSheet`, `ToDoFormPanel`, text/location search fields, created-by row, due-date picker, recurring picker, checkbox row, and form row header. `ToDoView.swift` still contains screen-level orchestration, summary/error views, the editor sheet, and editor form controls.

## Stage 3: Shopping Feature Refactor

### Why Second

`ShoppingListView.swift` formerly `ShoppingListMockupView.swift` is almost as large as `ToDoView.swift` and contains a full live data surface, editor, filters, product search, display models, and helper extensions.

### Proposed File Split

```text
LevyHome/Views/Shopping/
  ShoppingListView.swift
  ShoppingListContentView.swift
  Components/
    ShoppingLiveStatusBadge.swift
    ShoppingListSummaryCard.swift
    ShoppingViewerAvatarStack.swift
    ShoppingCategoryFilterBar.swift
    ShoppingCategorySection.swift
    ShoppingItemRow.swift
    ShoppingStoreListingSummaryRow.swift
    RowQuantityBadge.swift
  Filters/
    ShoppingListSearchField.swift
    ShoppingListFilterSheet.swift
    ShoppingFilterAccordionSection.swift
    ShoppingFilterOptionRow.swift
  Editor/
    ShoppingItemEditorSheet.swift
    ShoppingFormSection.swift
    ShoppingChoiceChip.swift
    ShoppingManualStoreDetailsDisclosure.swift
    ShoppingManualStoreDetailsEditor.swift
  ProductSearch/
    ShoppingProductSearchSheet.swift
    ShoppingProductResultRow.swift

LevyHome/ViewModels/Shopping/
  ShoppingListViewModel.swift

LevyHome/Models/Shopping/
  ShoppingItemEditorMode.swift
  ShoppingItemDraft.swift
  ShoppingDuplicateStatus.swift
  ShoppingListFilters.swift
  ShoppingStoreFilterOption.swift
  ShoppingCategoryGroup.swift
  ShoppingListDisplayItem.swift
  ShoppingLiveStatusBadge.swift

LevyHome/PreviewSupport/Shopping/
  ShoppingPreviewData.swift
```

### Implementation Steps

1. Rename the entry view if desired.
   - `ShoppingListMockupView` no longer appears to be merely a mockup.
   - Recommended path: introduce `ShoppingListView` and keep `typealias ShoppingListMockupView = ShoppingListView` temporarily, or update call sites in one small commit.
   - Verify `RootTabView` still points to the correct view.

2. Extract `ShoppingListViewModel`.
   - This is the highest-value move because it already has tests.
   - Preserve its dependency injection closures and live service handling.
   - Keep live update task cancellation behavior unchanged.
   - Run `ShoppingListViewModelTests` and full tests.

3. Extract editor domain models and draft mapping.
   - Move `ShoppingItemDraft`, `ShoppingItemEditorMode`, and duplicate-status logic.
   - Add tests for draft validation and request mapping if missing.

4. Extract filter models and UI.
   - Move `ShoppingListFilters`, `ShoppingStoreFilterOption`, search field, filter sheet, accordion section, and filter rows.
   - Keep filtering logic close to display models or the view model, not embedded deeply in view bodies.

5. Extract item display models.
   - Move `ShoppingCategoryGroup` and `ShoppingListDisplayItem`.
   - Move helper extensions currently at the bottom of the file into either model files or formatting helper files.

6. Extract product search UI.
   - Move product search sheet and result rows.
   - Keep Kroger-specific response models in API/model files unless they are purely display transforms.

7. Extract remaining row/card components.
   - Move summary card, category filter bar, category section, item row, listing summary row, and badges.

### Exit Criteria

- Shopping view file is page composition only.
- View model remains testable and still covered.
- The word `Mockup` is removed from the user-facing architecture if practical.
- Full test suite passes.

### Stage 3A Results

Completed on 2026-07-05 as the Shopping entry-view rename.

#### Renamed Entry View

Renamed the production-backed shopping entry view from:

```text
LevyHome/Views/Shopping/ShoppingListMockupView.swift
```

to:

```text
LevyHome/Views/Shopping/ShoppingListView.swift
```

The root view type is now:

```swift
struct ShoppingListView: View
```

To keep this low-risk while follow-on extraction continues, the file temporarily preserves:

```swift
typealias ShoppingListMockupView = ShoppingListView
```

#### Root Tab Wiring

Updated `RootTabView` so the List tab now instantiates `ShoppingListView()` directly.

#### Xcode Project Wiring

Updated `LevyHome.xcodeproj/project.pbxproj` so the existing Shopping source reference now points at `ShoppingListView.swift`.

The test build output confirmed Xcode removed stale `ShoppingListMockupView` build objects and compiled the renamed shopping file successfully.

#### Line-Count Impact

After Stage 3A:

```text
3529 LevyHome/Views/Shopping/ShoppingListView.swift
```

The file is two lines larger than the Stage 0 baseline because the temporary compatibility typealias was added.

#### Verification

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

Full test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Final result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

#### Remaining Stage 3 Work After Stage 3A

At the end of Stage 3A, the next step was to extract `ShoppingListViewModel` into `LevyHome/ViewModels/Shopping/ShoppingListViewModel.swift`, preserving dependency injection closures, live-service handling, live update task cancellation, and existing `ShoppingListViewModelTests` coverage.

### Stage 3B Results

Completed on 2026-07-05 as the Shopping view-model extraction.

#### Extracted View Model

Moved the production shopping view model from:

```text
LevyHome/Views/Shopping/ShoppingListView.swift
```

to:

```text
LevyHome/ViewModels/Shopping/ShoppingListViewModel.swift
```

The extracted file now owns:

- `ShoppingListViewModel`
- `ShoppingLiveStatusBadge`
- the shared `ResidentIdentity.shoppingListViewerId` helper used by shopping viewer identity and live presence display names

The move preserved the existing dependency injection closures, API-client convenience initializer, live-service connection handling, live message handling, task cancellation, and cancellation-aware refresh behavior.

#### Access-Control Adjustments

`ShoppingItemDraft` remains in `ShoppingListView.swift` for Stage 3C, but it is now module-internal instead of `fileprivate` so the extracted view model can accept drafts and build the existing create/update/add-back requests.

The view-model draft bridge methods are now module-internal instead of `fileprivate`:

```swift
func createItem(from draft: ShoppingItemDraft) async throws
func updateItem(id itemId: Int, with draft: ShoppingItemDraft) async throws
func addBackToNeeded(_ item: ShoppingListItem, from draft: ShoppingItemDraft) async throws
```

The lower-level request updater remains private inside `ShoppingListViewModel`.

#### Xcode Project Wiring

Updated `LevyHome.xcodeproj/project.pbxproj` with:

- a `ViewModels/Shopping` group
- a `ShoppingListViewModel.swift` file reference
- a `ShoppingListViewModel.swift in Sources` build entry for the `LevyHome` app target

#### Line-Count Impact

After Stage 3B:

```text
2933 LevyHome/Views/Shopping/ShoppingListView.swift
 600 LevyHome/ViewModels/Shopping/ShoppingListViewModel.swift
```

This removes about 600 lines from the Shopping SwiftUI file while keeping the editor, filter, row, and display-model declarations in place for later Stage 3 work.

#### Verification

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

Targeted shopping view-model test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:LevyHomeTests/ShoppingListViewModelTests
```

Final result:

```text
** TEST SUCCEEDED **
Executed 1 test, with 0 failures (0 unexpected).
```

Full test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Final result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

#### Remaining Stage 3 Work After Stage 3B

Stage 3C should extract the editor domain and draft-mapping declarations from `ShoppingListView.swift`, especially `ShoppingItemDraft`, `ShoppingItemEditorMode`, `ShoppingDuplicateStatus`, and `normalizedShoppingItemName`, then add or preserve focused draft/request-mapping tests.

## Stage 4: Home Feature Refactor

### Why Third

`HomeView.swift` is smaller than To Do and Shopping but still mixes page orchestration, weather UI, blueprint drawing, shortcut UI, recent activity UI, policy logic, colors, and previews.

### Proposed File Split

```text
LevyHome/Views/Home/
  HomeView.swift
  HomeContentView.swift
  HomeHeaderView.swift
  HomeSearchRow.swift
  Weather/
    HomeWeatherSummaryCard.swift
    HomeWeatherExpandedCard.swift
    HomeWeatherTemperatureChart.swift
    HomeWeatherChartPlot.swift
    HomeWeatherChartXAxis.swift
    HomeWeatherPrecipitationRow.swift
    HomeWeatherTomorrowSection.swift
    HomeWeatherMetricView.swift
    HomeWeatherMetricDivider.swift
    WeatherPanelToggleButton.swift
  Blueprint/
    HomeBlueprintView.swift
    BlueprintNodePositions.swift
    BlueprintNodeView.swift
    CenterHomeNode.swift
    FloorPlanLines.swift
    ConnectorLines.swift
    BlueprintDecorations.swift
  Shortcuts/
    AutomationShortcutStrip.swift
    ShortcutButton.swift
    AutomationShortcut.swift
    ShortcutTone.swift
  Activity/
    RecentActivityRibbon.swift
    ActivityRibbonRow.swift
    InlineStatusView.swift

LevyHome/Models/Home/
  GarageCompletionWatchPolicy.swift
  HomePalette.swift
```

### Implementation Steps

1. Move policy and helper types first.
   - `GarageCompletionWatchPolicy` already has tests and should not live inside a view file.
   - Keep `GarageCompletionWatchPolicyTests` passing.

2. Extract weather UI.
   - Weather cards and chart components are a natural subfeature.
   - Keep `HomeWeatherViewModel` unchanged during the first move.

3. Extract blueprint UI.
   - Move shapes and node views together.
   - Avoid changing drawing math during the move.

4. Extract shortcuts and recent activity UI.
   - Keep action closures injected.
   - Preserve the current quick-action completion watcher behavior.

5. Decide whether `HomePalette` belongs in feature-local styling or global theme.
   - If only Home uses it, keep it feature-local.
   - If other screens start using it, promote pieces into `Theme`.

### Exit Criteria

- `HomeView.swift` contains the entry view and top-level composition.
- Weather, blueprint, shortcuts, and recent activity are separately readable.
- Existing Home and Quick Actions tests pass.

### Stage 4 Results

Completed on 2026-07-05 as the Home feature extraction.

#### Extracted Home Composition

`HomeView.swift` now contains the app-environment entry wrapper plus the existing preview harness. The screen orchestration moved to:

```text
LevyHome/Views/Home/HomeContentView.swift
```

This preserved the existing load, pull-to-refresh, tab-visit weather refresh, app-foreground weather refresh, confirmation dialog, garage toggle, and quick-action completion watcher behavior.

#### Extracted Models And Styling

Moved Home-specific model and styling helpers into:

```text
LevyHome/Models/Home/GarageCompletionWatchPolicy.swift
LevyHome/Models/Home/HomePalette.swift
```

`GarageCompletionWatchPolicy` and the garage-state helper extension now live outside SwiftUI view files while preserving the tested open/close polling policy.

#### Extracted Home UI Components

Moved top-level Home components into:

```text
LevyHome/Views/Home/HomeHeaderView.swift
LevyHome/Views/Home/HomeSearchRow.swift
LevyHome/Views/Home/HomeCapsuleButtonStyle.swift
```

Moved weather UI into:

```text
LevyHome/Views/Home/Weather/HomeWeatherSummaryCard.swift
LevyHome/Views/Home/Weather/HomeWeatherExpandedCard.swift
LevyHome/Views/Home/Weather/WeatherPanelToggleButton.swift
LevyHome/Views/Home/Weather/HomeWeatherTemperatureChart.swift
LevyHome/Views/Home/Weather/HomeWeatherPrecipitationRow.swift
LevyHome/Views/Home/Weather/HomeWeatherTomorrowSection.swift
```

`HomeWeatherChartPlot` and `HomeWeatherChartXAxis` are kept private inside `HomeWeatherTemperatureChart.swift`. `HomeWeatherMetricView` and `HomeWeatherMetricDivider` are kept private inside `HomeWeatherTomorrowSection.swift`.

Moved blueprint UI into:

```text
LevyHome/Views/Home/Blueprint/HomeBlueprintView.swift
```

The blueprint node, connector, floor-plan, center-node, and decoration helpers are kept private in that file so the drawing math stays together.

Moved shortcut UI into:

```text
LevyHome/Views/Home/Shortcuts/AutomationShortcut.swift
LevyHome/Views/Home/Shortcuts/AutomationShortcutStrip.swift
LevyHome/Views/Home/Shortcuts/ShortcutButton.swift
```

Moved recent activity/status UI into:

```text
LevyHome/Views/Home/Activity/RecentActivityRibbon.swift
LevyHome/Views/Home/Activity/ActivityRibbonRow.swift
LevyHome/Views/Home/Activity/InlineStatusView.swift
```

#### Xcode Project Wiring

Updated `LevyHome.xcodeproj/project.pbxproj` with:

- a `Models/Home` group
- `Views/Home/Weather`, `Views/Home/Blueprint`, `Views/Home/Shortcuts`, and `Views/Home/Activity` groups
- source-build entries for every extracted Home file in the `LevyHome` app target

#### Test Stabilization

While validating the full suite, `QuickActionsViewModelTests.testDuplicateTapsAreIgnoredWhileActionIsInProgress` exposed an existing race: it waited for `isPerforming`, but the mock service request array could still be empty because the first task had not yet entered `service.perform`.

The test now waits for the mock perform call to start before asserting the duplicate-tap behavior. No production Quick Actions behavior changed.

#### Line-Count Impact

Before Stage 4:

```text
1853 LevyHome/Views/Home/HomeView.swift
```

After Stage 4:

```text
 398 LevyHome/Views/Home/HomeContentView.swift
 380 LevyHome/Views/Home/Blueprint/HomeBlueprintView.swift
 139 LevyHome/Views/Home/Weather/HomeWeatherSummaryCard.swift
 128 LevyHome/Views/Home/Weather/HomeWeatherTemperatureChart.swift
 123 LevyHome/Views/Home/HomeView.swift
  81 LevyHome/Models/Home/HomePalette.swift
  77 LevyHome/Views/Home/Weather/HomeWeatherExpandedCard.swift
  60 LevyHome/Views/Home/Activity/RecentActivityRibbon.swift
  57 LevyHome/Views/Home/Shortcuts/ShortcutButton.swift
  56 LevyHome/Views/Home/HomeHeaderView.swift
  55 LevyHome/Views/Home/Shortcuts/AutomationShortcutStrip.swift
  55 LevyHome/Models/Home/GarageCompletionWatchPolicy.swift
  52 LevyHome/Views/Home/Weather/HomeWeatherTomorrowSection.swift
  43 LevyHome/Views/Home/Activity/ActivityRibbonRow.swift
  41 LevyHome/Views/Home/HomeSearchRow.swift
  31 LevyHome/Views/Home/Shortcuts/AutomationShortcut.swift
  31 LevyHome/Views/Home/Activity/InlineStatusView.swift
  27 LevyHome/Views/Home/Weather/HomeWeatherPrecipitationRow.swift
  23 LevyHome/Views/Home/Weather/WeatherPanelToggleButton.swift
  15 LevyHome/Views/Home/HomeCapsuleButtonStyle.swift
```

#### Verification

Project file lint:

```bash
plutil -lint LevyHome.xcodeproj/project.pbxproj
```

Result:

```text
LevyHome.xcodeproj/project.pbxproj: OK
```

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

Focused Home and Quick Actions test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:LevyHomeTests/GarageCompletionWatchPolicyTests -only-testing:LevyHomeTests/HomeOverviewViewModelTests -only-testing:LevyHomeTests/HomeWeatherViewModelTests -only-testing:LevyHomeTests/QuickActionsViewModelTests
```

Final result:

```text
** TEST SUCCEEDED **
Executed 34 tests, with 0 failures (0 unexpected).
```

Full test command:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Final result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

## Stage 5: Services Refactor

### Objective

Split service files where the current file contains multiple providers or multiple protocol/model responsibilities.

### Targets

#### `HomeWeatherService.swift`

Current responsibilities:

- `HomeWeatherServicing`
- location provider
- service orchestration
- WeatherKit provider
- Open-Meteo provider
- National Weather Service provider
- provider DTOs
- parsing helpers
- weather-code mapping

Proposed split:

```text
LevyHome/Services/Weather/
  HomeWeatherService.swift
  HomeWeatherServicing.swift
  HomeLocationProvider.swift
  WeatherKitHomeWeatherProvider.swift
  OpenMeteoHomeWeatherProvider.swift
  NationalWeatherServiceHomeWeatherProvider.swift
  WeatherProviderModels.swift
  OpenMeteoDateParser.swift
  OpenMeteoWeatherCode.swift
```

Steps:

1. Move protocols and simple provider abstractions.
2. Move each provider one at a time.
3. Move provider DTOs with the provider that owns them.
4. Keep `HomeWeatherViewModelTests` passing after each move.
5. Avoid changing fallback/cancellation behavior during the split.

#### `ShoppingListLiveService.swift`

Current responsibilities:

- live-service protocol
- viewer identity/presence models
- server message decoding
- client message encoding
- connection state
- WebSocket connection lifecycle

Proposed split:

```text
LevyHome/Services/Shopping/
  ShoppingListLiveServicing.swift
  ShoppingListLiveService.swift
  ShoppingListLiveMessages.swift
  ShoppingListViewerPresence.swift
  ShoppingListLiveConnectionState.swift
```

Steps:

1. Move message models first.
2. Move viewer identity/presence models.
3. Keep the actual WebSocket implementation in one service file.
4. Run shopping tests and simulator smoke test if possible.

#### `APIClient.swift`

Current responsibility:

- Cross-domain HTTP endpoints.

Potential direction:

```text
LevyHome/Services/API/
  APIClient.swift
  APIClient+Activity.swift
  APIClient+Home.swift
  APIClient+Shopping.swift
  APIClient+ToDo.swift
  APIClient+Notifications.swift
```

Steps:

1. Split by extension files only after feature views/view models are extracted.
2. Keep a single `APIClient` type to avoid churn.
3. Move endpoint methods into domain extension files.
4. Keep `APIClientTests` passing after every endpoint-group move.

### Exit Criteria

- Each service file has a clear integration boundary.
- Tests still cover provider fallback, request encoding, response decoding, and cancellation behavior.

### Stage 5 Results

Completed on 2026-07-05.

#### Service Splits

`LevyHome/Services/HomeWeatherService.swift` was split into:

```text
LevyHome/Services/Weather/HomeWeatherServicing.swift
LevyHome/Services/Weather/HomeLocationProvider.swift
LevyHome/Services/Weather/HomeWeatherService.swift
LevyHome/Services/Weather/WeatherKitHomeWeatherProvider.swift
LevyHome/Services/Weather/OpenMeteoHomeWeatherProvider.swift
LevyHome/Services/Weather/NationalWeatherServiceHomeWeatherProvider.swift
LevyHome/Services/Weather/OpenMeteoDateParser.swift
LevyHome/Services/Weather/OpenMeteoWeatherCode.swift
LevyHome/Services/Weather/WeatherProviderModels.swift
```

Notes:

- Weather orchestration remains in `HomeWeatherService`.
- WeatherKit, Open-Meteo, and National Weather Service integrations now live in provider-specific files.
- Open-Meteo parsing/code mapping helpers moved into focused helper files.
- Provider fallback and cancellation behavior was preserved.

`LevyHome/Services/ShoppingListLiveService.swift` was split into:

```text
LevyHome/Services/Shopping/ShoppingListLiveServicing.swift
LevyHome/Services/Shopping/ShoppingListViewerPresence.swift
LevyHome/Services/Shopping/ShoppingListLiveMessages.swift
LevyHome/Services/Shopping/ShoppingListLiveConnectionState.swift
LevyHome/Services/Shopping/ShoppingListLiveService.swift
```

Notes:

- WebSocket lifecycle code remains in `ShoppingListLiveService`.
- Protocol, presence models, messages, and connection state are now separate declarations.

`LevyHome/Services/APIClient.swift` was split into:

```text
LevyHome/Services/API/APIClient.swift
LevyHome/Services/API/APIClient+Activity.swift
LevyHome/Services/API/APIClient+Home.swift
LevyHome/Services/API/APIClient+Shopping.swift
LevyHome/Services/API/APIClient+ToDo.swift
LevyHome/Services/API/APIClient+Notifications.swift
LevyHome/Services/API/APIClient+System.swift
```

Notes:

- The app still uses one `APIClient` type.
- The shared request sender remains in `APIClient.swift`.
- Endpoint methods moved into domain extension files.
- `DeviceRegistrationServicing` moved alongside notification/device registration endpoints.

#### File-Size Snapshot

Command:

```bash
wc -l LevyHome/Services/API/*.swift LevyHome/Services/Shopping/*.swift LevyHome/Services/Weather/*.swift
```

Result:

```text
      21 LevyHome/Services/API/APIClient+Activity.swift
      15 LevyHome/Services/API/APIClient+Home.swift
      35 LevyHome/Services/API/APIClient+Notifications.swift
      66 LevyHome/Services/API/APIClient+Shopping.swift
       9 LevyHome/Services/API/APIClient+System.swift
      47 LevyHome/Services/API/APIClient+ToDo.swift
     243 LevyHome/Services/API/APIClient.swift
      10 LevyHome/Services/Shopping/ShoppingListLiveConnectionState.swift
     151 LevyHome/Services/Shopping/ShoppingListLiveMessages.swift
     445 LevyHome/Services/Shopping/ShoppingListLiveService.swift
       5 LevyHome/Services/Shopping/ShoppingListLiveServicing.swift
      23 LevyHome/Services/Shopping/ShoppingListViewerPresence.swift
      23 LevyHome/Services/Weather/HomeLocationProvider.swift
     243 LevyHome/Services/Weather/HomeWeatherService.swift
      13 LevyHome/Services/Weather/HomeWeatherServicing.swift
     291 LevyHome/Services/Weather/NationalWeatherServiceHomeWeatherProvider.swift
      26 LevyHome/Services/Weather/OpenMeteoDateParser.swift
     208 LevyHome/Services/Weather/OpenMeteoHomeWeatherProvider.swift
      82 LevyHome/Services/Weather/OpenMeteoWeatherCode.swift
      51 LevyHome/Services/Weather/WeatherKitHomeWeatherProvider.swift
       9 LevyHome/Services/Weather/WeatherProviderModels.swift
    2016 total
```

#### Verification

Project file lint:

```bash
plutil -lint LevyHome.xcodeproj/project.pbxproj
```

Result:

```text
LevyHome.xcodeproj/project.pbxproj: OK
```

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

Focused tests:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LevyHomeTests/HomeWeatherViewModelTests
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LevyHomeTests/ShoppingListViewModelTests
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LevyHomeTests/APIClientTests
```

Results:

```text
HomeWeatherViewModelTests: ** TEST SUCCEEDED **, 16 tests, 0 failures.
ShoppingListViewModelTests: ** TEST SUCCEEDED **, 1 test, 0 failures.
APIClientTests: ** TEST SUCCEEDED **, 8 tests, 0 failures.
```

Full test suite:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

## Stage 6: Models And API DTO Refactor

### Objective

Reduce broad model files without breaking API decoding or request encoding.

### Targets

#### `APIResponses.swift`

This file contains DTOs for activity/events, home overview, quick actions, users, to-dos, shopping, notifications, and health.

Proposed split:

```text
LevyHome/Models/API/
  EventsAPIResponses.swift
  HomeAPIResponses.swift
  QuickActionAPIResponses.swift
  UserAPIResponses.swift
  ToDoAPIResponses.swift
  ShoppingAPIResponses.swift
  NotificationAPIResponses.swift
  HealthAPIResponses.swift
  JSONValue.swift
```

#### `APIRequests.swift`

Proposed split:

```text
LevyHome/Models/API/
  ToDoAPIRequests.swift
  ShoppingAPIRequests.swift
  NotificationAPIRequests.swift
  DeviceAPIRequests.swift
```

### Implementation Steps

1. Move DTOs by domain with no field changes.
2. Keep type names exactly the same to avoid cascading edits.
3. Move `JSONValue` only once and keep all API models referencing it.
4. Run model decoding and API client tests after each domain move.
5. Only after the split, consider whether any DTOs should map into separate app-domain models.

### Exit Criteria

- API model files are domain-oriented.
- `ModelDecodingTests` and `APIModelDecodingTests` pass.
- No backend contract changes are made as part of this refactor.

### Stage 6 Results

Completed on 2026-07-05.

#### API Model Splits

`LevyHome/Models/APIResponses.swift` and `LevyHome/Models/APIRequests.swift` were removed and replaced with domain-oriented files under `LevyHome/Models/API/`:

```text
LevyHome/Models/API/DeviceAPIRequests.swift
LevyHome/Models/API/EventsAPIRequests.swift
LevyHome/Models/API/EventsAPIResponses.swift
LevyHome/Models/API/HealthAPIResponses.swift
LevyHome/Models/API/HomeAPIResponses.swift
LevyHome/Models/API/JSONValue.swift
LevyHome/Models/API/NotificationAPIRequests.swift
LevyHome/Models/API/NotificationAPIResponses.swift
LevyHome/Models/API/NullableAPIValue.swift
LevyHome/Models/API/QuickActionAPIRequests.swift
LevyHome/Models/API/QuickActionAPIResponses.swift
LevyHome/Models/API/ShoppingAPIRequests.swift
LevyHome/Models/API/ShoppingAPIResponses.swift
LevyHome/Models/API/ToDoAPIRequests.swift
LevyHome/Models/API/ToDoAPIResponses.swift
LevyHome/Models/API/UserAPIResponses.swift
```

Notes:

- Type names and field names were preserved.
- No backend contract changes were made.
- `CreateToDoLocationRequest` moved from the old response file into `ToDoAPIRequests.swift`.
- `JSONValue` now lives in its own file and remains shared by shopping/Kroger DTOs.
- `ShoppingListNullableValue` moved into `NullableAPIValue.swift` because it is shared by shopping and to-do update requests.
- Extra existing request DTOs not listed in the initial target sketch were kept in focused files: `EventsAPIRequests.swift` and `QuickActionAPIRequests.swift`.
- Device registration request enums live in `DeviceAPIRequests.swift`; device/test-push responses remain with notification responses because they describe push delivery surfaces.

#### File-Size Snapshot

Command:

```bash
wc -l LevyHome/Models/API/*.swift | sort -nr
```

Result:

```text
     883 total
     375 LevyHome/Models/API/ShoppingAPIResponses.swift
      85 LevyHome/Models/API/ShoppingAPIRequests.swift
      84 LevyHome/Models/API/ToDoAPIRequests.swift
      83 LevyHome/Models/API/ToDoAPIResponses.swift
      54 LevyHome/Models/API/NotificationAPIResponses.swift
      53 LevyHome/Models/API/JSONValue.swift
      33 LevyHome/Models/API/QuickActionAPIRequests.swift
      26 LevyHome/Models/API/DeviceAPIRequests.swift
      25 LevyHome/Models/API/UserAPIResponses.swift
      23 LevyHome/Models/API/NotificationAPIRequests.swift
      14 LevyHome/Models/API/NullableAPIValue.swift
      10 LevyHome/Models/API/QuickActionAPIResponses.swift
       7 LevyHome/Models/API/HealthAPIResponses.swift
       4 LevyHome/Models/API/HomeAPIResponses.swift
       4 LevyHome/Models/API/EventsAPIResponses.swift
       3 LevyHome/Models/API/EventsAPIRequests.swift
```

#### Verification

Project file lint:

```bash
plutil -lint LevyHome.xcodeproj/project.pbxproj
```

Result:

```text
LevyHome.xcodeproj/project.pbxproj: OK
```

Whitespace check:

```bash
git diff --check
```

Result: passed with no output.

Focused tests:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LevyHomeTests/APIModelDecodingTests -only-testing:LevyHomeTests/APIClientTests
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LevyHomeTests/ModelDecodingTests
```

Results:

```text
APIModelDecodingTests + APIClientTests: ** TEST SUCCEEDED **, 22 tests, 0 failures.
ModelDecodingTests: ** TEST SUCCEEDED **, 12 tests, 0 failures.
```

Full test suite:

```bash
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Result:

```text
** TEST SUCCEEDED **
Executed 103 tests, with 0 failures (0 unexpected).
```

## Stage 7: Shared UI And Theme Cleanup

### Objective

Reduce duplicate visual patterns and make feature extraction cleaner.

### Candidate Shared Components

Review repeated patterns across To Do, Shopping, Home, Preferences, and Activity:

- metric pill / status pill
- inline badges
- empty/error/loading panels
- avatar stacks
- row metadata lines
- form section panels
- toggle/check rows
- search fields
- sheet headers

### Implementation Steps

1. Do not generalize too early.
   - Extract a shared component only when two or more screens use the same behavior and visual shape.

2. Prefer small shared components over a large design framework.
   - Existing `Views/Shared` is a good home for proven reusable pieces.

3. Keep feature-specific wording in feature files.
   - Shared components should not know about "To Do", "Shopping", or "Garage".

4. Review theme usage.
   - If feature files define repeated local colors or spacing, move only stable app-wide values into `Theme`.

### Exit Criteria

- Shared components are genuinely shared.
- Feature files remain easy to understand without a maze of generic abstractions.

## Stage 8: Test Refactor And Coverage Expansion

### Objective

Ensure the refactor improves confidence rather than just moving code.

### Add Or Improve Tests For

1. To Do
   - shared list load success/error/cancellation
   - task create/update/delete request mapping
   - task completion toggle behavior
   - Family Calendar zero-event state
   - Family Calendar permission denied/restricted states
   - Reminders zero-reminder state
   - Reminders permission denied/restricted states
   - Reminders completion behavior through a testable protocol if possible

2. Shopping
   - filter combinations
   - duplicate detection
   - draft-to-request mapping
   - live snapshot replacement
   - live update insert/update/delete handling
   - live connection state labels

3. Home
   - garage completion watch policy already exists; keep it near the policy type
   - quick action watcher behavior
   - weather refresh-on-visit behavior
   - cancellation-safe refresh behavior

4. Services
   - EventKit services through protocols or wrappers if direct `EKEventStore` is too hard to fake
   - weather provider fallback and cancellation
   - API endpoint request construction

### Test Organization

Move tests toward domain folders over time:

```text
LevyHomeTests/
  API/
  Home/
  Shopping/
  ToDo/
  Weather/
  Notifications/
```

### Exit Criteria

- Existing tests continue to pass.
- New tests cover moved business logic.
- UI-only components stay lightweight and preview-backed.

## Stage 9: Preview And Fixture Cleanup

### Objective

Keep previews and sample data useful after files are split.

### Tasks

1. Move large preview data out of view files.
   - `ToDoPreviewData` should live in `PreviewSupport/ToDo`.
   - Shopping preview fixtures should live in `PreviewSupport/Shopping`.
   - Home preview service mocks should live in `PreviewSupport/Home` if reused.

2. Keep previews feature-local where they help.
   - A `ToDoCalendarPanel` preview can live beside that panel.
   - Shared fixture builders can live in `PreviewSupport`.

3. Avoid preview-only logic in production view models.
   - Prefer injected fixtures/services.

### Exit Criteria

- Major extracted views have previews where helpful.
- Preview fixtures are reusable and not buried in large screen files.

## Stage 10: Naming And Cleanup Pass

### Objective

Use the refactor to remove confusing names only after behavior is stable.

### Candidates

1. `ShoppingListMockupView`
   - Completed in Stage 3A: the file and root type are now `ShoppingListView`, and `RootTabView` uses `ShoppingListView()`.
   - A temporary `typealias ShoppingListMockupView = ShoppingListView` remains for compatibility and can be removed after the Shopping extraction is complete.

2. Domain state names
   - Keep names expressive and feature-scoped.
   - Avoid generic names like `State` outside a containing type.

3. Preview-only service names
   - Move preview service mocks to `PreviewSupport` and make names explicit.

4. File names
   - Match the main type in each file.

### Exit Criteria

- File names, type names, and folder names describe their actual role.
- Temporary aliases or compatibility shims are removed.

## Stage 11: Optional Compile-Time And Tooling Improvements

### Objective

After the structural refactor, consider lightweight tooling to keep the codebase from drifting back into giant files.

### Options

1. Add SwiftLint or a custom line-count script.
   - Start advisory only.
   - Suggested warning threshold: 500 lines.
   - Suggested investigation threshold: 1,000 lines.

2. Add a project-health script.
   - Report top Swift files by line count.
   - Report files with many top-level declarations.
   - Do not fail CI at first.

3. Track build time.
   - Very large SwiftUI body files can slow type checking.
   - After splitting, compare clean build times if compile speed is a concern.

### Exit Criteria

- Tooling helps maintainability without blocking normal development.

## Per-Stage Verification Checklist

Run this after each meaningful stage:

```bash
git diff --check
xcodebuild test -project LevyHome.xcodeproj -scheme LevyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

For UI-heavy stages, also do a simulator smoke test of the touched tab:

- To Do: initial load, pull-to-refresh, Family Calendar permission/empty/events states, Reminders permission/empty/items states, add/edit/delete shared task.
- Shopping: live connection badge, filter/search, add/edit/delete item, product search sheet.
- Home: initial load, revisit refresh, pull-to-refresh, quick actions, weather expand/collapse.
- Preferences/Notifications: ensure navigation still reaches notification settings and developer/log surfaces.

## Risk Areas

1. Swift access control
   - Moving `private` declarations out of a file will break references until access is adjusted.
   - Prefer default internal access for app-target-only types.

2. Xcode project membership
   - New files that are not added to the target will compile in the editor poorly or fail at build time.

3. SwiftUI generic/type-checking errors
   - Moving views can expose missing imports or private helper access.
   - Fix by adding the correct imports and narrowing dependencies.

4. EventKit permission behavior
   - Do not accidentally move calendar/reminder permission prompts back to app launch.
   - To Do should remain the permission entry point for Family Calendar and Personal Reminders.

5. Async task cancellation
   - Preserve the cancellation-safe refresh wrappers in Home and To Do.
   - Avoid turning harmless SwiftUI task cancellation back into user-facing errors.

6. Live shopping updates
   - Preserve WebSocket task lifecycle and viewer identity behavior.
   - Avoid creating multiple live-service connections for one view session.

7. Preview data accidentally becoming production fallback
   - Existing views sometimes use preview data before the first live load.
   - Keep that behavior deliberate, or replace it in a separate behavior-change task.

## Definition Of Done

The refactor is successful when:

- No primary app screen file is carrying unrelated service/view-model/model/editor/preview responsibilities.
- `ToDoView.swift`, `ShoppingListView.swift`, and `HomeView.swift` are readable page composition files.
- EventKit, weather, live shopping, API, and notification integration logic live in service or view model layers.
- Domain models and API DTOs are grouped by feature.
- Existing tests pass, and key extracted business logic has focused tests.
- SwiftUI previews remain useful for major cards, rows, sheets, and panels.
- The app behavior is unchanged except for explicitly approved follow-up changes.
