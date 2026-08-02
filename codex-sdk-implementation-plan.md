# Codex SDK shopping stock and price checks

## Context

Levy Home already has a collaborative SwiftUI Shopping screen backed by the Express API. Each shopping item can persist one or more `storeListings`, which already carry a store, product details, aisle/shelf location, price, inventory payload, availability status, and check timestamp. The current UI renders those listings as store and price pills, gives `in_stock`, low/limited, and out-of-stock data distinct tones, and keeps devices in sync over the existing Shopping WebSocket.

The screen in `shopping_list_view.png` is presented inside the `RootTabView` tab bar. It currently has a scrolling list with a persistent tab bar at the bottom, so an AI entry point must stay visibly above the tab bar while content scrolls underneath it. It must not obscure the item controls, the tab bar, or the final rows in the list.

There is already a server-side Kroger/King Soopers product client, but this feature must **not** call it—or any Target, Kroger, or other retailer product API—to obtain product details. `shopping_locations` supplies the household stores; the test contract and supplied screenshot show Target and King Soopers. This MVP instead uses a constrained Codex SDK browser/web-search run to research only the retailers’ own user-visible websites, scoped to exactly these stores:

- **Target — Highlands Ranch:** `1365 Sgt Jon Stiles Dr, Highlands Ranch, CO`
- **King Soopers — Wildcat Reserve:** `2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO`

The only permitted external website hosts are `target.com`/`www.target.com` and `kingsoopers.com`/`www.kingsoopers.com`. The research may use their normal rendered store/product search pages only; it may not call site JSON/GraphQL endpoints directly, use an unofficial product API, invoke a third-party search engine, or visit/cite any other site.

The API does **not** currently include `@openai/codex-sdk`, a Codex client, or an AI job system. The production API is a Node 22 Alpine container deployed as one Render instance. The Codex TypeScript SDK is server-side and controls local Codex threads; it therefore needs a deliberately provisioned, authenticated Codex runtime in the deployment environment. A developer machine's `codex login` state cannot be assumed to exist in a fresh Render container.

## End goal

On the Shopping screen, a sticky circular **AI** button appears at the bottom-right above the tab list. Tapping it opens an extensible Shopping AI menu. Its first live action is **Check/Update Stock & Price**.

Selecting that action starts one durable, household-wide check of the items that are needed at the time the job starts (`purchased == false`). The server uses a constrained Codex SDK run to search the normal rendered pages on only `target.com`/`www.target.com` for the Highlands Ranch Target at `1365 Sgt Jon Stiles Dr` and `kingsoopers.com`/`www.kingsoopers.com` for King Soopers Wildcat Reserve at `2205 W Wildcat Reserve Pkwy`. It writes only facts observed for those exact stores back to the same items. For each matched item/store combination, the app displays the current price, availability (`in stock`, `low stock`, or `out of stock`), and exact in-store aisle/shelf location only when the site shows one. It uses `unknown` rather than guessing when a match, a price, an inventory state, or a location cannot be verified.

The UI immediately shows progress, prevents duplicate scans, receives committed listing changes through the existing live-shopping channel, and ends with an honest summary of updated, unmatched, and failed items. A site, Codex, or domain-scope failure must never mark an item out of stock, erase manual listing data, alter an item’s name/quantity/category/notes/image/picked-up state, expose credentials, or leak Codex thread IDs, prompts, browser history, raw site payloads, or filesystem paths to the iOS app.

## Product and architecture decisions

These decisions are part of the MVP contract. Later stages must preserve them unless this plan is intentionally amended first.

1. **The job snapshots all needed items, not the filtered or visible rows.** Category, text, store, and compact/detailed filters do not change its scope. Items picked up before the job begins are excluded. If an item is edited, deleted, or marked picked up after the snapshot, the writer detects that conflict and skips the stale result rather than overwriting a newer user change.

2. **The two first-party sites are the source of record.** Codex must read only the normal rendered product/store pages on `target.com`/`www.target.com` and `kingsoopers.com`/`www.kingsoopers.com`, after setting/verifying the exact Target Highlands Ranch and King Soopers Wildcat Reserve stores above. It must not invoke the existing Kroger client, Target APIs, a retailer JSON/GraphQL endpoint, a search-engine API, or any third-party site. It does not invent stock, prices, locations, UPCs, or product matches; it has no browser login, direct database access, or write access to the API workspace.

3. **Store and domain scope are mandatory, not prompt suggestions.** The Target research scope is only `1365 Sgt Jon Stiles Dr, Highlands Ranch, CO`; the King Soopers scope is only Wildcat Reserve at `2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO`. Stage 1 must prove that the Codex execution environment can enforce the four exact allowed hosts **and a browser-only boundary that rejects direct same-host JSON/GraphQL/API traffic**. A host allowlist by itself is insufficient because a direct product API can be served by an otherwise allowed host. A result is valid only if the rendered page/session confirms the matching store address. Redirects, location ambiguity, a missing in-store selection, a blocked page, or a request to any other host produces `unknown`/a failed outcome. Do not silently substitute another Target/King Soopers location or a one-store result.

