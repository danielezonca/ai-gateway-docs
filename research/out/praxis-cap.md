# Praxis Capability Inventory — Fact Sheet

**Repos analyzed (commits):**
- `clones/praxis-ai` (redhat-et/praxis-ai) — `8a9a2159`
- `clones/praxis-extproc` (opendatahub-io/praxis-extproc) — `012b70e`
- `clones/praxis` (older June 2026 snapshot) — not used as a capability source, per charter.

All paths below are relative to the workspace root (`/Users/dzonca/GIT/clones`). Registration line numbers refer to `praxis-ai/filters/src/register.rs` (the canonical filter registry, invoked via `register_ai_filters` at `praxis-ai/filters/src/register.rs:55`).

---

## 1. Full filter inventory

The complete registry is built in `praxis-ai/filters/src/register.rs`; per-filter generated docs live in `praxis-ai/docs/filters/`. Cargo feature gates per `praxis-ai/filters/Cargo.toml:13-63`. The registry test enumerates all opt-in filters and their feature gates (`praxis-ai/filters/src/register.rs:829-881`).

### Filter table

| Filter name | Area | Status | Registration / citation |
|---|---|---|---|
| `a2a` | Agentic (A2A) | Implemented | register.rs:114; `praxis-ai/filters/src/agentic/a2a/mod.rs:4`; e2e: `praxis-ai/tests/integration/tests/suite/a2a.rs` |
| `mcp` | Agentic (MCP classify/broker) | Implemented | register.rs:118; `praxis-ai/filters/src/agentic/mcp/mod.rs:4`, broker at `filters/src/agentic/mcp/broker/mod.rs:4-6`; e2e: `suite/mcp.rs`, `suite/mcp_broker.rs` |
| `aws_sigv4_sign` | Credential injection / auth signing | Implemented (feature `aws-sigv4-filter`, in `standard`) | register.rs:125; `praxis-ai/filters/src/aws/signing.rs:10-28` (OpenSSL-based SigV4) |
| `openai_chat_completions_to_bedrock_converse` | Translation (→Bedrock) | Implemented | register.rs:128; `praxis-ai/apis/src/bedrock/converse/mod.rs:4-10` (request + response + EventStream→SSE streaming) |
| `azure_ad` | Auth (Entra ID token for upstream) | Experimental feature | register.rs:142-150; `praxis-ai/filters/Cargo.toml:44-46`; e2e: `suite/examples/azure_ad.rs` |
| `openai_chat_completions_to_azureai_chat_completions` | Translation (→Azure OpenAI) | Implemented | register.rs:158; `praxis-ai/apis/src/azure/to_openai/mod.rs:4-10` |
| `gcp_adc` | Auth (Google ADC; metadata or key_file JWT) | Experimental feature | register.rs:171-179; `praxis-ai/filters/src/gcp/mod.rs:4-18` |
| `vertex` | Translation (Anthropic ⇄ Vertex rawPredict) | Implemented | register.rs:187; `praxis-ai/apis/src/vertex/mod.rs:4-17` |
| `openai_chat_completions_to_vertexai_gemini` | Translation (→Vertex Gemini) | Implemented | register.rs:191; e2e: `suite/examples/vertex_gemini.rs` |
| `http_callout` | Generic (branch-chain data) | Experimental (`http-callout-filter`) | register.rs:207; `praxis-ai/filters/src/callout/mod.rs:4-10` |
| `api_key_auth` | Auth (EnMaaS-style `sk-oai-*` key validation) | Implemented (feature `api-key-auth-filter`, part of `full`) | register.rs:212; `praxis-ai/filters/src/api_key_auth/mod.rs:4-14` |
| `model_catalog` | Routing/UX (serves `GET /v1/models` from config) | Implemented | register.rs:216; `praxis-ai/filters/src/model_catalog/mod.rs:4-12` |
| `content_normalize` | Translation (vLLM Anthropic block compat) | Implemented | register.rs:220; `praxis-ai/filters/src/content_normalize/mod.rs:4-18` |
| `model_access` | AuthZ (per-group model allow/deny lists, globs) | Implemented | register.rs:224; `praxis-ai/filters/src/model_access/mod.rs:4-13` |
| `identity_header_guard` | Auth/tenant isolation (capture+strip prefixed identity headers) | Implemented | register.rs:228; `praxis-ai/filters/src/identity_guard/mod.rs:4-11` |
| `model_to_header` | Routing (promote body `model` to header) | Implemented | register.rs:232; `praxis-ai/filters/src/inference/model_to_header.rs:4` |
| `model_to_provider` | Routing (model-id → provider + target model) | Implemented | register.rs:236; `praxis-ai/filters/src/inference/model_to_provider.rs:4-10` |
| `llmisvc_model_provider_resolver` | Routing (LLMISvc/KServe publisher-ID rewrite) | Implemented | register.rs:240; `praxis-ai/filters/src/inference/llmisvc_model_provider_resolver.rs:4-6` |
| `prompt_enrich` | Prompt manipulation | Implemented | register.rs:244; `praxis-ai/filters/src/prompt_enrich/mod.rs:4-5` |
| `reasoning_effort_map` | Request rewrite (effort vocabulary, e.g. Qwen3.8) | Implemented | register.rs:248; `praxis-ai/filters/src/reasoning_effort_map/mod.rs:4-16` |
| `time_to_first_token` | Observability (TTFT histogram) | Implemented | register.rs:252; `praxis-ai/filters/src/time_to_first_token/mod.rs:4-12` |
| `stream_usage_inject` | Metering enabler (force `stream_options.include_usage`) | Implemented | register.rs:277; `praxis-ai/filters/src/token_usage/stream_usage.rs:4-20`; e2e: `suite/examples/stream_usage_inject.rs` |
| `token_count` | Metering/token accounting | Implemented | register.rs:281; `praxis-ai/filters/src/token_usage/count.rs:4-13` |
| `token_usage_headers` | Metering (usage → response headers) | Implemented | register.rs:285; `praxis-ai/filters/src/token_usage/headers.rs:4` |
| `token_rate_limit` | Rate limiting (token-denominated) | Experimental (`token-rate-limit-filter`) | register.rs:290; `praxis-ai/filters/src/token_rate_limit/mod.rs:4-49` (in-memory or Valkey backend, sliding_window/token_bucket) |
| `token_ceiling` | Rate limiting (static pre-forward ceiling, fail-closed) | Experimental (`token-ceiling-filter`) | register.rs:295; `praxis-ai/filters/src/token_usage/ceiling.rs:4-9` |
| `reject_upgrade` | Security (block WebSocket bypass of metering) | Implemented | register.rs:266; `praxis-ai/filters/src/reject_upgrade/mod.rs:4-18` |
| `external_metering` | Metering (CloudEvents balance-check + usage report) | Implemented | register.rs:316; `praxis-ai/filters/src/metering/mod.rs:4-15`, config at `filters/src/metering/config.rs:50-120` |
| `intelligent_route` | Routing (edge, overlay-driven candidate selection) | Implemented | register.rs:325; `praxis-ai/filters/src/routing/intelligent_route.rs` |
| `provider_route` | Routing (provider-local validation, security-critical) | Implemented | register.rs:327; `praxis-ai/filters/src/routing/provider_route.rs:4-12` |
| `credential_inject` | Credential injection (bearer/API-key from routing metadata) | Implemented, security-critical | register.rs:328; `praxis-ai/filters/src/routing/credential_inject.rs:4-24` |
| `anthropic_messages_request` | Anthropic (classify+validate `/v1/messages` body) | Implemented | register.rs:355; `praxis-ai/apis/src/anthropic/messages_request/mod.rs:4-21` |
| `anthropic_messages_protocol` | Anthropic (native header normalization) | Implemented | register.rs:359; `praxis-ai/apis/src/anthropic/protocol/mod.rs:4-7` |
| `anthropic_messages_to_chat_completions` | Translation (Anthropic→OpenAI) | Implemented | register.rs:363; e2e: `tests/integration/sdk/anthropic/test_anthropic_messages_to_chat_completions.py` |
| `anthropic_messages_to_chat_completions_stream` | Translation (Anthropic→OpenAI, SSE) | Implemented | register.rs:367 |
| `anthropic_web_search` | Agentic (Anthropic server-side web-search loop) | Implemented | register.rs:600; `praxis-ai/docs/filters/anthropic_web_search.md:3-12` (brave/tavily/you providers) |
| `openai_responses_model_rewrite` | Responses | Implemented | register.rs:376 |
| `openai_tool_parse` | Responses (tool defs → routing facts) | Implemented | register.rs:380 |
| `openai_conversations` | Responses/state (serves `/v1/conversations` locally) | Implemented (feature `openai-conversations`, store-backed) | register.rs:385; `praxis-ai/apis/src/openai/conversations/filter.rs:4-10`; e2e: `suite/examples/openai_conversations.rs` |
| `openai_chat_completions_request` | OpenAI (chat completions validation/state) | Implemented | register.rs:389 |
| `ai_operation` | Routing (operation classifier) | Implemented | register.rs:393 |
| `state_owner`, `project_state_owner_headers`, `callout_credentials` | Security/state plumbing | Implemented, security-critical | register.rs:402, 414, 428 |
| `praxis_store_readiness_gate` | Store | Implemented (feature `store`) | register.rs:63; `praxis-ai/filters/src/store_readiness.rs:4` |
| `openai_doc_extract` | Responses (input_file → input_text) | Implemented | register.rs:442 |
| `openai_responses_request` | Responses (validate + init `ResponsesState`) | Implemented | register.rs:448; `praxis-ai/apis/src/openai/responses/mod.rs:4-27` |
| `openai_responses_rehydrate` | Responses/state (`previous_response_id` → history) | Implemented (feature `store`) | register.rs:453; e2e: `suite/examples/rehydrate.rs`, `suite/conversations_rehydrate.rs` |
| `openai_responses_compact` | Responses/state (context compaction) | Implemented (feature `openai-compact`) | register.rs:655; e2e: `suite/examples/compact.rs` |
| `openai_responses_store` | Responses/state (persist responses) | Implemented (feature `store`) | register.rs:467; e2e: `suite/examples/openai_responses_store*.rs` |
| `openai_stream_events` | Responses (compose IRR runs into one SSE stream) | Implemented | register.rs:471 |
| `openai_responses_proxy` | Responses (rebuild body from state, native passthrough) | Implemented | register.rs:475 |
| `openai_responses_to_chat_completions` | Translation (Responses→Chat Completions) | Implemented | register.rs:479; conformance: `tests/conformance/openresponses/manifest.yaml:1-33` |
| `openai_client_tool_compat` | Responses (rich tools ↔ function tools) | Implemented | register.rs:485 |
| `openai_file_resolve` | Responses (file_id/file_url inline) | Implemented (feature `openai-file-resolve-filter`) | register.rs:623 |
| `openai_file_search_dispatch` | Responses/agentic (vector-store dispatch) | Implemented | register.rs:674 |
| `openai_web_search_dispatch` | Responses/agentic (web_search_call dispatch) | Implemented | register.rs:704 |
| `openai_mcp_tool_resolve` | Responses/agentic (MCP tools/list discovery) | Implemented (feature `openai-mcp-tools`, chain-binding) | register.rs:524 |
| `openai_mcp_dispatch` | Responses/agentic (MCP tools/call executor) | Implemented (feature `openai-mcp-tools`, chain-binding) | register.rs:532 |
| `openai_mcp_streaming_selector` | Responses/agentic (MCP streaming mode) | Implemented | register.rs:540 |
| `openai_agentic_loop` | Responses/agentic (loop controller) | Implemented | register.rs:549; `praxis-ai/docs/filters/openai_agentic_loop.md:3-11` |
| `ai_guardrails` | Guardrails (NeMo provider) | Implemented (chain-binding; only `nemo` provider in code — see below) | register.rs:566; `praxis-ai/filters/src/guardrails/config.rs:54-57` |

