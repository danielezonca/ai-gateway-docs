All research complete. Below is the fact sheet.

---

# IPP GA Plugin Set — Fact Sheet

**Repos analyzed (read-only):**
- `ai-gateway-payload-processing` (opendatahub-io downstream) — HEAD `f0ddb04`
- `llm-d-inference-payload-processor` (llm-d upstream) — HEAD `4a38b6a`

All paths below are workspace-relative to `/Users/dzonca/GIT/clones/`.

---

## 1. GA plugin list, registry, and pipeline order

### Plugin registry (build)

Downstream `main` registers 6 additional plugin types with the upstream pluggable framework before starting the runner:

- `ai-gateway-payload-processing/cmd/main.go:26-42` — `plugins.RegisterPlugins()` then `runner.NewRunner().WithCustomControllers(providerController(), modelController(...), legacyMigrationController())`
- `ai-gateway-payload-processing/pkg/plugins/plugins.go:29-34` — registers:
  - `maas-headers-guard` (`plugins.go:29`)
  - `model-provider-resolver` (`plugins.go:30`)
  - `api-translation` (`plugins.go:31`)
  - `apikey-injection` (`plugins.go:32`)
  - `nemo-request-guard` (`plugins.go:33`)
  - `nemo-response-guard` (`plugins.go:34`)

Upstream registers in-tree plugins (also compiled into the downstream image, since the downstream binary embeds the upstream runner):

- `llm-d-inference-payload-processor/cmd/runner/runner.go:254-256` — `framework.Register(bodyfieldtoheader...)`, `framework.Register(basemodelextractor...)`, `framework.Register(datalayer.NotificationSource...)`

### Deployed GA pipeline (Helm values)

- `ai-gateway-payload-processing/deploy/payload-processing/values.yaml:15-39` — `customConfig.plugins` defines instances: `maas-headers-guard`, `body-field-to-header` (instance `model-extractor`, fieldName `model` → header `X-Gateway-Model-Name`), `model-provider-resolver`, `api-translation`, `apikey-injection`; `profiles[default]` fixes execution order:
  - **Request order:** maas-headers-guard → model-extractor (body-field-to-header) → model-provider-resolver → api-translation → apikey-injection
  - **Response order:** api-translation only
- Same chain in the e2e config: `ai-gateway-payload-processing/test/e2e/scripts/e2e-values.yaml` (with `model-provider-resolver` params `gatewayName`/`gatewayNamespace` and `api-translation` params `vertexOpenAI{project,location,endpoint}`)
- The nemo plugins are **registered in the binary but not in the default profile** (absent from `values.yaml:15-39`).
- Note: the pinned upstream OCI chart (`deploy/payload-processing/Chart.yaml` dependency `payload-processor` `v0.1.0-rc.2`) consumes `customConfig`; the in-repo upstream chart renders `payloadProcessor.plugins` → repeatable `--plugin <type>:<name>[:<json>]` args (`llm-d-inference-payload-processor/config/charts/payload-processor/templates/payload-processor.yaml:27-35`, flag format at `llm-d-inference-payload-processor/pkg/config/spec.go:22-64`). The `profiles`→flag rendering of the pinned OCI chart is NOT VERIFIABLE in these checkouts.
- Plugin instances are executed in the order their `--plugin` flags appear (`llm-d-inference-payload-processor/cmd/runner/runner.go:199-218`).
- Default upstream behavior with no plugin flags: `body-field-to-header` (model → `X-Gateway-Model-Name`) + `base-model-to-header` (`llm-d-inference-payload-processor/cmd/runner/runner.go:176-201`).

### Pipeline summary table

