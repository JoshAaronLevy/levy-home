# Activity Persistence Decision

Status: Keep memory-only for this refactor.

The API continues to treat recent Activity as a live feed cache backed by `RecentActivityStore`.
Live Home Assistant WebSocket ingestion and best-effort history backfill both feed `/api/events`,
but normalized Activity events are not persisted in Postgres in Stages 9 and 10.

This keeps the structural refactor focused and avoids introducing a second durable event model
before the product expectations for the Activity tab are settled.

Revisit Postgres persistence when one of these becomes true:

- Activity must survive Render restarts without relying on Home Assistant history backfill.
- The app needs audit-grade event history beyond the current recent feed.
- The API needs filtering, pagination, or search over historical Activity that Home Assistant cannot provide reliably.
- Non-Home-Assistant Activity sources become important enough to require durable history.

Current operational expectation:

- `/health` reports process liveness and recent in-memory event count.
- `/ready` reports Activity as `persistenceMode: "memory"` so this choice is visible during operations.
- Phone activity stays Activity/logging data only; it does not trigger APNs push delivery.
