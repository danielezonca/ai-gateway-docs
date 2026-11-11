# Praxis integration state in MaaS — fact sheet

**Repos analyzed:**
- `models-as-a-service` @ `8d30ae9a` (primary; all paths below workspace-relative to `models-as-a-service/` unless prefixed with the other repo)
- `ai-gateway-controller` @ `5502164` (cross-checked for praxis-side ownership, pipeline shape, and Responses/failover questions; cited with `ai-gateway-controller/` prefix)

"Praxis" in MaaS today concretely means: **the ai-gateway-controller (AGC) replaces maas-controller's legacy "IPP" (payload-processing / payload-pre-processing) Envoy ext_proc dataplane for a tenant.** Selection is per-tenant via a MaasTenantConfig annotation; MaaS's job for praxis tenants is to *not deploy* IPP, to *clean up* legacy IPP once, and to *hand off* to AGC — it does not itself render any praxis payload-processing resources.

---

## 1. What is actually deployed when praxis is selected, and who owns it

**Selection.** AITenant-managed MaasTenantConfigs carry annotation `maas.opendatahub.io/payload-processing-type`; absent or `"praxis"` → praxis (SkipIPP=true), `"ipp"` → legacy (`maas-controller/pkg/platform/tenantreconcile/platform_context.go:20-31`, `:119-127`). SkipIPP is resolved only for AITenant-managed configs (`platform_context.go:85-116`); legacy `Tenant` objects get no SkipIPP and therefore always deploy IPP (`platform_context.go:67-81`). Test asserting the default: `platform_context.go` semantics exercised in `maas-controller/pkg/platform/tenantreconcile/platform_context_test.go` and `pipeline_praxis_test.go:148-203` (`TestRunPlatform_PraxisSkipsIPPApply`).

**maas-controller still deploys for praxis tenants** (everything in the platform kustomize overlay except the IPP set): maas-api Deployment/Service/HTTPRoute (per-tenant suffixed), TLS serving cert, key-cleanup CronJob, NetworkPolicies, gateway AuthPolicy pieces, TokenRateLimitPolicy default-deny, telemetry (TelemetryPolicy + Istio Telemetry), gateway body-buffer-limit EnvoyFilter, usage-logs EnvoyFilter. The render path is `maas-api/deploy/overlays/odh/kustomization.yaml:10-13` (maas-api + policies + `deployment/base/payload-processing/default`); in post-render, praxis tenants drop every resource matched by `isIPPResource` (`maas-controller/pkg/platform/tenantreconcile/postrender.go:28-34`; IPP name set defined at `constants.go` `isIPPResource` ~line 379-404: payload-processing / payload-pre-processing Deployments, Services, DestinationRules, EnvoyFilter, ServiceAccount, plugins ConfigMap, NetworkPolicy, payload-processing-reader ClusterRoleBinding). HPA generation for IPP pods is also skipped (`postrender.go:86-92`). Tests: `pipeline_praxis_test.go:148-203` (asserts maas-api applied, zero IPP resources applied).

