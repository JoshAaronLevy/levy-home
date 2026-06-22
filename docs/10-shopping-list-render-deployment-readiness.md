# Shopping List Render Deployment Readiness

This is the Stage 11 deployment proof guide for shopping list CRUD plus WebSocket live updates on Render.

It builds on the local proof in `docs/09-shopping-list-realtime-local-verification.md` and focuses on the deployed API at:

```text
https://levy-home.onrender.com
```

## Render Platform Notes

Current Render docs confirm that web services can accept inbound WebSocket connections from the public internet, and that public WebSocket clients should use `wss://` instead of `ws://` because plain `ws://` can fail on Render's TLS redirect.

Render does not impose a fixed maximum WebSocket duration, but long-lived connections can still drop when an instance shuts down or is replaced during deploys, maintenance, or network interruption. The iOS client already has reconnect logic and refetches a fresh snapshot after reconnect.

For the current in-memory broadcaster, keep the API service at one running instance. Render can load-balance traffic across multiple instances, and this repo does not yet have cross-instance fan-out. Add Postgres `LISTEN` / `NOTIFY` or a managed pub/sub service before scaling the API above one instance.

References:

- https://render.com/docs/websocket
- https://render.com/docs/uptime-best-practices
- https://render.com/docs/scaling

## Render Service Checklist

In the Render dashboard, confirm:

| Setting | Expected value |
| --- | --- |
| Service type | Web Service |
| Source | Repo root |
| Runtime/deploy path | Root `Dockerfile` |
| Public URL | `https://levy-home.onrender.com` |
| Instance count | `1` until cross-instance broadcasting exists |
| `DATABASE_URL` | Configured in Render environment |
| `HOME_ASSISTANT_MODE` | `mock` or correctly configured `live` |
| `PORT` | Can be omitted; API defaults to `4000` |

The root `Dockerfile` builds `apps/api` and starts the production process directly:

```text
node apps/api/dist/server.js
```

That direct Node start path keeps shutdown logs cleaner than an npm wrapper and lets `apps/api/src/server.ts` handle `SIGTERM` / `SIGINT` gracefully.

## Passive Deployed Verification

Run this from repo root after Render has deployed the current branch:

```sh
node scripts/verify-shopping-list-render-readiness.mjs \
  --api-base-url https://levy-home.onrender.com
```

Expected output includes:

```text
/health ok service=levy-home-api ...
/api/shopping-list ok items=... stores=... categories=...
WebSocket hello ok connection=...
WebSocket snapshot_required ok reason=connected
WebSocket presence_changed ok viewers=Stage 11 verifier(stage11-render-verifier)
Render shopping-list readiness checks passed.
```

This default check is read-only except for ephemeral WebSocket presence. It confirms:

- Render routes HTTPS requests to the API.
- Render env has a usable `DATABASE_URL`.
- `GET /api/shopping-list` returns Neon-backed data.
- `wss://levy-home.onrender.com/api/shopping-list/live` upgrades successfully.
- Presence subscription works through the deployed socket.

## Deployed REST Broadcast Proof

Only run this when it is acceptable to create, update, and delete one temporary row in the real shopping list database:

```sh
node scripts/verify-shopping-list-render-readiness.mjs \
  --api-base-url https://levy-home.onrender.com \
  --write-proof
```

Expected additional output:

```text
Write proof create ok itemId=...
Write proof update ok itemId=...
Write proof delete ok itemId=...
```

This proves deployed REST mutations broadcast over the deployed WebSocket by matching mutation IDs for:

- `item_created`
- `item_updated`
- `item_deleted`

If the script fails after creating a proof item, it attempts to delete that item before exiting.

## Manual Deployed WebSocket Client

For a longer terminal watch session:

```sh
node scripts/shopping-list-live-client.mjs \
  --api-base-url https://levy-home.onrender.com \
  --viewer-id mallory \
  --display-name Mallory
```

Keep the terminal open, then change an item in the app or with `curl`. The terminal should print deployed `item_updated` or presence messages.

Use `Ctrl-C` to close the client cleanly.

## App Build URL Proof

The app target source setting currently points at Render:

```text
LEVY_HOME_API_BASE_URL = "https://levy-home.onrender.com";
```

