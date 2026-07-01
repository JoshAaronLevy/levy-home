# Notifications Implementation Plan

Created: 2026-06-30
Updated: 2026-07-01

This plan assumes the Apple-side APNs/TestFlight state still needs current verification before a physical-device rollout. The user has enabled the iOS location capability in Apple Developer/Xcode, so native location is available as an implementation option, but it still needs app code, permission UX, background-mode behavior, and backend event handling.

The first real notifications should be partner presence notifications: Josh is notified when Mallory leaves or arrives home only if Josh is already home, and Mallory is notified when Josh leaves or arrives home only if Mallory is already home.

Regardless of whether the presence signal comes from Home Assistant or native iOS location services, every notification should be delivered by the Levy Home app through the Levy Home backend and APNs. Home Assistant and CoreLocation are signal sources, not the notification delivery product.

## Current Starting Point

- iOS already has APNs registration scaffolding in `NotificationService`, `AppDelegate`, and `PushRegistrationViewModel`.
- The API already has `/api/devices/register`, `/api/notification-preferences`, `/api/debug/send-test-push`, and an `APNsPushSender`.
- Existing notification preferences are garage-only.
- Registered devices and synced notification preferences are currently stored in process memory inside `apps/api/src/server.ts`; these need Postgres persistence before TestFlight or Render restarts can be trusted.
- The shopping list already has REST mutations, mutation IDs, and a realtime WebSocket with viewer presence at `/api/shopping-list/live`.
- Home Assistant phone activity is intentionally Activity/logging data today. It should not automatically become push-notification noise, but Home Assistant presence state can be useful for the first partner-presence rules.
- Native iOS location capability has been enabled, but there is not yet an app-owned CoreLocation presence pipeline that reports home enter/exit events to the backend.

## Notification Philosophy

The app should feel like a helpful household assistant, not another noisy appliance app.

- Notify on outcomes, exceptions, and useful summaries rather than raw sensor state changes.
- Batch related actions into one message when a person is actively editing or doing a task.
- Do not notify the person who caused the event unless the notification is a reminder or confirmation they explicitly opted into.
- Prefer "only if this matters right now" rules: nobody home, after bedtime, someone is at the store, the app is backgrounded, or the other person is affected.
- Add cooldowns and dedupe keys for every category.
- Give each category an obvious preference toggle.
- Use push payload data for deep links, but keep sensitive details out of logs and APNs payloads.
- Separate the signal source from delivery. Home Assistant, iOS location, calendars, and app activity can create domain events; the Levy Home backend should apply preferences, suppression rules, cooldowns, delivery logs, and APNs sending.

## First Notification Milestone: Partner Presence

Target notifications:

- Notify Josh when Mallory leaves home, but only if Josh is already home.
- Notify Josh when Mallory arrives home, but only if Josh is already home.
- Notify Mallory when Josh leaves home, but only if Mallory is already home.
- Notify Mallory when Josh arrives home, but only if Mallory is already home.

This should be one preference category at first, such as `partner_presence`, with room to split arrival and departure toggles later if either one feels noisy.

Recommended v1 rule:

1. A tracked person transitions from home to away, or away to home.
2. The other person is currently home at the time the transition is evaluated.
3. The event source is fresh enough to trust.
4. A short grace window has passed to avoid false "left" notifications from momentary tracker flapping.
5. The backend records a dedupe key and sends one APNs notification to the other person's registered Levy Home devices.

Example copy:

- Title: `Mallory left home`
- Body: `You are still home.`
- Title: `Josh arrived home`
- Body: `Mallory is home.`

The body copy should stay intentionally plain for v1. The usefulness is in the timing and routing, not in a verbose message.

## Presence Signal Source Recommendation

Recommendation: use Home Assistant presence state/events as the first signal source, but do not send notifications from Home Assistant. Let Home Assistant tell the Levy Home backend that a presence transition happened, then let the Levy Home notification coordinator decide whether to send a Levy Home push notification.