| Plugin | Provider/scope | Request behavior | Response behavior | Streaming | Citation |
|---|---|---|---|---|---|
| maas-headers-guard | downstream, all requests | Captures all `x-maas-*` headers into CycleState key `maas-headers`, removes them from the request | none (no ProcessResponse) | n/a (headers only) | `pkg/plugins/maas-headers-guard/plugin.go:34-75` |
| body-field-to-header (`model-extractor`) | upstream, all requests | Extracts body field (config: `model`) → sets header `X-Gateway-Model-Name`; skips if field missing/empty | none | n/a | `llm-d-.../pkg/plugins/bodyfieldtoheader/body_field_to_header.go:87-105` |
| base-model-to-header | upstream (in binary, not in GA profile) | Maps `body.model` → `X-Gateway-Base-Model-Name` via LoRA-adapter ConfigMap store | none | n/a | `llm-d-.../pkg/plugins/basemodelextractor/base_model_to_header.go:87-106` |
| model-provider-resolver | downstream, external models | Parses `/<ns>/<model-name>/...` from `:path`, resolves ExternalModel/ExternalProvider, weighted-random provider-ref selection, writes 10 CycleState keys | none | n/a | `pkg/plugins/model-provider-resolver/plugin.go:139-180` |
| api-translation | downstream, external models | Path-rewrite and/or body translation per provider; removes client `authorization` header; applies `:path` override from CycleState | Translates provider-native response back to OpenAI Chat Completions (Anthropic full translation; Azure/Vertex field stripping; OpenAI/Bedrock no-op) | Request `stream` flag carried through for Anthropic; **response translation does not run on SSE streams** (see §3) | `pkg/plugins/api-translation/plugin.go:146-243` |
| apikey-injection | downstream, external models | Injects provider credential headers (simple/Bearer or AWS SigV4) from watched Secrets | none | n/a | `pkg/plugins/apikey-injection/plugin.go:118-159` |
| nemo-request-guard | downstream, opt-in | POSTs user messages (OpenAI chat or MCP JSON-RPC args) to NeMo Guardrails `/v1/guardrail/checks`; 403 on `blocked` | none | n/a | `pkg/plugins/nemo/request_guard.go:82-118` |
| nemo-response-guard | downstream, opt-in | none | POSTs assistant messages from `choices[].message/delta` or MCP `result.content` to NeMo; 403 on `blocked` | Handles `delta` in body parsing, but only runs on a full JSON body (see §3) | `pkg/plugins/nemo/response_guard.go:83-112,130-160` |

---

## 2. Per-plugin detail

### maas-headers-guard
- Prefix `x-maas-` (case-insensitive): `pkg/plugins/maas-headers-guard/plugin.go:34`
- Captures matching headers into `CycleState["maas-headers"]` (map[string]string) and removes them from the forwarded request: `plugin.go:62-75`
- **No downstream plugin in code reads `MaaSHeadersKey`** — only its own tests reference it (`pkg/plugins/maas-headers-guard/plugin_test.go:63,82,99`). The captured map is currently write-only at runtime.

### model-provider-resolver
- **CRDs watched** (controller-runtime, typed clients, registered via factory `ReconcilerBuilder`):
  - `inference.opendatahub.io/v1alpha1 ExternalProvider` (`pkg/plugins/model-provider-resolver/plugin.go:62-65`)
  - `inference.opendatahub.io/v1alpha1 ExternalModel` with a cross-watch on ExternalProvider so credential/endpoint changes propagate (`plugin.go:68-97`)
