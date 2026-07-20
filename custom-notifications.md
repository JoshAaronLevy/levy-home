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

## Notification 2: Nightly Tomorrow Preview

**Status:** Proposed

### Goal

Send each household member an optional evening notification that makes the next day easier to anticipate. The default message combines tomorrow's calendar and forecast, for example:

```text
Tomorrow: 2 calendar events. High of 92°, with a chance of afternoon rain.
```

Like the morning briefing, this must be independently enabled, scheduled, and configured on each phone. One person can receive it at 8:00 PM while another turns it off or receives it later.

### User Experience

Each phone has a `Tomorrow preview` settings surface with:

- An enable/disable switch.
- A local delivery time and IANA time zone.
- Calendar-summary and weather-forecast switches.
- A preview/test action that renders the next notification.
- Clear notification and calendar-permission states.

The calendar portion should give a concise count and optionally the next few event names/times. The weather portion should prioritize the expected high/low and noteworthy conditions, such as rain, snow, high wind, or extreme heat. Either section can be used alone; unavailable or disabled sections are omitted cleanly.

### Current Context

- This uses the same APNs registration, per-device preferences, EventKit calendar access, and weather services as the Custom Morning Briefing.
- The next-day calendar digest is device-owned: the backend should receive only the minimal, consented summary required to compose the notification.
- A fresh next-day forecast should be generated near delivery time, not copied from an earlier morning forecast.

### Feasibility

**Yes, this can be done.** It is largely the same backend and privacy problem as the morning briefing, but the notification composer needs a tomorrow-specific date window and forecast selection. The best production design is the same hybrid approach: device-scoped preferences and a small EventKit digest from the phone, with backend scheduling and APNs delivery.

### High-Level Implementation

1. Add a device-scoped `tomorrow_preview` profile: enabled state, local time zone/time, enabled sections, and delivery/deduplication metadata.
2. Extend the iOS settings and EventKit digest generation to provide tomorrow's selected calendar summary.
3. Add a backend message builder that evaluates tomorrow in the receiving device's local time zone and fetches a forecast for that calendar day.
4. Schedule, deduplicate, send, and log it through the same backend notification path as the morning briefing.
5. Add preview/test coverage and degraded-content rules for stale calendar data, denied permission, and weather-provider failures.

### Complexity

| Area | Complexity | Why |
| --- | --- | --- |
| Settings and preview UI | Low to Medium | Mirrors the Morning Briefing controls. |
| Tomorrow calendar and weather composition | Medium | Must calculate "tomorrow" in each device's time zone and keep concise, useful wording. |
| Reliable scheduled APNs delivery | Medium to High | Reuses the same scheduler, deduplication, retry, and logging needs as the morning briefing. |
| Privacy and stale-data handling | Medium | Calendar content remains consented, minimal, and honest about availability. |
| Overall | **Medium to High.** | Best implemented after, or jointly with, the Morning Briefing's shared scheduling and digest foundation. |

### Dependencies And Decisions For The Future Plan

- Confirm whether the calendar section should show only an event count or include the first few events.
- Set a maximum number of events and message length.
- Define which weather conditions warrant an explicit alert-style mention.
- Decide whether it should be a separate notification profile or share controls with the Morning Briefing while retaining independent schedules.

### Acceptance Criteria

- Each phone can independently configure or disable the Tomorrow Preview.
- Calendar-only, weather-only, and combined previews produce useful copy.
- The device receives at most one preview for a given tomorrow/local-date combination.
- The message identifies the next day correctly across time zones and daylight-saving changes.
- Missing calendar or weather data degrades cleanly and is visible in developer logs.

## Notification 3: Custom Weekly Briefing

**Status:** Proposed

### Goal

Send an optional, customizable weekly household briefing at a time and on a day each person chooses. It should provide a calm overview of the coming week without becoming another stream of alerts.

### User Experience

Each phone has a `Weekly briefing` settings surface with:

- An enable/disable switch.
- A preferred day of week, local delivery time, and IANA time zone.
- Independent switches for selected content sections, initially including the upcoming calendar, weekly weather outlook, household to-dos, and shopping-list summary.
- Per-section detail controls where needed, such as the maximum number of calendar events or whether to include completed shopping items.
- A preview/test action and clear permission/unavailable states.

Example copy:

```text
This week: 5 calendar events, warm through Thursday, rain expected Friday. You have 3 shared to-dos and 6 shopping items still needed.
```

The final message should include only enabled and available sections, and it should remain short enough to read from a notification.

### Current Context

- Calendar data is device-owned through EventKit; shared to-dos and shopping data are already Levy Home domain data.
- Weather, notification preferences, APNs delivery, and per-device registration already provide a foundation, but no general weekly scheduler or briefing profile exists yet.
- The weekly message must be generated in the recipient's local time zone and based on their selected content rather than a one-size-fits-all household summary.

### Feasibility

**Yes, this can be done.** The shared-list portions are straightforward once a scheduler exists. Calendar content carries the same local permission and digest constraints as the daily briefings. A weekly forecast is feasible but should be treated as a broad outlook, not precise daily promises.

### High-Level Implementation

1. Define a device-scoped `weekly_briefing` preference profile with schedule, time zone, enabled sections, section detail limits, and delivery metadata.
2. Add iOS settings, permission handling, and a minimal upcoming-week calendar digest when calendar content is enabled.
3. Add a backend weekly scheduler and a section-based message builder that can fetch weather and shared-list summaries at send time.
4. Enforce per-device/week deduplication, retries, quiet behavior, and detailed delivery/skip logs.
5. Provide a preview/test path that runs the same composition logic as scheduled delivery.

### Complexity

| Area | Complexity | Why |
| --- | --- | --- |
| Settings and independent schedules | Medium | Adds day-of-week, section selection, and detail controls per device. |
| Shared-list summaries | Low to Medium | Data is already backend-owned but needs concise, meaningful aggregation. |
| Calendar and weekly weather outlook | Medium to High | Requires the same privacy-safe calendar digest plus forecast interpretation. |
| Scheduler, deduplication, and logging | Medium to High | Must work reliably through deploys, time zones, and daylight-saving changes. |
| Overall | **High for the full customizable version; Medium for a calendar-and-weather-only first version.** | It is feasible and should reuse a general briefing/scheduling foundation rather than introducing a third independent scheduler. |

### Dependencies And Decisions For The Future Plan

- Choose the initial content sections and which are truly useful at weekly cadence.
- Decide whether the weekly briefing is purely individual or can include selected shared-household information.
- Set a concise message-length budget and per-section limits.
- Define behavior when an enabled section has no content: omit it, or show an intentionally reassuring zero-state.
- Decide whether all daily/weekly briefings should share one preferences model and scheduler engine.

### Acceptance Criteria

- Each household member can independently configure, preview, or disable the weekly briefing.
- The selected local day and time are honored with no duplicate weekly delivery.
- Only enabled, available sections appear in the notification.
- Calendar text leaves a phone only after that phone opts in and grants the required access.
- Shared-list information is summarized rather than sending a noisy item-by-item recap.
- Real-device tests prove scheduled APNs delivery and useful degraded behavior when a provider or permission is unavailable.