Do not build v1 from Home Assistant logs alone. Logs and Activity are useful for audit, debugging, and backfill, but the notification trigger should be a state transition or event stream/webhook from canonical presence entities. Logs can be delayed, duplicated, filtered, or missing context that the notification coordinator needs.

| Source | Best Use | Advantages | Trade-offs | Recommendation |
| --- | --- | --- | --- | --- |
| Home Assistant presence state/events | First implementation of Josh/Mallory home/away notifications. | Already has household context, can see both people at once, continues working even when the Levy Home app is not foregrounded, and fits the existing backend HA integration direction. | Depends on Home Assistant uptime, entity accuracy, iPhone tracker latency, exact entity mapping, and freshness checks. Requires debounce/grace windows to avoid tracker flapping. | Best v1 source if the tracked Josh/Mallory entities are reliable enough in fresh traces. |
| Home Assistant logs/activity | Audit trail and debugging evidence for why a notification did or did not send. | Good for explaining behavior after the fact and verifying source events against `/api/events`/Activity. | Not ideal as the primary trigger because logs are historical, can lag, and may not represent current recipient state at send time. | Use as evidence, not the primary trigger. |
| Native iOS CoreLocation | Later app-owned presence source or fallback/validator if HA is too slow or unreliable. | Keeps the signal inside Levy Home, can avoid depending on HA, and can eventually support app-owned geofences for stores, to-do locations, and calendar departure reminders. | Requires Always/When In Use permission design, background mode behavior, region monitoring edge cases, privacy explanation, battery care, per-device permission drift, and backend reconciliation between two phones. | Good later phase; not necessary for the first presence notifications unless HA proves unreliable. |
| Hybrid HA plus iOS | Long-term reliability and cross-checking. | HA can provide the household state, iOS can report direct app-owned geofence events, and the backend can choose the freshest trusted source. | More complex conflict resolution and observability. Needs clear source priority and stale-data rules. | Design the backend event contract now so a native iOS source can be added without changing notification rules. |

## Foundation Work Before New Notification Categories

1. Persist push devices and preferences.
   - Add `push_devices`, `notification_preferences`, and probably `notification_deliveries` tables.
   - Store hashed tokens for lookup/logging and encrypted/raw tokens only where needed for APNs delivery.
   - Track `user_id`, `device_name`, `platform`, `provider`, `environment`, `app_version`, `last_seen_at`, and invalid-token status.

2. Add stable user identity to app sessions.
   - The shopping WebSocket has `viewerId` and `displayName`, but mutations do not yet clearly carry the editor identity through the backend.
   - Notification routing needs to know "Mallory changed this" and "Josh should receive it."

3. Create a backend notification coordinator.
   - Keep APNs-specific sending in `apnsService.ts`.
   - Add a higher-level module that receives domain events, applies rules/preferences/rate limits, records delivery attempts, and calls APNs.

4. Expand notification preferences.
   - Keep garage categories, then add categories like `shopping_list_summary`, `shopping_last_minute_add`, `presence_safety`, `lights_left_on`, `doorbell_away`, and `developer_health`.
   - Support per-user/per-device preferences.

5. Add deep-link routing.
   - Shopping notifications should open the Shopping tab.
   - Garage/lights notifications should open Home.
   - Partner presence notifications can open Home or Activity; use Home for v1 unless Activity becomes the clearer place to explain presence events.
   - Delivery/debug notifications should open Preferences -> Developer -> Logs if that remains the chosen debug path.

6. Build a non-APNs test mode.
   - Add a mock push sender or delivery log endpoint so rules can be tested before Apple approval completes.
   - Keep `/api/debug/send-test-push` for end-to-end physical-device checks once APNs is available.

7. Add canonical household presence identities.
   - Map Josh and Mallory to stable backend users and exact Home Assistant presence entities.
   - Store the current presence state, source, last changed time, and last verified time.
   - Treat stale/unknown presence as "do not notify" for partner-presence v1.

## Candidate Notifications