**ai-gateway-controller owns the praxis dataplane.** Its tenant package "watches MaasTenantConfig CRs … and, for every tenant whose payload-processing annotation selects Praxis, renders and SSA-applies a dedicated per-tenant copy of the vendored praxis-extproc manifests into that tenant's Gateway namespace" (`ai-gateway-controller/pkg/tenant/constants.go:17-20`, `pkg/tenant/reconciler.go:55`). It applies with SSA field manager `ai-gateway-controller` (`ai-gateway-controller/pkg/render/apply.go:27-44`). Its per-tenant ownership target set (Deployments/Services/ConfigMaps/EnvoyFilters/DestinationRules incl. `payload-processing-external-model-*`) is at `ai-gateway-controller/pkg/tenant/reconciler.go:820-845`. Images: `quay.io/opendatahub/odh-ai-gateway-controller:odh-stable` manager and `quay.io/opendatahub/odh-praxis-extproc:odh-stable` ExtProc (defaults in `models-as-a-service/test/e2e/scripts/deploy-aigc-companion.sh:30-32` — MaaS does not deploy AGC itself; e2e clones and runs AGC's own deploy script, `deploy-aigc-companion.sh:50-62`).

**Readiness coupling.** Even with SkipIPP, MaaS waits on the gateway-namespace EnvoyFilter named `payload-processing-{tenantID}` that AGC owns ("Praxis tenants skip applying IPP resources (SkipIPP) but still wait on the same gateway-namespace EnvoyFilter AGC owns", `maas-controller/pkg/platform/tenantreconcile/pipeline.go:205-213`; check at `pipeline.go:813-855` `PayloadProcessingEnvoyFilterReady`). Test: `pipeline_praxis_test.go:205-258` (`TestRunPlatform_PraxisReadyWithEnvoyFilter`, pending detail names the EnvoyFilter).

**Ownership race guard.** `isMaaSOwnedIPPResource` refuses to delete any object whose managedFields contain the `ai-gateway-controller` field manager (`pipeline.go:609`, `:768-789`); MaaS itself SSA-applies as field manager `maas-controller` (`maas-controller/pkg/platform/tenantreconcile/apply.go:19,81`).

## 2. SkipIPP and the ownership-handshake marker: semantics, states, triggers

Annotation `maas.opendatahub.io/payload-processing-status` lives **only on MaasTenantConfig** and coordinates the backend swap between maas-controller (legacy IPP) and AGC (praxis) (`constants.go:51-76`). States from maas-controller's perspective (`constants.go:53-74`):

- `cleanup-complete` — peer cleanup finished; selected party may claim. When **praxis** is selected: cleanup already done, keep accepted-risk warnings visible. When **legacy** is selected: CAS-claim by deleting the annotation (back to absent), then deploy (`pipeline.go:649-666` `ensureLegacyMayDeploy`, `:677-706` `claimLegacySteady` — optimistic-concurrency Update, conflict → not claimed).
- `steady` — praxis owns the pipeline (maas-controller treats any non-cleanup-complete peer value as "not our turn"; it does not interpret peer-specific sentinels).
- **absent** — legacy steady when legacy selected; when praxis selected, absent means "still need to clean up legacy IPP, then write cleanup-complete" (`pipeline.go:306-445`).

**New tenants are seeded** with `cleanup-complete` at MaasTenantConfig creation so a first deploy is never blocked (`maas-controller/pkg/controller/maas/aitenant_controller.go:905-920` `seedPayloadProcessingStatusOnCreate`; must never re-run on update). AGC watches annotation changes on MaasTenantConfig (`maas-controller/pkg/controller/maas/tenant_controller.go:328-332`).

**One-shot IPP cleanup trigger** (`pipeline.go:297-445` `reconcilePayloadProcessingSwitch`): on a reconcile with SkipIPP=true and status absent, MaaS:
1. Evaluates the plugins-ConfigMap migration gate (`plugins_migration.go:101-198` `evaluatePluginsConfigMapMigration`). Block → set `maas.opendatahub.io/payload-processing-migration=blocked` (`constants.go:90-97`), keep IPP resources, continue applying non-IPP resources, report `blockedReason` (`pipeline.go:328-345`).
2. Persists API-translation migration intent (`pipeline.go:347-352`; `plugins_migration.go:288-338`).
3. Assesses legacy IPP translation compatibility per active ExternalModel binding; incompatible bindings block cleanup unless forced / explicitly disabled (`pipeline.go:353-414`; `plugins_migration.go:340-452` `legacyIPPTranslationModels`).
4. Runs `cleanupIPPResources` (`pipeline.go:834-850`): deletes the 14 MaaS-owned IPP operands (`ippResourcesForTenant`, `pipeline.go:811-832` — Deployments with foreground propagation, HPAs, Services, EnvoyFilter, NetworkPolicy, DestinationRules, ServiceAccount, plugins ConfigMap, ClusterRoleBinding), proves IPP writers stopped (`ensureIPPWritersStopped`, `pipeline.go:852-906`), deletes IPP-ExternalModel-owned HTTPRoutes (`pipeline.go:908-1020`) and IPP-ExternalProvider transport Service/ServiceEntry/DestinationRule (`pipeline.go:1022-1090`). Only MaaS-owned objects are deleted; AGC-owned ones at the same names survive (`pipeline.go:768-789`; test `ipp_cleanup_test.go:11-61`).
5. Clears the migration annotation and writes `cleanup-complete` (`pipeline.go:416-424`).

Steady state: with `cleanup-complete` or `steady`, praxis tenants skip re-cleanup and only re-emit accepted-risk warnings (`pipeline.go:307-319`; tests `pipeline_praxis_test.go:566-615` `TestRunPlatform_PraxisSkipsCleanupAfterMigrationComplete`, `:519-565` `TestRunPlatform_PraxisMigrationCleanupSkipsPraxisOwnedResources`). Legacy side: while praxis holds the dataplane (any non-absent, non-cleanup-complete status), legacy deploy returns pending ("waiting for the praxis payload-processing cleanup…", `pipeline.go:438-445`; test `pipeline_praxis_test.go:731-781`).

## 3. Plugins migration: which filters move to praxis, what the deployed praxis pipeline looks like

**Migration does not translate filters.** No IPP plugin config is converted into praxis config. The gate only *fingerprints* the live `payload-processing-plugins` ConfigMap against known-good baselines (`plugins_migration.go:101-198`, `:571-619` `matchKnownGoodIPPPluginsConfigMap`; tests `plugins_migration_test.go:138-486`):
- `"default"`: pre = `model-extractor` (body-field-to-header, model→`X-Gateway-Model-Name`) + `model-provider-resolver`; processing request chain = `maas-headers-guard`, `stream-usage-enforcer`, `model-provider-resolver`, `api-translation`, `apikey-injection`; response chain empty (`plugins_migration.go:622-640`, `:672-694`).
- `"default+response-api-translation"`: same, response chain = `api-translation` only (`plugins_migration.go:689-694`).
- `"odh-3.5.0"`: pre = `model-extractor` only; processing = `stream-usage-enforcer`, `model-provider-resolver`, `api-translation`, `apikey-injection` with response `api-translation`, no `maas-headers-guard` (`plugins_migration.go:642-670`).
- Anything else (custom/unknown keys, reordered plugins — chains are order-sensitive, `plugins_migration.go:700-707`) → **blocked** unless `maas.opendatahub.io/force-payload-processing-migration=true` (`constants.go:85-88`; `plugins_migration.go:152-198`). A ConfigMap already carrying praxis keys (`extproc.yaml`/`pre-extproc.yaml` with no IPP keys) is recognized as already-migrated (`plugins_migration.go:543-560`).

**MaaS stamps `opendatahub.io/managed=false`** on the IPP plugins ConfigMap it applies by default so customer edits survive steady-state SSA (`maas-controller/pkg/platform/tenantreconcile/apply.go:140-180` `preparePayloadProcessingPluginsConfigMapApply`; tests `apply_plugins_configmap_test.go:36-98`) — but that does **not** block one-shot cleanup, which deletes it so AGC can recreate it in its own schema (`pipeline.go:757-766` comment; `pipeline.go:827` includes the ConfigMap in `ippResourcesForTenant`).

**Deployed praxis pipeline (owned by AGC, not MaaS).** Base praxis-extproc ConfigMap (`ai-gateway-controller/config/manifests/praxis-extproc/base/config/configmap.yaml:1-41`):
- `pre-extproc.yaml`, chain `bbr`: `model_to_header` (→ `X-Gateway-Model-Name`), then `llmisvc_model_provider_resolver`.
- `extproc.yaml`, chain `ipp`: `request_id`.

AGC additionally generates a per-tenant `payload-processing-external-model-*-plugins` ConfigMap whose `extproc.yaml` chain `post-auth` runs `intelligent_route` (model header routing, routing overlay, provider hop clusters) followed by `credential_inject` when credentials exist (`ai-gateway-controller/pkg/tenant/extproc.go:176-199` `extprocPostAuthConfig`). Envoy wiring uses HTTP filters `envoy.filters.http.ext_proc.ipp-pre` and `envoy.filters.http.ext_proc.ipp` (`ai-gateway-controller/config/manifests/praxis-extproc/overlays/odh/envoy-filter.yaml:31,59`). So of the IPP filters: routing/credential concerns are re-implemented as `model_to_header`/`llmisvc_model_provider_resolver`/`intelligent_route`/`credential_inject`; `maas-headers-guard`, `stream-usage-enforcer`, and generic `api-translation`/`apikey-injection` have **no praxis equivalent in code** (only `request_id` and the route/credential filters above exist).

## 4. api-translation migration: current state

- **Field:** `MaasTenantConfig.spec.apiTranslation.enabled` (pointer bool; "Omission is equivalent to disabled for new tenants", `maas-controller/api/maas/v1alpha1/maastenantconfig_types.go:50-56`, `:88-95`).
- **Migration behavior:** for a recognized IPP baseline that translated requests (all three baselines, `plugins_migration.go:275-286` `ippBaselineTranslatesRequests`), MaaS durably writes `spec.apiTranslation.enabled: true` before cleanup, unless the operator already set it explicitly (`plugins_migration.go:288-338` `persistAPITranslationMigrationIntent`; tests `api_translation_migration_test.go:24-133`, `api_translation_cleanup_test.go:122-282`). An explicit `false` accepts the compatibility loss; forced migration records risk markers `maas.opendatahub.io/api-translation-migration-risk` = `explicit-false` / `forced` that persist after cleanup and feed Degraded-condition warnings (`constants.go:99-113`; `plugins_migration.go:219-273`).
- **What is actually translated today:** the compatibility check passes only (a) `openai` provider + `apiFormat: openai-chat` (pass-through, no translation), and (b) `anthropic` provider + `apiFormat: messages` **with** translation enabled — "which Praxis translates from OpenAI Chat Completions" (`plugins_migration.go:340-452`, safe combos at `:437-441`). Everything else (Azure OpenAI, Vertex, Bedrock, custom providers, cross-namespace providers, unresolvable refs — fails closed) blocks cleanup (`plugins_migration.go:395-436`). The actual format translation executes in the praxis ExtProc runtime, not in either controller's code; AGC code only qualifies credential strategies for `openai+openai-chat` (bearer_token) and `anthropic+messages` (apikey header) (`ai-gateway-controller/pkg/envelope/envelope.go:258-285` `StrategyFor`). Product doc summarizing the same: `docs/content/migration/upgrade-to-3.6.md:52-130`.
- Legacy IPP's multi-provider translator (OpenAI, Anthropic, Azure, Vertex, Bedrock) has **no praxis parity** — the code explicitly says "the installed Praxis ExtProc cannot preserve OpenAI Chat Completions → provider-format dispatch yet" (`plugins_migration.go:204-208` `apiTranslationCompatibilityRisk`).

## 5. Fallback / retry / model-failover routing

**NOT IMPLEMENTED IN CODE** (in `models-as-a-service`). Repo-wide searches for `failover` in Go code return nothing; all `fallback` hits are unrelated (gateway-ref fallback, TLS migration fallback, ext_proc router fallback when Kuadrant WASM is absent — e.g. `maas-controller/pkg/platform/tenantreconcile/pipeline.go:129-142`, `platform_context.go:51-80`). There is no retry-on-provider-failure routing in maas-controller, maas-api, or AGC.

What does exist and is adjacent:
- `ExternalModel.spec.externalProviderRefs[].weight` — "weighted random selection across multiple provider refs" (CRD `deployment/base/maas-controller/crd/bases/inference.opendatahub.io_externalmodels.yaml:150-157`) — a traffic-splitting knob, not failover.
- AGC resolver produces routes in "the deterministic first-admitted fallback order — IPP's refs[0] semantics" (`ai-gateway-controller/pkg/resolver/resolver.go:92-95`) — i.e. first-admitted provider selection, and AGC's `checkUniformWeights` **rejects** non-uniform weights across providers of one model (`ai-gateway-controller/pkg/envelope/envelope.go:297-306`), so even weighted split is unsupported in praxis today.

Any runtime retry/failover would live in the praxis ExtProc image (`odh-praxis-extproc`), not in either checked-out controller repo.

## 6. Responses API

**NOT IMPLEMENTED IN CODE.**
- No `/v1/responses` endpoint, route, or handler in maas-api or maas-controller (repo-wide search for `v1/responses` / Responses API in `maas-api/`, `maas-controller/`, `deployment/` returns nothing). The maas-api HTTPRoute only exposes `/v1/models`, `/v1/subscriptions`, `/v1/api-keys`, `/maas-api/v1`, `/maas-portal`, `/oauth2` (`deployment/base/maas-api/networking/httproute.yaml:17-80`); the gateway default-deny predicate enumerates the same management paths (`deployment/base/maas-controller/policies/gateway-default-deny.yaml:40`).
- AGC likewise has no Responses implementation; its test README explicitly states a contract check "does not add or imply support" for a Responses-capable implementation (`ai-gateway-controller/test/openshift-env/README.md:311`, and `test/openshift-env/test-render-manifests.sh:63` asserts no `apiFormat: responses` leaks into rendered manifests).
- References that exist are **docs/comments only**: proposals with Status "Proposed" at `docs/content/architecture-internals/proposals/guardrails-responses/01-guardrails-responses-high-level-design.md:3-29` ("Enable the Responses API at the AI tenant level … Praxis executes the resulting plan and owns the public Responses lifecycle" — planned, not built), and a rate-limiting caveat note that `/v1/responses` would not be token-rate-limited (`docs/content/configuration-and-management/quota-and-access-configuration.md:188-190`).

## 7. Feature flags / MaasTenantConfig fields and defaults

| Switch | Where | Default |
| --- | --- | --- |
| Payload-processing backend | MaasTenantConfig annotation `maas.opendatahub.io/payload-processing-type` (`platform_context.go:20-31`) | **absent or `"praxis"` → praxis (SkipIPP=true)**; only `"ipp"` opts back into legacy IPP (`platform_context.go:119-127`) |
| API translation | `MaasTenantConfig.spec.apiTranslation.enabled` (`maastenantconfig_types.go:88-95`) | omitted/false → **disabled** for new tenants; migration auto-writes `true` for recognized IPP baselines (`plugins_migration.go:288-338`) |
| Force migration | annotation `maas.opendatahub.io/force-payload-processing-migration=true` (`constants.go:85-88`) | off; only needed for non-standard plugins ConfigMaps or accepted translation risk |
| Migration blocked marker | annotation `maas.opendatahub.io/payload-processing-migration=blocked` (`constants.go:90-97`) | set only while blocked, cleared after cleanup (`pipeline.go:416-424`) |
| Accepted-risk marker | annotation `maas.opendatahub.io/api-translation-migration-risk` ∈ {`explicit-false`,`forced`} (`constants.go:99-113`) | absent |
| Handshake status | annotation `maas.opendatahub.io/payload-processing-status` (`constants.go:51-83`) | seeded `cleanup-complete` at creation (`aitenant_controller.go:905-920`) |
| IPP pod scaling (legacy only) | `spec.payloadProcessing` / `spec.payloadPreProcessing` (`maastenantconfig_types.go:63-69`) | irrelevant for praxis — HPAs skipped when SkipIPP (`postrender.go:86-92`) |

There is **no controller-level feature flag** for praxis (manager flags at `maas-controller/cmd/manager/main.go:1130-1161` are gateway/namespace/paths/caching only); selection is purely per-tenant. Related config defaults: praxis deployment of AGC itself is external to MaaS, driven by env vars in the e2e companion script (`test/e2e/scripts/deploy-aigc-companion.sh:10-32`).
