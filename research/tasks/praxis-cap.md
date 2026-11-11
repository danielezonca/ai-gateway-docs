# Task: Praxis capability inventory

Repos (read-only, record HEAD commit of each):
- `clones/praxis-ai` (redhat-et/praxis-ai) — CANONICAL filter implementation: `filters/src/` (agentic, api_key_auth, metering, token_rate_limit, routing, guardrails, model_access, model_catalog, prompt_enrich, reasoning_effort_map, token_usage, ...), `apis/src/` (anthropic, azure, bedrock, vertex, openai, mcp_client, web_search, openai_responses_request/store/rehydrate filters), `server/`, `store/`, `store-backends/`, `tests/`
- `clones/praxis-extproc` (opendatahub-io/praxis-extproc) — the deployed ext_proc artifact
- If useful for cross-checks only: `clones/praxis` (older June 2026 snapshot — do not use as source of current capability)

Goal: inventory what praxis actually implements today, to build an accurate flow visualizer and an honest IPP-parity picture.

Answer:
1. Full filter inventory from `filters/src/` and `apis/src/` (see register / lib.rs filter registry): for each filter — name, purpose, request/response behavior, config surface. Group by capability area (auth, rate-limit, translation, credential injection, routing, agentic, metering, guardrails).
2. Provider API support: which providers (anthropic, azure, bedrock, vertex, openai...) are implemented, and what "support" means per provider — path rewrite only, body translation, streaming, auth signing (SigV4?).
3. Responses API: exactly what exists — openai_responses_request / openai_responses_store / openai_responses_rehydrate filters and anything else (agentic: a2a, mcp, tool calling, conversation/state management). What request path do these serve? What is implemented end-to-end vs stub/partial? Cite test files that prove end-to-end behavior.
4. praxis-extproc: what it is (ext_proc adapter?), how it relates to praxis-ai, what phases/streaming it supports.
5. Deployment/config model: how is a praxis instance configured (static config, CRDs, ConfigMap)? Is there model/provider resolution at runtime?
6. Metering, usage tracking, token accounting: what exists.
7. Test coverage signals: which capabilities have passing e2e/integration tests (tests/, tests/integration, tests/conformance) — use these as evidence of what actually works.

Output: markdown fact sheet with a filter table (name | area | status: implemented/partial/stub | citation) plus sections per question. Mark anything not found in code as NOT IMPLEMENTED IN CODE.