| Notification | Trigger | Noise Control | Logic Difficulty | Code Complexity | Notes |
| --- | --- | --- | --- | --- | --- |
| Partner leaves home while recipient is home | Mallory transitions from home to away while Josh is already home, or Josh transitions from home to away while Mallory is already home. | Notify only the person still home; require fresh source state; debounce 2-5 minutes; one notification per departure episode; no self-notification. | Easy to Medium | Medium | First live category. Best v1 source is Home Assistant presence state/events, with logs used for audit and iOS location left as a later source. Delivered through Levy Home/APNs. |
| Partner arrives home while recipient is home | Mallory transitions from away to home while Josh is already home, or Josh transitions from away to home while Mallory is already home. | Notify only the person already home; require the arriving person to have previously been away; suppress duplicate arrivals during tracker flapping; one notification per arrival episode. | Easy to Medium | Medium | First live category paired with departure. Consider a shorter grace window than departure so arrivals feel timely. Delivered through Levy Home/APNs. |
| Shopping list edit summary | Mallory or Josh opens the shopping list, makes at least one successful change, then leaves the view or goes inactive. Notify the other person. | One notification per editing session; include counts like "added 3, updated 1"; no per-change pushes; suppress if recipient is also currently viewing the list. | Medium | Medium | Strong early "oh, nice" feature after partner presence. Existing WebSocket presence helps, but backend needs editor identity on mutations and session aggregation. |
| Shopping trip completed summary | A person checks off multiple items during a shopping session, then leaves the store/list or goes inactive. | One rollup per trip, e.g. "Mallory picked up 12 items. 3 left." Minimum threshold such as 3 purchased changes. | Medium | Medium | Makes the app feel collaborative without texting about every item. Can start with list-session inactivity before adding geofencing. |
| Last-minute item added while someone is shopping | One person is actively shopping and the other adds items. Notify the shopper with a short rollup. | Batch for 30-90 seconds; only notify if recipient is active in shopping mode or inside a store geofence; max once every few minutes. | Medium to Hard | Medium to High | Medium if based only on active Shopping tab presence. Hard if using CoreLocation store arrival/departure. |
| Store arrival reminder | A user arrives near King Soopers/Kroger and the shared list has unpurchased items. | Once per store visit; do not repeat while still at the store; optionally require at least one item with that store listing. | Hard | High | Requires iOS location permission, geofences, and careful battery/privacy handling. Very useful later, not the first APNs milestone. |
| Item aisle or availability ready | A newly added shopping item gets useful Kroger metadata after the user has backgrounded the app. | Notify only when the enrichment is actionable, such as aisle found or likely unavailable; no push if user is still viewing the item. | Medium | Medium | Ties nicely into existing Kroger/product lookup work. Could also remain in-app only unless it proves useful. |
| Duplicate item prevented | Someone tries to add an item already on the list. Notify nobody by default; show in-app only. | No push. | Easy | Low | Listed here intentionally as a "do not push" case. This prevents the notification system from turning validation into noise. |
| Garage opened while nobody is home | Garage opens and both Josh/Mallory presence states are away. | Immediate; dedupe by garage-open episode; suppress if a tracked phone arrives home within a short grace window. | Medium | Medium | High-value safety notification. Uses garage state plus Home Assistant presence. More useful than generic "garage opened" spam. |
| Garage still open when last person leaves | Last tracked person leaves home while garage is open. | Immediate once per departure; optional cooldown until garage closes. | Medium | Medium | Better than periodic "garage is open" reminders. Can deep-link to Home, and eventually support an action to close garage after confirmation. |
| Garage failed-to-open arrival watchdog | A phone arrives home but the garage automation does not open within a configured window. | Only when automation was expected; one notification per arrival. | Hard | Medium to High | Potentially delightful because it catches failures, but timing must be proven against real Home Assistant traces to avoid false alarms. |
| Garage still open bedtime summary | At 10 PM, garage is open. | Existing concept; once per night; critical severity only if still open. | Easy to Medium | Low to Medium | Already has a preference category and event type. Good early validation after partner presence. |
| After-hours garage opened | Garage opens between configured quiet hours. | One per open event; no extra close notification unless explicitly opted in. | Easy | Low to Medium | Existing event/preference scaffolding makes this straightforward. |
| Lights left on after everyone leaves | Last person leaves and one or more curated lights/light groups remain on. | One departure summary, e.g. "Kitchen and basement lights are still on"; no repeated reminders unless still on after a long interval. | Medium | Medium | Uses existing Home overview/light group concepts. Much better than notifying for every light switch. |
| Bedtime house check | At a chosen bedtime, summarize only actionable issues: garage open, lights on, stale Home Assistant data, etc. | One daily summary only if something needs attention. | Medium | Medium | This is a good "nice/cool/useful" notification because it replaces several possible noisy alerts with one calm check. |
| Doorbell person detected while nobody is home | Doorbell detects a person or is pressed when both tracked people are away. | Notify only for person/press events; suppress generic motion; cooldown per episode. | Medium | Medium | Existing event types include doorbell variants, but preferences and HA routing likely need expansion. |
| Doorbell after bedtime | Doorbell press/person detected during quiet hours. | Immediate for press/person; never for generic motion unless explicitly enabled. | Medium | Medium | Useful and rare. Avoids the common camera-app problem of motion spam. |
| Home Assistant data stale | Backend cannot reach Home Assistant or key entities are stale for a sustained period. | Developer/Josh-only; max once per day plus recovery notice only if useful. | Medium | Low to Medium | Operationally useful, but probably not a Mallory-facing feature. Keep this in Developer preferences. |
| Push delivery degraded | APNs credentials are missing, invalid, or repeated sends are failing. | Developer-only; throttle heavily; also write to Logs. | Easy to Medium | Low | Helps during TestFlight setup without exposing credentials or spamming both users. |
| API recovered after outage | Backend health returns after being unreachable. | Only if an external monitor or client-side failure window exists; max once per outage. | Hard | Medium | The API cannot reliably notify while it is down, so this likely needs an external monitor or client-side observation. |
| To-do location nudge | A user arrives near a saved/favorited To Do location with active related tasks. | Once per location visit; no push if there are no active tasks. | Hard | High | There is already a To Do location model. The hard part is iOS location permissions and mapping tasks to locations cleanly. |
| Family calendar departure reminder | A calendar event with a location is coming up and travel/departure time is near. | Only for selected calendars/events; one reminder per event. | Hard | High | Best kept as a later EventKit phase. Useful, but bigger than push plumbing. |
| "Other person is home, should I avoid garage/lights noise?" routing | Suppress or reroute household notifications when the affected person is home and already likely aware. | This is a rule used by other categories, not a standalone push. | Medium | Medium | Presence-aware suppression is one of the best ways to make notifications feel smart. |

