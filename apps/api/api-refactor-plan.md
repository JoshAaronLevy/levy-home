# API Refactor Plan

This plan is based on a review of the current `apps/api` codebase as of 2026-07-01.
The API is working, but the structure has outgrown the original flat `src` directory:

- `src/server.ts` mixes Express app composition, route handlers, startup/shutdown, device registration state, notification preferences, push dispatch, activity window parsing, event creation, shopping mutation helpers, and common middleware.
- `src/server.test.ts` is a broad integration suite covering shopping, users, to-do locations, Home Assistant actions, device registration, notification preferences, APNs test sends, Home Assistant webhook events, activity windows, and discovery routes.
- Unit tests currently live beside implementation files in `src/*.test.ts`.
- Several modules are already close to good boundaries (`homeService.ts`, `shoppingListRealtime.ts`, `activityStore.ts`), while others combine multiple roles (`homeAssistantClient.ts`, `krogerClient.ts`, `validation.ts`, `contracts.ts`).
- Runtime state for registered devices, notification preferences, and recent activity is in memory, which is fine for local scaffolding but fragile across Render restarts.
- Local secrets are ignored by Git, but Docker build hygiene should also explicitly exclude private key files from the build context.

The primary goal should be to improve structure without changing public API behavior first. After the tree is organized and tests are separated, later stages can improve durability and shared utilities with less risk.

## Workload Scale

- Low: less than half a day, mostly moves or small extractions.
- Medium: about 1 day, touches several imports/tests but low behavioral change.
- High: multiple days, crosses domains or changes runtime behavior.

## Proposed Target Shape

This is the recommended end-state direction, not a single giant commit.

```text
apps/api/
  api-refactor-plan.md
  migrations/
  package.json
  src/
    app.ts
    server.ts
    config/
      env.ts
      index.ts
      parsers.ts
    contracts/
      activity.ts
      home.ts
      notifications.ts
      shopping.ts
      todo.ts
      users.ts
      index.ts
    db/
      client.ts
      rowReaders.ts
    http/
      asyncHandler.ts
      errors.ts
      middleware/
        cacheControl.ts
        requireHaWebhookSecret.ts
    routes/
      activityRoutes.ts
      debugRoutes.ts
      deviceRoutes.ts
      healthRoutes.ts
      homeRoutes.ts
      notificationPreferenceRoutes.ts
      shoppingListRoutes.ts
      todoLocationRoutes.ts
      userRoutes.ts
      index.ts
    services/
      activity/
        activityEventService.ts
        activityWindow.ts
        recentActivityStore.ts
      home/
        homeService.ts
      notifications/
        deviceRegistry.ts
        notificationPreferenceStore.ts
        notificationService.ts
      shopping/
        shoppingListMutationService.ts
      realtime/
        shoppingListRealtimeHub.ts
    integrations/
      apple/
        apnsPushSender.ts
        privateKey.ts
      homeAssistant/
        activityBackfill.ts
        activityListener.ts
        activityNormalizer.ts
        facade.ts
        liveFacade.ts
        mockFacade.ts
        restClient.ts
      kroger/
        productClient.ts
        productDiagnostics.ts
        productNormalizer.ts
    repositories/
      shoppingListRepository.ts
      todoLocationRepository.ts
      userRepository.ts
    validation/
      activityValidation.ts
      deviceValidation.ts
      homeValidation.ts
      notificationValidation.ts
      shoppingValidation.ts
      todoValidation.ts
      index.ts
  test/
    integration/
      routes/
        activityRoutes.test.ts
        deviceRoutes.test.ts
        homeRoutes.test.ts
        notificationPreferenceRoutes.test.ts
        shoppingListRoutes.test.ts
        todoLocationRoutes.test.ts
        userRoutes.test.ts
    unit/
      config/
      integrations/
      repositories/
      services/
      validation/
    support/
      fakePushSender.ts
      httpServer.ts
      testConfig.ts
```

This tree keeps tests outside functional code while allowing tests to stay scoped by domain. I would avoid one giant `tests` pile with unrelated files side by side.

## Stage 0: Baseline, Safety, And Scope Lock