4. **Only managed listings change.** The job maintains one website-researched listing per requested store, identified by the canonical `storeId` plus `source` (`kingsoopers.com` or `target.com`) and the exact selected store address. Existing manual listings and listings from other stores remain in persistence. When both manual and verified listings exist for one store, the latest verified listing has display priority; the manual value remains a fallback rather than being destroyed. The UI must not render two contradictory chips for the same store.

5. **Availability meanings are fixed.** `in_stock`, `low_stock`, `out_of_stock`, and `unknown` are the only persisted normalized values. Only an explicit status shown by the permitted store page may produce `out_of_stock`; a missing result, ambiguous product, unverified store selection, missing page detail, timeout, blocked browser request, or domain-scope violation becomes `unknown`/a failed outcome, never out of stock.

6. **Jobs are asynchronous and durable.** A full list can contain dozens of items and two store-site searches, so the start route returns `202 Accepted` and a public job summary. The server, rather than the iPhone, owns the snapshot, Codex website research, writes, retry accounting, and final status. At most one stock-and-price job may run for the household at a time.

7. **Codex is least-privileged and ephemeral.** Use a fresh, single-purpose Codex thread for each job; do not retain a conversational shopping thread. Keep any internal thread identifier private and avoid persisting it unless restart recovery proves it is required. Run the agent with a read-only sandbox, approvals disabled, a domain allowlist containing only `target.com`, `www.target.com`, `kingsoopers.com`, and `www.kingsoopers.com`, and only read-only methods supported by the actual runtime (targeting `GET`, `HEAD`, and `OPTIONS`). It must also have a technically enforced browser-only boundary that rejects direct retailer APIs/JSON/GraphQL calls even when they share an allowed host. It may navigate/search the sites’ user-visible pages, but it may not use a direct retailer API or visit another host. Apply a short timeout and strict input/output limits, and include no secrets in the prompt. If that boundary cannot be technically enforced, Codex cannot be authenticated/started, or either store cannot be selected, the endpoint reports a safe unavailable/partial status and makes no unverified item changes.

8. **Every committed item update uses the established mutation/realtime path.** The stock-price writer must use or extend `ShoppingListMutationService` rather than bypassing it with an isolated SQL update. That preserves item versions, active-trip consistency, WebSocket `item_updated` broadcasts, and the existing client reconciliation behavior.

## Proposed public contract

The exact TypeScript and Swift names may follow existing project naming, but the API behavior below is the implementation contract.

### HTTP routes

| Route | Behavior |
| --- | --- |
| `POST /api/shopping-list/ai/stock-price-checks` | Validates a small request containing the existing actor identity and a client mutation/request ID; snapshots needed items on the server; creates a queued job; starts the worker; returns `202` with the public job summary. The body must never accept arbitrary item data, site URLs, prompts, location overrides, or credentials. |
| `GET /api/shopping-list/ai/stock-price-checks/:jobId` | Returns the current public summary for that job. It is safe to poll and has no raw site/Codex diagnostic data. |
| `GET /api/shopping-list/ai/readiness` | Returns feature-level readiness only: enabled/disabled, whether the fixed two-store website scope is enforceable, and whether the Codex runner is available. It exposes neither secret values nor authentication details. This can remain internal to the client flow if a separate route is unnecessary after implementation. |

Use `409` with the currently active public job when a second request arrives while one is queued/running, not a second worker. Use a stable, sanitized failure code (`ai_unavailable`, `site_scope_unavailable`, `store_not_confirmed`, `website_unavailable`, `invalid_agent_result`, etc.) plus user-safe text. Do not return stack traces, source URLs containing session data, tokens, raw page data, Codex messages, or thread IDs.

### Job summary

```json
{
  "ok": true,
  "id": "uuid",
  "status": "queued | running | completed | completed_with_issues | failed",
  "phase": "preparing | checking_stores | matching_products | applying_updates | finished",
  "requestedItemCount": 0,
  "processedItemCount": 0,
  "updatedItemCount": 0,
  "unmatchedItemCount": 0,
  "failedItemCount": 0,
  "skippedStaleItemCount": 0,
  "submittedAt": "ISO-8601",
  "startedAt": "ISO-8601 or null",
  "finishedAt": "ISO-8601 or null",
  "failureCode": "optional sanitized code",
  "message": "optional user-safe summary"
}
```

