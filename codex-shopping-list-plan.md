# Codex Shopping List MVP plan

## Context and end goal

This plan builds the first useful AI Shopping feature for Levy Home: quickly re-add familiar Shopping items from plain text or speech-to-text.

The common household workflow is not finding a new product online. It is remembering that staples such as eggs, milk, muffins, coffee, granola, or chocolate chips need to be bought again. Those items usually already exist in the shared Shopping list but are marked as picked up.

The intended experience is:

1. A household member taps the floating **AI** button in Shopping.
2. They type or dictate a request such as **“Add 2 coffees and eggs.”**
3. The app sends the text to the Levy Home API. The API reads a compact, current snapshot of all Shopping items—needed and picked up—and gives that snapshot to Codex as structured context.
4. Codex identifies the closest single existing item for each requested thing. It handles exact, plural/singular, loose, and semantic matches. For example, **“eggs”** should select `Eggs` over `Egg Cups`; **“2 coffees”** can select `Iced Coffee`.
5. Codex returns only a structured list of existing item IDs and explicitly requested quantities. It does not return database objects or executable instructions.
6. The API re-reads and validates every selected item, then applies the approved changes through the existing Shopping mutation service:
   - `purchased: false` makes an item needed again.
   - `quantity` is updated only when the request explicitly supplies one.
7. The original phone receives a concise result and an **Undo** option. The other household phone receives normal realtime list updates.

This MVP deliberately does **not** browse the web, call a retailer/product API, inspect product images, create new Shopping items, modify categories/notes/brands/store listings, or ask the user to choose between candidates. It automatically chooses the closest plausible existing item and is designed to be tuned using real household use and the Undo path.

### Current model and terminology

The database/API field is `purchased`, not `needed`:

- `purchased: false` means the item is needed and should be on the active Shopping list.
- `purchased: true` means the item has been picked up.

An existing Shopping item already contains the information needed for matching: `id`, `name`, optional `brand`, optional `notes`, `quantity`, `purchased`, and version information. The model does not need store listings, product images, browser data, retailer information, user contact data, raw database rows, or any data outside the Shopping list.

### Why Codex is appropriate for this MVP

This is a server-side, structured text-matching task. Codex receives a short user request plus a bounded JSON array of household Shopping candidates, then returns a schema-validated operation list. It has no need for web search, browser access, retailer access, shell access, or a free-form tool.

