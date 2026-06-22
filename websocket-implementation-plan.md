# Shopping List CRUD + WebSocket Implementation Plan

## Goal

Make the shopping list feel live for family use: if Josh and Mallory both have the app open, CRUD changes made on one device should appear on the other device without a manual refresh.

The API remains the source of truth. REST endpoints perform validated create, read, update, and delete mutations against Neon. WebSocket messages are used for live delivery of the committed server result to every connected app.

## Current Starting Point

- The backend is `apps/api`, an Express API using Neon through `apps/api/src/dbClient.ts`.
- `GET /api/shopping-list` already returns `shopping_list`, `stores`, and `categories`.
- The iOS List tab currently fetches the list with `APIClient.fetchShoppingList()`.
- The app already resolves relationships in code:
  - `shopping_list.store_ids` is JSONB containing an array of store IDs.
  - `shopping_list.category_id` is JSONB containing one category ID.
- There are no authenticated family users yet, so the first implementation should track a generated client/device connection ID for debugging, not true authorization.

## Design Principles

- Keep REST as the durable write path. WebSocket is a notification and synchronization channel, not the only way to mutate state.
- Broadcast only after the database transaction commits.
- Include enough metadata in every message for clients to ignore duplicates and recover from missed messages.
- Prefer full item payloads in mutation broadcasts over tiny patches. This keeps the Swift client simple and avoids partial-state bugs.
- Always support reconnect by re-fetching `GET /api/shopping-list`.
- Keep store/category relationships app-managed with JSONB IDs, as planned.
- Treat "who is viewing the list" as ephemeral WebSocket presence state. Do not store it in Neon, and keep the UI subtle so list items remain the main focus.

## Implementation Execution Rule for Codex

When implementing any stage from this plan, Codex should only review the requirements and make the needed code changes. Codex should not automatically write tests, run tests, run builds, run verification scripts, start the API solely for testing, boot Simulator, install the app on Simulator, launch Simulator, or launch the app.

This is intentional because the test suite and Simulator are slow and resource-heavy on Josh's computer. After code changes are complete, Codex should stop and report what changed, what still needs user verification, and any specific manual test steps Josh may choose to run personally.

Do not run commands such as:

- `npm test`
- `npm run api:test`
- `xcodebuild test`
- `scripts/build-install-simulator.sh`
- `scripts/verify-home-assistant-activity-simulator.sh`
- `xcrun simctl boot`
- `xcrun simctl install`
- `xcrun simctl launch`
- `open -a Simulator`

Only run tests, builds, simulator commands, local servers, or verification scripts if Josh explicitly asks for that in the current chat session.

## Stage 1: Stabilize Database Semantics

Objective: make every shopping-list mutation produce a reliable server-owned timestamp and ordering signal.

Backend changes:

- Confirm the API, not the iOS app, owns `created_at` and `updated_at`.
- On create, set `created_at = now()` and `updated_at = now()`.
- On update, set `updated_at = now()` even if the client only changed one field.
- On delete, return enough data for the WebSocket event before removing the row.

Recommended Neon migration:

```sql
ALTER TABLE shopping_list
  ALTER COLUMN quantity SET DEFAULT 1,
  ALTER COLUMN purchased SET DEFAULT false,
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET DEFAULT now();

ALTER TABLE stores
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE categories
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
```

Optional but recommended for cleaner sync:

```sql
ALTER TABLE shopping_list
  ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;
```

If we add `version`, every item update increments it. The client can then apply an incoming WebSocket item only if its version is newer than the local item.

Acceptance criteria:

- Existing `GET /api/shopping-list` still returns the current Soy Milk row.
- Created/updated rows always have useful timestamps.
- No join tables or foreign keys are introduced.

## Stage 2: Add Backend CRUD Store Methods

Objective: move all shopping-list writes into one tested store layer.

Files likely touched:

- `apps/api/src/contracts.ts`
- `apps/api/src/shoppingListStore.ts`
- `apps/api/src/shoppingListStore.test.ts`
- `apps/api/src/validation.ts`

Add request/response contracts:

- `ShoppingListItemLookupResponse`
- `CreateShoppingListItemRequest`
- `UpdateShoppingListItemRequest`
- `DeleteShoppingListItemResponse`
- `ShoppingListMutationResponse`

Store methods:

- `createItem(request)`
- `updateItem(id, request)`
- `deleteItem(id)`
- `fetchItem(id)`
- `findItemByName(name)`
- Optionally later:
  - `createStore(request)`
  - `updateStore(id, request)`
  - `deleteStore(id)`
  - `createCategory(request)`
  - `updateCategory(id, request)`
  - `deleteCategory(id)`

Validation rules:

- `name`: required for create, trimmed, non-empty.
- `brand`: optional, trimmed, empty becomes `null`.
- `quantity`: integer, minimum `1`.
- `notes`: optional, trimmed, empty becomes `null`.
- `purchased`: boolean, default `false`.
- `storeIds`: array of integers, default `[]`.
- `categoryId`: integer or `null`.

JSONB write rules:

- Store `storeIds` as a JSON array in `store_ids`.
- Store `categoryId` as a single JSON value in `category_id`.
- Do not add join tables.

Acceptance criteria:

- Store unit tests cover lookup, create, partial update, delete, JSONB mapping, defaults, and invalid values.
- Store methods return API-shaped rows, not raw database rows.

## Stage 3: Add REST CRUD Endpoints

Objective: make the API usable even before WebSocket is connected.

Endpoints:

- `GET /api/shopping-list`
- `GET /api/shopping-list/items/lookup?name=<item-name>`
- `POST /api/shopping-list/items`
- `PATCH /api/shopping-list/items/:itemId`
- `DELETE /api/shopping-list/items/:itemId`

Duplicate lookup:

- `GET /api/shopping-list/items/lookup?name=milk` should return a normalized exact-match result before the user submits a create request.
- The lookup should compare against both needed and picked-up items.
- Normalize by trimming whitespace and comparing case-insensitively.
- Consider adding a database index or constraint on normalized item names so `Milk`, `milk`, and ` milk ` do not become separate family-list items.
- Suggested response:

```json
{
  "ok": true,
  "query": "milk",
  "match": {
    "id": 3,
    "name": "Whole milk",
    "purchased": true,
    "quantity": 1,
    "storeIds": [2],
    "categoryId": 1
  }
}
```

- If no match exists, return `"match": null`.

Optional later endpoints:

- `POST /api/shopping-list/stores`
- `PATCH /api/shopping-list/stores/:storeId`
- `DELETE /api/shopping-list/stores/:storeId`
- `POST /api/shopping-list/categories`
- `PATCH /api/shopping-list/categories/:categoryId`
- `DELETE /api/shopping-list/categories/:categoryId`

Response shape for mutations:

```json
{
  "ok": true,
  "item": {
    "id": 1,
    "name": "Soy Milk",
    "brand": null,
    "quantity": 2,
    "notes": null,
    "purchased": false,
    "createdAt": "2026-06-22T20:00:00.000Z",
    "updatedAt": "2026-06-22T20:05:00.000Z",
    "storeIds": [2],
    "categoryId": 1
  },
  "mutationId": "client-generated-or-server-generated-id",
  "generatedAt": "2026-06-22T20:05:00.000Z"
}
```

Failure cases:

- `400 invalid_shopping_item`
- `404 shopping_item_not_found`
- `409 duplicate_shopping_item` if a create request races with another client and the item already exists
- `409 shopping_item_conflict` if version checks are added
- `503 database_not_configured`

Acceptance criteria:

- CRUD works from curl against the local API.
- Duplicate lookup returns an existing needed or picked-up item before create submission.
- The List tab can still load via `GET /api/shopping-list`.
- No WebSocket logic is required for basic add/edit/delete to work.

## Stage 4: Add API WebSocket Hub

Objective: let connected iOS clients receive committed shopping-list changes and lightweight viewer presence updates.

Backend dependency:

- Add `ws` and `@types/ws` to `apps/api`.

Architecture:

- Keep Express for HTTP.
- Attach a WebSocket server to the same Node HTTP server in `startServer`.
- Route WebSocket upgrades for one path, for example:
  - `GET ws://localhost:4000/api/shopping-list/live`
  - `GET wss://levy-home.onrender.com/api/shopping-list/live`

