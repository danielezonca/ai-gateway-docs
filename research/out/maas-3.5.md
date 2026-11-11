# MaaS 3.5 GA baseline — request-pipeline fact sheet

**Repo analyzed:** `models-as-a-service` @ commit `8d30ae9a` (workspace-relative path `models-as-a-service/`).
**Comparison target:** `ai-gateway-docs/ai-gateway-flow.html` (read-only; repo `ai-gateway-docs`, not a git analysis target).

**Version framing caveat (important):** HEAD `8d30ae9a` is *post*-3.5 development main. It contains both the RHOAI 3.5 legacy IPP dataplane **and** the 3.6 "Praxis" (ai-gateway-controller) migration machinery. The repo's own migration doc identifies the *RHOAI 3.5* plugin ConfigMap shape as: "ODH 3.5.0 default (no `model-provider-resolver` in pre-processing, no `maas-headers-guard` in processing, response `api-translation`)" (`models-as-a-service/docs/content/migration/upgrade-to-3.6.md:59`), whereas the checked-in default at HEAD adds `model-provider-resolver` to pre-processing, adds `maas-headers-guard` to processing, and ships `response: []` (`models-as-a-service/deployment/base/payload-processing/manager/plugins-configmap.yaml:12-53`; release note "Model-provider-resolver and maas-headers-guard added to the IPP pipeline for BBR support", `models-as-a-service/docs/content/release-notes/index.md:81`). Everything below cites what the code at HEAD actually builds; where the 3.5-GA-vs-HEAD distinction matters it is called out.

---

## 1. The exact ext_proc plugin/filter list deployed per tenant (legacy IPP dataplane)

### 1.1 Two ext_proc stages, not one

The kustomize base `deployment/base/payload-processing` renders **two** Deployments running the same IPP binary with different configs:

- **`payload-pre-processing`** — gRPC :9004, runs config `custom-pre-processing-ipp-config.yaml` (`models-as-a-service/deployment/base/payload-processing/pre-processing/deployment-patch.yaml:1-33`).
- **`payload-processing`** — gRPC :9004, runs config `custom-ipp-config.yaml` (`models-as-a-service/deployment/base/payload-processing/instance/deployment.yaml:1-90`).

Per tenant these are renamed/suffixed `-{tenantID}` (empty tenantID = default tenant keeps base names) by `PayloadProcessingDeploymentName`/`PayloadPreProcessingDeploymentName` (`models-as-a-service/maas-controller/pkg/platform/tenantreconcile/constants.go:351-368`), placed in the **gateway namespace** (`models-as-a-service/maas-controller/pkg/platform/tenantreconcile/params.go:1126-1127`), scoped with `GATEWAY_NAMESPACE`, `GATEWAY_NAME`, `TENANT_NAMESPACE`, and (non-default tenants) `DISABLE_EXTERNAL_MODEL_CONTROLLER=true` (`models-as-a-service/maas-controller/pkg/platform/tenantreconcile/params.go:1237-1252`), and each mounts the per-tenant plugins ConfigMap `payload-processing-plugins[-{tenantID}]` at `/config` (`models-as-a-service/maas-controller/pkg/platform/tenantreconcile/params.go:1257-1260`, `apply.go` volume patch).

### 1.2 Envoy filter-chain order

The per-tenant EnvoyFilter `payload-processing[-{tenantID}]` (priority 10, workloadSelector `gateway.networking.k8s.io/gateway-name: <gateway>`) inserts the two ext_proc filters around the auth wasm filter (`models-as-a-service/deployment/base/payload-processing/manager/envoy-filter.yaml:14-198`, patched per tenant at `models-as-a-service/maas-controller/pkg/platform/tenantreconcile/params.go:1589-1720`):

