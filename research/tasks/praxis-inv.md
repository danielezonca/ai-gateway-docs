# Task: Praxis integration state in MaaS

Repo: `clones/models-as-a-service` (read-only, record its HEAD commit). Focus on `maas-controller/pkg/platform/tenantreconcile/`: pipeline_praxis_test.go, ipp_cleanup_test.go, ipp_migration_marker_test.go, plugins_migration.go + tests, legacy_ipp_translation_test.go, api_translation_migration_test.go, constants.go, platform_context.go, postrender.go; plus API types (maas-controller/api/maas/v1alpha1/) and any ai-gateway-controller references.

Goal: establish what "praxis" concretely means in MaaS **today**, for a flow visualizer that must not show planned features as existing.

Answer:
1. When praxis is selected for a tenant: which resources/images/CRDs are actually deployed? Who owns them (maas-controller vs ai-gateway-controller)?
2. SkipIPP and the ownership-handshake marker: exact semantics, states, and what triggers one-shot IPP cleanup.
3. Plugins migration (plugins_migration.go, apply_plugins_configmap_test.go): which filters move to praxis, which stay on IPP, and what the deployed praxis pipeline looks like (filter names, order).
4. api-translation migration: current state — which providers, what is actually translated where.
5. Fallback / retry / model-failover routing: does ANY of it exist in code (search whole repo), or only in planning docs?
6. Responses API: any references in maas-controller or deployment manifests (endpoints, routes, config)? Distinguish code from docs/comments.
7. Which of these behaviors are behind feature flags / MaasTenantConfig fields, and what are their defaults?

Output: markdown fact sheet, one section per question, file:line citations. Mark anything not found in code as NOT IMPLEMENTED IN CODE.