Notes on status:
- **Guardrails providers**: only `ProviderType::Nemo` exists in code (`praxis-ai/filters/src/guardrails/config.rs:54-57`). Lakera is reached through the generic experimental `http_callout` filter, not a native guardrails provider (`praxis-ai/examples/configs/lakera-guard.yaml:53-58`).
- **Web-search providers**: `brave`, `tavily`, `you` (`praxis-ai/docs/filters/anthropic_web_search.md:20`; `praxis-ai/apis/src/web_search/config.rs:28-44`).
- Experimental (off-by-default) features: `http-callout-filter`, `azure-ad-filter`, `gcp-adc-filter`, `token-rate-limit-filter`, `token-ceiling-filter` (`praxis-ai/filters/Cargo.toml:44-63`).

## 2. Provider API support

| Provider | What "support" means | Citation |
|---|---|---|
| OpenAI | Native: Chat Completions request handling (`openai_chat_completions_request`), Responses API pipeline (see §3), model rewrite, tool parse | register.rs:376-393 |
| Anthropic | Native `/v1/messages`: classify/validate (`anthropic_messages_request`), header normalization (`anthropic_messages_protocol`); translation to Chat Completions (non-stream + SSE stream filters); `anthropic_web_search` server-tool loop | register.rs:355-367; `apis/src/anthropic/messages_request/mod.rs:4-21`; `apis/src/anthropic/protocol/mod.rs:4-7` |
| Azure OpenAI | Body/path translation (`openai_chat_completions_to_azureai_chat_completions`: deployment paths, `api-version`, `api-key` header, content-filter fields); Entra ID token acquisition (`azure_ad`, experimental) | `apis/src/azure/to_openai/mod.rs:4-10`; `filters/src/azure/mod.rs:4-5` |
| AWS Bedrock | Full body translation Chat Completions → Converse, incl. non-streaming response translation, error normalization, and **binary EventStream → OpenAI SSE inline translation**; **SigV4 signing implemented on system OpenSSL** (`aws_sigv4_sign`) | `apis/src/bedrock/converse/mod.rs:4-10`; `filters/src/aws/signing.rs:10-28` |
| Google Vertex | Two filters: `vertex` (Anthropic Messages ⇄ Vertex `rawPredict` dialect: model into URL, `:streamRawPredict`, marker header) and `openai_chat_completions_to_vertexai_gemini`; `gcp_adc` auth (experimental) | `apis/src/vertex/mod.rs:4-17`; register.rs:187-191; `filters/src/gcp/mod.rs:4-18` |
| vLLM / llm-d | Not a provider filter per se: compatibility filters (`content_normalize`, `reasoning_effort_map`, `llmisvc_model_provider_resolver`, `openai_doc_extract`) and extensive vLLM-backed test suites | `filters/src/content_normalize/mod.rs:4-18`; `filters/src/inference/llmisvc_model_provider_resolver.rs:4-6`; e.g. `tests/integration/sdk/anthropic/test_anthropic_messages_vllm.py` |