Workload: Low

Impact: High. This makes later file moves much safer and gives a clear "no behavior changed" checkpoint.

Tasks:

- Run the current baseline before moving files:
  - `npm run api:typecheck`
  - `npm run api:test`
  - `npm run api:build`
- Record the public route inventory from `src/server.ts`:
  - `GET /health`
  - `POST /api/devices/register`
  - `GET /api/notification-preferences`
  - `PUT /api/notification-preferences`
  - `POST /api/debug/send-test-push`
  - `GET /api/debug/home-assistant/phone-entities`
  - `GET /api/home/overview`
  - `GET /api/home/actions`
  - `POST /api/home/actions`
  - `POST /api/home/actions/open-garage`
  - `POST /api/home/actions/close-garage`
  - `POST /api/home/actions/lights-off`
  - `POST /api/home/actions/light-groups/:groupId/off`
  - `GET /api/users`
  - `GET /api/todo/locations`
  - `POST /api/todo/locations`
  - `GET /api/shopping-list`
  - `GET /api/shopping-list/items/lookup`
  - `GET /api/debug/kroger/products`
  - `GET /api/shopping-list/products/search`
  - `POST /api/shopping-list/items`
  - `PATCH /api/shopping-list/items/:itemId`
  - `DELETE /api/shopping-list/items/:itemId`
  - `POST /api/ha/events`
  - `GET /api/events`
- Add `*.p8` or `apps/api/*.p8` to `.dockerignore`. Git already ignores `*.p8`, but the root Dockerfile currently copies `apps/api` into the build stage, so Docker should explicitly exclude private APNs key files too.
- Do not rename endpoints, response shapes, env vars, or database table names in the structural stages.

Notes:

- The Docker ignore update is outside `apps/api`, but it is important because the API directory can contain local key material.
- Do not read, print, or move real secrets as part of the refactor.

## Stage 1: Move Tests Out Of `src`

Workload: Medium

Impact: Medium to high. This directly addresses the desired separation between test files and functional code, and it makes future source folder moves less noisy.

Tasks:

- Create `apps/api/test/unit` and `apps/api/test/integration`.
- Move focused module tests:
  - `src/activityNormalizer.test.ts` -> `test/unit/services/activity/activityNormalizer.test.ts`
  - `src/activityStore.test.ts` -> `test/unit/services/activity/recentActivityStore.test.ts`
  - `src/config.test.ts` -> `test/unit/config/env.test.ts`
  - `src/homeAssistantActivityBackfill.test.ts` -> `test/unit/integrations/homeAssistant/activityBackfill.test.ts`
  - `src/homeAssistantActivityClient.test.ts` -> `test/unit/integrations/homeAssistant/activityListener.test.ts`
  - `src/homeAssistantClient.test.ts` -> `test/unit/integrations/homeAssistant/facade.test.ts`
  - `src/krogerClient.test.ts` -> `test/unit/integrations/kroger/productClient.test.ts`
  - `src/shoppingListStore.test.ts` -> `test/unit/repositories/shoppingListRepository.test.ts`
  - `src/todoLocationStore.test.ts` -> `test/unit/repositories/todoLocationRepository.test.ts`
  - `src/userStore.test.ts` -> `test/unit/repositories/userRepository.test.ts`
- Move the large server integration test:
  - `src/server.test.ts` -> `test/integration/routes/server.test.ts` initially.
- Add shared test helpers:
  - `test/support/testConfig.ts` for the repeated `AppConfig`.
  - `test/support/httpServer.ts` for start/stop/restart helpers.
  - `test/support/fakePushSender.ts` for APNs tests.
- Update `apps/api/package.json`:
  - Change test script from `node --import tsx --test src/*.test.ts` to `node --import tsx --test "test/**/*.test.ts"`.
- Update `apps/api/tsconfig.json`:
  - Include both `src/**/*.ts` and `test/**/*.ts` for typechecking, or create a separate `tsconfig.test.json` if build output should remain source-only.

Suggested acceptance checks:

- `npm run api:typecheck`
- `npm run api:test`
- `npm run api:build`

Risk:

- NodeNext ESM import specifiers must keep `.js` suffixes even when importing from `.ts` tests through `tsx`.
- Relative imports will get longer after the move; this is acceptable for one stage. Path aliases can wait.

## Stage 2: Split App Composition From Process Startup

Workload: Medium

Impact: High. This removes a major source of coupling without changing behavior.

Tasks:

- Move `createApp` from `src/server.ts` to `src/app.ts`.
- Keep `src/server.ts` as the thin production entrypoint:
  - `import 'dotenv/config'`
  - `readConfig()`
  - create activity store and realtime hub
  - start HTTP server
  - wire WebSocket upgrade
  - start/stop Home Assistant activity listener and backfill
  - handle `SIGTERM` / `SIGINT`
- Move common HTTP helpers:
  - `asyncHandler` -> `src/http/asyncHandler.ts`
  - `HTTPError` -> `src/http/errors.ts`
  - global no-cache middleware -> `src/http/middleware/cacheControl.ts`
  - `requireHaWebhookSecret` -> `src/http/middleware/requireHaWebhookSecret.ts`
- Keep `createApp(options)` dependency injection intact. It is already one of the best safety features in the codebase.

Suggested acceptance checks:

- `npm run api:typecheck`
- `npm run api:test`
- `npm run api:build`

Risk:

- The existing `if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)` entrypoint guard should remain only in `server.ts`.
- Avoid starting WebSocket listeners from tests that only call `createApp`.

## Stage 3: Extract Route Modules By Domain

Workload: High

Impact: High. This turns `server.ts`/`app.ts` from a route pile into composition code and makes future feature work much easier to locate.

Recommended route modules:

- `src/routes/healthRoutes.ts`
- `src/routes/deviceRoutes.ts`
- `src/routes/notificationPreferenceRoutes.ts`
- `src/routes/homeRoutes.ts`
- `src/routes/userRoutes.ts`
- `src/routes/todoLocationRoutes.ts`
- `src/routes/shoppingListRoutes.ts`
- `src/routes/activityRoutes.ts`
- `src/routes/debugRoutes.ts`
- `src/routes/index.ts`

Tasks:

- Each route module should export a function that accepts explicit dependencies and returns an Express `Router`.
- Keep all route paths identical.
- Move one route group at a time and split the matching integration tests as each group moves.
- Use dependency objects instead of importing global singletons inside route modules.

Example shape:

```ts
export function createShoppingListRoutes(deps: ShoppingListRouteDependencies): Router {
  const router = Router();

  router.get('/api/shopping-list', asyncHandler(async (_req, res) => {
    // existing behavior
  }));

  return router;
}
```

Integration test split after route extraction:

- `test/integration/routes/shoppingListRoutes.test.ts`
- `test/integration/routes/homeRoutes.test.ts`
- `test/integration/routes/deviceRoutes.test.ts`
- `test/integration/routes/notificationPreferenceRoutes.test.ts`
- `test/integration/routes/activityRoutes.test.ts`
- `test/integration/routes/debugRoutes.test.ts`
- `test/integration/routes/todoLocationRoutes.test.ts`
- `test/integration/routes/userRoutes.test.ts`

Risk:

- Route ordering and middleware ordering matter. Register `express.json`, CORS, no-cache, route modules, then error middleware in the same order as today.
- `POST /api/ha/events` and `GET /api/debug/home-assistant/phone-entities` both require the Home Assistant webhook secret middleware; keep that explicit in their route modules.

## Stage 4: Extract Cross-Route Services From The Current Server Helpers

Workload: High

Impact: High. This removes the most important non-routing logic from the Express layer.

### Notifications

Move these responsibilities out of `server.ts`:

- `registeredDevicesById`
- `registeredDeviceIdsByLookupKey`
- `preferencesByDeviceKey`
- `createDeviceLookupKey`
- `createDeviceId`
- `hashToken`
- `deviceResponse`
- `preferenceKeyForLocator`
- `applyPreferenceUpdates`
- `sendPushToRegisteredDevices`
- `isNotificationPreferenceEnabled`
- `testPushMessage`
- `pushStatusFromSummary`
- `notificationCategoryForEvent`

