# Neon database usage audit

## Bottom line

The strongest code-level explanation for sustained Neon spend was the always-on delivery polling, not ordinary household-list use. Before the implementation recorded below, two independent workers polled the database every five seconds regardless of whether any push delivery existed. Together they executed approximately **4.15 million Postgres commands in a 30-day month per API process while idle**. The to-do reminder worker still adds roughly **403,200 commands/month** in its current schedule, including repeated work for the same reminder window.

Those counts are derived from source code, not from the Neon billing dashboard or production query telemetry. They show execution frequency and likely compute pressure; they cannot assign a dollar amount or prove which Neon billing meter produced the current $40+ charge. If Render has more than one API process/replica, multiply the worker estimates by the number of processes.

The lowest-risk remaining cost plan is:

1. Replace the to-do worker's continuous schedule with exact, idempotent morning/evening wake-ups plus startup/retry recovery.
2. Remove duplicate list snapshots caused by reconnecting the live WebSocket after already fetching the same snapshot.
3. Stop re-registering an unchanged APNs device token on every app launch/status refresh.
4. Add bounded retention for terminal operational rows, including the existing-but-never-called AI re-add purge.

The delivery-worker fix preserves normal interactive behavior: new delivery work and known retries are processed immediately or at their exact retry time. The deliberate recovery tradeoff is limited to delivery work that is not observed locally (for example, after a process restart): it can wait up to the 10-minute maintenance sweep.

## Scope and method

- Reviewed all API repositories, routes, database setup, migrations, background services, and iOS call sites that invoke the persistent API.
- The API has no ORM: repository calls use `@neondatabase/serverless` directly through `apps/api/src/db/client.ts`.
- Simple repository reads/writes use the `neon()` query client. Multi-statement work uses a module-global WebSocket `Pool` and explicitly sends `BEGIN`, the operation, and `COMMIT`.
- The inventory covers these persistent areas: shopping list/trips/Live Activities, shopping AI jobs, to-do items/locations/reminders, users, push devices, and notification preferences.
- Home status, Home Assistant activity, camera data, weather data, and the recent activity feed do **not** persist to Neon in this codebase. The activity store is in memory; Home Assistant is the source for those external reads.
- No production data, `DATABASE_URL`, Neon console analytics, or live `pg_stat_statements` output was accessed for this audit.

## Ranked findings and recommendations

### 1. Implemented: remove the two five-second delivery-worker polls

**Priority: highest. Implemented savings: very large. UX impact: none for ordinary delivery; only rare recovery of work not observed by the current process can be delayed by up to 10 minutes.**

| Worker | Source | Idle work each poll | Previous cadence | Approximate pre-change commands per 30 days, per process |
| --- | --- | --- | --- | ---: |
| Shopping Live Activity delivery | `apps/api/src/services/shopping/shoppingLiveActivityDeliveryService.ts` | `recoverStaleClaims()` (one `UPDATE`) plus transactional `claimDueDeliveries()` (`BEGIN`, claim query, `COMMIT`) | 5 seconds | 2,073,600 |
| Shopping trip summary delivery | `apps/api/src/services/shopping/shoppingTripSummaryDeliveryService.ts` | Same one recovery `UPDATE` plus the three-command empty claim transaction | 5 seconds | 2,073,600 |
| **Combined** | | | | **4,147,200** |

Calculation for each worker: `30 × 24 × 60 × 60 ÷ 5 = 518,400` polls. Each poll executed four Postgres commands even with zero queued deliveries.

That five-second cadence left no multi-minute quiet period for database compute to become idle. If the Neon plan's bill is materially affected by active compute or autosuspend behavior, this pattern was especially likely to be expensive; confirm that link against the project's Neon compute timeline before treating it as a dollar attribution.

This was avoidable idle work:

- The Live Activity service already calls `processPending()` immediately after `enqueueEvent()`.
- The trip service already calls the summary worker's `processPending()` immediately after a trip ends.
- Therefore the five-second interval is primarily a retry/recovery mechanism, not the normal path that makes a user wait for a notification.

Implemented behavior:

1. Preserved immediate processing on enqueue and server startup.
2. Replaced both fixed intervals with one-shot wake-ups: retryable and ambiguous APNs results schedule the earliest known retry exactly, while a 10-minute recovery sweep handles stranded work.
3. Drains complete 20-item batches in the same worker pass so a burst of queued deliveries does not wait for a future sweep.
4. This reduces the empty-work baseline from 4,147,200 to about **34,560 commands/month per API process** (two workers × six 4-command sweeps/hour), a reduction of roughly **99.2%**, before real delivery and retry work.
5. If the deployment ever has multiple API replicas, run these queue workers in only one designated worker process or use a lightweight lease. `FOR UPDATE SKIP LOCKED` protects correctness, but each replica still performs the 10-minute recovery sweep. This operational topology decision is not changed by the code implementation.

