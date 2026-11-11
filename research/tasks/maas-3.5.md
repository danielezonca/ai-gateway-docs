# Task: MaaS 3.5 GA baseline

Repo: `clones/models-as-a-service` (read-only, record its HEAD commit).

Goal: document the **currently deployed, GA** request pipeline exactly as code builds it, to ground the "RHOAI 3.5 GA" side of a flow visualizer.

Focus on `maas-controller/pkg/platform/tenantreconcile/` (pipeline.go, params.go, apply.go, kustomize.go, constants.go, plugins ConfigMap handling, usage_logs_envoyfilter.go, gateway_auth.go) plus kustomize manifests under deployment/ or maas-controller config.

Answer:
1. The exact ext_proc plugin/filter list deployed per tenant: names, order, and for each plugin: what it does to the request (path rewrites, headers added/removed, body mutations) and response. Cite code.
2. Auth flow: how Authorino validates against the MaaS API (callback endpoint), CRDs involved (MaaSModelRef, MaaSAuth, MaaSSubscription, AITenant, MaasTenantConfig), and what each contributes.
3. Metering/usage-logs: what usage_logs_envoyfilter.go actually emits — which Envoy hooks, what payload, where it goes.
4. EPP / llm-d integration for internal (on-cluster) models: how pod selection works, which components are deployed.
5. Anything gated by feature flags, versions, or MaasTenantConfig settings that distinguishes current GA behavior (e.g. usage-logs on/off, api-translation variants).
6. Anything that changed vs the visualizer's current claims (the visualizer lives at clones/ai-gateway-docs/ai-gateway-flow.html — you may read it for comparison, but cite MaaS code for every fact).

Output: markdown fact sheet, one section per question, every claim with file:line citations. Mark anything you cannot find in code as NOT IMPLEMENTED IN CODE.