## Recommended Build Order

### Phase 1: Make Existing Push Reliable

1. Verify or finish Apple-side APNs/TestFlight prerequisites.
2. Confirm the bundle ID, APNs entitlement, provisioning profile, and `APNS_ENVIRONMENT` match the installed build.
3. Persist device registrations and notification preferences in Postgres.
4. Add a delivery log and mock push sender for tests.
5. Add the `partner_presence` preference category and default policy.
6. Validate one debug push on a physical iPhone.

Best first live categories:

- Partner leaves home while recipient is home.
- Partner arrives home while recipient is home.

### Phase 2: Add Partner Presence Notifications

1. Choose canonical Josh/Mallory presence entities from Home Assistant.
2. Add a backend presence-state store with freshness timestamps.
3. Convert Home Assistant presence transitions into backend domain events like `person_left_home` and `person_arrived_home`.
4. Add partner-presence rules in the notification coordinator.
5. Add debounce, stale-state suppression, dedupe keys, and delivery logging.
6. Test all four routes:
   - Mallory leaves while Josh is home -> notify Josh.
   - Mallory arrives while Josh is home -> notify Josh.
   - Josh leaves while Mallory is home -> notify Mallory.
   - Josh arrives while Mallory is home -> notify Mallory.
7. Verify negative cases:
   - Other person is away -> no notification.
   - Source state is stale/unknown -> no notification.
   - Tracker flaps home/away/home quickly -> at most one sensible notification, ideally none until stable.

