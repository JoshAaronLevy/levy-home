# Neon database usage audit

## Bottom line

The strongest code-level explanation for sustained Neon spend was the always-on delivery polling, not ordinary household-list use. Before the implementations recorded below, two independent workers polled the database every five seconds regardless of whether any push delivery existed, and the to-do worker repeated its reminder work every 30 seconds for much of the day. Together those patterns generated millions of avoidable database commands per API process each month.

Those counts are derived from source code, not from the Neon billing dashboard or production query telemetry. They show execution frequency and likely compute pressure; they cannot assign a dollar amount or prove which Neon billing meter produced the current $40+ charge. If Render has more than one API process/replica, multiply the worker estimates by the number of processes.

The lowest-risk remaining cost plan starts with avoiding redundant To-do reference-data loads and snapshot reloads (Section 6).

The delivery and reminder-worker fixes preserve normal interactive behavior: new delivery work and known retries are processed immediately or at their exact retry time. The deliberate recovery tradeoffs apply only to exceptional, unobserved work after a process failure.

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

### 2. Implemented: replace the to-do worker's continuous reminder polling

**Priority: highest. Implemented savings: large. UX impact: none expected for scheduled reminders or known retries.**

Before this implementation, `apps/api/src/services/todo/todoDueReminderService.ts` ran every 30 seconds. Every run executed:

- `recoverStaleClaims()` — one `UPDATE` query.
- `discardExpiredAndIneligibleDeliveries()` — one `UPDATE ... FROM todo_list` query.

The schedule then returned `['morning']` for every time from 8:00 AM until 5:59 PM Denver time, and `['evening']` for every time from 6:00 PM until midnight. For every one of those repeated 30-second passes, the service also ran:

- `enqueueDueReminders()` — an `INSERT ... SELECT ... ON CONFLICT DO NOTHING` over the to-do/audience data.
- `claimDueDeliveries()` — an empty transactional claim (`BEGIN`, claim query, `COMMIT`) once all actual deliveries have been sent.

Per 30-day month, per API process, that source implied roughly:

| Work | Commands/month |
| --- | ---: |
| Recovery + invalidation sweep every 30 seconds | 172,800 |
| Morning enqueue/claim repeated for 10 hours daily | 144,000 |
| Evening enqueue/claim repeated for 6 hours daily | 86,400 |
| **Total before actual sends/retries** | **403,200** |

The unique constraint prevented duplicate notifications, but it did not prevent the repeated queries and table scans.

Implemented behavior:

1. Kept the delivery uniqueness constraint as the correctness backstop.
2. Schedules exactly one morning run at 8:00 AM and one evening run at 6:00 PM in `America/Denver`, including daylight-saving transitions. Server startup processes the current slot once as catch-up.
3. Schedules a one-shot wake-up for the earliest persisted pending/ambiguous delivery. A retry claims its original due-date/kind without re-enqueuing an extra reminder slot.
4. Runs stale-claim recovery, eligibility cleanup, and pending-retry discovery at startup, once 90 seconds later to catch a just-stale in-flight send, and then hourly. This keeps the old recovery timing without continuous polling.
5. Drains complete 50-item batches in one pass so a burst is not deferred to another scheduled wake-up.
6. The quiet baseline is now approximately **2,460 commands/month per API process**: 2,160 hourly maintenance commands plus 300 exact-slot commands, before real sends/retries and startup work. That is about a **99.4% reduction** from the prior 403,200-command estimate.
7. Multiple API replicas still make their own exact-slot/maintenance queries, though the uniqueness constraint and `FOR UPDATE SKIP LOCKED` preserve correctness. A designated worker or lease remains an operational topology decision, not a safe code-only default.

Expected user-experience reduction:

- Scheduled 8:00 AM/6:00 PM reminders and known retries: **none expected**; they are woken directly at the intended time and remain idempotent.
- A send that was in flight when a process died is recovered on restart when already stale, or by the 90-second startup recovery and its 30-second retry when the failure was immediate. This retains the old roughly two-minute exceptional-path timing without an all-day poll.