- **Stores:** in-memory `infoStore` (providers keyed by NamespacedName; models nested namespace→name), `pkg/plugins/model-provider-resolver/store.go:57-131`
- **Weighted selection:** `selectByWeight` — single ref returned directly; otherwise cumulative-weight random using `rand.IntN(totalWeight)` (`plugin.go:196-212`). Weight comes from `ExternalProviderRef.Weight` (default 1) (`external_model_reconciler.go:118-121`); CRD field `weight *int` at `api/inference/v1alpha1/externalmodel_types.go:108`.
- **Config merge:** `mergeConfig(providerConfig, modelConfig)` — provider config first, model-level `ExternalProviderRef.Config` overrides (`external_model_reconciler.go:140-149`). Provider config gets auth-header defaults injected per provider: Anthropic → `x-api-key`, Azure/azure-openai → `api-key` (`external_provider_reconciler.go:34-43,78-88`).
- **Path placeholders:** `{key}` in `ExternalProviderRef.Path` substituted from merged config (`external_model_reconciler.go:36-44`).
- **Ref auth override:** `ExternalProviderRef.Auth` (secretRef + type) overrides the provider-level auth (`external_model_reconciler.go:107-113`).
- **CycleState keys written** (all at `plugin.go:167-176`, key constants at `pkg/plugins/common/state/state-keys.go:20-31`): `provider`, `model` (targetModel), `api-format`, `auth`, `endpoint`, `path`, `credential-ref-name`, `credential-ref-namespace`, `model-config`, `input-api-format`.
- **Input format detection** from path suffix: `/v1/chat/completions` → `openai-chat`, `/v1/messages` → `messages`, `/v1/responses` → `openai-responses` (`plugin.go:182-193`); unsupported path → 400; model-body mismatch → 404 (`plugin.go:157-164`).
- Model key is taken from the **path** (`/<namespace>/<model-name>/…`, `plugin.go:143-151`), body `model` must equal ExternalModel's client-facing `modelName` (`plugin.go:158-162`).
- Requests whose model is not in the store are passed through unchanged (internal models) (`plugin.go:146-148`).

### api-translation
- Dispatch on CycleState `provider` key; no provider → no-op (`plugin.go:148-152`). Passthrough mode (input format == output format, excluding `openai-chat`) skips translation, still removes `authorization` and applies the `:path` override (`plugin.go:157-162,246-270`, design doc `docs/design-multi-provider-passthrough.md`).
- Registered translators (`plugin.go:85-99`): `openai`, `anthropic`, `azure-openai`, `bedrock-openai`, plus `vertex-openai` only when `vertexOpenAI{project,location,endpoint}` config is provided (all three fields required, `plugin.go:92-101`). Native `vertex` (Gemini) translator is implemented but **not registered** (commented out at `plugin.go:84`, code at `pkg/plugins/api-translation/translator/vertex/vertex.go`).
- Always removes client `authorization` header (credential re-injected by apikey-injection): `plugin.go:160,194`. `:path` set from CycleState `path` key (`plugin.go:137-142,196`).
- **Per provider:**

| Provider | Path rewrite | Body translation (request) | Response translation |
|---|---|---|---|
| OpenAI | `:path` → `/v1/chat/completions`; validates `model` + non-empty `messages` | none (nil body) | none (no-op) |
| Anthropic | `:path` → `/v1/messages`; sets `anthropic-version: 2023-06-01`, `content-type: application/json` | Full translation OpenAI→Messages: system messages separated to top-level `system` (incl. `developer` role), `tool_calls`→`tool_use` blocks, `tool` role→`tool_result` blocks, `max_tokens` (default 4096), `temperature`, `top_p`, `stop_sequences`, `tools`/`tool_choice`, `stream`, `response_format`, image content | Full translation back to `chat.completion`: content, `stop_reason` mapping, usage mapping, `tool_use`→`tool_calls`, error mapping |
| Azure OpenAI | `:path` → `/openai/v1/chat/completions`; `content-type: application/json` | none (same schema) | Strips `prompt_filter_results` and `choices[].content_filter_results` via ResponseFieldStripper |
| Bedrock (OpenAI-compat) | `:path` → `/v1/chat/completions`; `content-type: application/json`; validates `model` + `messages` | none | none (no-op) |
| Vertex OpenAI-compat | `:path` → `/v1/projects/{project}/locations/{location}/endpoints/{endpoint}/chat/completions` (from plugin config); `content-type: application/json` | none | Strips `usage.extra_properties` |
| Vertex native (Gemini) | `:path` → `/v1beta/models/{model}:generateContent` | Full OpenAI→GenerateContent translation (systemInstruction, contents, generationConfig, tools) | Full translation back (candidates, finishReason, usage, error mapping) — **NOT REGISTERED** |

  Citations: OpenAI `pkg/plugins/api-translation/translator/openai/openai.go:35-54`; Anthropic `translator/anthropic/anthropic.go:48-113,116-165` (version const `:30`, path `:31`, max tokens `:32`); Azure `translator/azure/azure_openai.go:24-38,46-56,63-66`; Bedrock `translator/bedrock/bedrock_openai.go:24-27,46-62,68-71`; Vertex OpenAI-compat `translator/vertex/vertex_openai.go:27-40,50-66,68-73`; Vertex native `translator/vertex/vertex.go:30,50-111,113-141`; stripper `translator/response_field_stripper.go:24-45`.

