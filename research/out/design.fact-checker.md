## Verdict
APPROVE WITH CHANGES — the honesty framing and 3.6 treatment are well-grounded, but the 3.5 flow outline is an internally inconsistent hybrid that matches no code-validated ConfigMap shape, and a few 3.6 claims under- or over-state the fact base.

## Critical

1. **B3's 3.5 chain matches neither cited basis and contradicts B2.** Verified directly: `git show v0.2.1:deployment/base/payload-processing/manager/plugins-configmap.yaml` has pre-chain `model-extractor` **+ `model-provider-resolver`** and post-chain `maas-headers-guard, stream-usage-enforcer, model-provider-resolver, api-translation, apikey-injection` + response `api-translation`. B3 shows `ipp-pre (model-extractor)` only — missing `model-provider-resolver` that B2 itself includes ("pre-auth (model-extractor, model-provider-resolver[3.5 only])") and that facts.md's per-flow status cites ("body-field-to-header + model-provider-resolver pre-auth"). B2 and B3 cannot both be right.

2. **"3.5 GA" is unresolved between two real shapes, and B3 mixes them.** The fact base itself is split: facts.md's matrix equates 3.5 GA with tag v0.2.1 (mpr in pre, maas-headers-guard present, response api-translation), while maas-3.5 §1.3 and praxis-inv §3 record that the **shipped RHOAI 3.5.0 default** ("odh-3.5.0" baseline, `plugins_migration.go` `matchODH350PreProcessing`/`matchODH350Processing`, verified in source) had **no model-provider-resolver in pre and no maas-headers-guard at all**. B3's outline (no mpr in pre, but headers-guard present) is a hybrid of the two that exists in no tag, no baseline, and no shipped release. The design must pick one shape, cite it, and record the variance in the version overlay.

3. **B2 and B3 contradict each other on the 3.6 legacy tenant's response chain.** B2: "Response plugins section per version: … 3.5 = api-translation, 3.6(ipp) = empty again." B3: 3.6 legacy flow is "identical to 3.5 flow" — which shows response api-translation. Additionally, "identical to 3.5" is wrong for a *freshly created* `"ipp"` tenant at HEAD, which gets HEAD's default ConfigMap (response `[]`, mpr in pre); only a tenant *upgraded from 3.5* preserves its old shape (ConfigMap is stamped `managed=false`, maas-3.5 §1.3). The design needs to say which 3.6-legacy tenant it depicts.

## Important

4. **3.6 praxis flow omits usage-logs — the "more conservative than facts" case the charter targets.** praxis-inv §1: for praxis tenants maas-controller *still deploys* "telemetry (TelemetryPolicy + Istio Telemetry), usage-logs EnvoyFilter" (telemetry default true). B3's praxis flow ends with "metering via Kuadrant TRLP unchanged" and no usage-logs node. The 3.6 header_to_metadata identity path is live for praxis tenants (Authorino still injects `X-MaaS-*`; the AGC chain has no `identity_header_guard` to strip them). The flow should show it.

5. **Migration flow's first step inverts the opt-in/opt-out semantics.** Per praxis-inv §1/§7 and facts.md headline #1: annotation **absent = praxis (default)**; only `"ipp"` opts back to legacy. "Operator sets annotation →" implies migration is an opt-in action; in code an upgraded tenant migrates *unless* the operator affirmatively sets `"ipp"`. The flow's framing should be "upgrade to 3.6 (no annotation = praxis default); operator may opt out with `"ipp"` / force with the force-migration annotation."

6. **CRD list applied unversioned to 3.4 and 3.5 scenes.** B2's fix list says it applies to "3.4 and 3.5 scenes", but AITenant, MaasTenantConfig, Config, ExternalProvider, and `inference.*` ExternalModel do not exist at v0.1.1 (facts.md matrix CRD row; 3.4 has `Tenant` + `maas.*` ExternalModel). Showing the full set in the 3.4 scene overstates. Version-scope the list (and note `Tenant` for 3.4).