Expected user-experience reduction:

- Normal shopping-trip starts, updates, ends, and summary pushes: **none expected**, because those paths already invoke the worker immediately.
- After an APNs timeout handled by the running worker: **none expected**; the precise retry time is scheduled directly rather than discovered by a sweep.
- After a lost process, an unavailable database, or work created by another process that this one does not observe: recovery can wait up to the next 10-minute sweep. This is a rare degraded path, not a normal screen interaction.

### 2. The to-do reminder worker repeats a full reminder pass for hours

**Priority: highest. Expected savings: large. UX impact: none if replaced with exact scheduled wake-ups; otherwise a configurable delay only.**

`apps/api/src/services/todo/todoDueReminderService.ts` runs every 30 seconds. Every run always executes:

- `recoverStaleClaims()` — one `UPDATE` query.
- `discardExpiredAndIneligibleDeliveries()` — one `UPDATE ... FROM todo_list` query.

The schedule then returns `['morning']` for every time from 8:00 AM until 5:59 PM Denver time, and `['evening']` for every time from 6:00 PM until midnight. For every one of those repeated 30-second passes, the service also runs:

- `enqueueDueReminders()` — an `INSERT ... SELECT ... ON CONFLICT DO NOTHING` over the to-do/audience data.
- `claimDueDeliveries()` — an empty transactional claim (`BEGIN`, claim query, `COMMIT`) once all actual deliveries have been sent.

Per 30-day month, per API process, the source implies roughly:

| Work | Commands/month |
| --- | ---: |
| Recovery + invalidation sweep every 30 seconds | 172,800 |
| Morning enqueue/claim repeated for 10 hours daily | 144,000 |
| Evening enqueue/claim repeated for 6 hours daily | 86,400 |
| **Total before actual sends/retries** | **403,200** |

The unique constraint prevents duplicate notifications, but it does not prevent the repeated queries and table scans.

Recommended change:

- Keep the database uniqueness constraint as the correctness backstop.
- Process a morning slot once at 8:00 AM and an evening slot once at 6:00 PM using timers aligned to `America/Denver`; schedule a one-time startup catch-up for the current slot so a restart cannot silently miss it.
- Only schedule a fast retry timer while there are actually pending/ambiguous deliveries. Move stale-claim recovery and the eligibility cleanup to startup plus a low-frequency maintenance sweep (for example hourly or daily, depending on the chosen retry policy).
- Persist or derive a slot key if more than one process can run the worker, so each process need not repeatedly discover the same slot. The existing delivery unique constraint keeps the result idempotent.

Expected user-experience reduction:

- With exact scheduled wake-ups and startup catch-up: **none expected**; reminders are still sent at the intended time and remain idempotent.
- With only a simpler five-minute interval: a reminder could arrive up to five minutes late. That is not necessary here; an exact wake-up design avoids it.

### 3. Shopping live synchronization fetches the same full snapshot twice per visit

**Priority: high. Expected savings: medium to high for active users. UX impact: none if the WebSocket becomes the single resync trigger.**

The shopping snapshot endpoint does four database queries per successful request:

1. all `shopping_list` items;
2. all `shopping_locations`;
3. all `shopping_categories`;
4. the active-trip aggregate.

See `apps/api/src/repositories/shoppingListRepository.ts` and `apps/api/src/routes/shoppingListRoutes.ts`.

When Shopping is selected or the app returns to foreground, `ShoppingListView.refreshForSelectedVisit()` explicitly calls `viewModel.refresh()`. That fetch starts/restarts the live WebSocket. On every WebSocket connection, the server sends `snapshot_required`, and `ShoppingListViewModel` fetches the entire snapshot again. The current normal visit is therefore approximately:

| Per selected Shopping visit | Database commands |
| --- | ---: |
| Explicit `GET /api/shopping-list` | 4 |
| Live WebSocket's immediate `snapshot_required` -> another `GET /api/shopping-list` | 4 |
| Stock-price readiness probe | 1 |
| AI re-add readiness probe | 1 |
| **Total before any active-trip display claim** | **about 10** |

An active trip adds a device lookup and a multi-query transaction for the idempotent display claim when the tab is revisited.