### apikey-injection (credential injection, incl. SigV4)
- **Secret watching:** controller-runtime reconciler on `corev1.Secret` filtered by label `inference.networking.k8s.io/bbr-managed=true` (`pkg/plugins/apikey-injection/reconciler.go:34-47,62-88`; store `store.go:110-171`). The e2e applies Secrets with this label (`test/e2e/e2e_test.go:52-55`). ⚠️ The sample manifests instead use label `inference.llm-d.ai/ipp-managed` (`deploy/samples/manifests/anthropic.yaml:4`, `multi-provider-weights.yaml:5`) — these would **not** be watched by the reconciler as written.
- **Auth generators** (`plugin.go:76-81`): `simple` and `sigv4`. `oauth2` is a defined type but marked "not used yet" (`pkg/plugins/common/auth/auth.go:27`) — NOT IMPLEMENTED IN CODE.
- **Simple generator:** header name/prefix resolved from CycleState `model-config` (`authHeaderName`/`authValuePrefix`), default `Authorization: Bearer `; non-default header (from provider defaults: Anthropic `x-api-key`, Azure `api-key`) implies no prefix unless `authValuePrefix` set; requires Secret field `api-key` (`pkg/plugins/apikey-injection/auth-generator/simple_auth_generator.go:25-40,42-56,58-76`; defaults table `pkg/plugins/model-provider-resolver/external_provider_reconciler.go:34-43`).
- **SigV4 generator** (`auth-generator/sigv4_auth_generator.go`):
  - Requires Secret fields `aws-access-key-id`, `aws-secret-access-key`, optional `aws-session-token` (`:30-32,101-107`).
  - Extracts request data: marshaled request body (deterministic sorted keys), CycleState `endpoint`, current `:path` header, `region` and `service` from model config; region falls back to parsing `service.region.amazonaws.com` hostnames (exactly 4 labels) (`:66-99,155-169`); `service` is mandatory (e.g. `bedrock`, `sagemaker`) (`:90-92`).
  - Signs with AWS SDK v4 signer over `https://<endpoint><path>`, SHA-256 body hash, and emits `Authorization`, `X-Amz-Date`, `X-Amz-Content-Sha256`, and `X-Amz-Security-Token` when a session token exists (`:109-151`).
- Injection happens by `request.SetHeader` for each generated header (`plugin.go:155-158`). Skipped entirely for internal models (no `auth` CycleState key) (`plugin.go:120-126`).

### body-field-to-header (upstream)
- Config `{fieldName, headerName}`; extracts any body field, stringifies, sets header; metrics `body_field_not_found_total`/`body_field_empty_total` on skip (`llm-d-.../pkg/plugins/bodyfieldtoheader/body_field_to_header.go:33-37,87-105`).

### base-model-to-header (upstream)
- Watches ConfigMaps labeled `inference.llm-d.ai/ipp-managed=true` holding `baseModel` + `adapters` (LoRA mapping), maintains an in-memory adapters store, sets `X-Gateway-Base-Model-Name` from `body.model` (empty string valid) (`llm-d-.../pkg/plugins/basemodelextractor/base_model_to_header.go:34-79,87-106`; `configmap_reconciler.go:32-47`; `adapters_store.go:32-40`).

### maas-headers-guard — see §2 first entry.