7. **`stream_usage_inject` in the B5 capability inventory needs a pin caveat.** praxis-cap explicitly flags: implemented in praxis-ai @ `8a9a2159` but **NOT at the praxis-extproc pinned v0.6.0** ("NOT IMPLEMENTED IN CODE at the pinned rev"). The inventory sits on the praxis-extproc node whose tip cites the v0.6.0 pin — as written it overstates the deployed runtime. Label the inventory with the praxis-ai commit it reflects, or annotate the filter. (Relatedly, `token_ceiling` is also experimental and implemented but is omitted while `token_rate_limit` is included — pick a consistent criterion.)

8. **"Anthropic rejects unmappable CC fields (400 vs 3.5 silent drop)" is uncited in the fact base.** praxis-inv §4 covers provider-level migration blocking, not per-field 400 behavior; no fact sheet cites the 400-rejection or the "silent drop" comparison. There is supporting code (praxis-ai `anthropic_messages_request` `on_invalid: reject` → `invalid_request_rejection`), but neither fact sheet cites it — per the plan's own C5 rule ("every step … traceable to research citation"), this needs a citation added before it ships.

9. **B2's "`model-provider-resolver`[3.5 only]" tag is wrong or meaningless.** At HEAD (the 3.6 `"ipp"` default) the pre chain still includes model-provider-resolver (maas-3.5 §1.3, v0.2.1 and HEAD both). If "[3.5 only]" means "absent in 3.4", that's trivially true because 3.4 has no pre-auth stage at all; if it means "absent in 3.6", it's false. Reword.

## Minor

10. **AGC deploys three chains, not two.** Base ConfigMap also has `extproc.yaml` chain `ipp: [request_id]` (verified in `ai-gateway-controller/config/manifests/praxis-extproc/base/config/configmap.yaml`), and `credential_inject` is emitted only "when credentials exist" (`extproc.go` `extprocPostAuthConfig`). B2's "two chains as AGC deploys them" omits `request_id` and the conditionality.

11. **"wasm token report → Limitador" steps retained without the Kuadrant-behavior labeling** that facts.md gap #9 / maas-3.5 §6.9 require ("keep but label accordingly"). B5 has no item covering this label.

12. **`intelligent-model-selection` relabel is uncited.** ipp-ga §1 verifies binary-registration-minus-profile only for the nemo plugins; upstream has a `modelselector` framework package, but no fact sheet establishes `intelligent-model-selection` is registered in the GA binary. Either cite it or keep it under a weaker "upstream framework, not deployed" label.

13. **"EPP in natural position" (3.4/3.5) is anchor-dependent.** With the ODH/community Kuadrant WasmPlugin it works; with RHCL router-anchored wasm or the router fallback, "the EPP never runs and pool traffic silently falls back to round-robin" (maas-3.5 §4.1). Worth one overlay caveat line rather than an unqualified node position.

14. **Citation nit inherited from facts.md:** the FILTER_STATE cite reads `envoy-otel-access-log.yaml:350-359`, but at v0.2.1 the file lives at `deployment/components/observability/usage-logs/` (no `dsci-managed/` segment; verified — `git show v0.2.1:...dsci-managed/...` fails). Substance confirmed (FILTER_STATE at :350-356); fix the path when C5 runs.

## Suggestions

- Add an explicit decision record in B1: "3.5 depicts tag v0.2.1" vs "3.5 depicts RHOAI 3.5.0 shipped default", with the other shape noted in the version overlay as shipped-release variance. This single decision resolves Critical #1–#2 and most of Important #9.
- For the 3.6 legacy flow, either depict the HEAD default (fresh `"ipp"` tenant) and say so, or depict the upgraded-3.5.0 tenant (preserved ConfigMap) and say so — don't blur them.
- Migration-gate overlay: name all three recognized baselines (`default`, `default+response-api-translation`, `odh-3.5.0`) rather than "default baselines pass" — the odh-3.5.0 recognition is exactly what makes real 3.5 upgrades eligible.
- Wherever the praxis capability inventory appears, state both revs side by side: "praxis-ai @ 8a9a2159 (research snapshot)" vs "praxis-extproc pins praxis-ai v0.6.0".
- Add the usage-logs node (header_to_metadata identity) to the 3.6 praxis flow; it also visually reinforces that metering survives the praxis swap.
