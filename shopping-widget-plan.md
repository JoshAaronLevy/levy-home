# Shopping Live Activity Implementation Plan

Created: 2026-07-11

Status: Stages 1 through 3 are implemented in code as of 2026-07-11. Stage 1 automated build, embedding, signing, install, and test checks pass; its manual physical-phone Lock Screen, Dynamic Island, and disabled-setting observations remain. Stages 2 and 3 migration/repository/API tests pass against a disposable Postgres-compatible database, but the migration has not been applied to the deployed database. Stages 4-9 remain planning only, and no Render or Home Assistant change has been made.

## What Josh Needs To Do Outside The Codebase

Codex can create the Xcode target and source files, write the migration and API code, add tests, run builds, deploy the migration when separately authorized, and verify an exported app. The items below require Apple-account access, physical-device interaction, or a product decision from Josh and Mallory.

### Required Before Or During Stage 1

1. Be signed into Xcode with the Apple Developer account for team **45K7QCRX6Y**.
2. Allow Xcode automatic signing to register and sign the proposed Widget extension bundle ID:

   **com.levyhome.app.widgets**

3. If automatic signing cannot make the change, use Apple Developer to register the extension App ID and regenerate the affected development or distribution provisioning profiles. An Account Holder or Admin may be required, depending on the current Apple Developer role.
4. Verify Push Notifications remains enabled for the host App ID **com.levyhome.app**.
5. Have at least one physical iPhone available for the Stage 1 Lock Screen test. Simulator previews can verify layout, but they cannot prove the real Lock Screen, Dynamic Island, or APNs behavior.
6. Confirm that showing the shopping estimate on a locked phone is acceptable. The proposed Live Activity intentionally exposes only counts and an estimated dollar amount; it does not show item names. Current Apple systems may also mirror an iPhone Live Activity to Apple Watch, Mac, or CarPlay, so the same privacy choice applies there.
7. Confirm the recommended v1 price rule:
   - The amount is an estimate, not the actual receipt total.
   - It uses the same conservative calculation the Shopping screen uses today: each listing contributes promo price when available, otherwise regular price; the highest available listing estimate is selected and multiplied by quantity.
   - The UI labels the amount **Est.**

If an actual paid total is required, the app first needs a separate actual-price entry, receipt scan, or checkout-total flow. That is intentionally outside this first implementation.

Apple references:

- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Activity authorization](https://developer.apple.com/documentation/activitykit/activityauthorizationinfo)
- [Live Activities design guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities)

### Required When The First Two-Phone Build Is Ready

On both Josh's and Mallory's iPhones:

1. Install and open the new Levy Home build at least once.
2. In Levy Home Preferences, set **Device Owner** to the correct resident.
3. Allow normal notifications so the end-of-trip summary can arrive.
4. In iOS Settings for Levy Home, leave **Live Activities** enabled.
5. Keep Levy Home installed long enough for each phone to upload its ActivityKit push-to-start token.
6. Test with the other phone:
   - unlocked with Levy Home open;
   - unlocked with Levy Home backgrounded;
   - locked;
   - with Levy Home terminated after it has been opened once.

The other phone does not need to leave Levy Home running. It does need the supporting build, a registered ActivityKit token, and Live Activities enabled. iOS may still decline a Live Activity if the user disabled the feature or the system has reached its active-activity limit; Levy Home must treat that as a display limitation, not as a failed shopping trip.

### Required For TestFlight Acceptance

1. Install the same TestFlight build on both phones.
2. Confirm the distribution build registers production ActivityKit and ordinary APNs tokens.
3. Start a trip from Josh's phone and prove Mallory's Lock Screen receives it.
4. Start a separate trip from Mallory's phone and prove Josh's Lock Screen receives it.
5. End each trip and confirm only the other resident receives the ordinary summary notification.
6. Confirm whether the completed Live Activity should remain visible for the recommended 15 minutes or use a different dismissal delay.

### Not Required For The Initial Implementation

- No Home Assistant changes.
- No Apple broadcast-push channel capability. Direct per-phone ActivityKit tokens are the correct fit for two residents.
- No **NSSupportsLiveActivitiesFrequentUpdates** plist flag. Human-paced item checkoffs do not justify it initially.
- No App Group. The Widget extension renders ActivityKit state and does not need shared database or UserDefaults access in v1.
- No location permission or background location work.
- No new APNs key is expected. The existing APNs key, Team ID, bundle ID, and private key can be reused.
- No new Render environment variable is expected. The implementation should reuse:
  - **DATABASE_URL**
  - **APNS_KEY_ID**
  - **APNS_TEAM_ID**
  - **APNS_BUNDLE_ID**
  - **APNS_PRIVATE_KEY_PATH** or **APNS_PRIVATE_KEY**
  - **APNS_ENVIRONMENT**
- No Home Screen widget is required. A Widget extension is still needed because that is how Apple packages Live Activity presentation code.

## Short Answer

Yes. The sports-score card is called a **Live Activity**. Levy Home can show a shopping trip on the Lock Screen and, on supported iPhones, in the Dynamic Island.

The initiating phone should start its Live Activity locally for immediate feedback. The Levy Home API should remotely start the counterpart's Live Activity, then send both phones authoritative count and estimate updates as Shopping items are checked off. Ending the trip should end both Live Activities and send one normal APNs summary notification to the resident who did not end the trip.

This is not a permanently running background view. iOS owns the Lock Screen presentation and Levy Home supplies small state updates through ActivityKit.

## Goal

When either Josh or Mallory taps **New** on the Shopping screen:

1. Levy Home creates one shared household shopping trip.
2. The initiating phone immediately shows a Live Activity.
3. The backend remotely starts the same trip on the other resident's phone.
4. As either resident marks items picked up, both Live Activities converge on:
   - picked-up item count;
   - remaining item count;
   - estimated picked-up total.
5. When either resident ends the trip:
   - the shared trip is finalized once;
   - both Live Activities receive the final state and end;
   - the other resident receives one ordinary summary notification.

Target Lock Screen copy:

~~~text
Shopping Trip
3 picked up • 7 left
Est. $25.50
~~~

Target completion notification:

~~~text
Shopping trip complete
Josh ended the trip: 8 picked up • 2 left • Est. $67.42
~~~

## Definition Of Done

The first implementation is complete only when all of the following are true:

1. There can be at most one active household shopping trip.
2. A simultaneous or repeated start request returns the same active trip instead of creating duplicates.
3. Starting from either phone creates a local Live Activity and remotely starts one on the counterpart's eligible phone.
4. A locked or terminated counterpart phone can receive the remote start after it has installed and opened the supporting build once.
5. The backend, not either phone, owns the canonical trip counts, estimate, version, and status.
6. Checking, unchecking, adding, restoring, or deleting an item during a trip follows the explicit v1 rules in this document.
7. Both Live Activities eventually display the same versioned trip state.
8. An APNs or ActivityKit failure never rolls back a committed list mutation or corrupts the trip.
9. Repeated end requests return the same completed trip and enqueue at most one counterpart summary.
10. The person who ends the trip does not receive the ordinary summary notification; the other resident does.
11. Ordinary per-item “picked up” pushes are suppressed during an active trip so the Live Activity does not create notification spam.
12. The exported production IPA embeds and signs the Widget extension, contains the correct Live Activity plist support, and uses production APNs entitlements.

## Starting Point Before Stage 1

### Shopping UI

- **LevyHome/Views/Shopping/ShoppingListView.swift** already renders the green **New** control.
- The current handler is literally **onStartShop: {}**, so tapping it does nothing.
- There is no corresponding End Shop control.
- The summary card currently displays:
  - the number of unpurchased rows;
  - the total number of Shopping rows;
  - an estimated total for unpurchased items.

### Shopping State And Price Data

- A picked-up item is represented only by the global **ShoppingListItem.purchased** Boolean.
- The checkoff path is:
  - **ShoppingListView.swift**
  - **ShoppingListViewModel.setPurchased**
  - **PATCH /api/shopping-list/items/:itemId**
- Counts currently mean Shopping rows, not summed unit quantities.
- Price data contains listing-level **regular** and **promo** estimates.
- There is no actual paid-price, receipt, checkout, trip, pickup timestamp, or pickup actor field.
- The current Shopping estimate omits missing prices and chooses the highest available listing estimate.

### API And Database

- **apps/api/src/contracts/shopping.ts** contains list items, stores, categories, and item mutations only.
- **apps/api/src/routes/shoppingListRoutes.ts** exposes list reads and item create, update, and delete operations only.
- **apps/api/src/repositories/shoppingListRepository.ts** persists global list state only.
- There is no **shopping_trips** or **shopping_trip_items** table.
- The current database wrapper exposes a tagged query but no explicit transaction abstraction. Trip and list transitions must not be implemented as two unrelated best-effort queries.

### Foreground Realtime

- **apps/api/src/shoppingListRealtime.ts** broadcasts item, store, category, and viewer-presence messages.
- **LevyHome/Services/Shopping/ShoppingListLiveMessages.swift** mirrors those messages.
- The Shopping WebSocket belongs to the Shopping view model and is not a background Lock Screen delivery system.
- A locked or terminated app cannot depend on that socket. Server-to-APNs ActivityKit pushes must be authoritative.

### Existing APNs Support

- Levy Home already registers ordinary APNs device tokens.
- **push_devices** persists the ordinary tokens and the selected resident name.
- The backend already routes list notifications from Josh to Mallory and from Mallory to Josh.
- **apps/api/src/integrations/apple/apnsPushSender.ts** already has APNs JWT authentication and sandbox/production endpoints.
- That sender is currently hardcoded to:
  - an ordinary alert payload;
  - **apns-push-type: alert**;
  - the base app topic;
  - priority 10.
- ActivityKit needs different payloads, tokens, topics, and headers.

### Xcode Project

- **LevyHome.xcodeproj** currently has the Levy Home app target and test target only.
- The deployment target is already iOS 18, which is sufficient for the proposed flow.
- There is no WidgetKit or ActivityKit target or source.
- **LevyHome/Resources/Info.plist** does not contain **NSSupportsLiveActivities**.
- Both app signing configurations already contain an APNs entitlement.
- **LevyHome/LevyHomeRelease.entitlements** currently declares **aps-environment** as **development**, so Stage 9 must inspect the signed export and correct the Release configuration if the exported app does not resolve to production.

## Recommended V1 Product Rules

| Situation | V1 behavior |
| --- | --- |
| What **New** means | Create or recover the one active household trip. |
| No currently needed items | Reject the start on both client and server; do not create an empty active trip. |
| Items included at start | Snapshot only rows whose global **purchased** value is false. |
| Old picked-up rows | Leave them untouched. Starting a trip does not reset or delete historical Shopping rows. |
| Count semantics | Count list rows. Quantity 3 for one row counts as one picked-up item, matching the current Shopping screen. |
| Cost semantics | Multiply estimated unit price by quantity, but label the result **Est.** |
| Missing price | Count the item, omit it from the dollar sum, and expose an unpriced count so zero dollars is not confused with no price data. |
| New item during a trip | Add it to the active trip as remaining. |
| Purchased item restored to Needed | Add or return it to the active trip as remaining. |
| Remaining item checked off | Mark its trip snapshot picked up, record actor/time, and add its estimated quantity-adjusted amount. |
| Picked-up item unchecked | Return it to remaining and remove its contribution from the running estimate. |
| Remaining item edited | Refresh name, quantity, and estimate snapshots until it is picked up. |
| Picked-up item edited | Keep the picked-up snapshot stable; uncheck and re-check to intentionally recalculate it. |
| Remaining item deleted | Mark the trip snapshot removed so it no longer counts as remaining. |
| Picked-up item deleted | Preserve the picked-up trip history even if the global Shopping row is removed. |
| Second start while active | Return the existing trip and recover that phone's Live Activity if it is missing. |
| Live Activities disabled on one phone | Keep the backend trip and the other phone working; show a local explanation instead of failing the trip. |
| Trip reaches Apple's eight-hour display limit | iOS ends the Live Activity display. Keep the backend trip active until a resident explicitly ends it; show a clear in-app explanation and End Shop recovery rather than silently completing a trip during a read. |
| End trip | Preserve Shopping row states, finalize the trip, end both Live Activities, and notify only the other resident. |

## Recommended Architecture

Use four separate concepts and keep their tokens distinct:

1. **Ordinary APNs device token**
   - Already used by Levy Home.
   - Used for the final summary notification.
2. **ActivityKit push-to-start token**
   - One current token per registered app device and APNs environment for this Activity type.
   - Used to remotely start the other phone's Live Activity.
3. **Per-activity update token**
   - One token for each phone's instance of a particular trip Live Activity.
   - Used to update and end that instance.
4. **Canonical shopping trip**
   - Stored in Postgres.
   - Owns status, counts, estimate, version, and summary delivery state.

Do not put ActivityKit tokens in **push_devices**. The ordinary notification service would otherwise mistake them for alert tokens.

Recommended flow:

~~~text
Josh taps New
    |
    v
POST /api/shopping-list/trips
    |
    +--> Postgres creates one active trip and snapshots needed items
    |
    +--> Josh's app starts a local ActivityKit Live Activity
    |
    +--> API sends ActivityKit push-to-start to Mallory's token
              |
              v
        Mallory's iPhone creates the matching Live Activity

Either phone checks off an item
    |
    v
PATCH /api/shopping-list/items/:id
    |
    +--> one atomic list + trip transition
    +--> canonical trip version increments
    +--> WebSocket updates open Shopping screens
    +--> ActivityKit update goes to both activity tokens

Either phone taps End Shop
    |
    v
POST /api/shopping-list/trips/:id/end
    |
    +--> trip finalizes once
    +--> ActivityKit end goes to both phones
    +--> ordinary APNs summary goes only to the other resident
~~~

Broadcast channels are intentionally excluded. They are designed for large audiences following one event, cannot start a Live Activity, and add portal and channel-management work that a two-phone household does not need.

## Canonical Data Design

### shopping_trips

Recommended fields:

| Field | Purpose |
| --- | --- |
| **id** | Server-generated UUID used in API, Activity attributes, logs, and deep links. |
| **status** | **active** or **completed** in v1. |
| **started_by** | Canonical resident value, Josh or Mallory. |
| **started_at** | Server timestamp. |
| **ended_by** | Resident who explicitly ended it. |
| **ended_at** | Server timestamp. |
| **version** | Monotonically increasing state version. |
| **currency_code** | **USD** in v1. |
| **start_mutation_id** | Makes repeated start requests idempotent. |
| **end_mutation_id** | Makes repeated end requests idempotent. |
| **summary_recipient** | Counterpart selected when an explicit end commits. |
| **summary_enqueued_at** | Records that per-device summary rows were created with the end transaction. |

Add a partial unique index that permits at most one **active** trip. The start service should return the existing active trip when two requests race.

For this two-person, list-sized workload, derive picked-up count, remaining count, estimate, and price coverage with one aggregate query over **shopping_trip_items** instead of persisting duplicate cached counters. The service returns that aggregate as the canonical public trip snapshot.

### shopping_trip_items

Recommended fields:

| Field | Purpose |
| --- | --- |
| **id** | Stable UUID for the trip snapshot row. |
| **trip_id** | Parent shopping trip. |
| **shopping_item_id** | Nullable reference to the global Shopping row; use **ON DELETE SET NULL** to preserve history. |
| **snapshot_position** | Stable zero-based ordering captured when the trip starts. |
| **name_snapshot** | Name used in the trip summary/history. |
| **quantity_snapshot** | Quantity used by the estimate. |
| **estimated_unit_price_cents** | Nullable integer-cents snapshot. |
| **price_source** | Store/source description used for diagnostics. |
| **store_id** | Optional selected listing source. |
| **state** | **remaining**, **picked_up**, or **removed**. |
| **picked_up_by** | Josh or Mallory. |
| **picked_up_at** | Server timestamp. |
| **created_at** and **updated_at** | Audit and reconciliation timestamps. |

Add a unique constraint for one active trip snapshot per original Shopping item. Aggregate trip counts from these rows inside the same transaction-scoped operation that returns the committed public trip snapshot.

### shopping_live_activity_registrations

Keep this table shopping-specific instead of building a generalized Live Activity framework prematurely.

Recommended fields:

| Field | Purpose |
| --- | --- |
| **id** | Server-generated UUID. |
| **push_device_id** | Reference to the ordinary **push_devices** row for this app installation. |
| **resident** | Josh or Mallory, derived from that device row's selected Device Owner value. |
| **environment** | **sandbox** or **production**. |
| **attributes_type** | Exact ActivityKit attributes type name. |
| **token_kind** | **push_to_start** or **activity_update**. |
| **token_hash** | Lookup, dedupe, and safe diagnostics. |
| **token** | Raw token required for APNs sending; never log or return it. |
| **shopping_trip_id** | Required for per-activity update tokens; null for push-to-start tokens. |
| **activity_id** | ActivityKit activity identifier for update tokens. |
| **last_accepted_version** | Records the newest version APNs accepted; delivery rows remain the durable in-flight record. |
| **registered_at** and **last_seen_at** | Rotation and health tracking. |
| **invalidated_at** | Soft invalidation after rotation or a permanent APNs rejection. |

Constraints should enforce the valid shape for each token kind and use different rotation scopes:

- Push-to-start: one current token per **push_device_id + environment + attributes_type**.
- Activity update: one current token per **shopping_trip_id + activity_id**.
- Rotating one Activity's update token must never invalidate a different Activity merely because both belong to the same resident.

### shopping_live_activity_deliveries

Use durable delivery rows so an API crash after a trip commit cannot leave a remote start unsent or completed Live Activities stuck active.

Recommended fields:

- trip ID;
- target Activity registration and target push-device ID;
- event type: **start**, **update**, or **end**;
- trip state version and ActivityKit timestamp;
- status: **pending**, **claimed**, **provider_accepted**, **skipped**, or **dead_letter**;
- attempt count, next-attempt time, and lease/claim time;
- token hash used for the attempt;
- APNs ID, last status code, and redacted failure reason;
- created, provider-accepted, and completed timestamps.

Enforce one provider-accepted **start** per trip and target device. Once APNs accepts a start, never intentionally send another start for that trip/device. For updates, coalesce pending work to the newest trip version and keep one immutable, monotonically increasing ActivityKit timestamp with that version across retries. Persist end delivery independently and retry after restart until APNs accepts it or the target token is permanently invalid. APNs acceptance does not prove that the system displayed the activity; physical-device observation remains the presentation test.

### shopping_trip_summary_deliveries

Create one ordinary-notification delivery row per eligible counterpart **push_devices** row when an explicit end commits.

Recommended fields:

- trip ID, persisted recipient, and target push-device ID;
- **pending**, **claimed**, **provider_accepted**, **skipped**, or **dead_letter** status;
- next-attempt and lease timestamps;
- attempt count, APNs ID, last status code, and reason;
- created and provider-accepted timestamps.

Use a unique constraint on **trip_id + push_device_id**. This lets one valid counterpart device succeed without repeatedly resending to it because another stale device failed.

## API Contract

### Trip Endpoints

Add:

~~~http
GET /api/shopping-list/trips/active
POST /api/shopping-list/trips
POST /api/shopping-list/trips/:tripId/end
~~~

Start request:

~~~json
{
  "actor": "Josh",
  "originatingDeviceId": "apns-production-device-id",
  "mutationId": "client-generated-uuid"
}
~~~

Start response:

~~~json
{
  "ok": true,
  "created": true,
  "activityDisposition": "startLocally",
  "trip": {
    "id": "trip-uuid",
    "status": "active",
    "startedBy": "Josh",
    "startedAt": "2026-07-11T18:00:00.000Z",
    "pickedUpCount": 0,
    "remainingCount": 10,
    "totalItemCount": 10,
    "estimatedTotalCents": 0,
    "pricedPickedItemCount": 0,
    "unpricedPickedItemCount": 0,
    "currencyCode": "USD",
    "version": 1
  }
}
~~~

Return **201** for a newly created trip and **200** with **created: false** when an active trip already exists.

The response must include a per-request-device disposition such as:

- **startLocally**
- **remoteStartPending**
- **alreadyRegistered**
- **unavailable**

This prevents a simultaneous-start race in which the counterpart starts locally while an already-accepted remote-start push is still in flight.

End request:

~~~json
{
  "actor": "Mallory",
  "mutationId": "client-generated-uuid"
}
~~~

Repeated end calls must return the same final trip without creating another summary notification.

### Include Trip State In Existing Shopping Responses

Add nullable **activeTrip** to:

- **GET /api/shopping-list**
- create-item response;
- update-item response;
- delete-item response.

This gives the initiating phone an immediate server-confirmed state for local Activity updates and lets an open Shopping screen recover without a separate race-prone calculation.

### ActivityKit Token Endpoints

Add:

~~~http
PUT /api/live-activities/shopping/push-to-start-token
PUT /api/shopping-list/trips/:tripId/live-activities/:activityId/token
DELETE /api/shopping-list/trips/:tripId/live-activities/:activityId/token
~~~

The app must persist the **device.id** returned by **POST /api/devices/register** and include that ID with ActivityKit token registration. The server derives the resident from the linked **push_devices.device_name** and rejects an inconsistent claimed resident. This is consistency validation, not authentication; broader API authentication remains separate.

When a per-activity update token arrives after the trip has already changed, immediately send the latest canonical trip content state to that token.

### Realtime Messages

Extend the Shopping WebSocket union with:

- **trip_started**
- **trip_updated**
- **trip_ended**

Each message should carry the complete public trip snapshot, mutation ID, state version, and server time. The foreground app uses these messages for UI synchronization; the Live Activity still uses ActivityKit pushes.

## ActivityKit State Contract

Use one shared Swift type compiled into both the app and Widget extension targets.

Shared attributes and dynamic state:

~~~swift
struct ShoppingTripActivityAttributes: ActivityAttributes {
    typealias ContentState = ShoppingTripActivityState

    let tripID: String
    let startedByName: String
    let startedAtEpochSeconds: Int
}

struct ShoppingTripActivityState: Codable, Hashable {
    let status: String
    let pickedUpCount: Int
    let remainingCount: Int
    let totalItemCount: Int
    let estimatedTotalCents: Int
    let pricedPickedItemCount: Int
    let unpricedPickedItemCount: Int
    let currencyCode: String
    let stateVersion: Int
    let updatedAtEpochSeconds: Int
}
~~~

Use integer epoch seconds and integer cents. Avoid custom JSON date or key strategies; ActivityKit's push payload must decode exactly into the Swift content state. Do not send item arrays, names, APNs tokens, or other private data in Activity state.

## Live Activity Presentation

### Lock Screen

Active:

- Header: **Shopping Trip**
- Main status: **3 picked up • 7 left**
- Amount: **Est. $25.50**
- Optional secondary note when needed: **2 picked items have no price**
- Small origin label: **Started by Josh**

Completed:

- Header: **Shopping Complete**
- Main status: **8 picked up • 2 left**
- Amount: **Est. $67.42**
- Keep visible for 15 minutes, then dismiss.

### Dynamic Island

- Compact leading: cart symbol.
- Compact trailing: remaining count.
- Minimal: cart or remaining count, whichever remains legible.
- Expanded: picked-up count, remaining count, and estimate.

Support every Dynamic Island presentation even if one of the two current phones does not have a Dynamic Island. Keep compact labels short enough for mirrored or constrained presentations, and visually check mirrored presentations on any available Apple Watch, Mac, or CarPlay surface.

### Tap Behavior

Use a deep link such as:

~~~text
levyhome://shopping?trip=trip-uuid
~~~

Add a small app navigation router so tapping the Live Activity selects the Shopping tab. Do not add interactive item controls to the Live Activity in v1; all list mutation continues in the real Shopping screen.

## Stage 1: Prove A Local Live Activity On One Physical Phone

### Goal

De-risk Widget-extension signing and real Lock Screen presentation before changing Shopping or the backend.

### Implementation

1. Add a Widget extension target named **LevyHomeWidgets** with bundle ID **com.levyhome.app.widgets** and iOS 18 deployment target.
2. Embed the extension in the Levy Home app and add the correct target dependency/build phase.
3. Add:
   - **LevyHomeWidgets/LevyHomeWidgetsBundle.swift**
   - **LevyHomeWidgets/ShoppingTripLiveActivity.swift**
   - **LevyHomeWidgets/Info.plist**, including **NSExtensionPointIdentifier = com.apple.widgetkit-extension**
   - **LevyHome/Models/Shopping/ShoppingTripActivityAttributes.swift**
4. Compile the Activity attributes file into both targets.
5. Add **NSSupportsLiveActivities = true** to **LevyHome/Resources/Info.plist**.
6. Add an app-scoped **ShoppingLiveActivityCoordinator** under **LevyHome/Services/Shopping/**.
7. Check **ActivityAuthorizationInfo().areActivitiesEnabled** before requesting an activity.
8. Add temporary Developer-only controls to:
   - start a sample local shopping activity;
   - update its sample counts and estimate;
   - end it with a final state.
9. Keep the real Shopping **New** handler unchanged during this proof.
10. Add Lock Screen and all Dynamic Island layouts with accessibility labels, monospaced digits, dark/light appearance, and large-number handling.

### Verification

1. Build the app and extension together.
2. Verify the extension is embedded in the built app.
3. Install a signed Debug build on Josh's physical phone.
4. Start the sample from Developer tools, lock the phone, and verify:
   - title;
   - picked-up count;
   - remaining count;
   - estimated amount;
   - update and end transitions.
5. If the phone has a Dynamic Island, verify compact, minimal, and expanded layouts.
6. Disable Live Activities in Settings and confirm the coordinator returns a useful, nonfatal explanation.

### Exit Criteria

- The signed Widget extension runs on a real phone.
- A sample Live Activity can start, update, and end locally.
- The real Shopping button still does not create an unpersisted fake trip.
- Layout is readable with 0, 3, 99, and 999 remaining items and estimates from zero through four digits.

### Implementation Status — 2026-07-11

- The Widget extension, shared ActivityKit state, app-scoped coordinator, and temporary Developer controls are implemented.
- Debug and Release simulator builds compile the app and extension together, and the built app embeds **PlugIns/LevyHomeWidgets.appex** with the expected bundle ID and WidgetKit extension point.
- The signed Debug app and extension validate under team **45K7QCRX6Y** and are installed on Josh's paired iPhone 16 Pro.
- The full iOS unit-test suite passes, including coordinator coverage for disabled authorization, start failure, active and pending deduplication, update stress states, and final dismissal.
- The Update control cycles through 0, 3, 99, and 999 remaining items and estimates from **$0.00** through **$9,999.99** for physical layout inspection.
- The real Shopping **New** handler remains **onStartShop: {}**.
- Manual phone acceptance is still required: launch the installed build, start the sample in **Preferences -> Developer**, inspect the Lock Screen and every Dynamic Island presentation, exercise update/end, and repeat once with Live Activities disabled.

## Stage 2: Add Durable Shopping Trip Persistence

### Goal

Create one backend-owned trip model before any user-facing start action depends on it.

### Implementation

1. Add a dated Postgres migration for **shopping_trips** and **shopping_trip_items**.
2. Add the partial unique index for one active trip.
3. Add indexes for active-trip lookup and trip item aggregation.
4. Extend the database layer with an explicit transaction-capable abstraction, or use a proven atomic SQL/CTE boundary for each list-plus-trip mutation. Both the Shopping repository and trip repository must receive the same transaction-scoped database client, or one repository method must atomically return the old item, new item, and trip snapshot. Merely adding a transaction helper that the two stores do not share is insufficient.
5. Add:
   - **apps/api/src/repositories/shoppingTripRepository.ts**
   - **apps/api/src/contracts/shoppingTrips.ts**
   - row readers and aggregate mapping;
   - in-memory test implementations only where current test composition requires them.
6. Implement the documented row-count and estimate rules using integer cents. Accept only finite, nonnegative listing prices and use one tested rounding rule when converting a price to cents.
7. Snapshot currently needed rows at start.
8. Derive counts and estimates from trip item states in one aggregate query instead of blindly incrementing counters or storing duplicate caches.
9. Emit WebSocket messages and enqueue APNs work only after the database transaction resolves successfully.

### Verification

1. Run the migration against a disposable/test database.
2. Prove a second active insert is rejected at the database level.
3. Prove deleting a Shopping row preserves its trip snapshot.
4. Prove integer-cents estimates for:
   - promo price;
   - regular-only price;
   - quantity greater than one;
   - multiple store listings;
   - missing price;
   - mixed priced and unpriced items.
5. Prove an induced failure rolls back the whole trip transition.

### Exit Criteria

- A trip survives API restart.
- One active-trip enforcement exists in Postgres, not only in process memory.
- Trip aggregates are generated from snapshot rows without a second cached source of truth.
- No ActivityKit or UI behavior depends on client-computed counts.

### Implementation Status — 2026-07-11

- Added **apps/api/migrations/2026-07-11-001-shopping-trips.sql** with durable trip and item snapshots, one-active-trip enforcement, lookup/aggregation indexes, mutation IDs, history-preserving Shopping references, state-shape checks, and stable snapshot ordering.
- Added **apps/api/src/contracts/shoppingTrips.ts** and **apps/api/src/repositories/shoppingTripRepository.ts** for active-trip reads, item snapshots, explicit completion persistence, and one-query canonical aggregates.
- Added a transaction-capable database runner backed by one checked-out Postgres connection. Trip creation and Shopping-list snapshot reads use the same transaction-scoped tagged-query client.
- Implemented the documented estimate rule in integer cents: valid promo before regular within each listing, highest usable listing across stores, quantity multiplication in the aggregate, and explicit priced/unpriced picked-item counts.
- Added disposable-database integration coverage using the real migration. Tests prove persistence across repository reconstruction, database-level rejection of a second active trip, historical snapshot preservation after Shopping-row deletion, stable ordering, mixed price aggregation, empty-list rejection, and full rollback after an induced snapshot failure.
- Added focused transaction and pricing unit tests. API typecheck, production build, and the full **127-test** API suite pass.
- No Stage 3 route, service, WebSocket, APNs, ActivityKit, or iOS behavior was added. The migration is checked in but has not been run against the configured/deployed database; that remains a separate deployment action.

## Stage 3: Add Trip Services, Routes, Contracts, And Foreground Realtime

### Goal

Expose an idempotent domain API that both phones can recover from.

### Implementation

1. Add:
   - **apps/api/src/services/shopping/shoppingTripService.ts**
   - **apps/api/src/routes/shoppingTripRoutes.ts**
   - **apps/api/src/validation/shoppingTripValidation.ts**
2. Implement active-trip read, create-or-return-active, and idempotent end.
3. Require a recognized Josh/Mallory actor.
4. Reject a start with zero needed rows using **409 shopping_trip_has_no_needed_items**. The iOS guard added later is only a convenience; the backend remains authoritative.
5. Use mutation IDs for start and end correlation and replay safety.
6. Add nullable **activeTrip** to Shopping snapshot and mutation response contracts.
7. Extend **apps/api/src/shoppingListRealtime.ts** with trip broadcasts.
8. Extend:
   - **LevyHome/Models/API/ShoppingAPIResponses.swift**
   - **LevyHome/Services/API/APIClient+Shopping.swift**
   - **LevyHome/Services/Shopping/ShoppingListLiveMessages.swift**
9. Wire the new backend slice through:
   - **apps/api/src/contracts/index.ts**
   - **apps/api/src/routes/index.ts**
   - **apps/api/src/app.ts** dependency construction and test injection.
10. Add API client methods for active-trip read, start, and end.
11. Do not send any ActivityKit push or summary notification yet.

### Verification

1. Add route tests for:
   - no active trip;
   - new trip;
   - repeated mutation ID;
   - second resident starting while active;
   - empty needed list;
   - explicit end;
   - repeated end;
   - wrong trip ID.
2. Add WebSocket decoder tests for all three trip message types and unknown-message forward compatibility.
3. Restart the API between start and active-trip read and confirm the same trip returns.

### Exit Criteria

- Both clients can read the same active trip.
- Simultaneous starts converge on one trip.
- End is durable and idempotent even before notification side effects are added.

### Implementation Status — 2026-07-11

- Added **GET /api/shopping-list/trip**, **POST /api/shopping-list/trip/start**, and **POST /api/shopping-list/trip/end**. Start and end require the recognized **Josh** or **Mallory** actor and UUID mutation ID; malformed requests receive **400 invalid_shopping_trip**.
- The trip service returns an existing trip for a repeated start mutation or a second start while another trip is active. It replays an end mutation without a second write or broadcast, and returns **409 shopping_trip_has_no_needed_items** for an empty needed list.
- Shopping list snapshots and item-mutation responses now carry nullable **activeTrip**. The app wires the durable PostgreSQL trip store when **DATABASE_URL** is configured and returns **503 database_not_configured** for trip routes otherwise, rather than creating an in-memory trip.
- The existing Shopping WebSocket now supports complete **trip_started**, **trip_updated**, and **trip_ended** messages. Only committed new start/end transitions broadcast in this stage; `trip_updated` is reserved for the atomic Shopping-item/trip mutations in Stage 6.
- Added Swift trip request/response models, active/start/end API client methods, and forward-compatible decoding/logging for the three trip messages. Stage 5 remains responsible for presenting active-trip state and real Start/End controls in the Shopping UI.
- Disposable-database route tests cover no trip, durable start/read after API reconstruction, repeated mutation IDs, second-resident convergence, empty-list rejection, explicit end, repeated end, wrong trip ID, and post-commit broadcasts. API typecheck/build and all **131** API tests pass; focused iOS API/decoder tests pass.
- No ActivityKit token registration, APNs/live-activity delivery, summary notification, or real Shopping UI action was added. The migration remains checked in but unapplied to the deployed database.

## Stage 4: Prove Remote Start, Update, And End On The Second Phone

### Goal

De-risk the ActivityKit token lifecycle and APNs headers before wiring the customer-facing **New** button.

### Implementation

1. Add a migration and repositories for **shopping_live_activity_registrations** and **shopping_live_activity_deliveries**.
2. At app startup, observe:
   - **Activity<ShoppingTripActivityAttributes>.pushToStartTokenUpdates**
   - **Activity<ShoppingTripActivityAttributes>.activityUpdates**
   - each active activity's **pushTokenUpdates**
3. Upload every token rotation and invalidate the superseded server record.
4. Extend **PushAPISyncState** in **LevyHome/Services/NotificationService.swift** to persist the **device.id** that **PushRegistrationViewModel** currently receives but discards, then use that device ID to associate ActivityKit registrations.
5. Add the token registration endpoints and strict validation.
6. Refactor the APNs implementation into:
   - a shared authenticated HTTP/2 transport;
   - the existing ordinary alert sender;
   - a new typed ActivityKit sender.
7. Add a restart-safe **shoppingLiveActivityDeliveryService**, inject it in **apps/api/src/app.ts**, and manage its **start()/stop()** lifetime in **apps/api/src/server.ts**.
8. ActivityKit requests must use:
   - **POST /3/device/{activity-token}**
   - **apns-push-type: liveactivity**
   - **apns-topic** composed from **APNS_BUNDLE_ID** followed by **.push-type.liveactivity**, rather than hardcoded;
   - the correct sandbox or production APNs host;
   - a complete ActivityKit **aps** payload.
9. Use priority 10 for start and end, and priority 5 for normal item-driven updates.
10. Capture the provider's **apns-id** and set an **apns-expiration** appropriate to the trip so a stored start cannot create an already-ended trip much later.
11. Remote start payload must include:
   - **event: start**
   - Unix **timestamp**
   - full **content-state**
   - **attributes-type**
   - static **attributes**
   - **input-push-token: 1** on iOS 18
   - the required visible start alert.
12. Update payload must include **event: update**, the immutable timestamp assigned to that committed/coalesced version, and the complete latest content state.
13. End payload must include **event: end**, the final content state, and a dismissal date.
14. Persist start intent before sending. Once APNs returns 200 for a trip/device, never send another start there. Treat a network timeout with no APNs response as ambiguous and use bounded reconciliation rather than blindly issuing another start.
15. Add Developer-only API controls that remotely start the current test trip on the counterpart phone, send an update, and end it.
16. Send the latest trip snapshot immediately when a late update token registers.
17. Handle permanent APNs failures such as **Unregistered**, **BadDeviceToken**, and **DeviceTokenNotForTopic** by invalidating the affected ActivityKit token.

Apple references:

- [Starting and updating Live Activities with ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
- [Setting up broadcast push notifications](https://developer.apple.com/documentation/usernotifications/setting-up-broadcast-push-notifications)

### Verification

1. Unit-test the exact APNs path, topic, push type, priority, and JSON for start, update, and end.
2. Assert raw ActivityKit tokens never appear in logs or API responses.
3. Open the new build once on both phones and confirm each current push-to-start token is stored.
4. From Josh's phone or Developer tools, remotely start Mallory's Live Activity while Mallory's phone is:
   - foregrounded;
   - backgrounded;
   - locked;
   - app terminated.
5. Repeat in the opposite direction.
6. Confirm a remotely started activity uploads its per-activity update token and then receives update and end pushes.
7. Rotate or replace a token in a test and confirm the prior token is invalidated.
8. Simulate an ambiguous start timeout and confirm the service does not intentionally enqueue a second start for the same trip/device.

### Exit Criteria

- Both directional remote-start paths work on physical phones.
- Three token types remain separate.
- A late update token catches up to the latest trip version.
- Broadcast channels and frequent-update mode are still unnecessary.

### Implementation Status — 2026-07-11

- Added **apps/api/migrations/2026-07-11-002-shopping-live-activity-delivery.sql** and a PostgreSQL-backed registration/delivery repository. It retains raw ActivityKit tokens only server-side, invalidates the superseded active token for the same device/scope, and persists per-trip APNs delivery intent, attempts, response IDs, errors, and due-retry state.
- Added **POST /api/shopping-list/live-activities/registrations** with strict schema validation for the APNs device, resident, environment, token kind, token shape, and trip scope. Registration responses and delivery/debug responses deliberately omit raw ActivityKit tokens.
- Refactored the APNs sender around a common authenticated HTTP/2 request path and added the typed Live Activity sender. It sends to the sandbox or production host with the documented Live Activity topic suffix, push type, priority, expiration, and start/update/end payload shapes. The start payload includes attributes, a visible alert, and **input-push-token: 1**; updates use priority 5 and end requests include the final state and dismissal date.
- Added a restart-safe **shoppingLiveActivityDeliveryService**. It claims durable work, records APNs IDs, retries retryable update/end failures with bounded backoff, invalidates permanent-token failures, and processes an update token registration as an immediate catch-up delivery. An ambiguous remote **start** is intentionally never retried: a later per-activity update token is the positive reconciliation signal, preventing a second start from creating a duplicate Activity.
- The app now persists the ordinary registered **device.id**, starts observing static push-to-start tokens, Activity updates, and per-activity update-token rotations after that ID is available, and uploads those tokens without logging their values. The temporary local sample still uses an ActivityKit update token, while the real Shopping **New** action remains unchanged for Stage 5.
- Added Developer-only remote Start, Update, and End controls under **Preferences -> Developer**. They queue delivery for the counterpart resident’s eligible device and require the current durable trip (with a completed trip for End); they do not alter the customer-facing Shopping flow.
- Added repository, route, delivery-safety, APNs-payload, API-client, and persisted-device-ID tests. API typecheck, production build, and all **137** API tests pass; the full iOS simulator suite also passes.
- This migration has **not** been applied to the configured/deployed database, and no real APNs request or physical two-phone acceptance run was performed. Stage 4’s physical checks—both directions, foreground/background/locked/terminated, update-token catch-up, and token rotation—remain required before its exit criteria can be declared met.

## Stage 5: Wire The Real Start And Recovery Experience

### Goal

Make **New** create a durable trip and start the correct local and remote Live Activities.

### Implementation

1. Add active-trip state and start/end busy state to **ShoppingListViewModel**.
2. Replace **onStartShop: {}** in **ShoppingListView.swift** with the start action.
3. Before starting, require at least one needed item. If none exist, show a clear in-app message and do not create an empty trip.
4. Call the trip start API first with the originating push-device ID.
5. In the start transaction, reserve the originating device's disposition and create one pending remote-start row for every other eligible device before returning the canonical snapshot.
6. Only a response with **startLocally** may immediately call **Activity.request(..., pushType: .token)**. Then observe that Activity's **pushTokenUpdates** stream and upload each per-activity token rotation.
7. A response with **remoteStartPending** must wait for the already-persisted remote start instead of creating a competing local Activity.
8. After the trip commit, have the backend process each durable counterpart start row once.
9. Add a bounded missing-start recovery path, and have the coordinator detect and end duplicate local Activities that share a trip ID if an ambiguous delayed start still races recovery.
10. Change the summary card while active:
   - replace **New** with **End Shop**;
   - show **x picked up • y left**;
   - show the picked-up estimate, not the pre-trip remaining estimate;
   - show who started the trip and when.
11. Make **ShoppingLiveActivityCoordinator** app-scoped so token and Activity recovery does not depend on the Shopping tab being mounted.
12. On screen load, app foreground, WebSocket reconnect, tab revisit, and process relaunch:
   - fetch the active trip;
   - attach to an existing local Activity by trip ID;
   - claim a missing display through the server disposition before starting locally;
   - never create a second backend trip just to repair the display.
13. Observe **scenePhase** and either pass Shopping an **isSelected** state like Home/To Do or route tab-revisit refresh through an app navigation coordinator; the current one-time Shopping task is not sufficient.
14. Register the **levyhome** URL scheme in **LevyHome/Resources/Info.plist**, make **RootTabView** selection routable instead of private view-only state, and handle **.onOpenURL** so a Live Activity tap selects Shopping.
15. Remove or disable the temporary Developer-only start controls after the real flow proves them redundant.

### Verification

1. Add view-model tests for new, existing, disabled, missing-token, and API-failure cases.
2. Double-tap **New** and confirm one trip and one local activity.
3. Tap **New** on both phones nearly simultaneously and confirm one shared trip.
4. Start when the counterpart has no ActivityKit token and confirm:
   - the trip still starts;
   - the initiating phone works;
   - the app reports the counterpart display limitation without claiming the trip failed.
5. Relaunch either app during the active trip and confirm UI/activity recovery.
6. Delay a remote-start push while the counterpart also taps **New** and confirm the per-device disposition prevents duplicate Activities.

### Exit Criteria

- **New** is no longer a no-op.
- One shared trip starts from either resident's phone.
- Starting and display delivery have honest, separate success states.

### Implementation Status — 2026-07-11

- Added **apps/api/migrations/2026-07-11-003-shopping-trip-display-dispositions.sql**. The start transaction now records **start_locally** for the originating APNs device and a **remote_start_pending** row for every counterpart device with an active static ActivityKit start token before the canonical trip response is returned.
- **POST /api/shopping-list/trip/start** accepts the originating push-device ID and returns its durable display disposition. A concurrent/replayed start claims that same device’s existing disposition instead of creating a second trip or local Activity. **POST /api/shopping-list/trip/:tripId/display/claim** provides the bounded relaunch/foreground recovery path for an active trip whose local display is missing.
- After a new trip commits, the backend queues only counterpart Live Activity start work through the existing durable dispatcher. The trip remains successful when no counterpart start token is available; the response carries a zero remote-start count rather than claiming that the remote display started.
- The Shopping UI now starts a trip from **New**, guards empty lists and a not-yet-registered originating device with clear in-app messages, and presents the canonical active-trip state. While active, the summary changes to **End Shop**, shows picked-up/remaining counts, picked-up estimate, and the resident who started it.
- The app uses the shared, app-scoped Activity coordinator to start or recover a local Activity only after a **start_locally** disposition. A **remote_start_pending** result waits for the already-persisted remote start, preventing the counterpart from creating a competing local Activity. Revisit, foreground, Live WebSocket trip messages, and relaunch recovery all claim/reconcile the current display without creating another backend trip; duplicate local displays for a trip are retired.
- Added the **levyhome://shopping** URL scheme and routable Shopping tab handling for Live Activity taps. The temporary local sample controls have been removed from Developer tools; the remote delivery diagnostics remain for APNs proof.
- Added API route and Swift view-model coverage for local/remote disposition, dispatch handoff, missing needed items, missing device registration, and API failure. API typecheck/build and all **138** API tests pass; the full iOS simulator suite passes.
- The new migration is not applied to the configured/deployed database and physical two-phone/APNs acceptance remains outstanding. Stage 6 must still make item mutations drive the durable trip counts and ActivityKit updates; the Stage 5 display state intentionally does not derive checkoffs from the current client list.

## Stage 6: Drive Counts And Estimate From Real Shopping Mutations

### Goal

Make every item checkoff update the canonical trip and both Lock Screen presentations.

### Implementation

1. Refactor **shoppingListMutationService** so an update can inspect the previous item state.
2. Apply each global Shopping mutation and corresponding trip transition atomically.
3. During an active trip, require a recognized actor for every mutation that carries **purchased**. Reject an unattributed pickup/unpickup, and reject **POST item** with **purchased: true** in v1 instead of inventing trip history.
4. Implement the v1 transition matrix:
   - false to true: remaining to picked up;
   - true to false: picked up to remaining;
   - false to false repeat: no duplicate pickup;
   - true to true repeat: no duplicate pickup;
   - create false: add remaining;
   - restore false: add or return remaining;
   - delete remaining: mark removed;
   - delete picked up: retain trip history;
   - remaining quantity/price edit: refresh its snapshot.
5. Derive counts and estimate from trip snapshot rows and increment the trip version only when public state changes.
6. Return the committed item and complete active trip immediately after the transaction; do not hold the grocery-tap response open while two ActivityKit HTTP/2 sends run.
7. Broadcast **trip_updated** only after the transaction commits.
8. Update the current phone's Activity immediately from the confirmed response.
9. Enqueue/coalesce the same complete state for every active per-trip ActivityKit token.
10. Use priority 5 for ordinary item-driven ActivityKit updates, without an alert.
11. Coalesce rapid successive checkoffs so the backend sends the newest state rather than spending push budget on every intermediate frame.
12. ActivityKit orders remote updates by the **aps.timestamp**, not Levy Home's custom state version. Assign one immutable, strictly increasing timestamp to each committed/coalesced version, reuse it on retry, serialize sends per trip, and never resend an older snapshot with a newly generated timestamp.
13. Use **staleDate: nil** in event-driven v1. Do not show “Update delayed” merely because no grocery state changed; add a heartbeat/freshness SLA first if stale presentation is wanted later.
14. Suppress ordinary counterpart item-mutation pushes for any active-trip request that carries **purchased**, whether true or false. Keep useful last-minute creates or non-purchase edits under the existing Shopping preference unless product testing shows they are noisy.
15. Treat ActivityKit delivery as post-commit work. A failed push is logged and the durable dispatcher retries or supersedes it with a newer snapshot; the item mutation remains successful.

### Verification

1. Add unit and integration tests for every transition in the matrix.
2. Prove an induced database failure changes neither the global item nor the trip.
3. Rapidly check and uncheck the same item and confirm:
   - the final database state is correct;
   - the total is not double counted;
   - both phones eventually show the highest committed version.
4. Test priced, unpriced, and mixed-price trips.
5. Add an item from the other phone during a trip and confirm remaining count increases.
6. Restart Render/API during a trip and confirm the next mutation continues from persisted state.
7. Commit several versions inside one wall-clock second and prove ActivityKit timestamps remain ordered without rolling either phone backward.

### Exit Criteria

- The Lock Screen numbers are derived from the durable trip, not view-local arrays.
- The two phones converge after rapid or reordered activity.
- Checking off groceries does not generate an ordinary notification per item.

## Stage 7: End The Trip And Notify Only The Other Resident

### Goal

Finalize the shared trip once, end both Live Activities, and deliver one useful counterpart summary.

### Implementation

1. Add the migration and repository for **shopping_trip_summary_deliveries**.
2. Add a confirmation sheet for **End Shop** showing the current final counts and estimate.
3. Call the idempotent end endpoint with actor and mutation ID.
4. In one database transaction:
   - mark the active trip completed;
   - derive the immutable final public snapshot from the trip item rows;
   - record **ended_by** and **ended_at**;
   - select the counterpart recipient;
   - create one deduplicated pending summary row per eligible counterpart push device.
5. Broadcast **trip_ended** after commit.
6. Enqueue ActivityKit **end** for every non-invalidated per-trip update token and process pending ends again after API restart.
7. Include the final content state and keep it on the Lock Screen for 15 minutes using a dismissal date.
8. Make ActivityKit end pushes non-alerting. The counterpart receives the separate ordinary summary alert; do not alert through both channels for the same completion.
9. Add a dedicated **sendShoppingTripSummaryPush** service method. Do not pretend the trip summary is an item mutation.
10. Use the ordinary APNs device token and the **summary_recipient** persisted by the end transaction. Strictly target that resident's devices; never fall back to broadcasting or merely excluding the actor after a restart.
11. Reuse the existing **shopping_list** notification preference in v1, applied per target device. Mark a preference-disabled or no-device row terminally skipped instead of retrying forever. A separate **shopping_trip_summary** toggle can be added later only if Josh and Mallory want independent control.
12. Use database uniqueness as the logical dedupe boundary. An **apns-collapse-id** based on trip ID and recipient is only best-effort queue coalescing, not exact deduplication. Also set **apns-expiration** so a stale completion alert cannot arrive much later.
13. Add a small restart-safe summary dispatcher, modeled after existing start/stop services:
    - claim pending summaries atomically;
    - send after the end transaction commits;
    - mark provider acceptance separately from observed phone presentation;
    - use bounded retry with backoff for transient failures;
    - never create a second row for the same trip and target device;
    - do not resend to a device whose prior row already reached provider acceptance.
14. Wire the dispatcher through **apps/api/src/app.ts** and its **start()/stop()** lifetime through **apps/api/src/server.ts**.
15. Suggested body rules:
    - no remaining items: **Josh ended the trip: 8 picked up • Est. $67.42**
    - some remaining: **Josh ended the trip: 8 picked up • 2 left • Est. $67.42**
    - no priced items: omit the dollar amount rather than saying zero.
16. Add Shopping deep-link data and implement **UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)** in **NotificationService.swift** so tapping the ordinary notification uses the same app navigation coordinator to select Shopping.

### Verification

1. Josh ends: Mallory's eligible devices alone receive the ordinary summary.
2. Mallory ends: Josh's eligible devices alone receive the ordinary summary.
3. Repeated end requests create one completed trip and one summary row per eligible counterpart device, with no duplicate row for the same device.
4. End succeeds when:
   - one Live Activity token is invalid;
   - ActivityKit delivery fails but ordinary APNs succeeds;
   - ordinary APNs fails but ActivityKit end succeeds.
5. Confirm both Live Activities display the final state and disappear after the chosen delay.
6. Confirm the global Shopping list is not bulk-cleared or reset.
7. Restart the API after the end commit but before delivery processing and confirm pending ActivityKit ends and summary rows resume.

### Exit Criteria

- Explicit end is durable and idempotent.
- Both Live Activities end.
- Exactly the intended counterpart is targeted for one summary.
- Delivery failure cannot reopen or roll back a completed trip.

## Stage 8: Add Recovery, Observability, And Operational Hardening

### Goal

Make the feature diagnosable and safe across APNs failures, token rotation, app termination, and Render restarts.

### Implementation

1. Add structured, redacted logs for:
   - trip start/update/end;
   - trip ID and version;
   - actor and recipient;
   - ActivityKit event type;
   - APNs environment/status/reason;
   - a safe **registrationFingerprint** derived from the token hash; do not name the structured field with **token**, because the shared logger deliberately redacts every token-like key;
   - coalesced or skipped updates;
   - summary retry state.
2. Never log raw normal APNs or ActivityKit tokens.
3. Track last provider-accepted trip version per activity registration.
4. Mark permanent ActivityKit token failures invalid; retry only transient failures.
5. Reconcile active activities at app startup and foreground transitions.
6. Treat a user-dismissed Live Activity as a display opt-out, not as End Shop.
7. Do not silently complete a backend trip when Apple's eight-hour Live Activity window ends. On the next app visit, explain that the Lock Screen display expired and let a resident explicitly end the still-active trip. Add a Developer/manual stale-trip recovery for exceptional cases.
8. End or retire orphaned local activities that no longer match an active server trip.
9. Add invalidation/removal support to **push_devices** and filter invalid rows so ordinary summary sends also clean up **Unregistered**, **BadDeviceToken**, and **DeviceTokenNotForTopic** after an app reinstall.
10. Extend **/ready** diagnostics with migration/readiness information without exposing tokens.
11. Add Developer diagnostics for:
    - current active trip/version;
    - ActivityKit authorization;
    - push-to-start token registered yes/no;
    - current activity count;
    - latest APNs delivery result.
12. Keep the static and dynamic Activity payload far below Apple's 4 KB limit.

### Verification

1. Run failure tests for:
   - APNs 410 Unregistered;
   - bad topic;
   - wrong environment;
   - missing APNs credentials;
   - late update token;
   - Render restart;
   - app reinstall/token rotation;
   - Live Activities disabled;
   - user dismisses one Live Activity;
   - Live Activity reaches the eight-hour system limit while the backend trip remains active.
2. Confirm logs make the failing device and trip version identifiable without revealing credentials.
3. Confirm a normal Shopping mutation still succeeds when every ActivityKit send fails.

### Exit Criteria

- A stale or invalid token cannot break Shopping.
- An old active trip has an explicit, user-visible End/recovery path and is never silently declared complete by a read.
- Production failures can be traced by trip ID, resident, event type, and APNs reason.

## Stage 9: Test, Deploy, And Prove The Full Two-Phone Story

### Goal

Deploy in dependency order and prove the exact locked-phone experience from the built artifact.

### Implementation And Deployment Order

1. Finish unit, integration, and view-model tests.
2. Build the iOS app and Widget extension without signing for compile coverage.
3. Run the migration against a disposable database first.
4. Deploy the checked-in migration and compatible API together through the current Docker flow, which runs **apps/api/scripts/run-migrations.mjs** before starting the server.
5. Verify Render startup applied the migration through deploy logs, **schema_migrations**, and **/ready**.
6. Verify:
   - **/health**
   - **/ready**
   - active-trip routes;
   - registered ordinary device count;
   - ActivityKit token registration for both residents.
7. Install signed Debug builds on both physical phones and run the full matrix.
8. Build the distribution archive and export the IPA.
9. Verify the exported IPA, not only the archive:
   - **LevyHome.app/PlugIns/LevyHomeWidgets.appex** exists;
   - the extension is signed by the expected team;
   - the host app has **NSSupportsLiveActivities = true**;
   - the app's production **aps-environment** is correct;
   - **LevyHomeAPIBaseURL** is the intended production API;
   - the host and extension bundle IDs, embedded provisioning profiles, Info keys, and code-sign entitlements are correct.
10. Install through TestFlight on both phones and repeat both start directions.
11. If available, visually inspect mirrored presentation on Apple Watch, Mac, and CarPlay; those surfaces must not reveal more than the approved counts and estimate.

### Required End-To-End Matrix

| Scenario | Expected result |
| --- | --- |
| Josh starts, both apps open | One trip; both Live Activities appear. |
| Josh starts, Mallory locked | Mallory's Live Activity appears without opening Levy Home. |
| Mallory starts, Josh app terminated | Josh's Live Activity appears after prior one-time token registration. |
| Both tap New together | One shared trip; no duplicate activities. |
| Josh checks an item | Both displays converge; no ordinary per-item pickup push. |
| Mallory unchecks it | Counts and estimate reverse on both displays. |
| Item with no price is picked | Count changes; total remains honest and price coverage is indicated. |
| Item is added mid-trip | Remaining count increases and open Shopping screens update. |
| Render restarts mid-trip | Trip survives and the next snapshot/update recovers. |
| Josh ends | Both activities end; Mallory alone gets the summary. |
| Mallory ends | Both activities end; Josh alone gets the summary. |
| End request repeats | No duplicate trip summary. |
| Live Activities disabled on one phone | Trip and other phone work; disabled phone gets an honest in-app status. |

### Exit Criteria

- Every required scenario passes on the two TestFlight-installed phones.
- The exported IPA contains the signed extension and correct production configuration.
- The plan's estimate wording matches what appears on both the Lock Screen and final summary.

## Testing Inventory

### iOS Unit Tests

Add coverage for:

- Activity content-state mapping from API trip snapshot.
- Currency formatting from integer cents.
- Priced, unpriced, and mixed-price presentation.
- Local start dedupe by trip ID.
- Local recovery and orphan cleanup.
- Live Activities disabled behavior.
- Shopping view-model start, active, end, and failure states.
- Deep-link selection of the Shopping tab.
- Realtime trip message decoding.

Suggested files:

- **LevyHomeTests/ShoppingTripActivityStateTests.swift**
- **LevyHomeTests/ShoppingLiveActivityCoordinatorTests.swift**
- **LevyHomeTests/ShoppingListViewModelTests.swift**
- **LevyHomeTests/RootNavigationTests.swift**

### API Unit And Integration Tests

Add coverage for:

- Trip repository start/aggregate/end.
- One-active-trip database constraint.
- Transaction rollback.
- Every item transition.
- Price estimator parity with the documented current UI rule.
- Trip routes and validation.
- WebSocket trip messages.
- Token registration and rotation.
- Exact ActivityKit APNs headers and payloads.
- Permanent versus transient APNs failures.
- Counterpart summary routing.
- Summary retry/dedupe.
- Server start/stop behavior for the summary dispatcher.

Suggested files:

- **apps/api/test/unit/repositories/shoppingTripRepository.test.ts**
- **apps/api/test/unit/services/shopping/shoppingTripService.test.ts**
- **apps/api/test/unit/services/shopping/shoppingListMutationService.test.ts**
- **apps/api/test/unit/integrations/apple/activityKitPushSender.test.ts**
- **apps/api/test/unit/services/notifications/notificationService.test.ts**
- **apps/api/test/integration/routes/shoppingTripRoutes.test.ts**

## Important Constraints

1. A Live Activity can remain active for at most eight hours. iOS can keep an ended presentation on the Lock Screen for up to four additional hours, but that system display limit does not itself complete Levy Home's backend trip.
2. Static plus dynamic Activity content is limited to 4 KB.
3. The Widget extension cannot fetch Levy Home's API directly. All state comes from the app or ActivityKit pushes.
4. APNs delivery is best effort and can be delayed, reordered, or rejected.
5. A push-to-start token is not an ordinary device token and is not a per-activity update token.
6. ActivityKit tokens can rotate; the app must continuously observe and upload replacements.
7. A user can dismiss the Live Activity without ending the backend trip.
8. Live Activity availability is controlled by the user and iOS. Levy Home can recover and explain, but it cannot force the system to display one.
9. The current dollar values are estimates. Calling them “spent” or “actual total” would be incorrect.
10. The current API has no application-level authentication. This feature should validate device/resident associations and protect token logs, but broader API authentication remains a separate security project.

## Explicitly Deferred

- Actual checkout-price entry.
- Receipt scanning or OCR.
- Store selection for a trip.
- Per-item actual price editing.
- Tax, coupons, loyalty discounts, and weighted produce.
- Interactive item checkoff directly from the Live Activity.
- Home Screen Shopping widget.
- Apple Watch app-specific controls.
- General multi-household, account, or arbitrary participant support.
- Automatic backend trip completion or cancellation solely because the Live Activity reached Apple's display limit.
- Broadcast ActivityKit channels.
- Frequent-update mode.
- Historical shopping-trip UI and analytics.
- A separate notification preference solely for trip summaries.
- iOS 27 beta landscape-specific compact/minimal Dynamic Island tuning; keep labels short now and run that beta QA separately.

## Recommended Future Follow-Ups

After the v1 feature is stable:

1. Add a Shopping History screen backed by the already-persisted trip snapshots.
2. Add an optional actual total at End Shop.
3. Add a store selection so the estimate uses the chosen store rather than the current conservative cross-store rule.
4. Add a last-minute item notification that deep-links to the active trip when the other resident adds something while someone is shopping.
5. Consider an interactive Live Activity action only after authentication, mutation idempotency, and accidental-tap UX are proven.

## Primary Apple References

- [ActivityKit](https://developer.apple.com/documentation/activitykit)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Starting and updating Live Activities with ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- [Activity authorization](https://developer.apple.com/documentation/activitykit/activityauthorizationinfo)
- [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
- [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
- [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Live Activities design guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- [Setting up broadcast push notifications](https://developer.apple.com/documentation/usernotifications/setting-up-broadcast-push-notifications)