Before TestFlight or physical-device proof, verify the built app bundle, not just source settings. For a simulator proof build:

```sh
LEVY_HOME_API_BASE_URL=https://levy-home.onrender.com \
  scripts/build-install-simulator.sh
```

Expected script output includes:

```text
Built app API base URL: https://levy-home.onrender.com
```

For a TestFlight/archive build, verify the archived app's `Info.plist` contains:

```text
LevyHomeAPIBaseURL = https://levy-home.onrender.com
```

## Physical Device Proof

Use two physical devices or one physical device plus the terminal WebSocket client.

Josh device:

1. Install the Render-pointed build.
2. Open Preferences.
3. Set Device Owner to `Josh`.
4. Open Shopping.

Mallory device:

1. Install the same Render-pointed build.
2. Open Preferences.
3. Set Device Owner to `Mallory`.
4. Open Shopping.

Expected:

- Josh sees `Mallory viewing`.
- Mallory sees `Josh viewing`.
- Adding, editing, marking picked up, or deleting an item on one device updates the other without pull-to-refresh.
- Closing one app clears presence on the other device after disconnect or timeout.
- If Render restarts during deploy, the app reconnects and refreshes from `GET /api/shopping-list`.

## Restart And Reconnect Proof

When you are ready to prove restart behavior:

1. Open Shopping on a physical device or simulator pointed at Render.
2. Keep `scripts/shopping-list-live-client.mjs` connected to Render as the other viewer.
3. Trigger a manual deploy or restart in Render.
4. Watch for the app to reconnect.
5. Confirm the list still loads and presence can reappear after the socket reconnects.

Expected:

- Existing WebSocket connections drop during old-instance shutdown.
- The app reconnects through `ShoppingListLiveService`.
- The view model handles `snapshot_required` or reconnect snapshot refresh without losing the shopping list.
- Pull-to-refresh remains available if reconnect takes longer than expected.

## Evidence Checklist

Record the deployed pass here:

| Check | Result | Notes |
| --- | --- | --- |
| Render deploy completed | Pending |  |
| Render service instance count is `1` | Pending |  |
| Render `DATABASE_URL` is configured | Pending |  |
| `GET /health` succeeds on Render | Pending |  |
| `GET /api/shopping-list` returns Neon data | Pending |  |
| `wss://levy-home.onrender.com/api/shopping-list/live` connects | Pending |  |
| Deployed WebSocket receives `hello` | Pending |  |
| Deployed WebSocket receives `snapshot_required` | Pending |  |
| Deployed WebSocket receives `presence_changed` | Pending |  |
| Optional deployed write proof receives `item_created` | Pending |  |
| Optional deployed write proof receives `item_updated` | Pending |  |
| Optional deployed write proof receives `item_deleted` | Pending |  |
| Built app bundle points at `https://levy-home.onrender.com` | Pending |  |
| Two physical devices see viewer presence | Pending |  |
| Two physical devices see live item updates | Pending |  |
| API restart causes reconnect and snapshot refresh | Pending |  |

## Troubleshooting

| Symptom | First check |
| --- | --- |
| Verifier rejects the URL | Use `https://...` for Render, not `http://...`. |
| WebSocket fails with redirect or handshake error | Confirm the client is using `wss://.../api/shopping-list/live`. |
| `/api/shopping-list` returns `database_not_configured` | Add `DATABASE_URL` to the Render service environment and redeploy. |
| Terminal WebSocket connects but app does not | Verify the built app bundle's `LevyHomeAPIBaseURL`; do not trust source settings alone. |
| Presence shows the wrong person | Set Device Owner in Preferences on each device. |
| One deployed client misses another client's update | Confirm the Render service has one instance. Multi-instance fan-out needs Postgres `LISTEN` / `NOTIFY` or managed pub/sub. |
| WebSocket drops during deploy | Expected; confirm reconnect and snapshot refresh happen after the new instance is live. |

## Completion Criteria

Stage 11 is ready when:

- Passive deployed verifier passes.
- Optional write proof passes, or the same create/update/delete sequence is proven from two devices.
- Built app/TestFlight artifact is proven to point at `https://levy-home.onrender.com`.
- Two physical devices can see presence and item updates over the deployed WebSocket.
- Restart/redeploy causes reconnect and a fresh list snapshot instead of a broken list.
