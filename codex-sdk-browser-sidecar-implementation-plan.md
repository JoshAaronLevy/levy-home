# Codex SDK browser-sidecar implementation plan

## Context and end goal

Levy Home already has a shared Shopping list and an AI entry point named **Check/Update Stock & Price**. The intended MVP is a user-initiated check of every Shopping item that is still needed (not picked up). For each needed item, the app should look only at the normal, user-visible websites for these exact stores:

| Retailer | Required store | Address | Approved website hosts |
| --- | --- | --- | --- |
| Target | Target — Highlands Ranch | 1365 Sgt Jon Stiles Dr, Highlands Ranch, CO | `target.com`, `www.target.com` |
| King Soopers | King Soopers — Wildcat Reserve | 2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO | `kingsoopers.com`, `www.kingsoopers.com` |

For each store, the check may update only a managed `storeListing` for the item: current price, visible availability (`in_stock`, `low_stock`, `out_of_stock`, or `unknown`), and aisle/location when the selected store’s rendered page visibly supplies it. It must never change the shopping item’s name, quantity, notes, category, image, or picked-up state. It must not use a Target, Kroger, King Soopers, Google, Bing, shopping-aggregator, map, or other product API.

The user chooses the action in the iOS app. The server owns the immutable list snapshot, work queue, retry/timeout policy, normalized result validation, safe listing writes, and realtime broadcasts to the other phone.

### Why the existing action is disabled

