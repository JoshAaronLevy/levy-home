# Codex SDK shopping stock and price — Stage 12 deployment gates

Verified on 2026-08-02 against the deployed Levy Home API and one paired physical iPhone. This is a release-gate record: it deliberately distinguishes confirmed deployment/device evidence from the unavailable live-retailer gate.

## Source and build evidence

| Evidence | Result |
| --- | --- |
| Deployed source commit | `c781daaf65a63030764ff76b31d97a6c906a0496` (`Implemented codex-sdk-plan.md stage 11`) |
| Render deployment | `dep-d9noh1tbedkc73f87cf0`, live; completed 2026-08-02T18:13:32Z |
| API migration | Render applied `2026-08-01-001-shopping-stock-price-checks.sql`; 1 migration applied and 13 skipped as already present |
| Physical-device build | Signed Debug `LevyHome` build succeeded for the paired iPhone |
| Built application configuration | `LevyHomeAPIBaseURL=https://levy-home.onrender.com`; bundle ID `com.levyhome.app` |

No Render secret or environment value was added or changed for this stage. The deployment uses the existing database configuration. No Target, Kroger, or other retailer product-API credential was configured or invoked.

## Render and realtime evidence

The deployed service returned healthy status and the normalized Shopping snapshot with 59 items, 2 stores, and 10 categories. The deployed migration completed before the new API process started.

`node scripts/verify-shopping-list-render-readiness.mjs --api-base-url https://levy-home.onrender.com` passed after correcting the verifier to compare the server's canonicalized presence viewer ID. It verified the Shopping WebSocket `hello`, `snapshot_required`, and `presence_changed` messages without writing a test item.

`GET /api/shopping-list/ai/readiness` returned a safe readiness projection:

- persistence and the immutable Target Highlands Ranch / King Soopers Wildcat Reserve scope passed;
- the only four configured research hosts and read-only method policy passed;
- the Codex runtime browser-only policy failed closed with `site_scope_unavailable`.

A valid `POST /api/shopping-list/ai/stock-price-checks` was rejected with HTTP 503 and `site_scope_unavailable`. This confirms no check job, Codex thread, retailer navigation, or listing mutation begins while the browser-only restriction remains unavailable. The subsequent Shopping snapshot remained at 59 items with zero AI-annotated listings.

## Physical-device evidence

The signed Render-pointed build was installed and launched on the paired physical iPhone (`com.levyhome.app`). This proves the device can install and launch the deployed-service build; it does not substitute for manual visual inspection.

## Intentionally unclaimed gates

The following gates are not complete and must remain separate from the successful build/deployment evidence:

- **Live-retailer evidence:** not run. The current server-side Codex SDK runtime cannot independently enforce browser-only navigation while rejecting same-host product/API/JSON/GraphQL access. No Target or King Soopers website navigation, product lookup, or product API call was attempted.
- **Two-device realtime/UI evidence:** not demonstrated. Only one physical iPhone was paired during this stage, so a second household device has not observed a live listing update. Manual confirmation of floating-control tab-bar clearance and VoiceOver behavior on the installed phone also remains required.

The feature is therefore deployed and safe to expose as unavailable, but it is **not fully production-proven for live stock/price checks**. Do not enable a live scan until a deployed, technically enforced browser-only runtime is available and the remaining live-retailer and two-device/manual UI gates are completed.