### Auth (Authorino interaction)
- **NOT IMPLEMENTED IN CODE.** No plugin in either repo references Authorino. The only mention is the e2e report describing the deployment topology: "Gateway (Istio-based) with Kuadrant (Authorino + Limitador) for auth and rate limiting" (`ai-gateway-payload-processing/test/e2e/reports/3.4/external-model-e2e-report.md:27`), with auth enforced *before* IPP (`report:401`). The downstream Helm README wires the ext_proc EnvoyFilter *after* the Kuadrant wasmplugin filter (`README.md:39-40`). Client `authorization` headers are stripped by api-translation and replaced by provider credentials (`pkg/plugins/api-translation/plugin.go:160,194`).

### Rate limiting
- **NOT IMPLEMENTED IN CODE.** No rate-limiting logic exists in either repo's plugin code (only mention of Limitador is the topology line in the e2e report, `report:27`). Rate limiting lives in the Kuadrant/Limitador gateway layer outside these repos.

### NeMo guardrails (downstream, opt-in)
- Both plugins POST `{model, messages}` to a configurable `nemoURL` (default timeout 360 s, 1 MiB response cap) and interpret NeMo's `status`: `passed` → allow, `modified` → pass through unchanged (redaction NOT IMPLEMENTED IN CODE, noted in comments), `blocked` → 403 (`pkg/plugins/nemo/nemo_guard_base.go:33-39,73-80`; `request_guard.go:82-118`; `response_guard.go:83-112`; guide `examples/nemo/README.md`).
- Request guard supports OpenAI `messages` arrays and MCP JSON-RPC `params.arguments` (string values sorted by key, joined) (`request_guard.go:120-195`). Response guard supports `choices[].message`/`delta` and MCP `result.content[].text` (`response_guard.go:130-171`).

---

## 3. Streaming support per plugin

Framework-level facts (upstream ext_proc server, inherited by downstream):

- The gRPC ext_proc server **buffers the entire request body** until `EndOfStream` before running request plugins (`llm-d-.../pkg/handlers/server.go:127-133`), and **buffers the entire response body** until `EndOfStream` before running response plugins (`server.go:139-145`).
- Request body must parse as JSON or the request is rejected with 400 (`llm-d-.../pkg/handlers/request.go:69-71`).
- **Response plugins run only if the full buffered body parses as JSON**; otherwise plugins are skipped and the raw bytes are replayed to the client unchanged (`llm-d-.../pkg/handlers/response.go:75-79,100-104`). There is **no SSE/`text/event-stream` parsing anywhere in either repo** (grep for `text/event-stream`/SSE returns nothing in `pkg/`).
- Consequence: for streaming (SSE) responses, **no response plugin (incl. api-translation and nemo-response-guard) executes** — the SSE byte stream is buffered and passed through verbatim. Anthropic→OpenAI response translation therefore applies only to non-streaming JSON responses. The Anthropic request translator does forward the `stream` flag (`pkg/plugins/api-translation/translator/anthropic/anthropic.go:97-98`).
- Request-side plugins (all of them) run on the complete buffered request body regardless of whether the client streams the upload.
- Chunked replay to Envoy uses `AddStreamedResponseBody` with a 62 KiB per-chunk safety limit (`llm-d-.../pkg/common/envoy/chunking.go:24-25`; `handlers/response.go:100-104`).
- The 3.4 e2e report claims SSE streaming PASS for all 5 providers (`test/e2e/reports/3.4/external-model-e2e-report.md:151-186`), but the **current** e2e suite has no streaming test (`grep stream test/e2e/e2e_test.go` → no matches) — streaming e2e coverage is NOT IMPLEMENTED IN CODE (report only).

---

## 4. Downstream fork vs upstream llm-d IPP

Downstream-only (present in `ai-gateway-payload-processing`, absent from `llm-d-inference-payload-processor` — verified by grep across all upstream `.go` files):

