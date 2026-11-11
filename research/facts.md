# Facts — consolidated Phase A output

Sources: `research/out/{maas-3.5,praxis-inv,praxis-cap,visualizer,ipp-ga}.md` (all citations in those files).
Repos at: models-as-a-service @ 8d30ae9a · ai-gateway-controller @ 5502164 · praxis-ai @ 8a9a2159 · praxis-extproc @ 012b70e · ai-gateway-payload-processing @ f0ddb04 · llm-d-inference-payload-processor @ 4a38b6a · visualizer @ 1ddbe07.

## Headline findings

1. **The 3.6 plan's "three flows" do not match code.** In code, the IPP→praxis swap is **per-tenant, whole-pipeline** (annotation on MaasTenantConfig; absent = praxis, only `"ipp"` opts back to legacy). There is no "praxis handles only new workloads alongside IPP" — for a praxis tenant, IPP is *deleted entirely* (one-shot cleanup) and ai-gateway-controller (AGC) owns the dataplane.
2. **Responses API: NOT IMPLEMENTED in MaaS/AGC**, but **substantially implemented in praxis-ai itself** (request/store/rehydrate filters, agentic loop, MCP dispatch, WebSocket passthrough, OpenResponses conformance suite). The gap is the control plane (MaaS/AGC) wiring it up, not praxis.
3. **Fallback/retry/failover routing: NOT IMPLEMENTED anywhere** (maas, AGC). AGC even *rejects* non-uniform provider weights and uses deterministic first-provider order.
4. **The deployed praxis pipeline (AGC-rendered) is thin**: pre-chain `model_to_header` + `llmisvc_model_provider_resolver`; post-auth chain `intelligent_route` + `credential_inject`. No maas-headers-guard, no stream-usage-enforcer, no api-translation, no apikey-injection equivalents in the AGC-rendered config — although praxis-ai the runtime *has* most of these capabilities (`identity_header_guard`, `stream_usage_inject`, provider-native translations, SigV4, `api_key_auth`, `token_rate_limit`, `external_metering`, `ai_guardrails`).
5. **3.5 GA is a specific ConfigMap shape** — migration doc pins it: no model-provider-resolver in pre-processing, no maas-headers-guard in processing, **response api-translation ON**. HEAD's default differs (adds those, response chain empty). The visualizer currently matches neither exactly.
6. **The current visualizer has real inaccuracies** vs 3.5 code: single IPP stage (code has pre-auth + post-auth ext_proc), wrong plugin list, missing subscription-select auth callback, fictional "MaaSAuth" CRD (real: MaaSAuthPolicy), no usage-logs/metering path, EPP topology wrong-ish.
7. **`responses-api/index.html` is entirely plan-derived** (Draft docs, May 2026); its stage names don't even match the planning docs' plugin names. Its engine and inspector payloads are reusable; its content must not be presented as implemented.
8. **enmaas-flow.html (not ai-gateway-flow.html)** carries the latest filter/metering/path-color work (live EnMaaS praxis chain, external_metering/PriceTag hooks, activePathColor) — a sibling page that already models the praxis dataplane for EnMaaS.

## Code-validated 3.4 / 3.5 / 3.6-dev matrix (git tags v0.1.1 / v0.2.1 / HEAD)

Validated directly against repo tags, not release notes. **Correction to maas-3.5 fact sheet:** it described HEAD (3.6-dev); the items below marked (3.6-dev) are NOT in the 3.5 GA tag.