Recommended change:

- Make one source authoritative for a reconnect snapshot. The cleanest version is: connect the live channel, fetch one snapshot because the connection asks for it, and do not also force `refresh()` for that same visit.
- Retain the in-memory snapshot while the tab is not selected. On return, reconnect and accept one server-directed snapshot; retain pull-to-refresh as the explicit "check now" action.
- Cache the two readiness responses for the current Shopping screen/session. The action-start endpoints already perform authoritative validation, so availability need not be probed on every tab select and foreground event.
- Cache the successful active-trip display claim by `tripId` + local device ID for the lifetime of the active trip, rather than posting the same idempotent claim on every foreground/selection transition.

Expected user-experience reduction:

- Normal shared-list freshness: **none expected**. The WebSocket already asks for a snapshot on connection and carries mutation/trip updates while connected.
- There can be a short existing loading period while the single snapshot arrives. Keeping the prior in-memory list visible avoids a visual regression on tab return.
- If live connection setup fails, keep the explicit manual refresh path; do not remove it.

### 4. Every unchanged push-registration refresh writes to the database

**Priority: high. Expected savings: medium, proportional to app launches/settings visits. UX impact: none for unchanged devices.**

`PushRegistrationViewModel.shouldSyncDeviceWithAPIOnRefresh` returns true whenever the app has an authorized APNs token. It does **not** compare that token/environment to the already persisted `PushAPISyncState` before calling `POST /api/devices/register`.

Each registration request currently performs three database queries:

1. find active device by lookup key;
2. upsert the device and update `last_seen_at`;
3. count active devices for the response.

The root app task invokes `prepareDeliveryIfNeeded()` on launch. Its task ID includes `registeredDeviceID`, which is set by the registration response; that state change can cause a second task run and another registration for the unchanged token. The status cards also call `refreshStatus()` when their views appear, which repeats the same write path.

Recommended change:

- Before registering, consult `PushAPISyncState`. Skip the API call when the token and APNs environment match, unless one of these changed: device name, app version, token, environment, or an explicit refresh/repair action was requested.
- If a server-side liveness timestamp is needed, use a bounded heartbeat (for example weekly) instead of every launch. Store the server sync timestamp locally.
- Consider returning a cached active-device count or omit it from ordinary upsert responses; it is only used for status text and costs a full count query.

Expected user-experience reduction:

- **None expected** for a token that has not changed. A new token, reinstall, environment change, app-version/device-name update, or explicit retry would still register immediately.
- With a weekly heartbeat, a stale device row may take up to a week to have `last_seen_at` refreshed; push delivery itself still uses the token already on file.

### 5. Terminal operational data has little or no retention

**Priority: high for storage growth and future query cost. Expected savings: increasing over time. UX impact: none if retention matches the real support/audit need.**

Several operational tables only append/update and are not cleaned up by any running code:

| Data | Evidence | Recommended bounded policy |
| --- | --- | --- |
| Live Activity deliveries | `shopping_live_activity_deliveries` has no cleanup path | Delete terminal `sent`/`failed` rows after 30–90 days in small batches. Keep pending/ambiguous rows. |
| Trip summary deliveries | `shopping_trip_summary_deliveries` has no cleanup path | Same terminal-row retention policy. |
| To-do reminder deliveries | `todo_due_reminder_deliveries` has no cleanup path | Retain terminal rows for a defined support period, then delete in batches. |
| Stock/price check runs and JSONB item outcomes | no retention/cleanup repository method | Retain final results for a bounded period, then delete completed/failed runs; cascading removes their item snapshots/outcomes. |
| Inactive push registrations | rows are marked inactive but never purged | Remove long-inactive tokens after a conservative retention period. |
| Completed shopping trips and snapshots | no cleanup path | Decide whether historical trips are a product requirement. If not, retain for a documented support period and delete completed trips, cascading their snapshots and delivery rows. |

There is also a concrete unfinished cleanup implementation: `shoppingListReaddRetentionDays` is 30, `purge_after` is set, and `cleanupExpiredRuns()` is implemented with an indexed bounded delete in `shoppingListReaddRepository.ts`. A repository-wide search finds no caller. As a result, terminal AI re-add runs and their operation rows remain indefinitely despite the explicit retention design.

Recommended change:

- Call `cleanupExpiredRuns()` from one low-frequency maintenance job (daily is sufficient) and log the number of rows deleted.
- Add similarly bounded, indexed cleanup methods for the other terminal operational tables. Delete small batches until empty rather than issuing one unbounded delete.
- Decide and document retention before deleting completed trips or AI results. The current user-facing app has no general history screen for old runs/deliveries, but support/debug needs are a product decision.