Suggested files:

- `src/services/notifications/deviceRegistry.ts`
- `src/services/notifications/notificationPreferenceStore.ts`
- `src/services/notifications/notificationService.ts`

Impact:

- Makes APNs push behavior testable without booting Express.
- Makes it easier to replace in-memory devices/preferences with Postgres later.
- Reduces risk when adding batching, cooldowns, or additional notification categories.

### Activity

Move these responsibilities out of `server.ts`:

- `parseActivityWindow`
- `parseTimestamp`
- `isEventInWindow`
- `fetchNormalizedHomeAssistantHistoryEvents`
- `mergeActivityEvents`
- `activityEventKey`
- `createStoredEvent`

Suggested files:

- `src/services/activity/activityWindow.ts`
- `src/services/activity/activityEventService.ts`

Impact:

- Keeps `/api/events` route small.
- Gives the Home Assistant webhook path and live activity ingestion a shared event construction path.
- Makes history/window bugs easier to test at unit level.

### Shopping Mutations

Move these responsibilities out of `server.ts`:

- `readShoppingListItemId`
- `mutationIdForRequest`
- `shoppingListMutationResponse`
- duplicate item checks
- database unique violation mapping
- realtime broadcast calls after successful mutations

Suggested file:

- `src/services/shopping/shoppingListMutationService.ts`

Impact:

- Keeps HTTP routes thin.
- Centralizes duplicate behavior across create/update.
- Makes realtime broadcasting an explicit side effect of successful mutations.

Risk:

- Do not introduce persistence changes in this stage. Keep behavior identical and move logic behind interfaces first.

## Stage 5: Organize External Integrations

Workload: Medium to high

Impact: Medium to high. This makes the difference between app-owned domain logic and third-party API code visible.

### Home Assistant

Current `homeAssistantClient.ts` includes facade creation, mock behavior, live REST behavior, phone entity discovery helpers, and entity state mapping.

Recommended split:

- `src/integrations/homeAssistant/facade.ts` for the `HomeAssistantFacade` type and factory.
- `src/integrations/homeAssistant/mockFacade.ts`
- `src/integrations/homeAssistant/liveFacade.ts`
- `src/integrations/homeAssistant/restClient.ts` for authenticated fetch and common response handling.
- `src/integrations/homeAssistant/activityListener.ts`
- `src/integrations/homeAssistant/activityBackfill.ts`
- `src/integrations/homeAssistant/activityNormalizer.ts`
- `src/integrations/homeAssistant/entityDiscovery.ts` if discovery grows further.

Impact:

- Home control, discovery, activity WebSocket, and history backfill become separately owned.
- Tests can focus on one integration behavior at a time.
- Future Home Assistant changes will be less likely to disturb shopping, APNs, or app startup code.

### Kroger

Current `krogerClient.ts` combines token fetch, product fetch, product normalization, diagnostic file writing, and secret redaction.

Recommended split:

- `src/integrations/kroger/productClient.ts`
- `src/integrations/kroger/productNormalizer.ts`
- `src/integrations/kroger/productDiagnostics.ts`

Impact:

- Product search route can call a simple client method.
- Diagnostic file-writing tests can stay separate from product normalization tests.
- Secret redaction remains easier to audit.

### Apple/APNs

Current `apnsService.ts` and `services/apple/config.ts` can become:

- `src/integrations/apple/apnsPushSender.ts`
- `src/integrations/apple/privateKey.ts`

Impact:

- Push sender code is clearly an external integration.
- Private key parsing remains isolated and easier to test.

Risk:

- Keep existing exported factory names temporarily or add barrel exports to reduce import churn during intermediate stages.

## Stage 6: Reorganize Data Access And Shared Row Readers

Workload: Medium

Impact: Medium. This reduces duplication and clarifies database ownership without changing SQL behavior.

Tasks:

- Move `dbClient.ts` to `src/db/client.ts`.
- Move store modules into `src/repositories`:
  - `shoppingListStore.ts` -> `shoppingListRepository.ts`
  - `todoLocationStore.ts` -> `todoLocationRepository.ts`
  - `userStore.ts` -> `userRepository.ts`