- `envoy.filters.http.ext_proc.ipp-pre` — INSERT_BEFORE the auth anchor; `failure_mode_allow: true`, request headers/body/trailers streamed, response headers/body **SKIP/NONE** (`envoy-filter.yaml:33-56, 94-113, 154-173`).
- `envoy.filters.http.ext_proc.ipp` — INSERT_AFTER the auth anchor; `failure_mode_allow: false`, request **and** response headers/bodies/trailers FULL_DUPLEX_STREAMED (`envoy-filter.yaml:62-90, 122-146, 182-205`).
- Auth anchors come in pairs because only one matches per cluster: ODH/community Kuadrant `WasmPlugin` (`extensions.istio.io/wasmplugin/<ns>.kuadrant-<gw>`) or RHCL 1.4's plain `envoy.filters.http.wasm` (`envoy-filter.yaml:88-146`).
- **Router fallback mode:** when no Kuadrant wasm auth exists on the gateway (`gatewayHasKuadrantWasmAuth` returns false — checked via EnvoyFilter/WasmPlugin `kuadrant-{gateway}` CRs, `models-as-a-service/maas-controller/pkg/platform/tenantreconcile/gateway_auth.go:28-68`, invoked at `pipeline.go:130-141`), the reconciler keeps only the two router-anchored patches so the order becomes `ipp-pre → ipp → router` (`params.go:1636-1640`, `envoy-filter.yaml:149-205`).
- Resulting chain with Kuadrant (per the usage-logs manifest's own ordering comment): `ext_proc.ipp-pre → wasm-auth → header_to_metadata(identity) → ext_proc.ipp → EPP ext_proc → router` (`models-as-a-service/deployment/components/observability/usage-logs/dsci-managed/envoy-otel-access-log.yaml:118-135`).
- ext_proc is **disabled per-route** on the six non-inference maas-api routes (`/v1/models`, `/v1/subscriptions`, `/v1/api-keys`, `/maas-api/v1/*`, `/maas-api/health`, `/v1/me`) via `ExtProcPerRoute disabled: true` MERGE patches (`envoy-filter.yaml:207-311`; route names rewritten per tenant at `params.go:1706-1721`).
- The final two patches REMOVE Istio's own `envoy.filters.http.ext_proc` and re-INSERT a copy before the router — see §4 (`envoy-filter.yaml:313-411`).

### 1.3 Plugin list, names, and order (from the deployed ConfigMap)

**Pre-processing service** (`custom-pre-processing-ipp-config.yaml`), request phase only, in order (`models-as-a-service/deployment/base/payload-processing/manager/plugins-configmap.yaml:12-27`):

1. `body-field-to-header` (named `model-extractor`) — parameters `fieldName: model`, `headerName: X-Gateway-Model-Name`. *(What it does to the body/headers beyond these parameters is implemented in the ai-gateway-payload-processing image, not in this repo — NOT IMPLEMENTED IN CODE in models-as-a-service.)*
2. `model-provider-resolver` (no parameters). *(Same caveat: resolves model→provider; behavior NOT IMPLEMENTED IN CODE in this repo.)*

**Processing service** (`custom-ipp-config.yaml`), request phase, in order (`plugins-configmap.yaml:28-46`):

1. `maas-headers-guard`
2. `stream-usage-enforcer`
3. `model-provider-resolver`
4. `api-translation`
5. `apikey-injection`

**Response phase: `response: []` — empty by default** (`plugins-configmap.yaml:47-53`). The comment states response api-translation is off so SSE streaming for internal/OpenAI-compatible models is not held by a response processor, and that operators may re-enable it (e.g. for Anthropic) by editing the ConfigMap — which is safe because the reconciler stamps `opendatahub.io/managed=false` on the live ConfigMap after first apply and then skips it (`models-as-a-service/maas-controller/pkg/platform/tenantreconcile/apply.go:104-146`, PostRender skip at `postrender.go:45-50`).

The ConfigMap is deliberately not annotated in source; the reconciler stamps `managed=false` at apply time (`apply.go:120-146`; source comment `plugins-configmap.yaml:6-10`).

Per-plugin request/response mutation details (path rewrites, header adds/removes, body transforms) are implemented in the **ai-gateway-payload-processing** image (`quay.io/opendatahub/odh-ai-gateway-payload-processing:odh-stable`, `models-as-a-service/maas-controller/pkg/platform/tenantreconcile/constants.go:139`) — NOT IMPLEMENTED IN CODE in this repo; only names, order, and the `body-field-to-header` parameters above are defined here.

**3.5-GA note:** the migration doc records that RHOAI 3.5.0's default ConfigMap had *no* `model-provider-resolver` in pre-processing, *no* `maas-headers-guard` in processing, and *response api-translation enabled* (`models-as-a-service/docs/content/migration/upgrade-to-3.6.md:59`) — i.e. the visualizer's "response api-translation" step matches 3.5 GA but **not** the checked-in HEAD default.

**Praxis dataplane (3.6 direction):** when `maas.opendatahub.io/payload-processing-type` is absent or `praxis` (the default at HEAD), `SkipIPP=true` and maas-controller renders/applies **no** IPP resources; ai-gateway-controller owns payload processing (`models-as-a-service/maas-controller/pkg/platform/tenantreconcile/platform_context.go:22-32, 103-110`; filter at `postrender.go:40-45`; IPP resource set listed at `pipeline.go:704-725`). The Praxis pipeline itself is NOT IMPLEMENTED IN CODE in this repo (lives in ai-gateway-controller).

---

## 2. Auth flow: Authorino ↔ MaaS API and the CRDs involved

### 2.1 The policy object

maas-controller builds a **single Gateway-level AuthPolicy** named `maas-gateway-auth` (per gateway/tenant) via `MaaSAuthPolicyReconciler.buildGatewayAuthPolicySpec` (`models-as-a-service/maas-controller/pkg/controller/maas/maasauthpolicy_controller.go:501, 819-830, 1750`). The old per-route `maas-api-auth-policy` was removed (comment at `models-as-a-service/maas-controller/pkg/platform/tenantreconcile/postrender.go:184-190`). All MaaSAuthPolicy CRs share this one policy; model identity is resolved dynamically per request via CEL from the path (`/<model-namespace>/<model-name>/...`) or the `X-Gateway-Model-Name` header (`maasauthpolicy_controller.go:474-498, 831`).

### 2.2 Authentication methods (OR semantics, by priority)

Built at `maasauthpolicy_controller.go:842-913`:

| Method | Mechanism | When | Priority |
|---|---|---|---|
| `api-keys` | plain credentials from `Authorization` header | `Bearer sk-oai-*` | 0 |
| `api-keys-x-api-key` | plain from `x-api-key` header (CEL expression, structured `when`) | `sk-oai-*` in x-api-key; only when x-api-key mode enabled | 1 |
| `oidc-identities` | JWT (issuerUrl+ttl from tenant ExternalOIDC) | non-API-key Bearer JWT-shaped tokens; tenant OIDC configured | 1 |
| `openshift-identities` | Kubernetes TokenReview against cluster audience | always available fallback | 2 |

### 2.3 HTTP callbacks into maas-api (the "callback endpoint")

Authorino **metadata** rules call maas-api over HTTPS (port 8443, in the infra namespace) (`maasauthpolicy_controller.go:830-831, 1190-1247`):

- `POST https://maas-api[-{tenant}].{infra-ns}.svc.cluster.local:8443/internal/v1/api-keys/validate` — body `{"key": <stripped sk-oai- key>}`; cached by key (`maasauthpolicy_controller.go:1190-1218`). maas-api handler: returns **200 with `valid:false`** for invalid keys (never an HTTP error), and the full identity (username, groups, subscription, keyName, keyId, userId) for valid keys (`models-as-a-service/maas-api/internal/api_keys/handler.go:777-825`).
- `POST .../internal/v1/subscriptions/select` — body `{groups, username, requestedSubscription, requestedModel}` (CEL-composed at `maasauthpolicy_controller.go:833-837`); returns subscription info incl. `name`, `phase`, `resolvedModel`, `rateLimitId`, `objective`, `fairnessId`, `organizationId`, `costCenter`, `accessAllowed` (`maasauthpolicy_controller.go:1220-1247`; response fields at `models-as-a-service/maas-api/internal/subscription/types.go:51-81`). Selection logic (requested subscription → single subscription → require explicit header) documented at `models-as-a-service/maas-api/internal/subscription/handler.go:58-73`.

Both are cached in Authorino (`cache.key`/`ttl`, `maasauthpolicy_controller.go:1209-1218, 1237-1246`).

### 2.4 Authorization rules

`maasauthpolicy_controller.go:920-1185`: `deny-api-key-management` (API keys cannot manage API keys, :923-938), `deny-client-identity-headers` (rejects any client-supplied `x-maas-*` / `x-aigateway-guardrail-*` headers, :940-979), `auth-valid` (OPA on apiKeyValidation, :980-998), `subscription-valid` (OPA on subscription-info phase/name/error/deletionTimestamp, :999-1022), `require-group-membership` (OPA on `accessAllowed == true`, :1023-1045), `guardrail-checks-known` (tenant catalog checks, :1046-1056), and for OIDC tenants `oidc-groups-safe` + `oidc-client-bound` (:1058-1185).

### 2.5 Response headers Authorino injects

On auth success (`maasauthpolicy_controller.go:1249-1355`): `X-MaaS-Username` (from apiKeyValidation for keys / identity claims for tokens), `X-MaaS-Group` (JSON array), `X-MaaS-Subscription`, `X-MaaS-Subscription-Rate-Limit-Id`, `X-MaaS-KeyName`, llm-d flow-control headers `x-llm-d-inference-objective`/`x-gateway-inference-objective` and `x-llm-d-inference-fairness-id`/`x-gateway-inference-fairness-id` (always set, possibly empty, from subscription-info, :1344-1347), `x-maas-organization-id`, `X-MaaS-Cost-Center`, `X-MaaS-Identity`. A JSON `identity` response filter also emits `auth.identity` (groups, groups_str, userid, keyId, keyName, selected_subscription, selected_subscription_key, selected_subscription_id) used by TokenRateLimitPolicy and telemetry (:1357-1410).

### 2.6 CRDs and what each contributes

Present in code (`models-as-a-service/deployment/base/maas-controller/crd/bases/`):

- **MaaSModelRef** (`maas.opendatahub.io_maasmodelrefs.yaml`; types at `models-as-a-service/maas-controller/api/maas/v1alpha1/maasmodelref_types.go:31-92`) — user-facing model name → underlying endpoint: `spec.modelRef.{kind,name}` referencing either an `ExternalModel` (external provider) or `LLMInferenceService` (internal, KServe-scheduled) in the same namespace. Drives per-model HTTPRoutes and the CEL model identity.
- **MaaSSubscription** (`maas.opendatahub.io_maassubscriptions.yaml`) — associates users/groups with allowed models, rate limits (`spec.inferencePriority`, token limits), and is the row maas-api's `/subscriptions/select` matches against.
- **AITenant** (`maas.opendatahub.io_aitenants.yaml`) — multi-tenant root; owns tenant namespace (`ai-tenant-<name>`), gateway ref (via `status.gatewayRef`), and external OIDC config (`models-as-a-service/maas-controller/pkg/platform/tenantreconcile/platform_context.go:66-87`).
- **MaasTenantConfig** (`maas.opendatahub.io_maastenantconfigs.yaml`) — namespace-local tenant runtime config driving the whole platform reconcile pipeline (constants.go:1-5 comment); carries telemetry/capture flags, payload-processing replicas/autoscaling, and the payload-processing handshake annotations (`constants.go:51-110`).
- **MaaSAuthPolicy** (`maas.opendatahub.io_maasauthpolicies.yaml`) — per-model subjects (groups) that feed `require-group-membership` in the gateway policy (`maasauthpolicy_controller.go:1861` comment).
- **ExternalModel / ExternalProvider** (`inference.opendatahub.io_external{models,providers}.yaml`) — the IPP-side CRDs for external provider endpoints/credentials (labelled/owned by the IPP ExternalModel/ExternalProvider reconcilers, `pipeline.go:664-680`).
- **Config** (`maas.opendatahub.io_configs.yaml`) — cluster singleton with `usageLogging`, `usageMetricsDashboard`, egress NetworkPolicy rules (`models-as-a-service/maas-controller/pkg/platform/tenantreconcile/pipeline.go:446-455, 1190-1196`).

**"MaaSAuth" — NOT IMPLEMENTED IN CODE.** No such CRD exists in this repo (the CRD set above is exhaustive; see `deployment/base/maas-controller/crd/bases/`). The closest real CRD is `MaaSAuthPolicy`.

---

## 3. Usage-logs / metering: what `usage_logs_envoyfilter.go` + the manifest actually emit

### 3.1 Deployment and gating

The per-tenant EnvoyFilter `maas-model-access-logs[-{tenantID}]` (`constants.go:180, 374-376`) is applied by the TenantReconciler from the manifest `deployment/components/observability/usage-logs/dsci-managed/envoy-otel-access-log.yaml` **only when `MaasTenantConfig.spec.telemetry` is enabled** (default true — `IsTelemetryEnabled`, `models-as-a-service/maas-controller/pkg/platform/tenantreconcile/postrender.go:191-193`; gating at `models-as-a-service/maas-controller/pkg/controller/maas/tenant_usage_logs_envoyfilter.go:89-116, 160-162`). It is deleted when telemetry is disabled (`tenant_usage_logs_envoyfilter.go:63-77`).

### 3.2 Envoy hooks (configPatches in the manifest)

From `models-as-a-service/deployment/components/observability/usage-logs/dsci-managed/envoy-otel-access-log.yaml`:

1. **CLUSTER / ADD** `otel_als_cluster` (:69-102) — STRICT_DNS OTLP/gRPC endpoint, TLS via OpenShift service CA, port 4317. The address is patched at apply time to `<collector>.<monitoring-ns>.svc.cluster.local` (`tenant_usage_logs_envoyfilter.go:180-186`, `usage_logs_envoyfilter.go:268-334`). Collector choice: `usage-logs-collector` (plaintext, TLS transport socket removed) when `Config.spec.usageLogging=true`; otherwise `data-science-usage-logs-collector-headless` with the manifest TLS (`tenant_usage_logs_envoyfilter.go:41-56, 186-193`).
2. **HTTP_FILTER / INSERT_AFTER wasm** (two anchor variants: `envoy.filters.http.wasm` :137-170 and WasmPlugin :171-204) — `envoy.filters.http.header_to_metadata.identity`: captures `X-MaaS-Subscription`, `X-MaaS-Group`, `X-MaaS-KeyName`, `X-MaaS-Cost-Center` into dynamic metadata *before* IPP strips the headers (:104-204). `user_id` (from `X-MaaS-Username`) and `organization_id` (from `X-MaaS-Organization-Id`) rules are injected at apply time by `PatchUsageLogsUserID`/`PatchUsageLogsOrganizationID` when `logs.captureUser`/`logs.captureOrganization` are set (`usage_logs_envoyfilter.go:163-266`; injection at `tenant_usage_logs_envoyfilter.go:152-178`).
3. **HTTP_FILTER / INSERT_FIRST** — a `composite` filter wrapping `json_to_metadata`, executed only on inference paths (suffix match `/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`, :205-351). Request rules extract `model` from the request body; response rules extract `usage.{total,prompt,completion}_tokens` and the authoritative `model` from JSON responses, with `"0"` + `preserve_existing_metadata_value` fallbacks for SSE/429 (:296-350).
4. **HTTP_FILTER / INSERT_BEFORE router** — `envoy.filters.http.lua.sse_tokens` Lua filter (:352-460): for `text/event-stream` responses, iterates `bodyChunks()` without buffering, regex-extracts `"total_tokens"/"prompt_tokens"/"completion_tokens"/"model"` from SSE chunks, writes them to the same metadata namespace (:389-460).
5. **NETWORK_FILTER / MERGE** on the http_connection_manager — the OTel access logger `envoy.access_loggers.open_telemetry` with a CEL filter restricting logging to `POST` on the three inference paths (:462-533).

### 3.3 Payload and destination

- `log_name: maas-usage-log`; body `"%RESPONSE_CODE% %REQ(:PATH)%"` (:481-490).
- Attributes: `response_code`, `response_type` (CEL hit/rate_limit/error), `subscription`, `groups`, `key_name`, `cost_center` (CEL preferring header_to_metadata, falling back to request headers), `tokens_total/prompt/completion`, `model`, `upstream_host` (:491-530).
- Resource attributes: `service.name: models-as-a-service` (:534-538), plus `service.namespace` = the tenant workload namespace and `tenant_name` = authoritative tenant name, both appended by the reconciler — never from request headers (`usage_logs_envoyfilter.go:17-18, 32-161`; applied at `tenant_usage_logs_envoyfilter.go:196-210`).
- Destination: OTLP/gRPC (port 4317) to the collector Service above; async — if the collector is unreachable Envoy silently drops the entry (manifest header comment, :44-47).

Downstream of the collector (Loki, Perses dashboards, tenancy proxy) exists under `deployment/components/observability/usage-logs/` (e.g. `dsci-managed/tenancy-proxy.yaml`, `usage-logs-dashboard.yaml`) but its internals are config/scripts, not Go code, and are out of scope of `usage_logs_envoyfilter.go`. maas-api additionally gets a read-only Loki proxy (`LOKI_READ_ENDPOINT`/`LOKI_READ_TOKEN` from the `usage-logs-loki` Secret, `pipeline.go:240-295`, `params.go:1076-1093`) serving `GET /v1/logs*` (comment at `pipeline.go:213-239`).

---

## 4. EPP / llm-d integration for internal (on-cluster) models

### 4.1 The EnvoyFilter EPP reorder (the gateway wiring)

The last two configPatches of the payload-processing EnvoyFilter REMOVE Istio's InferencePool ext_proc filter (`envoy.filters.http.ext_proc`) and INSERT_BEFORE the router a byte-copy of the static filter Istio renders, giving the chain `ipp-pre → auth → ipp → EPP → router` (`models-as-a-service/deployment/base/payload-processing/manager/envoy-filter.yaml:313-411`). Key facts from the code/manifest comments:

- The filter "binds the EPP once, from the route matched in its own decodeHeaders, and **KServe pool routes match on X-Gateway-Model-Name**" (`envoy-filter.yaml:307-310`).
- "Istio's ExtProcPerRoute override on every InferencePool route sends headers and bodies (FULL_DUPLEX_STREAMED) to that pool's EPP" and "**envoy.lb metadata carries the endpoint the EPP picked**" (`envoy-filter.yaml:324-330`).
- On a gateway without an InferencePool the inserted copy is inert (`envoy-filter.yaml:320-323`).
- The reason for the reorder: Istio places the InferencePool filter after the WasmPlugin phases; with RHCL's router-anchored wasm or the router fallback, "the EPP never runs and pool traffic silently falls back to round-robin" (`envoy-filter.yaml:299-306`).

So **pod selection** (P/D disaggregation, prefix caching, KV-cache-aware scheduling) is performed by the per-pool EPP deployed with llm-d/KServe — NOT IMPLEMENTED IN CODE in this repo. What MaaS contributes in code:

### 4.2 MaaS-side components for internal models

- **InferenceObjective CRs** (`inferenceobjectives.llm-d.ai`, llm-d-router apix v1alpha2): the MaaSSubscription controller creates one per (tenant, subscription, InferencePool), named `maas-<tenant>-<subscription>-<pool>-<hash>`, carrying request priority from `MaaSSubscription.spec.inferencePriority` (`models-as-a-service/maas-controller/pkg/controller/maas/maassubscription_inferenceobjective.go:46-107, 126-145`). Pool resolution: `MaaSModelRef.spec.modelRef.kind == LLMInferenceService` → KServe `LLMInferenceService.status.router.scheduler.inferencePool` (`maassubscription_inferenceobjective.go:172-246`); services without a scheduler or with multi-member routing groups are NotApplicable/Unsupported (`:187-213`). The controller watches LLMInferenceServices so pool changes refresh objectives (`maassubscription_controller.go:1552`).
- **Flow-control headers**: Authorino injects `x-llm-d-inference-objective` and `x-llm-d-inference-fairness-id` (plus `x-gateway-*` legacy aliases), "always set, empty when unknown, so client-supplied values never reach the scheduler" (`maasauthpolicy_controller.go:1339-1347`). Values come from maas-api's `/subscriptions/select` response fields `objective`/`fairnessId` (`maas-api/internal/subscription/types.go:68-74`).
- **Model name for routing**: the pre-processing IPP plugin sets `X-Gateway-Model-Name` from the request body (`plugins-configmap.yaml:16-20`), which both KServe pool routes (above) and the Authorino CEL model identity (`maasauthpolicy_controller.go:485-494`) consume.

The EPP/scheduler/vLLM/NIXL/P-D-sidecar components themselves are **NOT IMPLEMENTED IN CODE** in this repo (they belong to llm-d / gateway-api-inference-extension / KServe; this repo only wires the gateway filter and objectives). No `base-model-to-header` plugin exists in the deployed ConfigMap (`plugins-configmap.yaml` — absent) — NOT IMPLEMENTED IN CODE.

---

## 5. Feature flags / versions / MaasTenantConfig settings distinguishing current GA behavior

| Gate | Effect | Citation |
|---|---|---|
| `maas.opendatahub.io/payload-processing-type` = `ipp`/`praxis` (absent = **praxis**) | Selects legacy IPP vs ai-gateway-controller dataplane; `SkipIPP` filters IPP resources from render | `platform_context.go:22-32, 103-110`; `postrender.go:40-45` |
| Kuadrant wasm presence on gateway | Router-anchored ext_proc fallback vs wasm-anchored patches (avoids duplicate ext_proc) | `pipeline.go:129-141`; `gateway_auth.go:28-68`; `params.go:1636-1660` |
| IPP→Praxis migration gates | plugins-ConfigMap baseline fingerprint check; blocks on non-standard ConfigMap; `maas.opendatahub.io/force-payload-processing-migration=true` override; API-translation compatibility check blocks on non-OpenAI/Anthropic ExternalModel bindings; `spec.apiTranslation.enabled` intent persisted | `pipeline.go:297-420`; `plugins_migration.go:97-175, 269-285`; `upgrade-to-3.6.md:52-110` |
| `Config.spec.usageLogging` | Chooses `usage-logs-collector` (plaintext) vs `data-science-usage-logs-collector-headless` (TLS) for the usage-logs EnvoyFilter; changes DSCI prerequisite warnings | `tenant_usage_logs_envoyfilter.go:41-56, 180-193`; `prerequisites.go:56-61, 300-360` |
| `Config.spec.usageMetricsDashboard` | Gates the DSCI monitoring-stack prerequisite warning | `prerequisites.go:56-68` |
| `MaasTenantConfig.spec.telemetry.enabled` (default **true**) | Deploys/deletes usage-logs EnvoyFilter and TelemetryPolicy/Istio Telemetry | `postrender.go:191-193`; `tenant_usage_logs_envoyfilter.go:111-116` |
| `telemetry.logs.captureUser` (default **false**) / `logs.captureOrganization` (default **true**) | Injects user_id / organization_id capture into usage logs | `tenant_usage_logs_envoyfilter.go:152-178` |
| `telemetry.metrics.capture{Organization,User,Group,ModelUsage}` | TelemetryPolicy metric labels (model label via `responseBodyJSON("/model")`) | `postrender.go:498-560` |
| Tenant ExternalOIDC (`aitenant.spec.oidc`) | Adds `oidc-identities` auth method and `oidc-groups-safe`/`oidc-client-bound` authorization | `maasauthpolicy_controller.go:899-913, 1058-1185`; `platform_context.go:66-87` |
| x-api-key mode (`xAPIKeyEnabled`) | Adds `api-keys-x-api-key` auth method | `maasauthpolicy_controller.go:874-898` |
| `usage-logs-loki` Secret in app namespace | Enables maas-api read-only Loki proxy (`LOKI_READ_ENDPOINT`/`LOKI_READ_TOKEN`); absent = disabled | `pipeline.go:213-295`; `params.go:1076-1093` |
| `maas.opendatahub.io/experimental-body-buffer-limit-mb` on Gateway (default/max 64 MB) | Envoy per-connection buffer limit EnvoyFilter | `constants.go:24-28`; `params.go:620-641` |
| `spec.{maasApi,payloadProcessing,payloadPreProcessing}.replicas/autoscaling/resources` (+ deprecated `maas.opendatahub.io/*-replicas` annotations) | Replica/HPA/resource overrides; HPA generated in PostRender when autoscaling on | `params.go:186-300, 1048-1120, 1463+`; `postrender.go:366-470` |
| `Config.spec.maasApiEgressNetworkPolicy=Disabled`, `networkPolicyEgressRules`, `networkPolicyAdditionalEgressRules` | maas-api egress NetworkPolicy replace/disable/preserve-on-upgrade | `pipeline.go:1190-1218` |
| `maas-gateway-auth` AuthPolicy + `gateway-default-deny` TRLP | Primary 401/403 default-deny is the AuthPolicy; the gateway TRLP is defense-in-depth 0-token 429 on non-management paths | `deployment/base/maas-controller/policies/gateway-default-deny.yaml:1-43` |

**Rate limiting (Limitador)** is Kuadrant's `TokenRateLimitPolicy`: one aggregated per-model TRLP per HTTPRoute built by the MaaSSubscription controller (`maassubscription_controller.go:570-658`), plus the gateway default-deny (`gateway-default-deny.yaml`). Legacy vs short rate-limit identity (`selected_subscription_key` vs `selected_subscription_id`) is the 3.5→3.6 change documented at `upgrade-to-3.6.md:5-50` and implemented in the AuthPolicy response filter (`maasauthpolicy_controller.go:1387-1410`).

---

## 6. Differences vs the visualizer (`ai-gateway-docs/ai-gateway-flow.html`)

Every correction below is grounded in MaaS code; the visualizer claim is cited as `ai-gateway-flow.html:<approx line>` (single-file HTML).

1. **Version badge**: visualizer says "RHOAI 3.4 GA" (`ai-gateway-flow.html:154`); this analysis targets 3.5 GA per the repo's own migration doc (`upgrade-to-3.6.md:1-5`).
2. **Single IPP container vs two-stage ext_proc**: the visualizer shows one "Payload Processor / IPP (ext_proc)" with all plugins after auth (`ai-gateway-flow.html:246-257`). Code deploys **two** ext_proc services: `payload-pre-processing` (before auth wasm — it must run before auth so auth sees `X-Gateway-Model-Name`, `envoy-filter.yaml:23-25`) and `payload-processing` (after auth) (`envoy-filter.yaml:33-90`; `params.go:1589-1720`). `body-field-to-header` runs in the **pre-auth** stage (`plugins-configmap.yaml:12-27`), not in the post-auth plugin list the visualizer implies.
3. **Plugin list mismatch (request)**: visualizer shows request-guard (nemo), intelligent-model-selection, model-provider-resolver, body-field-to-header, base-model-to-header, api-translation, apikey-injection (`ai-gateway-flow.html:249-256`). Code's GA ConfigMap request chain is: `maas-headers-guard → stream-usage-enforcer → model-provider-resolver → api-translation → apikey-injection` (post-auth) plus `body-field-to-header → model-provider-resolver` (pre-auth) (`plugins-configmap.yaml:12-46`). `request-guard`, `intelligent-model-selection`, `base-model-to-header` are **NOT IMPLEMENTED IN CODE** (absent from the ConfigMap; visualizer marks them "coming soon" which is consistent). `maas-headers-guard` and `stream-usage-enforcer` exist in GA but are missing from the visualizer.
4. **Response api-translation**: visualizer's external flow shows an active "api-translation: Anthropic → OpenAI response" step (`ai-gateway-flow.html:1437-1443`, step 19). Code default is `response: []` — response translation **off** (`plugins-configmap.yaml:47-53`). (It *was* on in RHOAI 3.5.0 per `upgrade-to-3.6.md:59` — the visualizer matches 3.5 GA here, but not HEAD.)
5. **Auth callback topology**: visualizer shows "Kuadrant → MaaS API (key validation)" as a single hop (`ai-gateway-flow.html:1421-1426`). Code: **Authorino** makes two distinct cached HTTP metadata callbacks — `/internal/v1/api-keys/validate` **and** `/internal/v1/subscriptions/select` (`maasauthpolicy_controller.go:830-831, 1190-1247`; `maas-api/internal/api_keys/handler.go:781-825`; `maas-api/internal/subscription/handler.go:58-73`). The subscription-select hop (which resolves the subscription, rate-limit ID, objective/fairness, org/cost-center) is absent from the visualizer.
6. **"MaaSAuth" CRD**: the visualizer claims MaaS API "Requires 3 CRDs … MaaSModelRef, MaaSAuth, MaaSSubscription" (`ai-gateway-flow.html:333`). **MaaSAuth is NOT IMPLEMENTED IN CODE** — no such CRD exists (`deployment/base/maas-controller/crd/bases/`); the real set includes MaaSAuthPolicy, AITenant, MaasTenantConfig, Config, ExternalModel/ExternalProvider (§2.6).
7. **EPP wiring**: visualizer shows "Gateway → EPP (ext_proc)" as an independent hop after IPP (`ai-gateway-flow.html:1460-1466`). Code: the EPP is Istio's InferencePool `envoy.filters.http.ext_proc`, which MaaS *removes and re-inserts before the router*, with per-route ExtProcPerRoute overrides sending traffic to each pool's EPP; the EPP therefore runs after `ipp` in the same chain (`envoy-filter.yaml:313-411`). EPP/scheduler internals (P/D workers, sidecar, NIXL) are NOT IMPLEMENTED IN CODE in this repo.
8. **Usage logs / metering missing**: the visualizer has no usage-log emission path at all. Code emits OTel access logs (`maas-usage-log`) with tokens/model/identity attributes for every POST to inference paths, plus Kuadrant TelemetryPolicy and Istio Telemetry metrics with tenant labels (`envoy-otel-access-log.yaml:462-538`; `postrender.go:194-290`).
9. **Token accounting**: visualizer claims "Wasm reads usage.total_tokens … reports token count to Limitador" (`ai-gateway-flow.html:1452-1456`). MaaS code only *configures* TRLPs (per-model aggregated + gateway default-deny, `maassubscription_controller.go:570-658`, `gateway-default-deny.yaml`); the wasm/Limitador response-phase reporting mechanics are Kuadrant behavior — NOT IMPLEMENTED IN CODE in this repo (unverifiable here).
10. **Praxis**: the visualizer's flows are IPP-only. At HEAD, the product default for new tenants is the **Praxis** dataplane (`platform_context.go:22-32, 103-110`) — a 3.6 development state, not 3.5 GA.
