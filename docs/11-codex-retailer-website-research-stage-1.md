# Codex retailer website research — Stage 1 decision record

## Scope locked in source

The Stage 1 scope is immutable in `apps/api/src/services/shopping/retailerWebsiteScope.ts`:

- Target — Highlands Ranch: `1365 Sgt Jon Stiles Dr, Highlands Ranch, CO` (canonical Shopping store ID `1`, name `Target`).
- King Soopers — Wildcat Reserve: `2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO` (canonical Shopping store ID `2`, name `King Soopers`).
- The only allowed hosts are `target.com`, `www.target.com`, `kingsoopers.com`, and `www.kingsoopers.com`, over HTTPS without credentials or non-default ports.
- The requested read-only methods are `GET`, `HEAD`, and `OPTIONS`; the runner may claim those limits only after its actual runtime proves it can enforce them.
- Policy is a maximum of 100 items per job, 12 browser navigations per store, a two-minute job timeout, no automatic retailer retry, and fresh confirmed website data before a manual fallback. The public terminal/status vocabulary is defined beside the scope.

The Stage 1 fixture set covers the required in-stock, low-stock, explicit out-of-stock, no-match, ambiguous, mismatched-store, missing-price, missing-aisle, blocked-page, and domain-scope cases without product data or live website requests.

## Read-only environment review

The deployed Shopping endpoint returned a healthy list response with 59 items and the canonical `Target`/`King Soopers` store ID/name pairs above. The deployed readiness endpoint also reported healthy service status. Locally, a logged-in Codex CLI is available for development, but `apps/api` does not yet depend on `@openai/codex-sdk`. The current production Docker image is Node 22 Alpine and does not provision a Codex runtime or deployment authentication; Render-side configuration was not changed or assumed.

## Enforcement finding

Codex CLI documentation supports an exact domain network policy, which is useful for the four-host limit. That control alone cannot tell a user-visible page from a direct JSON, GraphQL, or product API endpoint hosted on the same allowed domain. The reviewed TypeScript SDK material establishes server-side local Codex threads, but does not establish a per-run browser-only guard, same-host path restriction, or HTTP-method enforcement suitable for this deployed feature.

No live Target or King Soopers spike was run. Without a proven browser-only policy, a live run could use disallowed same-host product traffic; a model promise or final narrative would not prove compliance.

## Stage 1 status and required gate

The static Stage 1 scope, policy, fixtures, and tests are implemented. The Stage 1 production-enforcement exit criterion is **not met**.

Before Stage 4 or any live website research, provide and verify in the actual Render-compatible execution profile a technical control that both restricts network destinations to the four hosts and forces rendered-page browser interaction while rejecting direct API/JSON/GraphQL requests, including on an allowed host. It must run with explicit deployment configuration rather than inherited local Codex settings. If that control is unavailable, this feature must remain unavailable under the current no-product-API requirement; do not substitute another site, store, or API.