- Extract repeated row parsing helpers into `src/db/rowReaders.ts`:
  - `requiredString`
  - `optionalString`
  - `requiredInteger`
  - `optionalInteger`
  - `optionalBoolean`
  - `optionalISOString`
  - `parseJSONBValue`
  - `jsonb`
- Keep domain-specific mapping in each repository. Shared helpers should parse primitives only; they should not know about `shopping_list`, `todo_locations`, or `users`.

Impact:

- Removes repeated parsing code across repositories.
- Makes schema-mapping bugs easier to locate.
- Gives future repository additions a consistent pattern.

Risk:

- Row parsing is surprisingly easy to change accidentally. Move helpers only after repository tests are under `test/unit/repositories`.

## Stage 7: Split Contracts And Validation By Domain

Workload: Medium

Impact: Medium. This makes route/domain ownership easier to understand while keeping one public import point.

Tasks:

- Split `contracts.ts` into domain files:
  - `contracts/activity.ts`
  - `contracts/home.ts`
  - `contracts/notifications.ts`
  - `contracts/shopping.ts`
  - `contracts/todo.ts`
  - `contracts/users.ts`
  - `contracts/index.ts`
- Keep `contracts/index.ts` as the stable barrel import while files are moved.
- Split `validation.ts` into:
  - `validation/activityValidation.ts`
  - `validation/deviceValidation.ts`
  - `validation/homeValidation.ts`
  - `validation/notificationValidation.ts`
  - `validation/shoppingValidation.ts`
  - `validation/todoValidation.ts`
  - `validation/index.ts`
- Add focused validation tests, especially for shopping item bodies, to-do location bodies, device registration, notification preferences, quick actions, and Home Assistant event payloads.

Impact:

- Route modules import only validators for their domain.
- Contract changes become easier to review.
- Future iOS/API contract updates become less likely to accidentally touch unrelated domains.

Risk:

- Do not add a new schema validation library in the same step. A library like Zod could be useful later, but mixing that with file moves would make review and regression detection harder.

## Stage 8: Persist Device Registrations And Notification Preferences

Workload: High

Impact: High. This changes runtime behavior from process-local state to durable API state.

Current state:

- Device registrations and notification preferences are held in `Map` instances inside `createApp`.
- That means they reset on process restart or redeploy.

Recommended approach:

- First keep the service interfaces introduced in Stage 4 backed by memory.
- Then add migrations for durable tables, for example:
  - `push_devices`
  - `notification_preferences`
- Store only hashed lookup keys where possible. Do not store raw tokens unless there is a clear delivery need.
- If APNs delivery requires raw tokens, store them deliberately, document why, and keep logs redacted.
- Update `/api/devices/register`, `/api/notification-preferences`, `/api/debug/send-test-push`, and Home Assistant event push dispatch to use the persistent service.
- Add tests for restart-like behavior by creating one app instance to register/sync and another app instance backed by the same fake repository.

Impact:

- Push registrations and preferences survive Render restarts.
- TestFlight push behavior becomes more reliable.
- The API becomes ready for richer notification preference categories.

Risk:

- Token storage has security implications. This should be treated as a behavioral feature, not a pure refactor.

## Stage 9: Decide Whether Recent Activity Should Stay In Memory

Workload: Medium to high, depending on persistence choice

Impact: Medium to high.

Current state:

- `RecentActivityStore` is in memory.
- Home Assistant live WebSocket ingestion and history backfill feed `/api/events`.
- Explicit time-window requests can fetch Home Assistant history best-effort.

Options:

- Keep activity memory-only and document it as a live feed cache. Workload: Low. Impact: Low to medium.
- Persist normalized activity events in Postgres. Workload: High. Impact: High for restart resilience, auditability, and future Activity features.
- Hybrid: keep memory for fast live display, persist only selected normalized events. Workload: Medium to high. Impact: High if Activity needs reliable history.

Recommendation:

- Do not persist activity as part of the structural refactor.
- After route/service extraction, revisit persistence based on product expectations for the Activity tab.

