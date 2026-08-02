# Codex SDK shopping stock and price — Stage 11 verification

Verified locally on 2026-08-02. This record is fixture-only evidence; it does not represent a live retailer check, Render deployment, or physical-device proof.

## Automated results

| Area | Command | Result |
| --- | --- | --- |
| API static checks | `npm run api:typecheck` | Passed |
| API production build | `npm run api:build` | Passed |
| API test suite | `npm run api:test` | Passed: 189 tests |
| iOS focused tests | `xcodebuild test ... -only-testing:LevyHomeTests/ShoppingListViewModelTests -only-testing:LevyHomeTests/APIClientTests -only-testing:LevyHomeTests/APIModelDecodingTests` | Passed: 61 tests |
| iOS unsigned simulator build | `xcodebuild build ... -destination 'generic/platform=iOS Simulator' -derivedDataPath build/StockPriceCheckValidation CODE_SIGNING_ALLOWED=NO` | Passed |

The focused iOS suite contains 30 `ShoppingListViewModelTests`, including the Stage 10 display-policy tests, plus 13 API-client and 18 API-model tests. No new warnings or errors were introduced by this feature verification. The focused iOS run logged a simulator-only WeatherKit service warning; all selected tests passed and it is outside the Shopping check path.

## Fixture coverage

The API suite uses disposable PGlite databases and injected fixture researchers. It does not create a Codex thread, make retailer API calls, or navigate to a retailer website.

- The stock-price migration and repository tests verify immutable snapshots, only-needed-item selection, active-job serialization, terminal aggregates, and stale/picked-up/deleted snapshot rejection.
- Route tests verify idempotent starts, second-client active-job handling, readiness failures, and rejection of arbitrary prompts, item lists, retailer URLs, and direct-product-API-shaped input.
- Service fixtures verify the fixed Target Highlands Ranch and King Soopers Wildcat Reserve scopes, manual-listing preservation, persisted normalized outcomes, stale-edit skipping, partial/failure results, and mutation broadcasts.
- Rendered-page contract fixtures cover explicit in-stock, low-stock, out-of-stock, unknown/no-match, missing price/location, mismatched stores, simulated website/Codex failures, and disallowed-host/direct-endpoint/method rejection.
- Shopping realtime tests verify a second connected WebSocket client receives committed item mutations. The full suite also retains normal Shopping CRUD, active-trip, and realtime regression coverage.

## Simulator evidence and remaining gates

The iPhone 16e simulator booted and launched the app for idle-state capture. Fixture-backed SwiftUI previews provide idle, running, unavailable, completed-with-issues, and compact layouts; the automated accessibility labels cover the action, progress/status, store availability, location, price, and freshness text. No live scan was started from the simulator.

Stage 12 remains required for all deployment evidence: Render readiness/migration/WebSocket validation, proof of browser-only enforcement in the deployed runtime, an authorized live rendered-page check limited to the two fixed stores, and physical-iPhone/two-device UI verification. The current fail-closed runtime remains unavailable for live retailer research until that browser-only enforcement gate is proven.
