# Codex Shopping List re-add — Stage 3 runtime configuration

Stage 3 adds only an offline, server-side matching adapter. It is not exposed
by an HTTP route yet and has no access to a Shopping repository or mutation
service. It therefore cannot create, update, or delete Shopping data by itself.

## Credential boundary

The deployed API will receive one dedicated Render secret named
`CODEX_SHOPPING_LIST_API_KEY`. The application composition root (added in a
later stage) must explicitly pass that value to `CodexShoppingListReaddMatcher`
as its `apiKey`. It must not put this value in source control, iOS settings,
logs, prompts, a database row, or API responses.

For local development, explicitly supply a secure development credential to
the matcher composition root. Do not copy, read, or depend on `~/.codex/auth.json`,
desktop credentials, browser storage, a ChatGPT sign-in session, or another
developer account cache. The matcher does not read any environment variable by
default, which makes this credential boundary explicit and testable.

The installed Codex SDK accepts a server-side API key and starts a fresh thread
for each request. Its environment is restricted to `PATH` plus the SDK-managed
credential; the API process environment (including database and Render secrets)
is not inherited by the SDK subprocess.

## Offline matching boundary

Every thread uses read-only sandboxing, approval policy `never`, disabled web
search, disabled network access, and `/tmp` as its work directory. The prompt
contains only the request text and bounded Shopping candidate fields:
`id`, `version`, `name`, optional `brand`/`notes`, `purchased`, and `quantity`.
It excludes images, store listings, retailer/product data, user/device data,
database instructions, and application paths.

The structured response is parsed and validated against the API-owned snapshot.
Malformed output, duplicate targets, unknown IDs, unsupported fields, invalid
quantities, timeouts, missing authentication, and runtime failures become safe
unavailable/invalid results. They never cause a Shopping write.

## Deployment note

Do not set the Render secret or enable this feature merely by adding the
adapter. Stage 6 adds the narrow public route and Stage 10 owns deployment
readiness. Before enabling it in Render, verify that the deployed image includes
the compatible Codex SDK/CLI runtime and that the dedicated secret is available
only to the API service.