Persist the snapshot and a per-item outcome internally so a worker restart, retry, support investigation, and final counts are deterministic. The public response contains counts and safe status only. Keep the run records for a documented bounded retention period; a scheduled cleanup is not required for the first functional stage unless the deployment needs it immediately.

### Managed listing shape

Continue to use `ShoppingItemStoreListing` / `ShoppingItemStoreListing` on the API and iOS side. Extend its typed availability metadata rather than replacing the existing JSONB `store_listings` column.

```json
{
  "storeId": 2,
  "storeName": "King Soopers Wildcat Reserve",
  "source": "kingsoopers.com",
  "selectedStoreAddress": "2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO",
  "product": {
    "productId": "site-visible product ID when supplied",
    "upc": "optional site-visible UPC",
    "brand": "optional site-visible brand",
    "name": "site-visible product name",
    "image": "optional product image"
  },
  "aisle": {
    "display": "aisle and shelf display only when supplied",
    "description": "optional location description",
    "number": "optional aisle",
    "shelfNumber": "optional shelf"
  },
  "price": { "regular": 0, "promo": 0 },
  "availability": {
    "status": "in_stock | low_stock | out_of_stock | unknown",
    "checkedAt": "ISO-8601",
    "matchStatus": "matched | no_match | ambiguous | website_error | store_unconfirmed"
  },
  "checkedAt": "ISO-8601"
}
```

Prices are USD and the UI continues to prefer a verified promotional price over a regular price. Missing price/location fields remain absent; no empty strings or fabricated `Aisle 0` placeholders. Store only the bounded, rendered-page facts required to show the result and the exact selected-store address; do not retain browser cookies, page dumps, screenshots, hidden data, or direct API payloads. The normalized availability and the check timestamp are the app-facing facts.

## Implementation stages

Stages are intentionally sequential and numbered only. A request such as `Please implement codex-sdk-implementation-plan.md stage 5` means implement that stage completely, run its listed verification, report the result, and do not begin a later stage.

### Stage 1 — Lock the two-site research boundary and deployment feasibility

**Purpose:** establish the fixed website/store scope and prove it can be enforced before any Codex implementation can reach the internet.

**Work:**

1. Read the live `GET /api/shopping-list` response and the relevant `shopping_locations` records using safe, read-only access. Record the canonical app store IDs/names, but lock the web-research targets to **Target Highlands Ranch, 1365 Sgt Jon Stiles Dr, Highlands Ranch, CO** and **King Soopers Wildcat Reserve, 2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO**. Never print database credentials or customer-specific secrets.
2. Audit current Render configuration, Docker build/runtime constraints, Node version, and the existing Codex CLI/SDK authentication method without changing secrets. Confirm the actual production execution environment can enforce all of these independently of the model prompt: exactly the four allowed hosts, only read-only methods that the runtime can technically restrict, and browser/page navigation while rejecting direct same-host JSON/GraphQL/API requests. A domain allowlist alone is not sufficient proof because it cannot distinguish a rendered page from a same-host product endpoint. A local logged-in CLI is useful only as a local development proof.
3. Only after Work 2 supplies that technical browser-only enforcement, run an isolated, non-product fixture/spike against the normal rendered websites. Confirm that the site UI can set/verify the exact store address and expose a user-visible product/search result without a product API, JSON/GraphQL endpoint, third-party search engine, or any other host. A prompt assertion or agent narrative is not proof. If the runtime cannot enforce the browser-only restriction, or a site needs a disallowed redirect, login, host, method, or direct API call, treat the scope as unavailable rather than weakening it.
4. Create one immutable `RetailerWebsiteScope` definition containing the two exact store names/addresses, the four allowed hosts, allowed read methods, and the rule that only the sites’ rendered search/product/store pages may be used. Make this an injected configuration/constant shared by the runner and tests—not free text that the caller or prompt can override.
5. Define the user-facing status vocabulary, one-store-per-item display precedence rule, requested run timeout, maximum list/batch size, browser-navigation limit, retry policy, and terminal statuses. Keep the first action limited to stock, price, and in-store location; do not add substitutions, cart building, purchase actions, notifications, or additional AI menu actions.
6. Add synthetic fixture examples for the two exact scoped stores: in stock, low stock, explicit out of stock, no match, ambiguous match, unconfirmed/mismatched store, missing price, missing aisle, blocked page, and domain-scope violation.

**Exit criteria:** The exact two-store/four-host boundary is encoded and technically enforceable, including a separately enforced browser-only/direct-API prohibition rather than only a domain allowlist; Codex has a documented production authentication/runtime path; and the service has defined limits and error behavior. If either site cannot be researched through its rendered pages inside that boundary, stop here and report the concrete limitation rather than adding a product API, a third-party site, an alternate store, or a local-only workaround.

### Stage 2 — Add durable scan and normalized-listing contracts