## 3. Responses API — what exactly exists

**Served paths** (`praxis-ai/apis/src/openai/responses/routes/mod.rs:186-255`):
- `POST /v1/responses` — `createResponse`, `HandlingMode::Transform` (Praxis owns the contract under the translated profile) (routes/mod.rs:188-193)
- `GET /v1/responses` as **WebSocket** upgrade — `praxis_createResponseWebSocket`, Passthrough (routes/mod.rs:203-204)
- `GET/DELETE /v1/responses/{response_id}`, `POST /v1/responses/{response_id}/cancel`, `GET /v1/responses/{response_id}/input_items`, `POST /v1/responses/input_tokens`, `POST /v1/responses/compact` — all Passthrough (routes/mod.rs:213-249)

**Request-path filters** (`openai_responses_request`): validates JSON, rejects conflicting history selectors, initializes `ResponsesState`, classifies without mutating the body (`apis/src/openai/responses/mod.rs:4-27`).

**Store/rehydrate**: `openai_responses_store` persists responses; `openai_responses_rehydrate` validates `previous_response_id` against the store (must be `completed`) and populates full conversation history (`apis/src/openai/responses/rehydrate/mod.rs`; README at `apis/src/openai/responses/README.md`). Backends: in-memory, SQLite, PostgreSQL (incl. cert-auth mTLS) — `praxis-ai/store-backends/src/postgres.rs:53`, `store-backends/src/sqlite.rs:37`, `store/src/memory.rs`.