New backend module:

- `apps/api/src/shoppingListRealtime.ts`

Responsibilities:

- Track connected clients.
- Send a `hello` message after connection.
- Accept a client `subscribe` message that identifies the viewer for presence.
- Track active viewers separately from raw sockets, because the same person may reconnect or briefly have multiple app sessions.
- Broadcast mutation events after REST mutations commit.
- Broadcast presence changes when a viewer opens the list, leaves the list, disconnects, or times out.
- Send heartbeat pings to detect dead sockets.
- Close sockets cleanly on `SIGTERM` / `SIGINT`.

Client-to-server message types:

```ts
type ShoppingListClientLiveMessage =
  | {
      type: 'subscribe';
      viewerId: string;
      displayName: string;
      deviceName?: string;
    }
  | {
      type: 'presence_ping';
      viewerId: string;
    };
```

The first app version can use stable values like `josh` and `mallory` for `viewerId`.

Presence model:

```ts
type ShoppingListViewerPresence = {
  viewerId: string;
  displayName: string;
  connectionId: string;
  deviceName?: string;
  lastSeenAt: string;
};
```

Message types:

```ts
type ShoppingListLiveMessage =
  | {
      type: 'hello';
      connectionId: string;
      serverTime: string;
    }
  | {
      type: 'presence_changed';
      viewers: ShoppingListViewerPresence[];
      serverTime: string;
    }
  | {
      type: 'snapshot_required';
      reason: 'connected' | 'missed_messages' | 'server_restart';
      serverTime: string;
    }
  | {
      type: 'item_created';
      item: ShoppingListItem;
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'item_updated';
      item: ShoppingListItem;
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'item_deleted';
      itemId: number;
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'stores_changed';
      stores: ShoppingStore[];
      mutationId: string;
      serverTime: string;
    }
  | {
      type: 'categories_changed';
      categories: ShoppingCategory[];
      mutationId: string;
      serverTime: string;
    };
```

Broadcast timing:

1. Validate REST request.
2. Write to Neon.
3. Read/return the committed row.
4. Send the HTTP response.
5. Broadcast the corresponding WebSocket event.

The HTTP response and WebSocket broadcast should contain the same committed item payload.

Presence behavior:

- Presence is scoped to the shopping list screen, not the whole app.
- On subscribe, add or refresh the viewer and broadcast `presence_changed`.
- On clean close, remove that connection and broadcast `presence_changed`.
- On heartbeat timeout, expire the connection and broadcast `presence_changed`.
- If one person has multiple active connections, the client UI should still show that person once.
- The first implementation can identify Josh/Mallory through a local app setting or device-specific default. True auth can come later.

Acceptance criteria:

- A test WebSocket client receives `item_updated` when another client sends `PATCH`.
- A test WebSocket client receives `presence_changed` when another viewer subscribes or disconnects.
- A connected client can disconnect without crashing the API.
- WebSocket shutdown is included in existing API graceful shutdown behavior.

## Stage 5: Add iOS Shopping List API Mutations

Objective: give the app first-class REST methods for CRUD.

Files likely touched:

- `LevyHome/Models/APIRequests.swift`
- `LevyHome/Models/APIResponses.swift`
- `LevyHome/Services/APIClient.swift`
- `LevyHomeTests/APIClientTests.swift`
- `LevyHomeTests/APIModelDecodingTests.swift`

New API client methods:

- `lookupShoppingListItem(named:)`
- `createShoppingListItem(_ request)`
- `updateShoppingListItem(id, _ request)`
- `deleteShoppingListItem(id)`

New Swift models:

- `ShoppingListItemLookupResponse`
- `CreateShoppingListItemRequest`
- `UpdateShoppingListItemRequest`
- `ShoppingListMutationResponse`
- `DeleteShoppingListItemResponse`

Mutation ID:

- Generate a UUID per app mutation.
- Send it with the REST request, either as:
  - `mutationId` in the JSON body, or
  - `X-Levy-Home-Mutation-ID` header.
- Echo it in the WebSocket broadcast.
- The initiating device can use this to avoid double-animating its own update.