**Purpose:** create the types and persistence needed for a safe asynchronous process before any external call can update a shopping item.

**Work:**

1. Add TypeScript domain types for normalized availability, match status, website-observed product results, selected-store evidence, per-item outcomes, and the public stock-price-check summary. Extend `apps/api/src/contracts/shopping.ts` and its barrel exports with backward-compatible optional fields.
2. Add the matching Codable Swift models in `LevyHome/Models/API/ShoppingAPIResponses.swift` and request types in `ShoppingAPIRequests.swift`. Existing response decoding must remain compatible with manual and older store listings that lack new metadata.
3. Create a forward-only SQL migration for a `shopping_stock_price_check_runs` table and a `shopping_stock_price_check_items` table (or an equivalently queryable parent/JSONB child design). Persist the job ID, state/phase, immutable item snapshot with item version, per-store outcomes, safe failure code, counters, actor, and timestamps. Add database constraints for allowed states, sane count values, and one active household job. Do not store Codex login data, raw prompts, tokens, or thread IDs in these tables.
4. Implement a repository that creates, claims, updates progress for, completes, and reads jobs atomically. Its snapshot query must use the established `fetchNeededShoppingListItems` behavior and capture the version/state used for stale-write protection.
5. Add unit and PGlite integration coverage for migration application, empty needed list, one-active-job enforcement, state transitions, persisted counters, and stale snapshot detection.

**Exit criteria:** Typecheck passes, migrations are repeatable on a disposable database, and a job can be created/read/transitioned entirely with fakes. No website navigation, retailer product API request, Codex invocation, endpoint, or UI appears yet.

### Stage 3 — Implement the first-party website-research contract

**Purpose:** define the only permitted way the job can obtain product facts: bounded, user-visible research on the two specified retailer sites.

**Work:**

1. Introduce a `RetailerWebsiteResearcher` interface with a fixed `RetailerWebsiteScope` and a bounded `research(item)` operation. Its result must distinguish a confirmed rendered-page match, no match, store-unconfirmed, website failure, and domain-scope failure; it carries only site-visible product name/brand/UPC when shown, price, availability text, and aisle/location fields without guessing.
2. Define the expected research sequence for each item/store: navigate directly to the permitted retailer homepage; set or confirm the exact address in the normal store-selection UI; use that site’s own search UI; open only same-host product/detail pages as needed; capture only user-visible stock, price, and location. The search must never invoke the existing Kroger client, an external/first-party JSON or GraphQL product endpoint, `fetch`/`curl`, an external search engine, or another website.
3. Require explicit evidence that the selected Target page says `1365 Sgt Jon Stiles Dr, Highlands Ranch, CO` and the selected King Soopers page says `2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO`. A product result without confirmed store context is `store_unconfirmed`, not a usable result. If the retailer does not show an aisle/shelf, leave it unknown.
4. Normalize only text/values visibly displayed by the permitted page to the four availability values. Map an explicit user-visible out-of-stock message to `out_of_stock`, a documented limited/low message to `low_stock`, and absent/unsupported data to `unknown`. Normalize a price only when finite and non-negative; preserve regular and sale prices only when separately shown.
5. Implement a strict `WebsiteResearchResult` validator: fixed store ID/address/host, one result per item/store, allowlisted same-host page URL without sensitive query data, bounded text lengths, and no data fields that cannot be linked to the rendered page result. Store page HTML, cookies, browser history, screenshots, hidden DOM content, and network traffic must not be persisted.
6. Add deterministic fixture tests for both exact website scopes, including visible in/low/out signals, no result, ambiguous result, mismatched store, blocked page, disallowed host, disallowed method, missing price, and missing aisle. Tests must never call live sites or product APIs.

**Exit criteria:** Given a needed item and synthetic rendered-page evidence, the contract returns a bounded, normalized result or a classified failure while rejecting every API/host/store-scope escape. No live website navigation occurs until the constrained Codex runner in Stage 4 is ready.

### Stage 4 — Add the constrained Codex SDK website-research runner

**Purpose:** use Codex as the only product-research worker while enforcing the two-site, two-store boundary outside of the model prompt.

**Capability-gate review:** The public TypeScript SDK controls local Codex CLI threads. Its published thread options provide sandbox, approval, network, web-search, and structured-output settings, but not a browser-only tool or a same-host API/JSON/GraphQL prohibition. The published Codex Browser capability is unavailable in the CLI/IDE. Exact-host local network rules are useful but do not make rendered-page research safe by themselves. Therefore an SDK dependency or a prompt is not Stage 4 completion: until a server-compatible browser runtime with those independently enforced controls is verified in the deployed environment, the researcher must return `site_scope_unavailable` without starting a Codex thread or visiting a retailer website.

**Work:**