**Agentic**: `openai_agentic_loop` (iteration bookkeeping, tool-call extraction, `iterative_request_router` transitions, `max_infer_iters`), `openai_mcp_tool_resolve` (top-level `tools/list`), `openai_mcp_dispatch` (per-round `tools/call`, runs inside IRR steps), `openai_web_search_dispatch`, `openai_file_search_dispatch`, `openai_responses_compact`, `openai_conversations` (local Conversations API) — all registered and documented (register.rs:524-549, 655, 674, 704; `docs/filters/openai_agentic_loop.md:3-11`).

**End-to-end test evidence**:
- Codex CLI over Responses HTTP and WebSocket passthrough: `praxis-ai/tests/integration/tests/suite/codex_http.rs:4-14`, `suite/codex_websocket.rs:4-13`
- OpenAI Agents SDK with tool loop: `tests/integration/sdk/openai/test_openai_agents_sdk.py:528` (`test_function_tool_loop_over_responses`)
- Responses→vLLM: `tests/integration/sdk/openai/test_openai_responses_vllm.py`
- OpenResponses conformance (pinned suite, strict all-pass gate on supported templates): `tests/conformance/openresponses/manifest.yaml:1-33`, runner `tests/integration/sdk/openai/test_responses_conformance.py:6-11`
- Store/rehydrate/compact/conversations/MCP: `suite/examples/openai_responses_store*.rs`, `suite/examples/rehydrate.rs`, `suite/examples/compact.rs`, `suite/examples/openai_conversations*.rs`, `suite/examples/openai_mcp_*.rs`
- Claude Code CLI over `/v1/messages`: `suite/claude_code.rs:6-12`, `suite/claude_code_vllm.rs`