| Downstream-only component | Citation |
|---|---|
| `maas-headers-guard` plugin | `pkg/plugins/maas-headers-guard/plugin.go` |
| `model-provider-resolver` plugin (+ ExternalModel/ExternalProvider stores & reconcilers) | `pkg/plugins/model-provider-resolver/plugin.go` |
| `api-translation` plugin (+ 5 translator packages + response field stripper) | `pkg/plugins/api-translation/` |
| `apikey-injection` plugin (+ simple & SigV4 auth generators, Secret store/reconciler) | `pkg/plugins/apikey-injection/` |
| `nemo-request-guard` / `nemo-response-guard` plugins | `pkg/plugins/nemo/` |
| `inference.opendatahub.io/v1alpha1` CRDs: ExternalProvider, ExternalModel | `api/inference/v1alpha1/`, CRDs at `config/crd/bases/` |
| Controllers: externalprovider (Service/ServiceEntry/DestinationRule), externalmodel (HTTPRoute with gateway parentRef), legacy `maas.opendatahub.io` migration | `cmd/controllers.go:32-98` |
| Shared plugin common packages (state keys, apiformat, auth, provider constants) | `pkg/plugins/common/` |

Upstream plugins compiled into the downstream binary and available (registered in the shared registry) but **not in the downstream GA profile**: `body-field-to-header` is in the GA profile (as `model-extractor`); `base-model-to-header` and datalayer `NotificationSource` are registered (`llm-d-.../cmd/runner/runner.go:254-256`) but absent from `deploy/payload-processing/values.yaml:15-39`.

Upstream-only recent framework work not used by the downstream profile: model-selector pipeline (`llm-d-.../pkg/framework/modelselector`, `pkg/modelselector`) and datalayer notification source (`pkg/datalayer/notification_source.go`) — registered upstream but not part of the downstream GA chain.

---

## 5. Test coverage signals

**e2e (kind cluster, llm-katan simulator)** — `ai-gateway-payload-processing/test/e2e/e2e_test.go` (436 lines), driven by `test/e2e/scripts/e2e-ci.sh` + `e2e-values.yaml` (full 5-plugin GA chain):
- Per provider (openai, anthropic, azure-openai, bedrock-openai, vertex-openai; `e2e_test.go:34-46`): 200 smoke + OpenAI-format response assertion (`:194-247`), tool calling incl. `finish_reason=tool_calls` (`:284-320`), multimodal image content (`:323-352`), JSON mode (`:355-388`), system prompt + multi-turn (`:390-434`).
- apikey-injection (simulator key validation, tier2, gated on `E2E_SIMULATOR_VALIDATE_KEYS`): wrong key → 401 (`:250-281`).
- model-provider-resolver error paths covered in the 3.4 report only: model mismatch → 404, malformed JSON → 400 (`test/e2e/reports/3.4/external-model-e2e-report.md:407-476`).
- SigV4: unit tests only (`pkg/plugins/apikey-injection/auth-generator/sigv4_auth_generator_test.go`, 280 lines) — **no e2e** for sigv4 auth type.
- Streaming: report-only (`report:151-186`), no test in current e2e code.
- NeMo: unit tests only (`pkg/plugins/nemo/request_guard_test.go`, `response_guard_test.go`); manual guide `examples/nemo/README.md` — no automated e2e.
- maas-headers-guard: unit tests only (`pkg/plugins/maas-headers-guard/plugin_test.go`); not directly asserted in e2e.
- Unit test suites exist for every plugin: api-translation plugin+all translators (`plugin_test.go`, `translator/*/*_test.go`), model-provider-resolver (plugin/reconciler/store tests), apikey-injection (plugin/reconciler/store/generators).

**Upstream** e2e/integration equivalents: hermetic integration tests for body-based routing and body mutation (`llm-d-.../test/integration/hermetic_test.go:38`, `body_mutation_test.go:56`) — cover body-field-to-header/base-model-to-header behavior end-to-end at the ext_proc layer, not the downstream plugins.

**Weighted selection** e2e: NOT IMPLEMENTED IN CODE — a weighted sample manifest exists (`deploy/samples/manifests/multi-provider-weights.yaml`, 80/20 split) and `selectByWeight` has unit coverage (`plugin_test.go`), but no e2e asserts traffic splitting.
