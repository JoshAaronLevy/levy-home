# Shopping List Realtime Local Verification

This is the Stage 10 manual proof guide for the shopping list CRUD plus WebSocket work. It proves the family scenario locally before Render deployment: one client changes the shared list, another connected client sees the committed server result without pull-to-refresh, and presence appears and clears.

## What This Proves

- The local API can read and mutate the Neon-backed shopping list.
- `/api/shopping-list/live` accepts WebSocket clients.
- REST mutations broadcast `item_created`, `item_updated`, and `item_deleted`.
- Presence broadcasts `presence_changed` when another viewer subscribes or disconnects.
- The iOS List tab still works through REST if the WebSocket client is not connected.

## Prerequisites

- `apps/api/.env` exists and has a real `DATABASE_URL`.
- Local API port is `4000`.
- Dependencies are installed with `npm install`.
- Xcode and at least one available iPhone simulator are installed if you want to include the app UI.

Do not print or paste the real `DATABASE_URL`. The examples below only call the local API.

## Terminal A: Start The Local API

From repo root:

```sh
cd /Users/joshlevy/Desktop/levy-home
npm run api:dev
```

Expected startup signal:

```text
Levy Home API listening on http://localhost:4000
```

In another terminal, confirm the API and shopping list respond:

```sh
curl -sS http://localhost:4000/health
curl -sS http://localhost:4000/api/shopping-list
```

If `/api/shopping-list` returns `database_not_configured`, stop here and fix `DATABASE_URL` in `apps/api/.env`.

## Terminal B: Connect A WebSocket Viewer

Use the local helper client:

```sh
node scripts/shopping-list-live-client.mjs \
  --viewer-id mallory \
  --display-name Mallory
```

Expected output includes:

```text
hello connection=...
snapshot_required reason=connected
presence_changed viewers=Mallory(mallory)
```

Keep this terminal running. It prints item and presence broadcasts as they arrive.

To represent Josh instead:

```sh
node scripts/shopping-list-live-client.mjs \
  --viewer-id josh \
  --display-name Josh
```

Stop the client with `Ctrl-C`. Connected app clients should receive a `presence_changed` update shortly after it disconnects.

## Terminal C: Prove CRUD Broadcasts

Create a temporary proof item:

```sh
PROOF_NAME="Stage 10 proof $(date +%H%M%S)"
CREATE_RESPONSE="$(
  curl -sS -X POST http://localhost:4000/api/shopping-list/items \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${PROOF_NAME}\",
      \"quantity\": 1,
      \"notes\": \"Local realtime proof\",
      \"mutationId\": \"manual-stage10-create-$(date +%s)\"
    }"
)"
printf '%s\n' "$CREATE_RESPONSE"
ITEM_ID="$(
  printf '%s' "$CREATE_RESPONSE" |
    node -e 'let input = ""; process.stdin.on("data", chunk => input += chunk); process.stdin.on("end", () => console.log(JSON.parse(input).item.id));'
)"
echo "Proof item id: $ITEM_ID"
```

Expected in Terminal B:

```text
item_created #<id> "Stage 10 proof ..." qty=1 purchased=false mutation=...
```

Update the item quantity:

```sh
curl -sS -X PATCH "http://localhost:4000/api/shopping-list/items/${ITEM_ID}" \
  -H "Content-Type: application/json" \
  -d "{
    \"quantity\": 2,
    \"mutationId\": \"manual-stage10-update-$(date +%s)\"
  }"
```

Expected in Terminal B:

```text
item_updated #<id> "Stage 10 proof ..." qty=2 purchased=false mutation=...
```

Mark it picked up:

```sh
curl -sS -X PATCH "http://localhost:4000/api/shopping-list/items/${ITEM_ID}" \
  -H "Content-Type: application/json" \
  -d "{
    \"purchased\": true,
    \"mutationId\": \"manual-stage10-purchased-$(date +%s)\"
  }"
```

Expected in Terminal B:

```text
item_updated #<id> "Stage 10 proof ..." qty=2 purchased=true mutation=...
```

Clean up the proof item:

```sh
curl -sS -X DELETE "http://localhost:4000/api/shopping-list/items/${ITEM_ID}" \
  -H "X-Levy-Home-Mutation-ID: manual-stage10-delete-$(date +%s)"
```

Expected in Terminal B:

```text
item_deleted itemId=<id> mutation=...
```

## Option 1: One Simulator Plus Terminal Viewer

This is the fastest app-facing proof.

Build, install, and launch the app against the local API:

```sh
LEVY_HOME_API_BASE_URL=http://localhost:4000 \
  LAUNCH_APP=true \
  scripts/build-install-simulator.sh
```

In the app:

1. Open Preferences.
2. Open Device Owner.
3. Choose `Josh`.
4. Open the Shopping tab.

In Terminal B, keep the Mallory WebSocket client running:

```sh
node scripts/shopping-list-live-client.mjs \
  --viewer-id mallory \
  --display-name Mallory
```

Expected:

- The Shopping summary panel shows `Mallory viewing`.
- Running the Terminal C create/update/delete commands updates the Shopping tab without pull-to-refresh.
- Pressing `Ctrl-C` in Terminal B clears `Mallory viewing`.

## Option 2: Two Simulators

Use this when you want the closest local family scenario.

List available simulators:

```sh
xcrun simctl list devices available
```

Install and launch the app on two devices. Replace the UUIDs with real simulator IDs:

```sh
SIMULATOR_DEVICE_ID=JOSH_SIMULATOR_UUID \
  LEVY_HOME_API_BASE_URL=http://localhost:4000 \
  LAUNCH_APP=true \
  scripts/build-install-simulator.sh

SIMULATOR_DEVICE_ID=MALLORY_SIMULATOR_UUID \
  LEVY_HOME_API_BASE_URL=http://localhost:4000 \
  LAUNCH_APP=true \
  scripts/build-install-simulator.sh
```

In the first simulator:

1. Preferences -> Device Owner -> `Josh`.
2. Open Shopping.

In the second simulator:

1. Preferences -> Device Owner -> `Mallory`.
2. Open Shopping.

Expected:

- Josh sees `Mallory viewing`.
- Mallory sees `Josh viewing`.
- Editing quantity, purchased state, or an item from one simulator updates the other without pull-to-refresh.
- Closing one simulator app clears the other simulator's presence indicator after disconnect or timeout.

## Duplicate UI Proof

With the app installed against `http://localhost:4000`:

1. Open Shopping.
2. Tap `+`.
3. Type the name of an existing needed item.
4. Confirm the sheet shows `Already on the list` before submit.
5. Type the name of an existing picked-up item.
6. Confirm the sheet shows `Picked up before`.
7. Tap `Add Back to Needed`.
8. Confirm the existing row moves back to needed instead of creating a duplicate.

## Evidence Checklist

Record the local pass here when you run it:

| Check | Result | Notes |
| --- | --- | --- |
| API starts on `http://localhost:4000` | Pending |  |
| `GET /api/shopping-list` returns Neon data | Pending |  |
| WebSocket client receives `hello` | Pending |  |
| WebSocket client receives `snapshot_required` | Pending |  |
| WebSocket client receives `presence_changed` on subscribe | Pending |  |
| WebSocket client receives `item_created` | Pending |  |
| WebSocket client receives `item_updated` after quantity PATCH | Pending |  |
| WebSocket client receives `item_updated` after purchased PATCH | Pending |  |
| WebSocket client receives `item_deleted` | Pending |  |
| Simulator app is built with `LevyHomeAPIBaseURL=http://localhost:4000` | Pending |  |
| App shows the other viewer's presence | Pending |  |
| App updates without pull-to-refresh | Pending |  |
| Presence clears after the other client disconnects | Pending |  |
| Duplicate needed item is detected before submit | Pending |  |
| Picked-up duplicate can be added back to needed | Pending |  |

## Troubleshooting

| Symptom | First check |
| --- | --- |
| `database_not_configured` | `DATABASE_URL` is missing from `apps/api/.env`. |
| WebSocket closes immediately with 404 | Confirm the URL is `ws://localhost:4000/api/shopping-list/live`. |
| App says network request failed | Confirm the app build printed `Built app API base URL: http://localhost:4000`. |
| Presence does not show in app | Confirm the app's Device Owner differs from the terminal viewer. Josh filters out Josh; Mallory filters out Mallory. |
| WebSocket shows updates but app does not | Pull to refresh once. If it works after refresh, the socket may have reconnected and should produce a fresh snapshot. |
| Duplicate create gets `409 duplicate_shopping_item` | Expected if the proof item name was reused. Change `PROOF_NAME` or delete the existing proof row. |

## Completion Criteria

Stage 10 is locally proven when:

- The backend REST/WebSocket terminal proof passes.
- At least one app client shows presence from another client.
- At least one app client receives a create/update/delete change without pull-to-refresh.
- The duplicate-entry sheet detects needed and picked-up duplicates before submit.