Expected user-experience reduction:

- None in everyday use if the policy keeps a reasonable support window. AI re-add Undo is only valid for five minutes, so deleting its terminal rows after the already intended 30 days has no normal user-facing effect.
- Developers lose access to old debug history after the chosen retention deadline; export/aggregate any history that must be kept first.

### 6. To-do reloads include stable reference data and an extra users request

**Priority: medium. Expected savings: medium for app launches and To-do use. UX impact: a bounded staleness window for rarely changed reference data.**

`GET /api/todo-list` executes three queries in parallel: the to-do items query, categories, and active locations. `ToDoViewModel.load()` concurrently issues `GET /api/users`, adding a fourth query. On every To-do WebSocket connection the server sends `snapshot_required`, which reloads the three-query to-do snapshot again.

The root `TabView` creates `ToDoView`; its `.task { await load() }` is not gated by `isSelected`. Depending on SwiftUI view-task lifecycle, that can load to-do data on app launch even when the user remains on Home. This should be confirmed with request logging on a physical device, but the source makes it a likely avoidable request.

Recommended change:

- Gate the initial To-do load on `isSelected`, then load on first To-do selection. If a fast first visit matters, prefetch after the Home screen is settled rather than unconditionally at launch.
- Load users only when `users` is empty or its short TTL expires; they are not part of the normal live snapshot.
- Cache categories and locations per app session (or give them separate cacheable endpoints). Invalidate the location cache after creating a location and offer pull-to-refresh/TTL refresh for administrative changes.
- As with Shopping, avoid a separate initial fetch plus an automatic live-channel `snapshot_required` fetch for the same visit.

Expected user-experience reduction:

- First To-do visit after a cold launch may show the existing loading state briefly instead of preloading in the background.
- A newly added location/category/user created outside this device might remain stale until the short TTL, reconnect, or manual refresh. Local creates can invalidate immediately, avoiding a visible regression.

### 7. AI job polling and job persistence are intentionally durable but chatty

**Priority: medium. Expected savings: low unless the AI tools are used frequently. UX impact: progress updates become less granular if polling is slowed.**

Both stock/price checks and AI re-add use a client poll sequence of up to 30 reads: immediately, then after 1, 1, 2, 3, and repeatedly 5 seconds. Each status endpoint is one run query. This is bounded (about 30 reads per active job) and stops when the Shopping screen leaves, so it is not the primary ongoing cost.

The more meaningful per-job writes are:

- Stock/price check creation inserts one run, fetches needed items, then inserts one durable item snapshot per needed shopping item.
- Each item outcome performs an item update, a full counter recomputation over all run items, and a run fetch, all inside a transaction. Applying an outcome can then cause another shopping-list mutation transaction.
- AI re-add writes durable pre-operation state, performs per-item shopping mutations, then upserts each final operation so Undo remains safe.

Recommended change:

- Keep the durability/Undo semantics; these are user-visible correctness features.
- For stock checks, batch initial item-snapshot inserts and batch or increment counters rather than scanning all run items after every outcome. This reduces work for a large shopping list without changing the result.
- Add a terminal job event to the existing Shopping live channel, then use a slower 10–15 second polling fallback while visible. Do not remove the fallback until reconnection behavior is tested.

Expected user-experience reduction:

- With live terminal/progress events: none expected in normal conditions.
- With a 10–15 second polling fallback only, the progress count can be that much less fresh; completed results still arrive reliably.

### 8. Notification fan-out re-reads devices and preferences for every event

**Priority: medium/conditional. Expected savings: meaningful only if Home Assistant events are frequent. UX impact: none with correct invalidation.**

For each push-producing Home Assistant/list/weather/reminder event, `notificationService.ts` reads all active devices, then reads notification preferences once per target APNs device. With two phones, a normal event is at least three Neon reads before APNs delivery. Doorbell motion or other high-frequency event types can make this visible in query volume.

Recommended change:

- Add a small in-process cache for active devices and preference records (for example 1–5 minutes).
- Invalidate the device cache on registration/invalidation and the preference cache on preference updates. This preserves immediate effect for changes made through this API.
- Measure event rate first; do not prioritize this ahead of the empty worker polls.

Expected user-experience reduction:

- None for changes that occur through this API and invalidate the cache.
- Without explicit invalidation, an externally changed preference could be honored up to the cache TTL late. That is why cache invalidation is required.