The existing implementation deliberately returns `site_scope_unavailable`. It is not waiting for a local Codex sign-in. The public TypeScript Codex SDK starts local Codex CLI threads, but the SDK/CLI does not provide a server-side browser-only tool that can independently prevent an agent from calling a same-host retailer JSON, GraphQL, or product endpoint. A normal host allowlist alone cannot distinguish `www.target.com` rendered pages from `www.target.com` product APIs. Codex Browser is a ChatGPT browser capability, not a browser runtime exposed through the current SDK/CLI service process. See the current [Codex SDK](https://learn.chatgpt.com/docs/codex-sdk.md) and [Browser](https://learn.chatgpt.com/docs/browser.md) documentation.

The previously implemented fail-closed behavior is therefore correct, but it is not the final product. This replacement plan supplies the missing architectural component: a private, constrained browser sidecar. Codex may reason over a minimal item request and structured visible-page evidence, but it never receives direct internet access or a generic browser/terminal escape route. The sidecar—not a Codex prompt—enforces which browser actions are possible.

### What is already implemented and must be preserved

Do not rebuild or delete these working pieces while implementing this plan:

- The immutable `RETAILER_WEBSITE_SCOPE` with the two exact stores, addresses, four approved hosts, allowed read methods, item/browser limits, and failure vocabulary.
- The `RetailerWebsiteResearcher` interface, rendered-page evidence validator, normalized availability types, bounded result schema, and the current `CodexShoppingWebsiteResearcher` fail-closed implementation.
- The stock-price-check migration, durable parent/item run records, one-active-run protection, stale/picked-up/deleted snapshot protection, progress/terminal state handling, and managed-listing merge logic.
- The secure Shopping HTTP routes, public readiness response, background runner, WebSocket updates, Swift request/response models, view-model polling/recovery, and iOS AI entry point.
- Existing fixture coverage and the deployed guard that refuses a live scan without a proven runtime.

The change is intentionally narrow: replace the disabled external-research adapter with a browser-sidecar-backed adapter after every gate in this plan passes. The current unavailable state remains the safe default until then.

## Security and product contract

These rules are binding for every stage.

1. **Only two research destinations.** The browser may start at and visibly navigate only the four hosts in the table above. It must verify the exact address selected in the normal retailer store-selection interface before accepting product facts. It must not search, navigate, extract, or cite another website.
2. **No direct retailer product API calls.** Levy Home code, Codex, the browser-tool interface, and the sidecar must not use `fetch`, `curl`, axios, Playwright’s request client, direct JSON/GraphQL/product URLs, or retailer product API credentials to obtain product details. The sidecar may use only browser navigation, form fill, click, select, wait-for-rendered-state, and visible-text extraction.
3. **Normal browser rendering is distinct from a direct API integration.** Modern retailer pages may make opaque background requests as part of rendering their normal UI. The agent must not choose, invoke, inspect, persist, or derive facts from those requests. It sees only an allowlisted high-level browser tool and text rendered to the user. If the user’s policy instead means that even the browser may not make normal page-rendering background requests, the feature is not technically feasible for modern commerce pages; do not silently weaken this distinction.
4. **Codex has no direct external network path.** The Codex process must run with network access disabled. It communicates with the browser only through a local stdio/private tool bridge that exposes a fixed command vocabulary. Codex must not receive arbitrary shell, file-write, HTTP, browser-devtools, JavaScript-evaluation, raw-HTML, cookie, response-body, or screenshot tools.
5. **Browser actions are allowlisted, not prompt-restricted.** The sidecar validates every command, URL, form target, store key, text length, navigation count, and timeout before executing it. It rejects a disallowed host, a path classified as a direct API endpoint, non-read-only action, login/cart/checkout/pickup action, or malformed command before the browser receives it.
6. **No secret or account leakage.** Do not use a developer’s local ChatGPT/Codex cache in Render. Do not copy `auth.json`, browser profiles, cookies, or login state into Docker, Render, the repository, an IPA, logs, test fixtures, or database tables. Any eventual Codex service credential belongs only in Render’s secret store. Retailer login is out of scope.
7. **Only bounded visible facts persist.** Persist the normalized product name/brand/UPC only if visibly shown, price, availability text/status, aisle/location, selected-store address, and checked timestamp. Never persist raw HTML, screenshots, browser history, cookies, page/network response bodies, Codex transcripts, thread IDs, or credentials.
8. **Failure is safe.** On a blocked domain, unsupported page flow, missing store confirmation, ambiguous/no match, browser/Codex timeout, malformed result, stale item, or browser failure, preserve existing verified listings and record the classified outcome. There is no fallback to another store, another website, a retailer API, a search engine, or an inferred value.
9. **One active household scan.** Existing durable job serialization remains in force. A second phone observes the active job and receives committed listing updates; it does not start another one.
10. **Do not claim live proof early.** Source/build, sidecar-policy, Render/readiness, live-retailer, physical-device, and two-device realtime evidence must be recorded separately.

## Required runtime architecture

```text
iOS action
  -> Levy Home API job/worker
     -> Codex SDK thread (no external network; structured result only)
        -> private stdio browser-tool bridge (fixed commands only)
           -> isolated browser sidecar (normal rendered-page UI only)
              -> Target or King Soopers visible page for the fixed store
  -> existing validator -> durable job records -> safe storeListing write -> WebSocket update
```

The browser sidecar is private infrastructure, not an app-facing endpoint. The API cannot proxy arbitrary URLs through it. The browser tool must be driven by a fixed state machine instead of a generic `openURL`, `runScript`, or `getPageSource` primitive.

The exact implementation library (for example, a supported headless browser plus a local stdio MCP-style bridge) is a Stage 1 decision. The security properties above are mandatory regardless of library. If a library cannot provide them, reject it rather than adapting the policy around it.

## Implementation stages

Stages are sequential and intentionally numbered only. A request such as `Please implement codex-sdk-browser-sidecar-implementation-plan.md stage 4` means implement only that stage, run its stated verification, document the result, and do not begin a later stage.

### Stage 1 — Freeze the browser-sidecar contract and choose a viable runtime

**Purpose:** convert the architectural direction into executable constraints before adding a browser dependency or credentials.

**Work:**

1. Add a short architecture decision record under `docs/` that repeats the two exact stores/addresses, the direct-API definition above, and the private sidecar boundary. This record must be independently understandable if this plan is later moved or deleted.
2. Inspect the current API Docker image, Render service topology, Node version, current `@openai/codex-sdk` version, and the installed browser automation candidates. Do not change Render configuration, credentials, or the currently deployed availability flag in this stage.
3. Select a browser runtime that can run in a Render-compatible Linux container and can: create an ephemeral browser context; route or abort navigation before it occurs; restrict downloads; clear context data; disable popup/new-window escapes; bound navigation time; and return visible text without returning page source or network response bodies.
4. Select a private bridge mechanism supported by the installed Codex SDK/runtime. Prefer a local stdio tool bridge with a fixed schema. Document how Codex will call it and how the Codex process will be denied direct external network access. Do not assume an unsupported SDK tool feature exists—verify the installed API/configuration first.
5. Define the browser session state machine and command set. At minimum it must represent `new_session`, `open_store_home`, `confirm_store`, `search_needed_item`, `open_candidate_product`, `read_visible_product_facts`, and `close_session`. Each command must take fixed store/item inputs and return bounded structured data; none may accept arbitrary URLs, selectors, scripts, request headers, or cookies from Codex or an HTTP client.
6. Define the direct-API path classifier and allowlist strategy. It must reject explicitly requested API/JSON/GraphQL-style paths, query patterns, non-HTTPS URLs, credentials in URLs, custom ports, and non-read-only browser actions. Its purpose is defense in depth; the primary defense is that no generic navigation/request tool exists.
7. Define a non-secret readiness model with separate checks for: persistence, fixed store scope, browser binary/runtime, browser-policy enforcement, private bridge availability, Codex authentication, and Codex runtime. A check may say unavailable without exposing a credential name/value, filesystem path, raw URL, or browser output.

**Verification:**

- Unit-test the command schema and state-transition table with fakes.
- Unit-test direct-API/path/host/method rejection and input size limits.
- Build the API container locally without credentials and prove the new disabled-by-default readiness projection is deterministic.
- Review the proposed Docker/runtime dependency licenses and image footprint before committing to it.

**Exit criteria:** a concrete, Render-compatible browser and private bridge are selected with proof they can enforce the required state machine. If no candidate can do so, stop and record the limitation; do not add a generic browser endpoint, direct retailer client, or local-auth workaround.

### Stage 2 — Create the isolated browser sidecar with no retailer research

**Purpose:** make the browser process operational and disposable without giving it product-search capability yet.

**Work:**

1. Add the browser runtime and system dependencies in a dedicated Docker build layer. Keep the API image deterministic and do not bake a browser profile, user data directory, Codex cache, `.env`, or credentials into it.
2. Create a private browser-sidecar module/process that starts an ephemeral context with downloads disabled, popup handling blocked, a temporary profile, bounded CPU/memory/time limits, and guaranteed cleanup on normal completion, error, timeout, worker cancellation, and process shutdown.
3. Bind the sidecar only to the local/private bridge. Do not create a public HTTP route, public port, general proxy, or iOS-accessible endpoint.
4. Implement a network/navigation policy at the sidecar boundary: only HTTPS, only the four approved retailer hosts for user-visible navigations, only `GET`/`HEAD`/`OPTIONS` where the runtime can control the method, no credentials/ports/fragments that alter scope, no downloads, and no browser permission grants.
5. Add a browser event ledger containing only safe metadata: fixed store key, policy decision, sanitized host/path classification, elapsed time, navigation count, and classified failure code. Do not log query strings, body content, cookie values, rendered text, screenshots, raw URLs, or headers.
6. Add a test-only local fixture site and test-only direct-API-shaped endpoint. Use it to prove that a normal allowed rendered page can be opened while a requested `api`, `graphql`, `json`, or forbidden-host path is rejected before data reaches the caller.

**Verification:**

- Build and start the production Docker image locally.
- Run automated sidecar lifecycle tests: successful cleanup, popup attempt, download attempt, timeout, crash, forbidden host, forbidden scheme, credentials in URL, non-read-only action, and direct-API-shaped path.
- Confirm no sidecar port is exposed by the application and no browser data remains after the test context closes.

**Exit criteria:** an ephemeral, private browser sidecar runs in the production image and can prove policy enforcement against fixtures without visiting a retailer or invoking Codex.

### Stage 3 — Implement the fixed browser command state machine

**Purpose:** replace generic browsing with a narrow set of retailer-page interactions that cannot be repurposed as a web client.

**Work:**

1. Implement typed sidecar commands for the Stage 1 state machine. Each request includes only a `RetailerWebsiteStoreKey` and, after store confirmation, bounded needed-item name/brand/quantity from the existing immutable snapshot.
2. Make `open_store_home` derive its homepage URL from `RETAILER_WEBSITE_SCOPE`; it must not accept an address or URL. Make `confirm_store` compare user-visible page text to the exact configured address and return only `{ confirmed: Bool }` plus bounded safe diagnostics.
3. Implement `search_needed_item` through the rendered site search UI only. The command must not accept CSS selectors, arbitrary form actions, URL fragments, or raw script. Keep all retailer-specific selectors/interaction logic private to the sidecar and versioned by store key.
4. Implement `open_candidate_product` only for candidates discovered from the rendered search state. It must reject product URLs not generated by the current browser session and not classified as a normal visible product/detail route.
5. Implement `read_visible_product_facts` using only visible rendered text/semantic labels. Return the existing bounded `RetailerWebsiteRenderedPageEvidence` shape: selected-store text, product name/brand/UPC when visible, availability text, regular/promo price when separately visible, and aisle/location when visibly supplied. Never return DOM source, arbitrary text dumps, script values, network bodies, cookies, or screenshots.
6. Cap every store session by the existing navigation and job time limits. A blocked action ends that store’s result with a classified safe failure; it does not try a fallback URL, retailer API, web search, or another host.
7. Add fixture-based contract tests for Target and King Soopers state transitions, including in/low/out/unknown/no-match/ambiguous, store mismatch, missing price, missing aisle, blocked page, browser timeout, and every rejected command.

**Verification:**

- All state-machine tests run entirely against local fixtures.
- Tests prove that the commands cannot be used to access arbitrary first-party routes, execute JavaScript, call an endpoint directly, or persist raw browser data.
- Existing retailer-result validator tests remain green without changes to their safety semantics.

**Exit criteria:** the sidecar can produce exactly the existing rendered-page evidence contract from fixtures, and every unsupported transition ends safely.

### Stage 4 — Prove first-party browser feasibility with non-product live checks

**Purpose:** learn whether the two retailer websites can be used through normal rendered UI under the fixed-store and sidecar policies before any shopping item or product fact is touched.

**Work:**

1. Add a separately invokable, operator-only feasibility command that uses the sidecar—not Codex—to open each fixed homepage and reach only the normal store-selection UI. It must not enter a product name, open a product page, call a product endpoint, or write any Shopping data.
2. Record only aggregate/sanitized results: browser launched, fixed host accepted/rejected, store selector reached, exact address visibly confirmed/not confirmed, navigation count, and policy failure code. Do not save page text, screenshots, HTML, cookies, URL queries, or browser network data.
3. Observe whether normal page rendering requires a host outside the four approved hosts. Treat that as `site_scope_unavailable`; do not add a supporting host automatically. Record the host category only as narrowly as needed for a later user decision, without using it as a research source.
4. Confirm that the browser policy rejects a direct-API-shaped navigation on each allowed hostname before it can produce data. This can use a clearly non-product, synthetic path and must not discover or call a retailer product endpoint.
5. Do not provision Codex credentials or enable the iOS action in this stage.

**Verification:**

- Run each feasibility command once in a disposable local/container environment and once in the Render-compatible runtime when available.
- Confirm no database rows, shopping listings, Codex threads, retailer product searches, or product facts are created.
- Add a brief `docs/` verification record distinguishing local fixture proof from live non-product page feasibility.

**Exit criteria:** both retailers can reach and visibly confirm the required store through the sidecar under the user-approved host policy, or a precise blocked prerequisite is recorded for user approval. No product data is collected in either outcome.

### Stage 5 — Add the private Codex browser-tool bridge

**Purpose:** allow Codex to reason over a bounded shopping item while making the sidecar state machine its only research capability.

**Work:**

1. Implement the Stage 1 private stdio/tool bridge using only the supported installed Codex SDK/runtime mechanism. The bridge exposes the typed Stage 3 commands and schemas; it exposes no filesystem, shell, raw-network, raw-browser, screenshot, DOM, or HTTP client functionality.
2. Run Codex with external network disabled, read-only filesystem access, approvals disabled, a temporary working directory, bounded environment variables, one fresh thread per job, and no inherited developer or deployment credentials other than the eventual dedicated Codex credential.
3. Replace the current future-only prompt with a minimal orchestration prompt that tells Codex to call the browser commands in order, requires exact store confirmation, and asks for only the existing JSON schema. The prompt is not a security boundary and must contain no notes, images, user data, raw database rows, credentials, internal paths, or browser diagnostics.
4. Require structured output and continue to run the existing TypeScript result validator after Codex responds. Invalid/missing/duplicate outcomes become safe classified failures.
5. Add an injected fake bridge and fake Codex thread for deterministic tests. Tests must prove Codex receives neither an arbitrary URL nor a direct API tool and cannot obtain a result without `confirm_store` succeeding.
6. Keep `CODEX_SHOPPING_WEBSITE_RESEARCH_READINESS.enabled` false until all Stage 5 tests and Stage 6 credential checks are complete.

**Verification:**

- Run an end-to-end fixture turn: fixed-store confirmation, search, candidate open, visible evidence, structured result, existing validator.
- Run adversarial fixture turns requesting `curl`, `fetch`, a product API, a third-party site, login, checkout, script execution, arbitrary URL, raw page source, and repeated navigation. Each must be rejected by tooling/policy, not merely ignored by the prompt.
- Verify no direct internet connection is possible from the Codex process in the test runtime.

**Exit criteria:** Codex can complete a fake browser-mediated research turn, but cannot reach a retailer or another host directly and cannot invoke capabilities outside the bridge.

### Stage 6 — Add dedicated Codex authentication and accurate readiness

**Purpose:** authenticate the production Codex worker safely and report authentication separately from browser-policy readiness.

**Work:**

1. Decide the supported service credential using current OpenAI documentation: a dedicated API key for server automation, or an organization-approved access token where applicable. Do not use a personal cached desktop/CLI login, copied `auth.json`, a browser profile, or an iOS-provided credential.
2. Add only the required secret to local secure development configuration and Render’s secret store. Do not add it to source, `.env.example`, Docker `ARG`/`ENV`, build logs, test output, or documentation. Never print the name/value while verifying it.
3. Add a non-sensitive startup/readiness probe that distinguishes: missing/invalid Codex authentication, browser sidecar unavailable, bridge unavailable, policy enforcement unavailable, and fixed-store scope unavailable. It must not make a retailer navigation or expose identity/token details.
4. Validate the Codex service credential using a non-retailer, non-product fixture bridge command. It must confirm only that a fresh Codex thread can run a bounded structured tool turn.
5. Keep all existing direct-SDK network proxy configuration as defense in depth, but do not rely on it for browser-only enforcement. Configure Codex itself with external network disabled for this feature.
6. Update API/iOS availability text so it reports a generic safe unavailable state without revealing which secret or runtime check failed.

**Verification:**

- A missing credential produces a sanitized unavailable readiness code and no thread/browser activity.
- A valid credential passes the fixture-only thread probe without a retailer call.
- Logs and public readiness responses contain no secret value, credential type, account identity, internal URL, prompt, raw browser output, or thread ID.

**Exit criteria:** a dedicated Render-held credential can start a bounded Codex fixture turn, and all readiness dimensions are accurately separated without exposing sensitive detail.

### Stage 7 — Connect the sidecar researcher to the existing durable scan worker

**Purpose:** replace the always-unavailable adapter while preserving the established durable job and safe-writing behavior.

**Work:**

1. Implement a new injected `BrowserSidecarCodexShoppingWebsiteResearcher` conforming to `RetailerWebsiteResearcher`. Keep the existing fail-closed researcher available for tests and rollout rollback.
2. Make the researcher process one immutable needed-item/store request at a time. It starts an ephemeral sidecar session, invokes the constrained Codex bridge, validates the response through the existing validator, and closes the session in `finally`.
3. Wire the new researcher into `createApp` only when every readiness check is true. Any unavailable check must select the fail-closed path and preserve the `site_scope_unavailable` behavior.
4. Reuse the existing job snapshot, bounded batching, one-active-job constraint, stale-item protection, managed-listing merge rules, terminal aggregate counts, and WebSocket `item_updated` behavior. Do not add a new mutation path or alter normal Shopping CRUD.
5. Ensure a failed/blocked store leaves prior verified listing data intact while recording a safe per-store outcome. A completed job with some blocked/no-match items becomes `completed_with_issues`; a total infrastructure failure is `failed`.
6. Add recovery behavior for sidecar/browser process loss. A restart may resume only from persisted safe inputs and never reuse a browser context, browser cookies, Codex thread, or unverified partial result.

**Verification:**

- Run full API typecheck, production build, migration/repository/route/orchestrator tests, and existing Shopping realtime/CRUD/active-trip tests.
- Add integration tests for happy-path fixture outcomes across both stores, stale/picked-up/deleted items, concurrent starts, sidecar timeout/crash, malformed Codex output, blocked direct API, no-match/ambiguous/store-unconfirmed, manual-listing preservation, and second-client realtime updates.
- Prove picked-up items never create a browser session or receive a listing update.

**Exit criteria:** a fixture-backed job completes from durable snapshot to safe listing updates using the new adapter, with no regression to ordinary Shopping behavior.

### Stage 8 — Update iOS availability and run-state presentation

**Purpose:** make the existing iOS UI accurately reflect the newly detailed server readiness without exposing security internals or making unavailable functionality look broken.

**Work:**

1. Extend only the public-safe readiness model if required to distinguish “not configured,” “browser policy unavailable,” and “temporarily unavailable.” Do not expose host diagnostics, credential state, browser/session data, Codex details, or raw failures to the phone.
2. Keep the blue AI control disabled and visibly unavailable whenever the backend does not report full readiness. Keep the unavailable state on the button itself; do not restore the persistent translucent status banner removed in the prior UI update.
3. When readiness is true, restore the ordinary enabled blue AI button and its action sheet. The one MVP action remains exactly **Check/Update Stock & Price**; do not add chat, free-form prompts, or speculative AI actions.
4. Preserve current one-start, `409` active-job adoption, polling cancellation/resume, terminal snapshot refresh, WebSocket reconciliation, and summary behavior.
5. Add Swift API-client/view-model tests for safe readiness decoding, unavailable button state, enabled action only when ready, `202`, `409`, progress, completed-with-issues, and sanitized failure messages.
6. Add SwiftUI previews for unavailable, ready, running, completed-with-issues, and compact layouts. Confirm accessibility label/value/hint distinguish an unavailable disabled button from an enabled action.

**Verification:**

- Run focused iOS API model/client/view-model tests and an unsigned simulator build.
- Manually check simulator portrait tab-bar clearance, final-row scroll clearance, action-sheet use, Dynamic Type, VoiceOver order, and disabled-button clarity.

**Exit criteria:** iOS accurately presents only the safe public feature state and cannot initiate a scan before the backend’s complete readiness projection is true.

### Stage 9 — Deploy the sidecar safely to Render

**Purpose:** deploy the private browser/Codex runtime without treating a successful container build as live retailer proof.

**Work:**

1. Review Render configuration before changes: the API remains one instance for its existing in-memory Shopping realtime architecture; the browser sidecar is private to the API/worker topology and exposes no public endpoint.
2. Configure only approved non-secret values and the dedicated Codex credential through Render’s secret store. Confirm the production Docker image contains required browser binaries/dependencies but no login state, browser profile, secret, or test fixture data.
3. Deploy the migration-compatible API and sidecar. Confirm startup, migration completion, health/ready behavior, the normal Shopping snapshot, and Shopping WebSocket `hello`, `snapshot_required`, and presence messages.
4. Run the sidecar policy fixture/health probe in the deployed environment. It must confirm browser startup and bridge/Codex fixture readiness without opening a retailer page or creating a Shopping job.
5. Confirm the public readiness endpoint says enabled only when persistence, fixed scope, browser runtime, sidecar policy, bridge, and Codex fixture authentication are all ready. If any check is false, the button remains disabled and no live research begins.
6. Maintain one clear rollback: switch dependency injection back to the existing fail-closed researcher and redeploy. Do not roll back migrations or erase job history.

**Verification:**

- Record deployment commit, migration result, health/readiness aggregate, sidecar fixture check, WebSocket result, and rollback method in a new `docs/` deployment-gate record.
- Confirm no retailer product page, product endpoint, item listing, or live scan occurred during deployment verification.

**Exit criteria:** the deployed service has a private functioning sidecar and safe readiness truthfully reports whether it is ready. Live retailer research is still not claimed.

### Stage 10 — Perform a controlled live rendered-page research proof

**Purpose:** prove the exact two-store website workflow with the smallest authorized scope before enabling a normal household scan.

**Work:**

1. Obtain explicit authorization for one small, known needed test item that may receive a listing update. Do not use a picked-up item or an item whose listing should not be changed.
2. Run one job through the actual deployed sidecar/Codex path. Verify Target only after visible confirmation of `1365 Sgt Jon Stiles Dr, Highlands Ranch, CO`, and King Soopers only after visible confirmation of `2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO`.
3. Verify from the sidecar’s sanitized policy ledger that the agent used only the constrained rendered-page commands, remained within navigation limits, did not invoke an API/JSON/GraphQL/direct-request tool, and did not navigate/search another website.
4. Inspect only aggregate job state and normalized persisted listing fields through the app/API. Compare price, availability, and aisle/location to the visible selected-store page without retaining raw page text, screenshots, HTML, network data, cookies, prompts, or Codex output.
5. Trigger a controlled blocked action using safe test wiring or a non-product forbidden route. Confirm the job records a safe unavailable/partial result, preserves existing listing data, and does not fall back to any other source.
6. Do not batch more items, add a schedule, add notifications, or expand to another store in this stage.

**Verification:**

- Record the exact fixed stores, aggregate outcome counts, store-confirmation success, policy decision summary, and safe failure result in the release-gate document.
- Confirm no direct retailer API credential/request, third-party site, alternate store, login, cart, pickup, checkout, or purchase occurred.

**Exit criteria:** one authorized item has a safe, visibly sourced, normalized two-store result from the deployed browser flow, and a controlled block proves safe failure behavior.

### Stage 11 — Complete physical-device and two-device release evidence

**Purpose:** prove that the working deployed feature behaves correctly in the actual household app, not only in tests or backend logs.

**Work:**

1. Build the signed Render-pointed iOS app. Inspect the built `Info.plist` and confirm `LevyHomeAPIBaseURL` before installation. Do not substitute a simulator build for this evidence.
2. Install and launch it on one physical iPhone. Confirm the AI button is enabled only when readiness is fully true, remains above the tab bar, is reachable with Dynamic Type, exposes the correct VoiceOver state, and opens the single action sheet.
3. With two household devices when available, start one authorized small scan from one phone. Confirm the other phone adopts the active run or receives resulting `item_updated` messages without starting a duplicate job.
4. Confirm terminal summary states, partial/unavailable messaging, fresh listing price/availability/location display, and existing manual listing precedence behavior. Verify the final row can scroll clear of the floating button.
5. Perform no unapproved retailer scan. If any live research gate fails, return the app to its disabled state and use the existing fail-closed researcher until resolved.

**Verification:**

- Record source/build, Render/readiness, controlled-live-retailer, physical-device, and two-device evidence separately.
- Run the full relevant API and focused Swift regression suites once more before release handoff.

**Exit criteria:** the browser-sidecar-backed feature works for the authorized controlled scan on the deployed service and installed physical app, with two-device realtime proof when a second device is available. Do not call it fully production-proven if any of those evidence categories is missing.

## Guardrails for every implementation stage

- Do not make a live retailer call merely because a stage is being implemented. Only Stage 4’s non-product feasibility checks and Stage 10’s explicitly authorized controlled scan may touch retailer pages.
- Do not set `enabled: true`, remove the disabled UI state, or swap out the fail-closed researcher until the preceding stage’s exit criteria are demonstrably met.
- Do not introduce retailer API keys, a product API client, screen scraping through `curl`/`fetch`, a third-party search service, a generic browsing endpoint, or a free-form user prompt.
- Do not broaden host/store scope automatically. If ordinary page rendering or a store flow needs another host, an account, a CAPTCHA, a redirect, a different store, or a login, stop and request an explicit product/security decision.
- Do not persist or log raw browser/Codex material. Keep support/release evidence to safe aggregate counts and sanitized codes.
- Do not begin a later stage in the same request. Each stage should leave the app safe and deployable, with the feature unavailable unless its complete runtime gate has been proven.

## Non-goals

- Retailer product APIs, direct JSON/GraphQL calls, retailer credentials, Google/Bing/third-party search, maps, or additional store locations.
- Login, account sharing, coupons, substitutions, cart modifications, pickup, checkout, or purchases.
- A user-facing chat interface, arbitrary “ask AI” prompt, automated scheduled scans, price history, price alerts, or new AI menu actions.
- Persisting browser data, raw website content, Codex transcripts, thread IDs, screenshots, credentials, or deployment secrets.