Acceptance criteria:

- API client tests assert the correct method, path, JSON body, and decoded response.
- Lookup tests assert item names are query-encoded correctly and decode `match` / no-match responses.
- App code has REST mutation primitives before UI controls are enabled.

## Stage 6: Add iOS WebSocket Service

Objective: maintain a live subscription while the List tab is active.

New service:

- `LevyHome/Services/ShoppingListLiveService.swift`

Implementation:

- Use `URLSessionWebSocketTask`.
- Convert API base URL:
  - `http://localhost:4000` -> `ws://localhost:4000/api/shopping-list/live`
  - `https://levy-home.onrender.com` -> `wss://levy-home.onrender.com/api/shopping-list/live`
- Decode messages into `ShoppingListLiveMessage`.
- Expose messages through `AsyncStream<ShoppingListLiveMessage>` or an observable service.
- Send a `subscribe` message with the current viewer identity after the socket opens.
- Send periodic `presence_ping` messages while the List tab remains active.
- Reconnect with exponential backoff.
- On reconnect, trigger a fresh `GET /api/shopping-list` snapshot before applying live messages.

Lifecycle:

- Connect when `ShoppingListViewModel.loadIfNeeded()` succeeds or when the List tab appears.
- Disconnect when the List tab disappears only if we want to conserve resources.
- A simpler first version can keep the socket alive for the app session.

Fallback:

- If WebSocket connection fails, keep REST CRUD functional.
- Show a small degraded state only if needed, for example `Live updates paused`.
- Pull-to-refresh remains available.

Acceptance criteria:

- Unit tests cover URL conversion, message decoding, presence message encoding, and reconnect policy.
- The service does not crash on unknown message types.
- The view model can consume a fake stream in tests.

## Stage 7: Update ShoppingListViewModel for Live State

Objective: merge REST loads, local mutations, and WebSocket events into one consistent list.

View model responsibilities:

- Load initial snapshot using `fetchShoppingList()`.
- Keep `items`, `stores`, and `categories` as the single UI state.
- Apply incoming live events:
  - `item_created`: insert or replace item by ID.
  - `item_updated`: replace item by ID.
  - `item_deleted`: remove item by ID.
  - `presence_changed`: update active viewers without changing list item state.
  - `stores_changed`: replace stores array.
  - `categories_changed`: replace categories array.
  - `snapshot_required`: call `fetchShoppingList()`.
- Preserve current search and category filter while data changes.
- Keep rows sorted with needed items above picked-up items.
- Keep active viewer display state separate from item state so presence updates do not cause unnecessary row churn.

Optimistic UI policy:

- Stage 7A: no optimistic updates. Wait for REST response, then update UI. This is simpler and safer.
- Stage 7B: add optimistic updates after CRUD correctness is proven.

Conflict policy:

- Last committed server write wins for the first implementation.
- If `version` is added, ignore WebSocket item updates older than the local item version.
- If a mutation fails, show the existing error banner and leave the last confirmed server state.

Acceptance criteria:

- If Mallory changes Soy Milk from quantity 1 to 2, Josh sees quantity 2 without pull-to-refresh.
- If Mallory has the List tab open, Josh sees a subtle indication that Mallory is viewing the list.
- If Mallory leaves the List tab or loses connection, Josh's presence indicator clears after the disconnect or timeout.
- If Josh has a filter active, incoming updates do not reset his filter.
- If the WebSocket reconnects, the app resyncs from `GET /api/shopping-list`.

## Stage 8: Add Subtle Viewer Presence UI

Objective: show whether the other family member is currently viewing the list without taking attention away from the items.

UI placement:

- Add a small presence indicator inside the existing summary panel or near the live-status badge.
- Avoid a large banner, modal, or dedicated row.
- Keep the list items as the dominant screen content.

Recommended copy:

- If Mallory is viewing and Josh is the current viewer: `Mallory viewing`.
- If Josh is viewing and Mallory is the current viewer: `Josh viewing`.
- If both are somehow represented by multiple devices, still show the person once.
- If nobody else is viewing, show nothing or keep the existing compact live status only.

Visual treatment:

- Use a small `person.2` or `eye` icon.
- Use the existing `StatusBadgeView` style if it fits without crowding.
- Prefer muted/accent styling over warning or success treatment.
- Do not animate aggressively; a gentle appearance/disappearance is enough.

Viewer identity:

- Add a lightweight local setting for "This device is Josh" or "This device is Mallory" if the app cannot infer it safely.
- Store the setting locally on-device.
- Send only `viewerId`, `displayName`, and optional `deviceName` over the WebSocket.
- Do not store viewer presence in Neon.

View model behavior:

- Filter the current viewer out of the visible "other viewers" indicator.
- Deduplicate viewers by `viewerId`.
- Expire stale viewers if the server sends no presence update after reconnect.
- Preserve the current list scroll position and filters when presence changes.

Acceptance criteria:

- With Josh and Mallory both on the List tab, each sees that the other is viewing.
- The indicator disappears after the other person leaves or times out.
- Presence changes do not reset search, selected category, scroll position, or list row state.
- The UI remains readable on small iPhone screens.

## Stage 9: Enable Add, Edit, Delete UI

Objective: expose full CRUD in the List tab after the data layer is reliable.

Mockup reference:

- Use [add-new-item-text-input.png](docs/mockups/shopping_list/add-new-item-text-input.png) as the visual reference for the add-new-item sheet.
- Preserve the low-friction flow shown in the mockup: item name first, compact quantity control, quick category/store chips, Notes as a true text input, and one prominent Add button.

Add item:

- Reintroduce the add button.
- Use database categories and stores instead of fixed mock categories.
- Let the user choose:
  - name
  - brand
  - quantity
  - notes
  - category
  - one or more stores

Debounced duplicate detection:

- As the user types in `What do we need?`, debounce duplicate lookup by roughly 250-350 ms after the latest keystroke.
- Do a fast local check against the current in-memory list immediately, then confirm with `GET /api/shopping-list/items/lookup?name=...`.
- Do not wait until the user taps Add to reveal a duplicate.
- If the item already exists in the needed section:
  - Show a small inline state such as `Already on the list` with the existing quantity/category.
  - Disable the primary `Add` action or change it to open the existing item.
- If the item exists in the picked-up section:
  - Show a small inline state such as `Picked up before` with a quick action like `Add back to needed`.
  - The quick action should `PATCH` the existing item, for example `purchased: false`, and optionally update quantity/store/category from the current sheet.
- If no duplicate exists:
  - Keep the primary button as `Add <Item Name>`.
  - Keep the flow fast and ready to submit.
- If the lookup request fails:
  - Do not block typing.
  - Fall back to local duplicate detection and still let the create request handle a final server-side duplicate guard.

Edit item:

- Tap row or use swipe action.
- Allow quantity stepper for the fastest common edit.
- Allow changing purchased state.
- Allow editing category/stores.

Delete item:

- Use destructive swipe action.
- Confirm only if the UI feels too easy to mis-tap.

Fast family-shopping interactions:

- Quantity stepper should call `PATCH`.
- Purchased toggle should call `PATCH`.
- While a mutation is in flight, disable only the affected row control.

Acceptance criteria:

- Add/edit/delete works without WebSocket connected.
- A user sees duplicate status while typing, before submitting.
- A picked-up item can be quickly added back to needed instead of creating a duplicate row.
- A second device sees the change live when WebSocket is connected.
- The initiator does not see duplicate rows or flicker.

## Stage 10: End-to-End Local Verification

Objective: document how Josh can personally prove the real family scenario before deploying. Codex should not run this stage automatically during implementation.

Local proof setup:

- Start local API with `DATABASE_URL`.
- Install the app on two simulators, or one simulator plus one curl/WebSocket client.
- Use API base URL `http://localhost:4000`.

Manual test script ideas:

- Terminal A: run the API.
- Terminal B: connect a WebSocket client to `/api/shopping-list/live`.
- Terminal C: call `PATCH /api/shopping-list/items/1` with `{ "quantity": 2 }`.
- Terminal D or second simulator: subscribe as Mallory and confirm Josh's app shows `Mallory viewing`.
- Confirm Terminal B receives `item_updated`.
- Confirm app UI updates without pull-to-refresh.
- Confirm the presence indicator clears when Terminal D or the second simulator disconnects.