1. Add `@openai/codex-sdk` as an API runtime dependency and create a small injected `CodexShoppingWebsiteResearcher` service. Isolate SDK-specific code so routes, repository, orchestration, and result validation can be tested with a fake researcher.
2. Confirm the installed SDK’s actual supported thread/run and agent-internet options before coding them. Create a fresh thread per scan, run it server-side, use a read-only sandbox and approvals disabled, and enforce an empty-baseline exact-host allowlist containing only `target.com`, `www.target.com`, `kingsoopers.com`, and `www.kingsoopers.com`. Independently prove a browser-only runtime/tool policy that rejects direct HTTP clients and same-host product API/JSON/GraphQL endpoints; apply read-only method limits only where the actual runtime supports their enforcement. Do not rely on a prompt to enforce any part of this boundary. If the SDK/runtime cannot enforce every required control, the feature remains unavailable.
3. Make the runtime use only normal browser/page navigation and each site’s visible search/store-selection/product pages. It must not expose `curl`, `fetch`, scripts, direct HTTP calls, or API/JSON/GraphQL requests for product information; it must not use Google, Bing, a shopping aggregator, a map service, a CDN, login, cart, pickup, or checkout flow. A browser redirect or resource request to any host outside the four-host list terminates that site’s result as a domain-scope failure. If the browser itself requires a resource from another host, do not relax the scope; return an unavailable outcome.
4. Construct a minimal prompt from the immutable needed-item snapshot and fixed `RetailerWebsiteScope`. For every item it must: (a) research Target only after confirming `1365 Sgt Jon Stiles Dr, Highlands Ranch, CO`; (b) research King Soopers only after confirming `2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO`; (c) report only rendered-page facts; (d) choose `no_match`, `ambiguous`, `store_unconfirmed`, or `website_error` rather than infer; and (e) emit a compact machine-readable result. The prompt contains no app paths, service credentials, user contact data, raw database rows, or writable instructions.
5. Require structured output using the SDK/CLI’s supported JSON-schema mechanism where available; otherwise parse the final response defensively. Validate in ordinary TypeScript: expected item/store IDs; fixed store address; allowed source host; one outcome per requested pair; finite observed prices; four normalized availability values; bounded product/aisle strings; no duplicate results; and no private/internal fields. Codex text is never executed and is not returned to iOS.
6. Provision the runtime in the actual deployment image/service only after a local fake-run test and a non-secret startup/readiness check prove compatibility. The current Alpine production image may need a supported Codex-compatible base image; make that change only with an explicit build and startup verification. Keep authentication outside source control and Docker layers.
7. Add unit tests for prompt redaction/bounds; each exact address/host requirement; valid visible-page result; no match; mismatched store; disallowed host/method; direct-API attempt; malformed JSON/text; duplicate item/store results; timeout; unavailable authentication/runtime; and no-write behavior on every runner error.

**Exit criteria:** The API can invoke a fake website researcher end-to-end, and the real SDK is isolated behind a tested, technically enforced four-host, browser-only gate. Tests must prove that a direct product API/JSON/GraphQL attempt on an allowed host is rejected, not merely described as prohibited in a prompt. No result from another site, another store, a direct product API, or unconfirmed rendered-page state can be applied.

### Stage 5 — Build the scan orchestrator and safe item writer

**Purpose:** combine the snapshot, constrained Codex website research, durable run state, and existing shopping mutation system into one restart-safe workflow.

**Work:**

1. Implement `StockPriceCheckService` with explicit phases: claim queued job; load immutable needed-item snapshot; run constrained Codex website research for both fixed store scopes in size-limited batches; validate/normalize website outcomes; apply safe listing changes; persist progress and terminal result. It must make zero external product API calls.
2. Define batch behavior for a large list. Bound simultaneous Codex research/browser navigations and input size, report incremental counts, and continue independent items after one item/store failure. The service must classify the final job as `completed`, `completed_with_issues`, or `failed` from the recorded outcomes.
3. Merge a verified website-researched listing by canonical `storeId`/source/exact address while retaining unrelated/manual data. A confirmed rendered-page result replaces the prior managed listing for that same site/store. A `no_match`, `ambiguous`, or `store_unconfirmed` result produces an explicit `unknown` managed state with no stale price or fabricated location; a website/domain-scope failure leaves prior verified data intact and records the failure rather than pretending it was freshly checked.
4. Before applying each item result, re-read/lock the current item and compare its snapshot version and needed state. If it was deleted, changed in a material matching field, or marked purchased, record `skipped_stale` and do not write. Do not mutate name, brand, quantity, notes, category, image, or purchased status in this workflow.
5. Route every successful listing write through an intentional bulk extension of `ShoppingListMutationService` (or its documented equivalent), with an `AI stock check` actor and unique internal mutation IDs. Preserve optimistic versioning, active-trip updates, and `item_updated` broadcasts. Do not emit per-item push notifications merely because stock data changed.
6. Make job recovery deterministic. On process startup, reconcile jobs left `queued`/`running` by either safely resuming from persisted inputs with a new private Codex run or marking them failed/retryable by the documented timeout policy—never leave them permanently in progress.
7. Add integration tests with fake website researcher/realtime hub for success across both exact stores, low/out/unknown mapping, no match, mismatched store, blocked page, direct-API/domain rejection, invalid Codex output, concurrent job rejection, stale item skip, manual-listing preservation, managed listing replacement, WebSocket broadcasts, and recovery after a simulated interruption.

