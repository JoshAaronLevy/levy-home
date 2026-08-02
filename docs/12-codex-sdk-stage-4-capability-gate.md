# Codex SDK Stage 4 capability gate

## Reviewed runtime surface

The installed `@openai/codex-sdk` provides server-side local Codex threads, read-only sandbox and approval settings, `networkAccessEnabled`, web-search controls, structured JSON output, an abort signal, and CLI configuration overrides. Its local network proxy can encode the four exact retailer hosts.

The SDK does not expose a browser-only tool or policy that can reject a direct product API, JSON, or GraphQL request on one of those same allowed hosts. Codex’s published Browser capability is not available in the Codex CLI or IDE, which is the runtime the TypeScript SDK controls. The separate cloud-agent internet documentation describes per-environment domain/method controls and does not establish an equivalent server-side SDK browser runtime for the Render service.

## Implemented fail-closed behavior

`CodexShoppingWebsiteResearcher` is present as the Stage 4 injected implementation, but its readiness is deliberately disabled. Every request resolves to the fixed-store `unknown`/`website_error` result with `site_scope_unavailable`; it never creates a Codex client/thread, sends a prompt, performs navigation, or reads a retailer response.

The module also contains the future execution seam: a minimal redacted prompt, the structured-output schema, response parser, exact-host proxy configuration, read-only/approval-free thread options, and abort-based timeout. Those helpers are covered only with fakes. They cannot be wired to a live service until an independently enforced browser-only/direct-API guard is demonstrated in the actual deployment runtime.

## Required before enabling live research

Do not flip the readiness value based on an SDK upgrade, a prompt, a local login, or successful domain allowlisting alone. First demonstrate, in the Render-compatible runtime, that:

1. only the four exact retailer hosts are reachable;
2. non-read-only methods are blocked;
3. navigation uses a rendered-page browser tool; and
4. a direct API/JSON/GraphQL request on an otherwise allowed retailer host is rejected before it can return product data.

Until all four are proven, the feature remains unavailable under the no-product-API requirement.
