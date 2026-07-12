# Custom Notifications Backlog

This file is the product backlog for notification ideas. It is intentionally not an implementation plan: each entry records the desired experience, the relevant current architecture, feasibility, and a high-level complexity estimate. When an entry is selected later, create a separate detailed implementation plan before changing production code.

## How To Use This Backlog

1. Add one proposed notification as an entry below.
2. State the user goal, delivery rules, data sources, and per-person/per-device settings.
3. Identify whether it can be done with the current Levy Home backend and iOS app, plus any privacy, permission, or reliability constraints.
4. When ready, request: `Please create an implementation plan for <notification name>.`
5. The resulting plan should preserve this entry's intent, confirm current code/API facts, and define migrations, API contracts, iOS work, tests, rollout, and physical-device validation.

## Notification 1: Custom Morning Briefing

**Status:** Proposed

### Goal

Send each household member a useful morning notification at the time that person chooses. Josh might receive it at 6:00 AM and Mallory at 8:00 AM. Each phone can independently enable or disable the briefing and choose which sections appear:

- Today’s calendar items
- A weather forecast

The briefing should support all useful combinations: calendar-only, weather-only, both, or disabled.

### User Experience

Each phone has a `Morning briefing` settings surface with:

- An enable/disable switch.
- A local delivery time.
- A calendar-summary switch.
- A weather-forecast switch.
- A preview that shows the next generated notification.
- A clear unavailable/permission state when calendar or notification access is not granted.

Example copy:

```text
Good morning, Josh
Today: Dentist at 9:30 AM, Dinner with Mallory at 6 PM.
Denver: 72°, clear this morning, rain likely after 3 PM.
```

The app should omit a disabled or unavailable section cleanly rather than including an empty heading. If neither content switch is enabled, the app should prompt the person to enable a section or turn the briefing off.

### Current Context

- Levy Home already has APNs device registration and backend-owned notification preferences, including per-device state.
- The iOS app already reads calendar/reminder information with EventKit and gets weather through its existing home-weather services.
- Calendar information is device-owned. The backend does not, and should not, log into a person’s iCloud account.
- The current backend can send APNs, but it does not yet own a per-device, time-zone-aware morning-briefing schedule or a stored calendar digest.

### Feasibility

**Yes, this can be done.** The main design choice is freshness and delivery reliability while the app is closed:

| Approach | What it does well | Limitation | Recommendation |
| --- | --- | --- | --- |
| Device-local scheduled notification | Keeps calendar data on the phone and supports independent times without backend calendar access. | Notification content is prepared before scheduling. iOS background refresh is best-effort, so it cannot guarantee a newly computed calendar/weather summary at an exact morning time. | Good low-complexity prototype, but do not promise perfectly fresh content. |
| Backend APNs briefing with device snapshots | Supports reliable per-device timing and can generate weather server-side. Each phone periodically uploads a minimal, privacy-reviewed calendar digest for its own briefing. | Requires new preference, digest, scheduling, privacy, and stale-data logic. | Recommended production design when fresh content at a chosen time matters. |
| Backend connects directly to iCloud calendars | Could generate calendars centrally. | Adds account credentials, consent, synchronization, and security complexity that Levy Home does not need. | Do not use. |

The recommended production version is a hybrid: per-device preferences and scheduled delivery live in the Levy Home backend; weather is generated at send time; calendar text comes from a small per-device digest created on the phone with EventKit. The notification must label stale or unavailable calendar data honestly.

### High-Level Implementation

1. Add a device-scoped `morning_briefing` preference profile:
   - enabled
   - local time and IANA time zone
   - include calendar
   - include weather
   - last successful schedule/delivery metadata
2. Add an iOS Morning Briefing settings page and notification/calendar permission handling.
3. On each phone, use EventKit to produce a minimal digest of the selected calendar items for the upcoming day. Upload only the text/time needed for that phone’s briefing, not full calendar records.
4. Add a backend scheduler that evaluates due device profiles in their local time zones, deduplicates each device/day, fetches a fresh weather forecast, and sends APNs through the existing delivery path.
5. Build the final message from enabled, available sections only. If a calendar digest is stale or missing, send weather-only when enabled, or skip and record the reason when no useful content remains.
6. Add a preview/test action that exercises the same server-side message builder without waiting until morning.
7. Record delivery, preference-disabled, missing-permission, stale-calendar, and provider-failure outcomes in the existing notification/logging surfaces.

### Complexity

| Area | Complexity | Why |
| --- | --- | --- |
| Per-phone settings UI | Low to Medium | Standard toggles, time picker, preview, and independent device preferences. |
| Weather section | Medium | Forecast must be fresh, time-zone aware, concise, and resilient to provider failure. |
| Calendar section | Medium to High | EventKit permission is local to each phone; a reliable closed-app briefing needs a carefully limited device-to-backend digest. |
| Scheduled APNs delivery | Medium to High | Requires time-zone scheduling, deduplication, quiet behavior, retries, delivery logging, and no duplicate sends after deploy/restart. |
| Privacy and failure UX | Medium | Calendar text is personal data; the app must be explicit about what leaves the phone and degrade gracefully. |
| Overall | **High for a reliable production version; Medium for a best-effort local prototype.** | The feature is feasible, but reliable fresh content at an exact time is more than a static local notification. |

### Dependencies And Decisions For The Future Plan

- Confirm whether the calendar summary should use the Family calendar only, chosen calendars, or all visible calendars.
- Decide the maximum number of calendar items and weather detail level so the notification stays glanceable.
- Decide the acceptable freshness window for a cached calendar digest.
- Confirm whether a weather-only briefing should still send when calendar access is denied.
- Decide whether the briefing should respect a per-device quiet-hours setting in addition to its chosen time.
- Verify the deployed backend’s scheduler/runtime capabilities before selecting a queue, cron, or durable-job mechanism.

### Acceptance Criteria

- Josh and Mallory can independently enable/disable the briefing and choose different times.
- Each person can independently enable calendar, weather, or both.
- No calendar text is sent without that phone granting the needed access and opting into the calendar section.
- The same device receives at most one morning briefing per local calendar day.
- A disabled section never appears as empty or misleading content.
- The app can show why a briefing was skipped or degraded in developer logs.
- Physical phones prove delivery at each configured time through the real APNs path.