**Exit criteria:** A seeded shopping list can complete a fake two-store scan from durable job creation through live item updates. Assertions prove that only listing data changes and every displayed value originated from allowed, store-confirmed rendered-page fixture evidence—not an API response or another website.

### Stage 6 — Expose secure HTTP routes, readiness, and observability

**Purpose:** make the background workflow reachable by the iOS app without turning the API into a prompt, product-data API proxy, or unrestricted browser endpoint.

**Work:**

1. Add the Stage 2 `POST` and `GET` routes to `shoppingListRoutes` (or a tightly scoped sibling router), validators, dependency injection in `createApp`, and route registration. Follow existing async-handler and error-response conventions.
2. Validate the start body strictly: accepted actor values/length and one caller mutation/request ID only. The server determines items and stores. Reject oversized/unrecognized fields, empty/invalid IDs, and duplicate active requests without starting work.
3. Return `202` immediately after durable enqueue/claim. Start the runner outside the response path while retaining a process-local guard; let job persistence, not a request-held promise, be the source of truth. Return the active job on `409` so a second phone can monitor it instead of starting another scan.
4. Add a non-sensitive readiness projection to the existing health/readiness surface. It should say whether the Target Highlands Ranch scope, King Soopers Wildcat Reserve scope, four-host/method allowlist, Codex runtime/authentication, and database persistence are ready, but never output token status codes, account identities, secret names/values, prompts, browser history, page URLs with query data, or stack traces.
5. Add structured logs/metrics containing only job ID, phase, elapsed time, aggregate counts, fixed store key, and sanitized failure code. Add bounded request, browser-navigation, and Codex-run timeouts. Ensure error handlers redact secrets and raw page/Codex output.
6. Add route integration tests for `202`, empty needed list, `409` active job, read status transitions, invalid body, unavailable readiness, site-scope/Codex failure, direct-product-API rejection, and public-response redaction. Run the existing API typecheck, test suite, and production build.

**Exit criteria:** The HTTP contract is safe to call from any connected household device, is test-covered, accurately signals when the two-site feature cannot run, and exposes no internal agent, browser, or website-research details.

### Stage 7 — Add iOS API contracts and polling support

**Purpose:** let Swift decode the public job contract and request/observe one scan without coupling the UI to backend internals.

**Work:**

1. Add Codable request/response/status/phase models and availability/match metadata to the shopping API model files. Unknown future enum values should decode safely as an `unknown` case or a user-safe fallback rather than crash the Shopping screen.
2. Add `APIClient+Shopping` methods to start a stock-and-price check, fetch a check by ID, and optionally fetch readiness. Use the existing base URL, JSON decoder, API error handling, and mutation/request-ID conventions; do not call Codex, any retailer product API, or retailer website directly from iOS.
3. Preserve HTTP semantics in Swift: decode `202`, surface `409` with the active job, and turn sanitized API failures into local `APIError` messages. Treat a network interruption while polling as recoverable; the job continues on the server.
4. Add `URLProtocol`/API client tests for coding/decoding, request method/path/body, `202`, `409`, malformed public response, availability values, and proof that a response cannot contain internal thread/path/raw-output fields.

**Exit criteria:** iOS can start and monitor only the public job API against fixtures, with no UI behavior changed yet.

### Stage 8 — Extend `ShoppingListViewModel` for one active check

**Purpose:** give the SwiftUI screen a single observable state machine that starts, resumes, polls, refreshes, and reports the server-owned job correctly.

**Work:**

1. Add injected closures/protocol methods for start/get/readiness so the view model remains unit-testable. Add published state for current job summary, feature readiness, start/poll error, and a computed `isStockPriceCheckActive`.
2. Implement `startStockPriceCheck()` to prevent local double taps, generate a request ID, request a server job, adopt a `409` active job, and begin bounded polling. The method must require the already-loaded list state only for UI messaging; the server remains the authoritative snapshot owner.
3. Poll only while a job is queued/running and the selected/active Shopping screen is visible. Use a modest backoff, cancel tasks on disappear/background, resume the same job on foreground/selection, and refresh the normal shopping snapshot at every terminal state. A canceled poll task must never cancel the server job.
4. Reconcile WebSocket item updates normally while a scan runs. Do not locally overwrite live results with a stale response or run a second refresh that discards a newer mutation. Keep an explicit final summary for completed-with-issues and recoverable offline/poll failures.
5. Add async view-model tests for one start call under rapid taps, `409` adoption, progress polling, terminal refresh, background cancellation/resume, transport failure with later recovery, no needed items, and live-realtime updates arriving during a job.