| Aspect | 3.4 (v0.1.1) | 3.5 GA (v0.2.1) | 3.6-dev (HEAD) |
|---|---|---|---|
| ext_proc stages | 1 (`ext_proc.bbr`, after auth wasm) | 2 (`ipp-pre` before auth + `ipp` after) | same 2 |
| IPP request plugins | model-extractor, model-provider-resolver, api-translation, apikey-injection | + maas-headers-guard, stream-usage-enforcer | same as 3.5 |
| IPP response plugins | none | api-translation | none (empty by default) |
| Auth policy shape | per-HTTPRoute Kuadrant AuthPolicies | single gateway `maas-gateway-auth` | same |
| maas-api callbacks (validate + subscription-select) | both exist | both exist | both exist |
| Usage-logs OTel | — (no component) | json_to_metadata + lua SSE + OTLP; identity via FILTER_STATE | + per-tenant usage-logs EnvoyFilter controller, identity via header_to_metadata |
| CRDs | Tenant, MaaSModelRef/AuthPolicy/Subscription, maas.* ExternalModel | + AITenant, MaasTenantConfig, Config, ExternalProvider, inference.* ExternalModel | same |
| EPP/InferencePool reorder before router | — | — (envoy-filter 201 lines) | ✓ (3.6-dev) |
| InferenceObjectives / inference priority | — | — (added 2026-10-05, #1616) | ✓ (3.6-dev) |
| gateway-default-deny TRLP | ✓ (since bdae2c84, 2026-03-05) | ✓ | ✓ |
| router-fallback auth anchor (`gatewayHasKuadrantWasmAuth`) | — | — | ✓ (3.6-dev) |
| Praxis backend selection / IPP cleanup | — | — | ✓ (3.6-dev) |

Citations: `git show v0.1.1:deployment/base/payload-processing/manager/plugins-configmap.yaml` (4 plugins, single config) vs `v0.2.1:` (pre/post split, full chains, response api-translation); `v0.1.1:...envoy-filter.yaml` (single `ext_proc.bbr` INSERT_AFTER) vs `v0.2.1:` (ipp-pre INSERT_BEFORE + ipp INSERT_AFTER, dual anchors, per-route disable); `git grep "only allows one AuthPolicy per HTTPRoute" v0.1.1` (maasauthpolicy_controller.go:382); `git grep subscriptions/select v0.1.1` (both callbacks exist); `git ls-tree v0.1.1` (no usage-logs files) vs `v0.2.1` (full usage-logs component; FILTER_STATE identity at envoy-otel-access-log.yaml:350-359); CRD dirs per tag; `git log v0.2.1..HEAD -- '*inferenceobjective*'` (#1616, 2026-10-05); v0.2.1 envoy-filter = 201 lines (no router reorder); gateway-default-deny present at both tags (`git grep gateway-default-deny v0.1.1 v0.2.1`).

**3.5 shape variance (from design review):** the shipped **ODH 3.5.0** product image is the migration code's `"odh-3.5.0"` baseline (pre = model-extractor only, **no maas-headers-guard**, response api-translation ON — plugins_migration.go:586, upgrade-to-3.6.md:59), while the **v0.2.1 repo tag** includes e245289c (2026-07-19: pre-mpr + maas-headers-guard) — i.e., 3.5.0-shipped vs 3.5.z-tag differ. Visualizer depicts the v0.2.1 shape and documents the variance.

**Praxis fact corrections (from design review, supersede praxis-cap.md notes):** `stream_usage_inject` **IS present and ungated at the pinned v0.6.0** (upstream #1231, 2026-09-28; v0.6.0 tagged 2026-10-09; registered at `git show v0.6.0:filters/src/register.rs:215`) — praxis-cap.md's "NOT IMPLEMENTED at the pinned rev" and the praxis-extproc migration doc's "no filter injects stream_options" (docs/migration-ipp-to-praxis.md:228-234) are stale. The deployed `odh-praxis-extproc` image is the **FIPS feature set** (`responses,aws-sigv4,store-postgres-cert-auth`, Makefile FIPS_FEATURES) — it **excludes** responses-full extras (MCP tools, compact, conversations, file-resolve) and experimental features (token_rate_limit, token_ceiling, policy-engine). `api_key_auth` is **fork-only** (redhat-et/praxis-ai, not upstream praxis-proxy/ai). The `vertex` rawPredict filter is post-v0.6.0 upstream (#1695) — not in the deployed image.

## Per-flow status

| Flow / feature | Status | Evidence (see out/ files) |
|---|---|---|
| 3.5 GA — Chat Completions, external (IPP) | **Implemented** (MaaS + IPP; two-stage ext_proc; plugin chain maas-headers-guard → stream-usage-enforcer → model-provider-resolver → api-translation → apikey-injection post-auth; body-field-to-header + model-provider-resolver pre-auth; response api-translation ON in 3.5.0) | maas-3.5 §1, ipp-ga §1 |
| 3.5 GA — internal (llm-d, EPP) | **Implemented** (MaaS wires EPP reorder + InferenceObjectives; EPP/scheduler in llm-d/KServe) | maas-3.5 §4 |
| Auth (Authorino → maas-api validate + subscription-select) | **Implemented** — two callbacks, not one | maas-3.5 §2 |
| Usage-logs metering (OTel access logs, telemetry) | **Implemented** (telemetry default true) | maas-3.5 §3 |
| Token rate limiting (Kuadrant TRLP) | **Implemented** (Kuadrant side unverified here) | maas-3.5 §5 |
| 3.6 — praxis tenant swap (per-tenant, whole pipeline) | **Implemented** (annotation, SkipIPP, one-shot cleanup, AGC ownership, readiness handshake) | praxis-inv §1–2 |
| 3.6 — AGC-rendered praxis pipeline | **Partial** (model_to_header, llmisvc_model_provider_resolver, intelligent_route, credential_inject only) | praxis-inv §3 |
| 3.6 — api-translation under praxis | **Partial** (openai passthrough + anthropic messages only; Azure/Vertex/Bedrock blocked from migration) | praxis-inv §4 |
| 3.6 — Fallback / retry / failover | **NOT IMPLEMENTED IN CODE** | praxis-inv §5 |
| 3.6 — Responses API end-to-end (MaaS/AGC) | **NOT IMPLEMENTED IN CODE** (docs/proposals only) | praxis-inv §6 |
| Praxis runtime Responses API (filters, store, agentic loop, MCP, WS) | **Implemented in praxis-ai** (+ e2e/conformance tests); served paths exist incl. POST /v1/responses Transform mode | praxis-cap §3 |
| Praxis runtime: auth (api_key_auth), metering (external_metering/token_*), guardrails (NeMo), SigV4, provider translations (Bedrock Converse+EventStream, Azure, Vertex, Anthropic↔OpenAI) | **Implemented in praxis-ai** (some behind experimental features; token_rate_limit/token_ceiling experimental) | praxis-cap §1–2, 6 |
| praxis-extproc as Envoy ext_proc adapter | **Implemented** (pins praxis-ai v0.6.0; 4 phases; ODH EnvoyFilter overlays) | praxis-cap §4 |
| Live CRD watching / runtime model resolution in praxis | **NOT IMPLEMENTED IN CODE** (controller-rendered static config, hot reload) | praxis-cap §5 |

## Visualizer gaps vs 3.5 facts (from maas-3.5 §6)

1. Badge "RHOAI 3.4 GA" → 3.5; stats line inconsistent.
2. One IPP stage shown → must show pre-auth (ipp-pre) and post-auth (ipp) stages.
3. Plugin list: remove/keep-as-coming-soon `request-guard`, `intelligent-model-selection`, `base-model-to-header`; add `maas-headers-guard`, `stream-usage-enforcer`; correct order.
4. Response api-translation step matches 3.5 GA (keep, with 3.6-HEAD caveat).
5. Add subscription-select auth callback hop.
6. Replace "MaaSAuth" CRD with the real CRD set (MaaSAuthPolicy, AITenant, MaasTenantConfig, …).
7. Fix EPP depiction (reordered InferencePool ext_proc before router, per-route ExtProcPerRoute).
8. Add usage-logs path (header_to_metadata → json_to_metadata/lua SSE → OTel collector).
9. Metering token-report steps are Kuadrant behavior — keep but label accordingly.

## Implications for the visualizer design (input to Phase B)

- A simple "3.5 vs 3.6" toggle underestimates the change: the honest 3.6 picture is **per-tenant backend selection** — legacy IPP tenants (3.5 GA upgrade path, `"ipp"`) vs praxis tenants (default) with the one-shot migration story. Consider a "Migration" flow: blocked-gate → compatibility check → cleanup → AGC claim → steady.
- A 3.6 praxis Chat Completions flow exists in code (the thin AGC chain) and is the accurate thing to show — *not* the rich praxis-ai filter inventory (which the runtime supports but MaaS does not deploy). The rich inventory belongs in node-overlay details with clear "praxis-ai capability, not deployed by AGC" labeling.
- Responses API: at most a cross-linked/ghost treatment ("implemented in praxis runtime, not wired in MaaS 3.6") — no runnable MaaS-level flow. `responses-api/index.html` content is plan-derived and needs re-grounding against praxis-cap §3 before reuse.
- The `enmaas-flow.html` page already models a live praxis dataplane (EnMaaS) with external_metering/PriceTag — decide the relationship between it and the 3.6 story (cross-link vs merge).

Phase A complete → awaiting user review before Phase B design.