## Query-shape and indexing observations

The delivery tables already have good partial due indexes, and the shopping-list duplicate lookup has a normalized-name unique index. The first priority is eliminating executions, not adding indexes.

Items to validate with `EXPLAIN (ANALYZE, BUFFERS)` only after the frequency fixes:

- `todo_list.created_for @> ...` is a JSONB audience filter with no visible GIN index. Add one only if the to-do table grows enough for this query to be material; every added index raises write/storage cost.
- The to-do location display is calculated with a correlated `jsonb_array_elements_text(location_ids)` subquery for every returned item. This is acceptable for a small household list but should be measured if the list grows.
- The fixed worker recovery queries filter `status = 'sending'`, while the current partial due indexes only cover pending/ambiguous states. Once polling frequency is reduced, verify whether a narrowly scoped stale-claim index is still necessary before adding it.
- The full shopping snapshot intentionally returns all items and JSONB store listings. Avoid pagination until the list size or payload measurements justify it; paging can harm the shared-list experience more than it saves today.

## Connection and deployment guardrails

`getDatabaseTransactionRunner()` creates a module-global Neon `Pool` without an explicit maximum or idle policy. This is not the main demonstrated cost driver, but it is a useful guardrail:

- Set a modest explicit pool maximum after measuring normal concurrent mutations (for a household app, 2–4 is a reasonable starting hypothesis, not a confirmed final number).
- Set an idle timeout compatible with the Neon connection mode in use.
- Load-test active Shopping mutations, AI writes, and delivery workers before tightening it. Too-small pool limits can turn concurrent requests into short waits.

The Docker command runs migrations before every API process start. That is a small deploy-time cost, not a steady-state explanation: the runner closes its pool before starting the server.

## Recommended implementation sequence

| Phase | Change | Expected database effect | Expected UX effect |
| --- | --- | --- | --- |
| 1 | 5-second delivery polls -> 60 seconds, keep immediate enqueue/startup processing | ~3.80M fewer idle commands/month per process from the two delivery workers | No normal change; rare retry/recovery can be up to ~55 seconds later |
| 1 | Exact to-do reminder wake-ups + startup/retry recovery | Removes most of ~403k monthly reminder-worker commands | No normal change when scheduled exactly |
| 2 | One snapshot per Shopping/To-do live visit; cache readiness/reference data | Removes duplicate 4-query Shopping and 3-query To-do reads, plus readiness/users reads | Brief first-load only; manual refresh remains |
| 2 | Skip unchanged push-device upserts | Removes 3 queries per avoided registration | None for unchanged tokens |
| 3 | Run existing AI re-add cleanup; add retention for terminal operational rows | Prevents unbounded storage and keeps indexes/table scans small | Debug history only becomes bounded by policy |
| 4 | Batch AI job writes/counters; cache notification fan-out reads | Reduces work during optional high-volume features/events | Slightly less granular progress only if fallback polling is slowed |

## Verification plan before and after changes

1. Record a seven-day Neon baseline: compute time, active time, storage, database size, and any query/connection metrics exposed by the current Neon plan.
2. Add structured application counters around each worker cycle: worker name, `claimedCount`, elapsed time, and whether a cycle was event-triggered or idle. Do not log SQL parameters or device tokens.
3. If `pg_stat_statements` is available in this Neon project, capture top statements by calls and total execution time before changing code. Otherwise use Neon query insights and the application counters.
4. Deploy Phase 1 alone, then compare the same seven-day window. The worker command reduction should be immediately visible in application counters even if Neon billing reports on a slower cadence.
5. Verify user-critical paths on both phones: trip start/update/end Live Activities, trip-summary push, morning/evening to-do reminder, app restart during a pending delivery, manual Shopping refresh, and APNs token refresh after a token change.
6. Only then apply the client snapshot/cache improvements and retention changes. Keep a manual refresh/retry control for every cache-backed view.

## Things not to do first

- Do not turn off the durable delivery tables or AI job persistence; they protect retry, idempotency, Live Activity, and Undo behavior.
- Do not make the entire app rely solely on a live WebSocket. Keep explicit snapshot/manual-refresh fallbacks for reconnects and server restarts.
- Do not add speculative indexes or reduce data retention before measuring table size and support needs. Those changes can add write cost or remove useful debugging evidence while not addressing the largest known source of spend.
- Do not assume the source-level command counts equal Neon dollars. Confirm whether the bill is dominated by compute, storage, data transfer, or a plan minimum after Phase 1 instrumentation.