**Exit criteria:** The view model can drive the entire action without the screen knowing about Codex/browser details, and no duplicate client request or poll loop survives navigation.

### Stage 9 — Add the sticky AI entry point and extensible menu

**Purpose:** implement the requested visual control without changing the existing shopping controls or tab navigation.

**Work:**

1. In `ShoppingListContentView`, place a dedicated overlay/safe-area composition outside the `ScrollView`, aligned bottom-trailing. Use SwiftUI safe-area layout rather than a hard-coded tab-bar offset, and retain enough bottom scroll padding so the last row remains reachable behind the control.
2. Add a circular, minimum 44-point tappable control styled with the existing app palette, a `sparkles` symbol, and visible `AI` affordance where it fits the design. It is sticky while the content scrolls, sits above the tab bar on compact and large iPhones, and has the accessibility label **Shopping AI**.
3. Model menu options as a small enum/data source so later actions can be added without duplicating presentation logic. Present an action sheet/confirmation dialog titled **Shopping AI**. For this MVP, the one selectable action is exactly **Check/Update Stock & Price**; do not add speculative AI actions or a chat composer.
4. Selecting that action calls `viewModel.startStockPriceCheck()`. Disable/relabel the action while a job is active, show a lightweight in-context progress affordance (for example, `Checking stock & price… 12 of 24`), and provide a clear non-blocking unavailable/error message. No extra confirmation is required after the user selects the action.
5. Respect Dynamic Type, VoiceOver order, reduced motion, color contrast, and keyboard/sheet presentation behavior. The plus button, search, filters, New/End Shop action, category chips, row controls, and tab list must remain unchanged.
6. Add SwiftUI previews for idle, running, unavailable, completed-with-issues, and compact screen sizing. Perform an interactive simulator check specifically for tab-bar clearance and scrolling the final item into view.

**Exit criteria:** The requested floating button and menu work visually and accessibly, invoke only the view-model API, and remain safely above the bottom tab list without altering current Shopping interactions.

### Stage 10 — Present verified listing freshness and outcomes clearly

**Purpose:** make the new data useful without implying certainty the allowed store pages did not supply.

**Work:**

1. Update the store-listing row/display helpers to use the normalized availability values consistently: green for in stock, warning for low stock, critical for out of stock, and neutral for unknown. Continue rendering location only from `aisle.display`/description visibly supplied by the confirmed store page and price only when valid.
2. Coalesce manual and website-researched entries for the same canonical store in the screen display. Prefer the freshest verified Target Highlands Ranch or King Soopers Wildcat Reserve listing, maintain a manual fallback, and do not render duplicate Target or King Soopers chips. Keep full raw/manual editing behavior intact in the item editor.
3. Add concise freshness/context text where it fits the existing design—such as an accessible `Checked just now`/timestamp detail in item details or the scan summary—without crowding the compact list. A missing price/location must read as unavailable/unknown, not as `$0.00` or a placeholder aisle.
4. Present terminal job results as a dismissible, truthful summary: updated count, review/unmatched count, failed count, and stale-skip count when nonzero. It should guide the user to review the affected list entries without exposing agent/browser diagnostics or implying that another store was searched.
5. Add view-level/unit tests for price precedence, all four availability tones, no duplicate store rendering, unknown/missing values, stale timestamps, and accessible labels that include the store, availability, location when known, price when known, and freshness.

**Exit criteria:** The visible Shopping list accurately distinguishes a verified result from unknown/failed data and cleanly displays the requested stock, location, and price for both stores.

### Stage 11 — Complete automated and manual integration verification

**Purpose:** prove the complete feature across API, persistence, realtime, SwiftUI, and deployment-like conditions before release work.

**Work:**