## Stage 10: Improve Observability And Operational Hygiene

Workload: Medium

Impact: Medium to high.

Tasks:

- Introduce a tiny logger abstraction or injected `logger` dependency for modules that currently call `console` directly.
- Keep logs redacted by default for APNs, Home Assistant, Kroger, and database errors.
- Add route-level request IDs only if the client or logs will actually use them.
- Add health/readiness details carefully:
  - `/health` can keep basic process status.
  - A separate readiness route can check optional dependencies if needed, without requiring local mock mode to have real secrets.
- Keep `.env.example` synchronized with `readConfig`.
- Explicitly ignore private APNs key files in Docker context as noted in Stage 0.

Impact:

- Easier Render debugging.
- Less risk of accidental secret exposure.
- Clearer distinction between liveness and dependency readiness.

Risk:

- Avoid logging request bodies by default. Some bodies can contain device tokens, Home Assistant metadata, or user-entered notes.

## Suggested Commit Sequence

1. Baseline and Docker secret hygiene.
2. Move tests to `test/` and add shared test support helpers.
3. Split `createApp` and startup into `app.ts` and `server.ts`.
4. Extract one route group at a time, starting with low-risk routes:
   - health
   - users
   - to-do locations
   - home
   - shopping list
   - device and notification preferences
   - activity and Home Assistant webhook
   - debug routes
5. Extract notification, activity, and shopping mutation services.
6. Reorganize integrations.
7. Reorganize repositories and row readers.
8. Split contracts and validation.
9. Add durable notification/device persistence.
10. Revisit activity persistence and observability.

## Verification Checklist For Each Stage

Run these after every stage:

```sh
npm run api:typecheck
npm run api:test
npm run api:build
```

For stages that touch Render/startup behavior, also run:

```sh
npm run api:start
```

Then check:

- `/health` still returns `ok: true`.
- `/api/events` still returns `Cache-Control: no-store`.
- `/api/shopping-list` still returns `database_not_configured` instead of crashing when `DATABASE_URL` is absent.
- Home Assistant webhook routes still require `Authorization: Bearer <LEVY_HOME_HA_WEBHOOK_SECRET>`.
- APNs test sends still return `apns_credentials_not_configured` when credentials are absent.

## Highest-Value Refactor Suggestions

| Suggestion | Workload | Impact | Why |
| --- | --- | --- | --- |
| Move tests out of `src` into `test/unit` and `test/integration` | Medium | High | Directly separates tests from production code and makes later moves easier. |
| Split `createApp` from process startup | Medium | High | Keeps tests and app composition clean while preserving the production entrypoint. |
| Extract route modules by domain | High | High | Shrinks `server.ts` and makes endpoint ownership obvious. |
| Extract notification service and device/preference stores | High | High | Prepares for durable push registration and lower-noise notification features. |
| Extract activity window/event service | Medium | High | Reduces risk around `/api/events`, HA history, and Activity tab behavior. |
| Split Home Assistant integration files | Medium to high | Medium to high | Separates REST facade, WebSocket listener, backfill, and normalization concerns. |
| Split Kroger client, diagnostics, and normalization | Medium | Medium | Makes shopping product search easier to maintain and keeps diagnostic redaction auditable. |
| Extract shared DB row readers | Medium | Medium | Removes duplicated primitive parsing across repositories. |
| Split validation and contracts by domain | Medium | Medium | Keeps route modules small and future API contract work easier to review. |
| Add durable storage for devices/preferences | High | High | Fixes restart/deploy fragility for push registration and synced preferences. |
| Explicitly exclude private key files from Docker context | Low | High | Reduces risk of shipping local APNs key material into a build image. |

## Recommended First PR

The first implementation PR should be intentionally boring:

1. Add `.dockerignore` coverage for `*.p8`.
2. Move tests from `src/*.test.ts` to `test/...`.
3. Add `test/support` helpers.
4. Update `package.json` test script and TypeScript test config.
5. Run `npm run api:typecheck`, `npm run api:test`, and `npm run api:build`.

That PR gives the repository the test layout you want and creates a safer platform for the route/service refactor without mixing in runtime behavior changes.