### 3. Implemented: use one server-directed snapshot for each retained Shopping revisit

**Priority: high. Implemented savings: medium to high for active users. UX impact: none expected during ordinary returns to Shopping.**

The shopping snapshot endpoint does four database queries per successful request:

1. all `shopping_list` items;
2. all `shopping_locations`;
3. all `shopping_categories`;
4. the active-trip aggregate.

See `apps/api/src/repositories/shoppingListRepository.ts` and `apps/api/src/routes/shoppingListRoutes.ts`.

Before this implementation, when Shopping was selected again or the app returned to foreground, `ShoppingListView.refreshForSelectedVisit()` explicitly called `viewModel.refresh()`. That fetched a snapshot and restarted the live WebSocket. The server then sent `snapshot_required`, which made `ShoppingListViewModel` fetch the entire snapshot again. A repeated visit was therefore approximately:

| Per repeated selected Shopping visit before implementation | Database commands |
| --- | ---: |
| Explicit `GET /api/shopping-list` | 4 |
| Live WebSocket's immediate `snapshot_required` -> another `GET /api/shopping-list` | 4 |
| Stock-price readiness probe | 1 |
| AI re-add readiness probe | 1 |
| **Total before any active-trip display claim** | **about 10** |

An active trip also added a device lookup and a multi-query transaction for the idempotent display claim whenever the tab was revisited.

Implemented behavior:

1. `refreshForSelectedVisit()` now reconnects with `loadIfNeeded()` rather than forcing `refresh()`. When the retained view model already has a snapshot, it stays visible while the live channel reconnects, and the server's `snapshot_required` is the sole full resync for that return.
2. Pull-to-refresh still calls `refresh()` and remains the explicit "check now" path.
3. The stock-price and AI re-add readiness responses are retained for the view-model session, and an in-flight readiness request is coalesced. Returning to the tab restarts monitoring for an active job but does not repeat an unchanged readiness probe; each action-start endpoint still validates eligibility authoritatively.
4. A successful active-trip display claim is now cached and concurrent claims are coalesced by `tripId` plus local device ID. The cache is cleared when the active trip changes.

For a retained Shopping revisit with no active long-running job or new display claim, the normal database work falls from about 10 commands to one four-query server-directed snapshot: roughly a **60% reduction per revisit**, before considering the avoided active-trip claim. The first creation of a Shopping view model retains its existing bootstrap fetch; this change targets the repeated selection/foreground path that previously did the duplicate work.

Expected user-experience reduction:

- Normal shared-list freshness: **none expected**. The WebSocket already asks for a snapshot on connection and carries mutation/trip updates while connected.
- On return, the previously confirmed list remains visible while the single snapshot arrives, avoiding the prior loading/flicker risk. Manual pull-to-refresh is unchanged.
- If live connection setup fails, the prior snapshot remains visible and the explicit manual refresh path remains available. A first-ever load still uses the established HTTP bootstrap path.

### 4. Implemented: avoid unchanged push-registration writes and device counts

**Priority: high. Implemented savings: medium, proportional to app launches/settings visits. UX impact: none for unchanged devices; operational liveness metadata can be up to seven days old.**

Before this implementation, `PushRegistrationViewModel.shouldSyncDeviceWithAPIOnRefresh` returned true whenever the app had an authorized APNs token. It did **not** compare that token/environment to the already persisted `PushAPISyncState` before calling `POST /api/devices/register`.

Each registration request previously performed three database queries:

1. find active device by lookup key;
2. upsert the device and update `last_seen_at`;
3. count active devices for the response.

The root app task invokes `prepareDeliveryIfNeeded()` on launch. Its task ID includes `registeredDeviceID`, which is set by the registration response; that state change could cause a second task run and another registration for the unchanged token. The status cards also call `refreshStatus()` when their views appear, which repeated the same write path.

Implemented behavior:

1. `PushAPISyncState` now fingerprints the APNs token, environment, normalized device name, and app version, as well as the successful-sync time. A launch/status refresh with an exact match makes **no** request to Neon.
2. A changed token, APNs environment, app version, or device name registers immediately. The explicit native registration action remains an immediate repair path even when the persisted fingerprint matches.
3. An unchanged device sends a bounded weekly heartbeat so `last_seen_at` is refreshed without an every-launch write. Older persisted sync records lack the new fingerprint and therefore make one safe registration after the app update.
4. The iOS client now requests `includeDeviceCount: false` for its registrations. The API skips `countDevices()` and omits `registeredDeviceCount` in that response; legacy callers that omit the flag retain the prior counted response for deployment compatibility.

Repeated unchanged launch/refresh work therefore falls from three database commands to zero. A registration that is actually needed falls from three to two commands (lookup plus upsert), because the active-device count is not a user-facing requirement on that path.

Expected user-experience reduction:

- **None expected** for an unchanged device. A new token, reinstall, environment change, app-version/device-name update, or explicit registration action still registers immediately.
- `last_seen_at` can be up to seven days stale for an otherwise inactive app installation. Push delivery still uses the registered token already on file; this only reduces the precision of operational liveness metadata.
- The developer-only registration status no longer displays an active-device total after the modern iOS registration request. The count was not product-facing, and legacy callers can still request it.

### 5. Implemented: bounded retention for terminal operational data

**Priority: high for storage growth and future query cost. Implemented savings: increasing over time as old rows and JSONB outcomes are removed. UX impact: none in normal use; completed shopping-trip history is deliberately retained.**

The API now has one low-frequency operational-retention service. It runs once at API startup, then once every 24 hours, logs the deletion count for each data type, and stops during graceful shutdown. A failure for one retention target is logged but does not prevent the other targets from being cleaned up.

The documented policies are:

| Data | Implemented retention | Safety boundary |
| --- | --- | --- |
| AI Shopping re-add runs and operations | 30 days (the pre-existing `purge_after` policy) | Only terminal runs; the five-minute Undo window is long expired. |
| Live Activity deliveries | 90 days | Only `sent`/`failed`; pending, sending, and ambiguous recovery work is retained. |
| Trip-summary deliveries | 90 days | Only `sent`/`failed`/`skipped`; ambiguous retries are retained. |
| To-do reminder deliveries | 90 days | Only `sent`/`failed`/`skipped`; pending and ambiguous reminders are retained. |
| Stock/price-check runs and their JSONB outcomes | 30 days | Only completed, completed-with-issues, or failed runs; child item snapshots cascade with the parent run. |
| Inactive push devices | 180 days after invalidation | Active devices are never selected. Associated preference rows are removed with the inactive device. |
| Completed shopping trips and snapshots | Retained indefinitely for now | Historical trip retention remains a product decision and is not silently changed. |

Implemented behavior:

1. `cleanupExpiredRuns()` is now called daily, so the existing 30-day AI re-add policy is no longer dormant.
2. New partial indexes cover only the terminal rows selected by retention. Each new cleanup query selects at most 100 oldest candidates, locks them with `FOR UPDATE SKIP LOCKED`, and deletes that batch. The service drains batches until the target is current, avoiding one unbounded delete while remaining safe if multiple API processes run the maintenance pass.
3. The stock-run delete cascades to durable item snapshots/outcomes. Inactive-device cleanup also deletes matching token/device-keyed notification preferences, preventing orphaned preference records.
4. Pending, sending, and ambiguous deliveries are intentionally excluded from all retention deletes, preserving retry and crash-recovery behavior.

Expected user-experience reduction:

- **None expected** in everyday use. A 90-day delivery support window, 30-day job-debug window, and 180-day inactive-device window are far longer than the user-visible action/retry windows.
- AI re-add Undo remains available for its existing five-minute window; terminal run history disappears only after 30 days.
- Developers lose older delivery/job diagnostics after their policy deadline. Completed shopping-trip history is not deleted by this implementation.

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