I found no separate `openai_responses_store`/`rehydrate` "stub" markers — both are registered, tested, and store-feature-gated. The pipeline hook matrix for all Responses filters is auto-generated in `apis/src/openai/responses/README.md` (filter/hook table).

## 4. praxis-extproc

- **What it is**: a standalone Envoy **ExtProc (external processing) gRPC server** that runs Praxis filter pipelines inside Envoy without replacing the data plane (`praxis-extproc/README.md:9-14`; `praxis-extproc/docs/architecture.md:3-6`).
- **Relation to praxis-ai**: it is a thin transport adapter. It depends on `praxis-ai-filters` **pinned to upstream tag `v0.6.0`** (`praxis-extproc/Cargo.toml:56-59`) and builds the same registry via `praxis_ai_filters::build_ai_registry()` (`praxis-extproc/src/bin/praxis_extproc.rs:78`). Default features: `aws-sigv4`, `policy-engine`, `responses-full` (all Responses groups + store backends, `praxis-extproc/Cargo.toml:17`). A FIPS profile (`store-postgres-cert-auth`) selects the cert-only Postgres store (`Cargo.toml:41-47`).
- **Phases supported**: request headers, request body, response headers, response body; trailers are passthrough (`docs/architecture.md:59-118`). Body modes per Envoy config: `None`, `Streamed`, `Buffered` (`src/response.rs:36-44`); body accumulation capped at 10 MiB, outbound chunking at 62 KiB (`docs/architecture.md:59-118` body sections).
- **Aux services**: gRPC :50051, health :50052, Prometheus metrics :9090; "alive-but-not-ready" on bad config (`docs/architecture.md:154-181`).
- **Tests**: in-process gRPC integration (`tests/grpc_server.rs:4-7`), K8s/Istio e2e (`tests/integration.rs:4-13`), and ODH EnvoyFilter ordering tests (`tests/odh_envoy_filter.rs:4-8`).

## 5. Deployment/config model