### Phase 3: Add The Delightful Household Notifications

1. Add editor identity to shopping list mutations.
2. Add a shopping edit session aggregator.
3. Send the shopping list edit summary after the editor leaves the list or is inactive.
4. Add the shopping trip completed summary.
5. Add last-minute item rollups while the other person is actively shopping.

Best first "Mallory notices this is useful" category:

- "Josh updated the shopping list: added 3 items and checked off 2."

### Phase 4: Add Presence-Aware Safety And Convenience

1. Add robust presence-aware rules using Home Assistant tracked phone entities.
2. Add garage/lights departure summaries.
3. Add bedtime house check.
4. Add doorbell away/bedtime categories.

### Phase 5: Add Location And Calendar Intelligence

1. Add iOS location permission and geofence handling only after the core push system feels trustworthy.
2. Add store arrival reminders.
3. Add To Do location nudges.
4. Add Family calendar/EventKit reminders if the app becomes the place for household scheduling.

## Detailed Design: Partner Presence Notifications

Target behavior:

- Mallory leaves home while Josh is already home; Josh receives one notification.
- Mallory arrives home while Josh is already home; Josh receives one notification.
- Josh leaves home while Mallory is already home; Mallory receives one notification.
- Josh arrives home while Mallory is already home; Mallory receives one notification.

Non-goals for v1:

- Do not notify when the recipient is away.
- Do not notify the person who left or arrived.
- Do not send Home Assistant mobile-app notifications, SMS, email, or direct Apple pushes from the iPhone. The Levy Home backend sends APNs to the Levy Home app.
- Do not turn every Home Assistant phone activity log entry into a push.

Domain events:

- `person_left_home`
- `person_arrived_home`

Minimum event fields:

- `actorUserId`
- `actorDisplayName`
- `transition`: `left_home` or `arrived_home`
- `previousPresence`
- `currentPresence`
- `source`: `home_assistant` first, later possibly `ios_location`
- `sourceEntityId` or `sourceDeviceId`
- `sourceChangedAt`
- `observedAt`

Rules:

- Notify only the other household user.
- Recipient must currently be `home`.
- Actor must have a real transition, not just a repeated same-state update.
- Source state must be fresh. If HA or iOS has not reported recently enough, skip and log `skipped_stale_presence`.
- For departures, wait a short grace window before sending and re-check that actor is still away and recipient is still home.
- For arrivals, use a shorter grace window or no grace window if traces prove arrivals are stable enough.
- Use a dedupe key such as `partner_presence:{actor}:{transition}:{episodeStart}`.
- If both HA and iOS eventually report the same transition, collapse them into one episode.

Implementation outline:

1. Add backend user identities for Josh and Mallory if they are not already stable enough for notification routing.
2. Add a canonical presence mapping for each user:
   - backend `user_id`
   - display name
   - Home Assistant entity ID
   - optional future iOS device/location source IDs
3. Subscribe to or ingest Home Assistant presence state changes.
4. Store current presence per user with source freshness.
5. On each transition, evaluate the other user's current presence.
6. Queue delayed departure evaluation if needed.
7. Write notification decision rows for sent, skipped, deduped, stale, and preference-disabled outcomes.
8. Send APNs through the Levy Home app's existing push sender.
9. Deep-link to Home or Activity.

Testing outline:

- Unit-test the rule matrix for both users and both transitions.
- Test recipient-away suppression.
- Test stale source suppression.
- Test departure debounce with flapping states.
- Test duplicate HA/iOS source collapse once iOS is added.
- Use a mock push sender before physical-device APNs tests.

## Detailed Design: Shopping List Edit Summary

Target behavior:

- Mallory opens Shopping.
- Mallory adds, edits, deletes, or checks off one or more items.
- The app does not send anything per mutation.
- When Mallory leaves Shopping, backgrounds the app, disconnects from the shopping WebSocket, or has no shopping mutations for a short inactivity window, Josh receives one concise notification.

Example copy:

- Title: `Mallory updated the shopping list`
- Body: `Added 3 items and checked off 2.`

Rules:

- Do not notify Mallory about her own edits.
- Do not notify Josh if Josh is currently viewing the shopping list; let realtime sync handle it.
- Batch edits by editor, recipient, and session.
- Close a session on explicit view exit, WebSocket disconnect, app background, or 90-180 seconds of inactivity.
- Use a cooldown such as 10 minutes per editor-recipient pair unless a new session has materially different changes.
- Prefer counts and high-level action labels over a long item list.
- Include a deep link to Shopping.

Implementation outline:

1. iOS sends stable viewer identity when subscribing to `/api/shopping-list/live`.
2. iOS includes `actorUserId` or a backend-issued session/user identifier on shopping REST mutations.
3. Backend records shopping mutation facts in a short-lived session accumulator:
   - actor
   - affected item IDs
   - counts by action: added, edited, deleted, checked off, unchecked
   - first mutation time
   - last mutation time
4. Backend closes the session on explicit `shopping_session_ended` message, WebSocket disconnect, or inactivity timer.
5. Notification coordinator selects recipients, applies preferences/cooldowns, suppresses active viewers, writes delivery rows, and sends APNs.
6. Tests cover one mutation, many mutations, disconnect, inactivity close, active-recipient suppression, cooldown, and no self-notification.

## Noise Controls To Bake Into The System

- Dedupe key: category plus relevant entity/session/episode ID.
- Cooldown: per category, actor, recipient, and entity.
- Episode tracking: open garage episode, shopping edit session, store visit, doorbell visit.
- Recipient targeting: send to the person who needs to know, not every registered device blindly.
- Foreground suppression: if the target app screen is already visible, rely on realtime UI instead of push.
- Quiet hours: suppress low-priority notifications, but allow safety exceptions.
- Rollups: prefer one summary with counts over a sequence of tiny pushes.
- Delivery log: record attempted, sent, skipped, failed, and preference-disabled outcomes for debugging.

## Suggested Preference Categories

- `partner_presence`
- `garage_security`
- `garage_reminders`
- `shopping_list_summary`
- `shopping_last_minute_adds`
- `shopping_trip_summary`
- `lights_left_on`
- `bedtime_house_check`
- `doorbell_away`
- `doorbell_quiet_hours`
- `todo_location_nudges`
- `developer_health`

The current garage-specific categories can keep working, but the UI should eventually group them so the Preferences screen does not become a giant list of tiny toggles.

## Open Questions

- Should Josh and Mallory each have an explicit backend `user_id`, or should the app start with a simple local household identity picker?
- Which exact Home Assistant entities are canonical for Josh and Mallory presence?
- What grace window feels right for a departure notification: 2 minutes, 5 minutes, or something else?
- Should arrival notifications open Home or Activity?
- Should shopping summaries include item names or only counts? Counts are safer and calmer; item names are more useful when the list is small.
- Should garage/lights pushes ever include action buttons, or should the first version deep-link into the app for confirmation?
- Should native iOS location become a fallback/validator after Home Assistant v1, or only be used for future store/to-do/calendar geofences?
- Which notifications should be enabled by default for Mallory on first TestFlight install?

## Suggested First Defaults

Enable by default:

- Partner presence: the other person leaves home while I am home.
- Partner presence: the other person arrives home while I am home.
- Garage still open at 10 PM.
- Garage opened while nobody is home.
- Shopping list edit summary.
- Shopping trip completed summary.
- Lights left on after everyone leaves.
- Doorbell person/press while nobody is home.

Disabled by default or developer-only:

- Generic garage opened/closed.
- Generic doorbell motion.
- Home Assistant/API health.
- Push delivery degraded.
- Store/location nudges until location behavior is proven.