Future automated tests, only if Josh explicitly requests them:

- Backend:
  - REST CRUD tests.
  - WebSocket broadcast tests.
  - WebSocket presence subscribe/update/disconnect tests.
  - WebSocket disconnect/cleanup tests.
- iOS:
  - request encoding/decoding tests.
  - live message decoding tests.
  - viewer presence merge/deduplication tests.
  - view-model event merge tests.
- Simulator:
  - build/install script still proves the API base URL baked into the app.

User-run verification criteria, when Josh chooses to run them:

- Full backend test suite passes.
- Full iOS test suite passes.
- Manual two-client live update proof passes.
- Manual two-client presence proof passes.

## Stage 11: Render Deployment Readiness

Objective: make live updates work outside the local simulator.

Render checks:

- Confirm the Render service supports WebSocket upgrades on the existing API service.
- Confirm `DATABASE_URL` is configured in Render.
- Confirm deployed `GET /api/shopping-list` returns real Neon data.
- Confirm `wss://<render-host>/api/shopping-list/live` connects.

Important deployment note:

- In-memory WebSocket fan-out works only for clients connected to the same running API instance.
- This is fine for a single Render instance.
- If the service later runs multiple instances, add a cross-instance broadcaster:
  - Postgres `LISTEN` / `NOTIFY`, or
  - a managed pub/sub service.

Acceptance criteria:

- TestFlight or device build points at the Render API URL, not `localhost`.
- Two physical devices can see live updates over the deployed WebSocket.
- Two physical devices can see subtle viewer presence over the deployed WebSocket.
- API restart causes clients to reconnect and refresh the list.

## Stage 12: Observability and Debuggability

Objective: make failures understandable when someone is standing in a store.

Backend logs:

- Log WebSocket connect/disconnect counts.
- Log presence subscribe/disconnect by viewer ID and connection ID.
- Log mutation type, item ID, and mutation ID.
- Do not log secret env values.
- Do not log full notes if they may contain private family text.

iOS logs:

- Record live connection state in the existing app log store.
- Record presence subscribe status and received viewer count.
- Record reconnect attempts.
- Record when a `snapshot_required` message triggers a refetch.

Useful UI states:

- `Live` when connected.
- `Mallory viewing` / `Josh viewing` when the other person is on the List tab.
- `Reconnecting` after a dropped socket.
- `Live updates paused` when repeated reconnects fail.
- Pull-to-refresh always remains available.

Acceptance criteria:

- A failed WebSocket does not make the list unusable.
- Logs make it clear whether the problem is REST, WebSocket, or database.

## Suggested Implementation Order

1. Stage 1: database timestamp/default cleanup.
2. Stage 2: backend CRUD store methods.
3. Stage 3: REST CRUD endpoints.
4. Stage 5: iOS REST mutation methods.
5. Stage 9 partial: enable add/edit/delete using REST only.
6. Stage 4: backend WebSocket hub.
7. Stage 6: iOS WebSocket service.
8. Stage 7: view model live event merge.
9. Stage 8: subtle viewer presence UI.
10. Stage 9: complete add/edit/delete UI.
11. Stage 10: local two-client proof.
12. Stage 11: Render deployment proof.
13. Stage 12: polish observability and degraded states.

This order gets useful CRUD into the app before live sync, then adds WebSocket without making basic list editing depend on it.

## First Milestone Worth Shipping

The first family-usable milestone should include:

- REST create/update/delete for `shopping_list` items.
- Quantity and purchased controls in the app.
- Debounced duplicate detection while entering a new item name, including a quick way to add picked-up items back to needed.
- WebSocket `item_created`, `item_updated`, and `item_deleted` broadcasts.
- WebSocket `presence_changed` broadcasts.
- Subtle `Mallory viewing` / `Josh viewing` indicator when the other person has the List tab open.
- Reconnect with full snapshot refresh.
- Local two-client proof where changing quantity on one client updates the other without refresh and presence appears/disappears correctly.

Store/category CRUD can follow after item CRUD is stable unless category/store management is blocking real grocery use.