- **praxis-ai**: static YAML config (listeners + named `filter_chains` + filters) loaded at startup, with a **compiled-in default** (`praxis-ai/server/src/default.yaml:1-9`). **Hot reload**: a file watcher (`notify`) validates, rebuilds, and atomically swaps pipelines (`server/src/watcher.rs:4-9`, `server/src/reload.rs:4`). Store backends are provisioned per listener (`server/src/store_provision.rs`, referenced at `server/src/pipelines.rs:79`).
- **praxis-extproc**: YAML with `filter_chains`, `server` (addresses, TLS), `insecure_options`; listeners/clusters omitted because Envoy owns networking (`praxis-extproc/docs/configuration.md:3-15`). Kubernetes deployment via Kustomize overlays (`deploy/base`, `deploy/overlays/{odh,demo,e2e,openshift}`); the ODH overlay wires two ExtProc EnvoyFilters (pre/after) into an Istio gateway with Kuadrant anchors (`deploy/overlays/odh/envoy-filter.yaml:1-47`).
- **Runtime model/provider resolution**: there is **no live Kubernetes CRD watch** in praxis-ai. `model_to_provider` explicitly "does not watch Kubernetes resources or perform request-time control-plane lookups" (`praxis-ai/filters/src/inference/model_to_provider.rs:10`). `intelligent_route` consumes a controller-rendered routing overlay with hot reload; K8s-native routing from `ExternalModel`/`ExternalProvider` CRDs is the controller's job (`praxis-extproc/docs/migration-ipp-to-praxis.md:199-208`). In praxis-extproc the controller renders config from CRDs — "CRDs are unchanged; consumed by the controller, which renders Praxis config" (`docs/migration-ipp-to-praxis.md:20-24`).

## 6. Metering / usage / token accounting

- **Extraction**: `token_count` parses usage from streaming SSE and non-streaming JSON across provider formats; Bedrock `InvokeModel` usage is read from response headers instead (`praxis-ai/filters/src/token_usage/count.rs:4-13`).
- **Enabler**: `stream_usage_inject` forces `stream_options: {"include_usage": true}` on streaming chat requests so metering works regardless of client (`filters/src/token_usage/stream_usage.rs:4-11`).
- **Exposure**: `token_usage_headers` emits normalized counts as response headers (`filters/src/token_usage/headers.rs:4`).
- **Reporting**: `external_metering` does pre-request entitlement/balance checks and post-response usage reporting as CloudEvents to an external metering service; reads `token.input/output/total`, `cache_read/write`, `reasoning` from filter metadata; supports fail-open, model-policy preflight, identity-header capture (`filters/src/metering/mod.rs:4-15`; `filters/src/metering/config.rs:50-120`).
- **Rate limiting**: `token_rate_limit` (experimental) — per-rule static header matchers, `sliding_window` or `token_bucket`, reservation-based admission reconciled against provider-reported usage, 429 + token-denominated RL headers; in-process (default) or shared **Valkey** backend (`filters/src/token_rate_limit/mod.rs:18-39`). `token_ceiling` (experimental) — fail-closed static pre-forward ceilings (`filters/src/token_usage/ceiling.rs:4-9`).
- **Observability**: TTFT/TPOT/ITL histograms, finish-reason and token metrics, per model/cluster labels (`filters/src/llm_metrics.rs:4-12`; `docs/llm-metrics.md`).
- **API-key auth + metering pairing**: `api_key_auth` validates keys against an external service and injects verified identity for metering/audit (`filters/src/api_key_auth/mod.rs:4-14`).

## 7. Test coverage signals (evidence of what works)