1. Run the API typecheck, tests, and production build. Run focused migration/repository/route/orchestrator tests against a disposable database and all existing shopping tests to catch regressions in normal CRUD, active trips, and realtime behavior.
2. Run the relevant Swift test target, including `ShoppingListViewModelTests`, API client/model tests, and newly added tests. Build the iOS app without signing for a simulator; investigate new warnings/errors rather than attributing failures to unrelated existing warnings.
3. Execute a local end-to-end fixture scenario: several needed and one picked-up item; both fixed website scopes; visible in/low/out/unknown/no-match outcomes; a mismatched store and disallowed-host/direct-API attempt; a concurrent second phone request; a stale edit while the job is running; and a simulated site/Codex failure. Confirm the picked-up item is never researched or altered, only intended listings change, job counts match, and second-client updates arrive via WebSocket.
4. Use a simulator to capture the screen during idle, running, and terminal states. Confirm the floating button stays above the tab bar in portrait, the final row can scroll above it, the action sheet is usable, filters do not change scan scope, and VoiceOver labels make the action/status understandable.
5. Add a brief verification record to the plan’s implementation notes or project documentation with commands run, fixture-only versus live-site proof, results, and remaining external gates. Do not put credentials, tokens, browser history, raw page data, or Codex output in it.

**Exit criteria:** All automated checks pass and the feature has full local fixture proof. This stage does not claim physical-device or live-site production proof until Stage 12 is completed.

### Stage 12 — Deploy safely and obtain real-device evidence

**Purpose:** verify the production worker environment and the actual household stores without confusing build proof with live stock proof.

**Work:**

1. Configure Render only with approved non-secret configuration names and secret values through its secret store: database access already required by the API, the immutable two-store/four-host/method allowlist, and the supported Codex service authentication/runtime configuration. Do not configure, invoke, or add credentials for a Target, Kroger, or other retailer product API. Update the Docker image/base only as required by the Stage 4 runtime proof. Do not bake login state, `.env`, or secrets into an image, IPA, repository, logs, or docs.
2. Deploy with one API instance as required by the existing in-memory Shopping realtime architecture. Confirm the new migration ran, health remains good, WebSocket connectivity remains healthy, and AI readiness proves the exact site allowlist before enabling the UI action for a live scan.
3. First run an opt-in live smoke check using a small, known needed test item with authorization to update it. Confirm Codex searches only the rendered pages on `target.com`/`www.target.com` for `1365 Sgt Jon Stiles Dr, Highlands Ranch, CO` and `kingsoopers.com`/`www.kingsoopers.com` for `2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO`. Verify only aggregate API job status and persisted normalized listing fields; compare them against those user-visible pages without recording protected raw content or navigating elsewhere.
4. Build, install, and launch the Render-pointed app on a physical iPhone. Confirm the built app’s `LevyHomeAPIBaseURL` before installation. On two household devices when practical, start one check, watch the other receive listing updates, and confirm the floating control’s real tab-bar clearance and accessible behavior.
5. Verify failure behavior in the deployed environment: temporarily use only safe readiness simulation/test wiring, or observe a controlled blocked-page/domain-scope condition, to prove the app reports unavailable/partial results without corrupting existing listings or falling back to another site/store/API. Remove any temporary test configuration afterward.
6. Record release gates separately: source/build evidence, Render/readiness evidence, live-retailer evidence, and physical-device evidence. Do not call the feature fully production-proven if any gate is missing.

**Exit criteria:** The feature works on the deployed service and an installed physical iPhone, two-device realtime behavior is demonstrated when available, and current data is visibly sourced/normalized without leaking any secret or internal agent state.

## Verification commands and guardrails

Use the exact commands appropriate to the changed stage; do not interpret a successful API build as visual or physical-device proof.

```sh
npm run api:typecheck
npm run api:test
npm run api:build

xcodebuild test \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -destination 'platform=iOS Simulator,id=<verified-simulator-id>' \
  -derivedDataPath build/StockPriceCheckTests

xcodebuild build \
  -project LevyHome.xcodeproj \
  -scheme LevyHome \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/StockPriceCheckValidation \
  CODE_SIGNING_ALLOWED=NO
```

Before any deployed proof, use the existing read-only Shopping readiness workflow and inspect only its safe aggregate output. Before an iPhone install, build and verify the device bundle URL, then install/launch and inspect the actual UI; simulator proof alone is not physical-device proof.

## Non-goals for this MVP

- No user-facing chat, free-form shopping prompt, or direct iOS-to-Codex connection.
- No Target, Kroger, or other retailer product API calls; no direct JSON/GraphQL endpoint calls; no third-party search engine, shopping site, map, CDN, or website. The only allowed external research is normal rendered-page navigation/search on `target.com`/`www.target.com` and `kingsoopers.com`/`www.kingsoopers.com` for the two exact addresses in this plan.
- No account sharing, login, cart changes, checkout, substitutions, coupons, or purchases.
- No automatic changes to the shopping item itself beyond its website-researched `storeListings`.
- No scheduled/background recurring scans, notifications for price/stock changes, or historical price charts.
- No additional AI menu actions until the first action is deployed, verified, and intentionally planned.
- No exposure of API secrets, retailer credentials, retailer raw data, Codex transcripts/thread IDs, or deployment filesystem paths in the app or logs.