Codex authentication is still required in the deployed API, but it is now a straightforward service-runtime concern rather than the browser-security blocker from the previous stock/price feature. The deployed API must use a dedicated OpenAI service credential stored only in Render’s secret store; it must never copy a developer’s local Codex/ChatGPT login cache or `auth.json`. The current [Codex SDK](https://learn.chatgpt.com/docs/codex-sdk.md) supports server-side TypeScript threads, while the current [authentication documentation](https://learn.chatgpt.com/docs/auth.md) describes API-key authentication for programmatic workflows.

## Binding product rules

1. **Existing items only.** This MVP only reactivates or changes the quantity of existing Shopping rows. If a request has no plausible existing match, it is reported as unmatched and makes no database change.
2. **Automatic closest match.** The server does not ask for confirmation before applying a plausible single match. Exact normalized name matches win over plural/singular matches; those win over loose semantic matches; additional qualifiers are penalized. Thus `eggs` should outrank `Egg Cups` for “eggs.”
3. **No unrelated guess.** “Closest” does not mean arbitrary. If no item is plausibly related to the requested phrase, return `unmatched`; do not turn an unrelated item into a needed item merely to produce a result.
4. **Quantity means set, not increment.** “Add 2 coffees” sets the selected item’s quantity to `2`; it does not add two to its existing quantity. A request with no quantity preserves the current quantity.
5. **Only two mutable fields.** An AI re-add operation may change only `purchased` to `false` and, when explicitly requested, `quantity` to a bounded positive integer. Name, brand, notes, category, image, store listings, and every other field remain unchanged.
6. **The API owns writes.** Codex output is untrusted input. It may refer only to IDs in the API-created snapshot. The API re-reads each item, applies stale/deleted protection, performs the database mutation, and broadcasts committed changes. It never persists a full object returned by Codex.
7. **No external research.** Disable Codex network access and web search for this feature. Do not use the browser-sidecar plan, retailer sites, retailer APIs, external search, Maps, or product images.
8. **One request is idempotent.** The iOS request includes a mutation/request ID. Retrying the same request must return the same completed result rather than reapplying quantity or flipping state again.
9. **Undo is required.** Because fuzzy matching is automatic, a successful request creates a short-lived, durable undo record containing only the prior `purchased`, quantity, and version values needed to safely revert its own updates. Undo reverts only unchanged AI-applied rows and skips later user edits.
10. **No secret or transcript retention.** Do not persist raw Codex prompts/responses, thread IDs, service credentials, or account identities. Store only sanitized request/result summary data needed for idempotency, UI feedback, undo, and debugging.

## Data flow and contracts

### API-to-Codex snapshot

The API reads the Shopping list itself. iOS never sends the list or its own candidate IDs. Codex receives a bounded snapshot such as:

```json
{
  "request": "Add 2 coffees and eggs",
  "items": [
    { "id": 14, "name": "Iced Coffee", "brand": "Stok", "quantity": 1, "purchased": true, "version": 8 },
    { "id": 22, "name": "Eggs", "quantity": 1, "purchased": true, "version": 4 },
    { "id": 23, "name": "Egg Cups", "quantity": 1, "purchased": true, "version": 2 }
  ]
}
```

The real payload is bounded by a documented maximum item count and per-field lengths. It includes optional `brand` and `notes` only when useful for disambiguation. It excludes `storeListings`, item images, categories, timestamps, user/device data, database metadata, and all secrets.

### Codex-to-API structured answer

Codex returns a restrictive schema, not Shopping objects:

```json
{
  "operations": [
    {
      "requestIndex": 0,
      "requestedText": "2 coffees",
      "itemId": 14,
      "quantity": 2,
      "matchKind": "semantic"
    },
    {
      "requestIndex": 1,
      "requestedText": "eggs",
      "itemId": 22,
      "matchKind": "exact"
    }
  ],
  "unmatched": []
}
```

The server validates that every `itemId` exists in the immutable snapshot, each request index appears at most once, no item is targeted twice, quantities are only present when explicitly requested and are within the allowed range, and `matchKind` is one of the public-safe values. Any malformed, duplicate, unknown, out-of-range, or stale operation is skipped or fails the request safely; it is never guessed or repaired by model text.

## Implementation stages

Stages are sequential and numbered only. A request such as `Please implement codex-shopping-list-plan.md stage 3` means implement only that stage, run its stated verification, report the result, and do not begin a later stage.

### Stage 1 — Lock the AI re-add scope and public contracts

**Purpose:** define the feature independently of the disabled stock/price browser work and create the type boundaries before enabling Codex or changing the UI.

**Work:**

1. Add API domain types for an AI Shopping re-add request, public result summary, operation summary, unmatched phrase, match kind (`exact`, `normalized`, `semantic`), and undo availability. Keep them separate from stock-price-check contracts.
2. Add matching Codable iOS models and API request types. Unknown future enum strings must decode to a safe `unknown` case instead of crashing Shopping.
3. Define strict request validation: one actor (`Josh` or `Mallory`), UUID mutation/request ID, nonempty trimmed text, a safe maximum text length, and no client-provided item list, IDs, quantities, or raw model instructions.
4. Define the compact internal candidate snapshot type. It must include only item ID, name, optional brand/notes, purchased flag, quantity, and current version. Establish maximum list size, maximum item-field length, maximum requested phrases, and quantity range (minimum 1; use a documented conservative maximum such as 99).
5. Define exact public semantics for each outcome: re-added, quantity-updated, already-needed, unmatched, stale-skipped, invalid-request, unavailable, and undone. Do not expose prompts, confidence narratives, model names, thread IDs, or internal validation details to iOS.
6. Define the automatic matching policy in code-adjacent documentation: normalized equality; singular/plural and punctuation normalization; strong token overlap; brand/notes cues; semantic similarity; penalty for extra qualifiers; and unmatched when no plausible relation exists. Codex chooses one candidate, but the server remains the final policy validator.
7. Record the MVP non-goals: no new-item creation, browsing, retailer lookup/API, image matching, category selection, quantity increment/decrement semantics, recurring automation, free-form chat, or user confirmation picker.

**Verification:**

- Unit-test validation for text, actor, UUID, request bounds, result decoding, quantity bounds, duplicate operation rejection, unknown IDs, and unknown enum values.
- Add a contract fixture for “Add 2 coffees and eggs” that selects `Iced Coffee` and `Eggs`, not `Egg Cups`.
- Confirm existing Shopping CRUD and stock-price contracts remain backward compatible.

**Exit criteria:** typed public/internal contracts and an unambiguous automatic-match policy exist, with no Codex invocation, route, database write, or UI change yet.

### Stage 2 — Add durable request, result, and undo persistence

**Purpose:** make automatic fuzzy updates idempotent and safely reversible before any model response can change a Shopping item.

**Work:**

1. Add a forward-only migration for an `shopping_ai_readd_runs` parent record and queryable operation records (or an equivalently constrained parent/child design). Persist request ID, actor, sanitized requested text, state, timestamps, aggregate counts, bounded public summary, and undo expiry.
2. Persist only the operation facts needed for idempotency and undo: target item ID, snapshot version, prior purchased state, prior quantity, applied purchased state, applied quantity, operation status, and sanitized match kind. Do not persist the full Shopping snapshot, raw Codex response, prompt, thread ID, tokens, or credentials.
3. Enforce one durable result per request ID and define the lifecycle `queued`, `matching`, `applying`, `completed`, `completed_with_issues`, `failed`, and `undone` (or equivalent). A repeated request ID returns the stored result and never applies a second mutation.
4. Implement repository methods to create/read/claim/finalize a run, persist operation results atomically, identify an undoable completed run for its bounded window, and mark a run undone only after all eligible reversions complete.
5. Define cleanup/retention behavior for expired undo records. Retention must be bounded and must not delete ordinary Shopping history.

**Verification:**

- Run repeatable migration tests on a disposable database.
- Test duplicate request IDs, transition validity, parent/child consistency, expiry, run readback, and cleanup.
- Test that no stored column contains a prompt, raw model text, thread ID, token, cookie, website data, or credential.

**Exit criteria:** the server can persist an idempotent AI request and the exact minimum pre-update state required for a safe undo, entirely with fakes and no Codex call.

### Stage 3 — Build the offline Codex matching adapter and authentication gate

**Purpose:** configure Codex as a private structured list matcher, not as an internet-connected agent or autonomous database writer.

**Work:**

1. Add an injected `ShoppingListReaddMatcher` interface with `match(requestText, candidateSnapshot)` and a deterministic fake implementation for tests. Keep it independent of the browser-sidecar and stock-price researcher interfaces.
2. Implement `CodexShoppingListReaddMatcher` with a fresh server-side Codex thread per request, structured output schema, bounded timeout, read-only sandbox, approvals disabled, web search disabled, and external network access disabled.
3. Construct a minimal prompt containing only the requested text, matching rules, and compact candidate JSON. Explicitly prohibit new items, item IDs outside the snapshot, duplicate targets, extra fields, quantity inference where none was stated, web use, tool use, and any prose outside the output schema.
4. Verify the installed SDK’s supported authentication configuration. For local development, use an explicitly supplied secure credential only; for production, document a dedicated Render secret. Do not use or copy local `auth.json`, desktop credentials, browser data, or a developer’s account cache.
5. Add a non-sensitive readiness check that separately reports matcher runtime unavailable, authentication unavailable, persistence unavailable, and ready. It must not make a retailer request, call web search, or expose secret/account details.
6. Implement a strict parser/validator around Codex output. A malformed response, timeout, duplicate operation, unknown item ID, invalid quantity, or unsupported field becomes a safe failed/unavailable result with no Shopping mutation.

**Verification:**

- Use a fake Codex thread to test exact, normalized, and loose-semantic fixture outputs.
- Test prompts/outputs for no item images, store listings, user/device data, retailer terms, browser commands, or direct database instructions.
- Test network-disabled thread configuration and a missing/invalid credential path without logging a secret.
- Run a fixture-only successful structured turn once credentials are available; it must produce no database write by itself.

**Exit criteria:** Codex can return a validated, bounded plan for fixture candidates while having no network/browser capability and no path to write the database directly.

### Stage 4 — Implement closest-match planning and automatic-match safeguards

**Purpose:** make fuzzy automatic selection useful for real household language while preventing unrelated guesses.

**Work:**

1. Add deterministic candidate normalization in ordinary TypeScript before Codex: case/punctuation normalization, singular/plural variants, tokenization, safe aliases derived from item name/brand/notes, and duplicate candidate detection. This reduces ambiguity and keeps matching behavior understandable.
2. Give Codex the full bounded candidate list plus the normalized matching rules. Require one best candidate per requested phrase or `unmatched`; do not allow a ranked candidate array or user-confirmation flow in this MVP.
3. Apply a server-side plausibility check to Codex’s answer. It must accept exact/normalized matches readily, allow loose semantic matches such as `coffee` → `Iced Coffee`, and reject clearly unrelated selections. Make this check intentionally permissive at first but observable through sanitized match kinds and Undo usage so it can be tuned from real household behavior.
4. Enforce the `Eggs` versus `Egg Cups` rule with fixtures: exact normalized `eggs` must select `Eggs`; a request explicitly mentioning cups must select `Egg Cups`; plural/singular variants must behave identically.
5. Parse explicit numeric and written quantities from the original requested phrase. A quantity belongs only to that phrase’s selected item; absent quantity preserves the current item quantity. Reject zero, negative, decimal, oversized, or ambiguous quantity instructions.
6. Define duplicate phrase/target behavior. If multiple phrases resolve to the same item, merge only when a deterministic quantity rule is safe; otherwise retain one operation and report the duplicate phrase as an issue rather than applying an unpredictable mutation twice.
7. Add fixture coverage for staples, brand cues, notes cues, pluralization, punctuation, “Add 2 coffees,” already-needed items, unmatched requests, close-but-unrelated requests, and multiple similar list entries.

**Verification:**

- Unit tests prove “eggs” chooses `Eggs`, “egg cups” chooses `Egg Cups`, and “2 coffees” chooses `Iced Coffee` with quantity 2.
- Tests prove an absent quantity preserves the existing value; an explicit quantity sets rather than increments it.
- Tests prove Codex cannot cause an update to an item outside the API’s candidate snapshot.

**Exit criteria:** fixture requests produce one deterministic, validated automatic target per plausible phrase, with safe unmatched behavior for unrelated requests.

### Stage 5 — Apply validated plans through safe Shopping mutations and add Undo

**Purpose:** turn a validated matching plan into committed shared-list updates without losing concurrent user edits.

**Work:**

1. Implement a service that claims a re-add run, fetches the current candidate snapshot, calls the injected matcher, validates the plan, and applies operations one at a time through an intentional extension of `ShoppingListMutationService`.
2. Before each update, re-read/lock the item and compare its version/state to the matching snapshot. If it was deleted or materially edited, record `stale_skipped`; do not overwrite a newer user update.
3. For a picked-up match, set `purchased: false` and preserve quantity unless the request explicitly supplies one. For an already-needed match, change quantity only when explicitly supplied and different; otherwise record `already_needed` with no write.
4. Use unique internal mutation IDs, the selected actor, normal optimistic/version behavior, active-trip handling, and existing `item_updated` WebSocket broadcasts. Do not create an alternate direct repository write path.
5. Persist the exact prior values before each committed update. Implement a single-run Undo service that reverts only rows whose version still matches the AI-applied update; later user edits are skipped, never overwritten.
6. Return a public summary listing applied item names, requested quantities, already-needed items, unmatched phrases, stale skips, and whether Undo is currently available. Keep internal candidate scores and model details private.
7. Do not create new Shopping items in any failure/unmatched path.

**Verification:**

- Integration tests with fake matcher/realtime hub for picked-up re-add, already-needed no-op, explicit quantity update, stale/deleted skip, duplicate request replay, partial completion, and broadcast behavior.
- Undo tests for a full revert, expired Undo, already-undone request, and a row changed by another phone after the AI update.
- Existing normal Shopping CRUD, active-trip, and realtime tests remain green.

**Exit criteria:** a fixture-backed request safely changes only `purchased` and explicit quantity, emits normal realtime updates, is idempotent, and can safely undo its own unchanged changes.

### Stage 6 — Expose narrow HTTP routes, readiness, and observability

**Purpose:** let iOS send one natural-language re-add request and observe/undo its result without exposing Codex as a general endpoint.

**Work:**

1. Add narrowly scoped routes such as `POST /api/shopping-list/ai/readd`, `GET /api/shopping-list/ai/readd/:runId`, and `POST /api/shopping-list/ai/readd/:runId/undo`. Use existing async handler, mutation ID, actor, and error conventions.
2. The start body accepts only requested text, actor, and mutation ID. Reject client-supplied candidate lists, item IDs, quantities, prompts, model controls, URLs, store data, or arbitrary fields.
3. Return `202` after durable creation/claim and complete matching/applying outside the request-held promise. Return the stored run for an idempotent replay. Define a safe policy for concurrent different requests rather than allowing competing updates to race.
4. Add a public-safe readiness projection specific to re-add matching. It must not be coupled to the disabled stock-price/browser readiness, because offline re-add matching can be ready while stock/price checking remains unavailable.
5. Add structured sanitized logs/metrics with run ID, phase, aggregate counts, elapsed time, and safe error code. Do not log requested text if it may include private notes; do not log candidate names, prompts, responses, credentials, or thread IDs.
6. Add bounded request/model timeouts, cancellation behavior, and recovery for runs interrupted by a process restart. A recovered run must never duplicate an already committed mutation.

**Verification:**

- Route tests for valid start, invalid body, idempotent replay, status read, undo, expired undo, matcher unavailable, malformed model response, and concurrent requests.
- Confirm public JSON is redacted and direct web/retailer access is impossible from this feature.
- Run API typecheck, full API tests, and production build.

**Exit criteria:** iOS has a small secure public API for one re-add action, and the API cannot be used as a generic Codex, prompt, candidate-selection, or website endpoint.

### Stage 7 — Add iOS API, view-model, and offline-safe state handling

**Purpose:** connect Shopping to the public re-add contract while retaining existing list refresh and realtime behavior.

**Work:**

1. Add Codable request/run/operation/undo models and `APIClient+Shopping` methods for start, fetch status, and undo. Use the established API base URL, error handling, and UUID mutation ID conventions.
2. Extend `ShoppingListViewModel` with an injected re-add client, observable current run, start/poll/undo state, and a computed availability separate from `isStockPriceCheckUnavailable`.
3. Implement one active local request guard, bounded polling while the Shopping screen is visible, cancellation on background/disappear, recovery on foreground, and terminal Shopping snapshot refresh.
4. Reconcile normal WebSocket item updates during and after the run. Never let a stale polling response overwrite a newer item mutation from the server.
5. Surface the public summary: re-added names, quantities changed, already-needed items, unmatched phrases, partial issues, and Undo availability. Do not expose model confidence, candidate list, prompts, or runtime details.
6. Add async tests for start, idempotent retry, progress, terminal refresh, transport interruption/recovery, Undo, expired Undo, realtime updates during a run, and unavailable matcher state.

**Verification:**

- Run focused API client/model/view-model tests with URLProtocol fixtures.
- Confirm an unavailable re-add service leaves the text input usable but clearly explains that it cannot submit; it must not affect the separate stock-price feature state.

**Exit criteria:** iOS can initiate, observe, and undo one server-owned re-add run safely, without direct Codex access or duplicate local work.

### Stage 8 — Build the AI text-entry experience and keyboard dictation path

**Purpose:** make quick typed or dictated re-add requests fast enough to beat manual list editing.

**Work:**

1. Change the AI menu so the first MVP action is clearly named **Add items from text** (or an equivalent user-tested label). Keep the existing stock-price action separate and unavailable; do not pretend the two features share readiness.
2. Present a compact sheet with an accessible multiline text field, example placeholder such as “Add 2 coffees and eggs,” Submit/Cancel actions, loading state, result summary, and Undo button when available.
3. Ensure the text field supports the standard iOS keyboard dictation microphone automatically. Do not add a custom microphone permission flow in this stage; system dictation is the simple first talk-to-text experience.
4. Disable only duplicate submits while a run is starting/running. Do not disable the entire Shopping screen, existing plus/search/filter/trip controls, or normal item checkboxes.
5. Use clear fast feedback: “Finding items…,” then “Added 2 items,” plus specific compact details. Unmatched phrases should say they were not found in the existing list; do not offer web search or create a new item.
6. Keep the existing visually disabled strike-through AI button only for an unavailable action. When offline re-add readiness is true, the AI entry point must be usable even if stock-price checking is still unavailable.
7. Add Dynamic Type, VoiceOver, reduce-motion, keyboard focus, sheet dismissal, error, result, and compact-device previews.

**Verification:**

- Test the text-entry, starting, result-with-Undo, unmatched, unavailable, and compact states in SwiftUI previews and simulator.
- Confirm iOS keyboard dictation can place text in the field on a physical device when the device/user has dictation enabled; no speech audio is sent to Levy Home by this stage.

**Exit criteria:** a user can type or use the iOS keyboard microphone to submit one natural-language re-add request, see the result, and undo it without leaving Shopping.

### Stage 9 — Add an optional dedicated microphone control

**Purpose:** provide an explicit tap-to-talk control only after the typed/system-dictation experience is proven useful.

**Work:**

1. Decide whether the standard iOS keyboard dictation experience is sufficient. Implement this stage only if a prominent in-app microphone is still desired.
2. If implemented, use Apple’s on-device/system speech facilities where available. Add the minimal microphone and speech-recognition usage descriptions, permission handling, interruption behavior, language selection, and clear fallback to typing.
3. Keep audio/transcripts local to the phone until the user submits the resulting text. Levy Home sends only submitted text to its API; it does not upload/store raw audio or keep an audio recording.
4. Make microphone start/stop/cancel behavior accessible, visibly obvious, and non-blocking. Do not auto-submit speech; the user remains able to edit the recognized text before sending it.
5. Add unit/UI-adjacent tests for permission denied, unavailable recognizer, interrupted recording, cancellation, successful transcription, and text editing before submit.

**Verification:**

- Test on a physical iPhone with permission allowed and denied.
- Verify no microphone/speech permission is requested when a user simply types or uses the standard keyboard dictation path.

**Exit criteria:** if this optional stage is implemented, it provides a safe, editable voice input path with no stored audio and no impact on the server matching contract.

### Stage 10 — Deploy, validate, and tune on real household requests

**Purpose:** deploy the offline matcher safely and observe real fuzzy behavior before expanding scope.

**Work:**

1. Configure only the dedicated Codex service credential in Render’s secret store and the non-secret runtime settings required for the offline matcher. Do not configure retailer credentials, browser access, a local Codex cache, or general external network access.
2. Deploy one API instance, run migrations, confirm normal `/health`, re-add readiness, existing Shopping snapshot, and Shopping WebSocket behavior. Confirm the disabled stock-price feature remains independently disabled unless its own requirements are met.
3. Build, install, and launch the Render-pointed app on a physical iPhone. Confirm the built `LevyHomeAPIBaseURL` before installation.
4. Run a small authorized set of real household requests covering exact, plural, loose, and quantity cases: for example “Add eggs,” “Add 2 coffees,” and one expected unmatched phrase. Review only the public result/undo summary and committed Shopping rows.
5. Use the Undo action for at least one successful request. Confirm it restores only the AI-applied fields and does not undo a later manual change.
6. When two household devices are available, start from one and confirm the other receives item updates and does not create duplicate changes.
7. Record source/build, Render/readiness, physical-device, two-device, exact/fuzzy/quantity, unmatched, and Undo evidence separately. Use these observations to tune matching rules in a later intentional stage; do not silently broaden scope or add browsing.

**Verification:**

- Run API typecheck/tests/build and relevant Swift tests/build before release.
- Confirm no retailer domains, browser tools, web search, product APIs, image lookup, or new-item creation appear in logs, configuration, dependencies, or network policy for this feature.

**Exit criteria:** household members can quickly re-add existing items through typed or dictated natural language, quantities update as explicitly requested, fuzzy matching can be safely undone, and realtime updates reach the other device. Product/web matching remains explicitly out of scope.

## Guardrails for every stage

- Do not begin a later stage in the same request.
- Do not use the browser-sidecar, retailer website/product APIs, web search, item images, or any external data source for this plan.
- Do not allow Codex to create items, delete items, mark an item purchased, change a category, rename an item, alter notes/brand/image/store listings, or execute a tool/database command.
- Do not send full database objects from Codex back to the persistence layer. Validate IDs against the server snapshot and compute every actual update on the server.
- Do not weaken idempotency, stale-write protection, normal Shopping mutations, or realtime broadcasts to make matching easier.
- Do not expose credentials, account identity, prompts, raw responses, thread IDs, internal scores, or private item text in public API responses, logs, docs, or the app UI.
- Do not implement retailer/product matching or new-item creation as a hidden fallback for unmatched phrases. Those are separate future features.