- **Rust integration suite** (`praxis-ai/tests/integration/tests/suite/`): 25+ top-level suites incl. `a2a.rs`, `mcp.rs`, `mcp_broker.rs`, `claude_code.rs`, `claude_code_vllm.rs`, `codex_http.rs`, `codex_websocket.rs`, `conversations_rehydrate.rs`, `guardrails.rs`, plus `suite/examples/` with **~60 example-driven e2e tests** covering nearly every filter (aws_sigv4, azure_ad, azure_translation, bedrock, gcp_adc, vertex_gemini, vertex_anthropic, external_metering, token_rate_limit, token_ceiling, openai_responses_store_postgres(+mtls), openai_mcp_*, web_search, compact, etc. — full listing `tests/integration/tests/suite/examples/`).
- **SDK-level Python tests** against real vLLM/LLM Katana backends: `tests/integration/sdk/anthropic/` (6 files) and `tests/integration/sdk/openai/` (9 files incl. `test_openai_agents_sdk.py`, `test_openai_conversations.py`, `test_responses_conformance.py`).
- **Conformance**: pinned OpenResponses suite triaged into supported/unsupported/inapplicable with a strict CI all-pass gate on supported templates (`tests/conformance/openresponses/manifest.yaml:1-33`).
- **Qualification**: vLLM qualification harness (`tests/qualification/test_vllm_qualification.py`).
- **praxis-extproc**: in-process gRPC tests (`tests/grpc_server.rs`), TLS listener tests (`tests/tls_listener.rs`), service tests (`tests/services.rs`), ODH EnvoyFilter ordering tests (`tests/odh_envoy_filter.rs`), KIND-based integration (`tests/integration.rs`, `hack/setup-kind.sh`).

---

## IPP-parity notes (from code)

The praxis-extproc migration doc gives the authoritative plugin mapping against its **v0.6.0 pin** (`praxis-extproc/docs/migration-ipp-to-praxis.md:150-158`):

| Go IPP plugin | Praxis filter | Parity (per doc) |
|---|---|---|
| `body-field-to-header` | `json_body` (`request_extract`) | Full* |
| `maas-headers-guard` | `headers` + `when`/`unless` | Partial (#5) |
| `model-provider-resolver` | `intelligent_route` (controller-rendered overlay) | Partial, K8s (#5, #7) |
| `stream-usage-enforcer` | *(none yet)* | **None** (#44) |
| `api-translation` | provider-native chains | Partial, reverse (#6) |
| `apikey-injection` | `credential_inject` | Partial, SigV4/OAuth2 (#6) |
| `nemo-request/response-guard` | `ai_guardrails` | Partial, timeout unit (#111) |

**Discrepancy worth flagging**: the migration doc states no Praxis filter injects `stream_options: {include_usage: true}` (`docs/migration-ipp-to-praxis.md:228-234`), but the analyzed praxis-ai HEAD (redhat-et fork, `8a9a2159`) **does** implement `stream_usage_inject` (`filters/src/token_usage/stream_usage.rs:4-20`, registered at `register.rs:277`, added upstream as #1231 and present in the fork's rebase commit `065bd1ae`). The extproc's pinned v0.6.0 apparently predates it; **NOT IMPLEMENTED IN CODE at the pinned rev** (planned per `praxis-extproc` issue #44, cited in `docs/migration-ipp-to-praxis.md:34`).

Also in praxis-ai proper, `maas-headers-guard` semantics are covered natively by `identity_header_guard` (generic configurable prefix, documented as mapping to IPP's plugin — `filters/src/identity_guard/mod.rs:9-11`), which is a stronger parity position than the core `headers`-filter approach the extproc doc describes for its v0.6.0 pin.

**Not found in code** (marked per charter):
- No native guardrails provider other than NeMo — Lakera only via experimental `http_callout` (`filters/src/guardrails/config.rs:54-57`). NOT IMPLEMENTED IN CODE as a native provider.
- No live Kubernetes CRD watching/model resolution in praxis-ai — controller-rendered config only (`filters/src/inference/model_to_provider.rs:10`; `praxis-extproc/docs/migration-ipp-to-praxis.md:199-208`). NOT IMPLEMENTED IN CODE.
- No streaming body processing in praxis-extproc beyond Envoy's `Streamed`/`Buffered` body modes with per-stream buffered accumulation; no SSE-aware incremental mutation at the extproc layer (`praxis-extproc/src/response.rs:36-44`; `docs/architecture.md:59-118`). (SSE translation happens inside praxis-ai filters, which the extproc carries via buffered bodies.)
