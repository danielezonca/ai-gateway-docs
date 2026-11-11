# Plan: AI Inference Gateway Flow Visualizer — RHOAI 3.5 / 3.6

**Branch:** `rhoai-3.6-flow` (off `noyitz/main` @ 1ddbe07)
**Target file:** `ai-gateway-flow.html`

## Principle

The visualizer must reflect **what the code actually does today**, not what planning documents promise. The 3.6 plan README describes target architecture (e.g. Responses API, fallback routing, legacy-payload-processing→praxis swap) whose implementation status is unknown. Therefore: **research first via subagents, then design, then implement.** No visualizer change starts until the fact base is written.

## Repos in scope

| Clone | Role |
|---|---|
| `clones/models-as-a-service` | maas-controller: tenantreconcile pipeline, praxis/IPP migration, plugins ConfigMap, metering EnvoyFilter |
| `clones/praxis-extproc` | opendatahub-io/praxis-extproc (Rust ext_proc adapter) |
| `clones/praxis`, `clones/praxis-ai`, `clones/praxis-ai-upstream`, `clones/praxis-policy` | praxis core/filter ecosystem — **must determine which is canonical and where filters actually live** |
| `clones/ai-gateway-payload-processing`, `clones/llm-d-inference-payload-processor` | IPP GA filter set (3.5 baseline) |
| `clones/ai-gateway-docs` (this repo) | visualizer + existing `responses-api/` visualizer |

All repos are pinned snapshots — read-only analysis, refs recorded per repos.yaml conventions.

---

## Phase A — Code research (headless pi subagents)

Each task runs as a one-shot `pi --print --no-session` subagent (pattern from `spare-notes/ai-gateway-control-plane-evolution/reviews/run-review.sh`) and produces a fact file under `research/out/`. Facts must cite file:line. Anything not found in code is marked **NOT IMPLEMENTED IN CODE (planned only)** with the planning doc that claims it.

**Runner:** `research/run-research.sh` — usage:

```bash
./research/run-research.sh maas-3.5 praxis-inv   # any subset
./research/run-research.sh all                    # all five in parallel
# env: RESEARCH_MODEL, RESEARCH_THINKING (default high)
```

Charters in `research/tasks/`; subagent output lands in `research/out/<task>.md` (+ `.err`).

### A1. MaaS 3.5 GA baseline
**Input:** `models-as-a-service` (maas-controller, especially `pkg/platform/tenantreconcile/`)
**Questions:**
- Exact ext_proc plugin list deployed in the current GA pipeline (pipeline.go, plugins ConfigMap, apply/params) — names, order, per-plugin behavior (headers added/removed, body mutations)
- Auth flow: Authorino → MaaS API callback, exact endpoints, CRDs involved
- Metering/usage-logs: `usage_logs_envoyfilter.go` — what's actually emitted, per-request hooks
- EPP/llm-d integration for internal models
- Anything version-gated or feature-flagged that distinguishes 3.5 from 3.4

**Output:** `research/out/maas-3.5.md`

### A2. Praxis integration state in MaaS
**Input:** `models-as-a-service` tenantreconcile: `pipeline_praxis_test.go`, `ipp_cleanup_test.go`, `plugins_migration.go`, `legacy_ipp_translation_test.go`, `constants.go`, MaasTenantConfig/AITenant types
**Questions:**
- What does "praxis selected" concretely deploy today? Which images, which CRDs, which resources?
- SkipIPP / ownership-handshake / one-shot cleanup: actual semantics and current status
- api-translation migration: which filters moved to praxis, which remain on IPP, per `api_translation_migration_test.go`
- Is there any fallback/retry routing in code, or only in the plan?
- Any Responses API references in maas-controller (grep showed almost none — confirm)

**Output:** `research/out/praxis-inv.md`

### A3. Praxis capability inventory
**Input:** `clones/praxis-ai` (redhat-et/praxis-ai — **canonical filter implementation**: `filters/src/`, `apis/src/`, `server/`, `store/`, `tests/`) + `clones/praxis-extproc` (deployed ext_proc artifact). `clones/praxis` is a stale June 2026 snapshot — cross-checks only.
**Questions:**
- Canonical repo + commit for praxis filters; inventory of implemented filters with actual capabilities (auth? rate-limit? api-translation — which providers? credential-injection? guardrails? MCP?)
- ext_proc protocol handling in praxis-extproc: request/response phases, streaming support
- Responses API / agentic loop: **what exists in code** (endpoints, filters like conversation-manager/response-store) vs. what is issue/plan-only. User's expectation: not fully implemented — establish exactly what exists.
- Deployment model: how praxis is configured (static config bridge? CRD-watching? nothing yet)
- Test coverage signals (e2e tests show what actually works end-to-end)

**Output:** `research/out/praxis-cap.md`

### A4. Visualizer current-state inventory
**Input:** `ai-gateway-docs`: `ai-gateway-flow.html`, `responses-api/index.html`, `responses-api/0*.md` docs
**Questions:**
- Exact node/flow/step structure of `ai-gateway-flow.html` (N, tips, flowMap, flow* step arrays) — the extension points
- What `responses-api/index.html` already visualizes and whether its content is code-grounded or plan-derived (check its `0*.md` sources)
- Which filter/step claims in the current visualizer are stale vs the noyitz/main "live EnMaaS filters" update

**Output:** `research/out/visualizer.md`

### A5. IPP GA filter set
**Input:** `ai-gateway-payload-processing` (+ upstream `llm-d-inference-payload-processor`)
**Questions:**
- Implemented GA plugins and their exact request/response behavior (this grounds the 3.5 side-by-side and the parity table)

**Output:** `research/out/ipp-ga.md`

**Phase A exit:** consolidate `research/out/*.md` into `research/facts.md` — one page: per flow (3.5 GA / each candidate 3.6 flow): implemented | partial | planned-only, with citations. Reviewed with user before Phase B.

---

## Phase B — Design (approved facts → concrete design)

Design principle: the visualizer shows **what code deploys per version tag**, honestly labeled. Version is the primary dimension; flows within a version reflect the verified pipeline for that tag. Nothing plan-only gets a runnable flow.

### B1. Version selector & framing

- Add a **version toggle** in the flow bar (segmented buttons: `3.4` / `3.5` / `3.6`) next to `#flow-select`. Mechanism (revised per review): `version` state + per-version `flowMaps`/`flowLabels`; **node/line visibility is flow-driven (flow + version), not version-only** — the 3.6 scene contains both the legacy and praxis stacks and shows one per selected flow. The inspector dispatch (`inspStep`, currently keyed on `activeFlow` + step number with inlined ext cases :1140–1269) must be made **version-aware first** (composite key `version:flow`, extracted inspector functions per flow) — otherwise two versions' `ext` flows collide in the same switch. This refactor is part of C1, before any new flow lands.
- **Layout plan required before coding** (review: largest schedule risk): current scene is 33 nodes at LW=1250/LH=1050; 3.6 both-stacks estimate is 42–46 nodes. Grow LH to ~1300 only for the 3.6 scene (accepting sc≈0.75 on small laptops) or use per-scene node sets; pre-auth container goes in the free gap x≈490–740 between Kuadrant and the payload-processing container; the migration flow is control-plane and gets a **separate compact strip** (control-plane row) rather than sharing the data-plane packet animation; `drawBounds` hard-coded section rects (:497–527) get version-aware rects. Coordinates are drafted in C0 below.
- Version badges: desktop badge in `.viz-title` (new element) + mobile splash (`:118`) derive from `version` state: **3.4 GA** / **3.5 GA** / **3.6 TP** (amber accent #f0883e for TP).
- Per-version canvas scene: see layout plan above — flow-driven visibility, version-aware geometry.
- Version overlay (click badge or toggle): one-paragraph summary of what changed between versions, citing facts.md matrix (single ext_proc→two stages; per-HTTPRoute→gateway AuthPolicy; usage-logs added in 3.5; EPP reorder + InferenceObjectives + praxis swap in 3.6-dev; gateway-default-deny present since 3.4), plus the 3.5 shape variance note (B2) and the label→resource-name mapping table (B2 addendum).

### B2. Node set changes (all versions, same canvas)

**3.5 baseline decision (resolves review conflict):** two real shapes exist — the shipped **ODH 3.5.0** product image (migration-doc `"odh-3.5.0"` baseline: pre = model-extractor only, no maas-headers-guard, response api-translation ON) and the **v0.2.1 repo tag** (adds model-provider-resolver to pre + maas-headers-guard via e245289c, 2026-07-19; maps to RHOAI 3.5.z). The 3.5 scene renders the **v0.2.1 tag shape** (code-verifiable, repo's own mapping table) and the version overlay documents the odh-3.5.0 initial-release variance so operators debugging a 3.5.0 cluster are not misled. B2 and B3 use this one shape consistently.

**Fixes applying to 3.4 and 3.5 scenes** (from maas-3.5 §6, code-validated). **Terminology rule: do not use the term "IPP" in user-facing labels.** "IPP" names the legacy ai-gateway-payload-processing implementation that praxis-extproc replaces; in MaaS code `ipp`/`ipp-pre` are merely EnvoyFilter/ext_proc filter names (which AGC reuses for the praxis dataplane), so the term is actively misleading. Use: **"Payload Processor (ext_proc)"** for the 3.4/3.5 dataplane, **"praxis-extproc"** for the 3.6 dataplane, **"legacy payload processing"** in migration context. Raw code names (`envoy.filters.http.ext_proc.ipp-pre` etc.) may appear only as quoted identifiers inside overlay detail tables, never as node/step labels.
- Split the Payload Processor container into **pre-auth** (`model-extractor`, `model-provider-resolver`) and **post-auth** (`maas-headers-guard`, `stream-usage-enforcer`, `model-provider-resolver`, `api-translation`, `apikey-injection`) for 3.5/3.6-legacy; 3.4 shows the single post-auth stage only (pre-container absent, matching the single `bbr` ext_proc at v0.1.1). Node labels: "Payload Pre-Processing (ext_proc)" / "Payload Processing (ext_proc)" (matches the deployed Deployment names `payload-pre-processing` / `payload-processing`).
- Response plugins section per version: 3.4 = empty (dashed outline), 3.5 = api-translation (ON in both 3.5 shapes), 3.6-legacy = depends on tenant history — upgraded-from-3.5 tenants keep their stamped-`managed=false` ConfigMap shape (response ON); freshly-created `"ipp"` tenants get HEAD default (response `[]`). The 3.6 legacy flow depicts the **upgraded-from-3.5 tenant** (the common case) and says so in its label/overlay.
- Auth container: relabel callbacks — **two** maas-api hops (`api-keys/validate`, `subscriptions/select`), both cached.
- Replace fictional **MaaSAuth** CRD reference with real set (MaaSAuthPolicy, MaaSModelRef, MaaSSubscription, AITenant, MaasTenantConfig, Config, ExternalModel/ExternalProvider) in `tips.maas`.
- Add **usage-logs path** (3.5+): OTel access-log node + attributes; identity via **FILTER_STATE** in 3.5, header_to_metadata in 3.6.
- EPP depiction: 3.4/3.5 = Istio InferencePool ext_proc in natural position (post-payload-processing, before router); 3.6 = reordered before router (3.6-dev). InferenceObjective nodes only in 3.6. (Correction from review: the **gateway-default-deny TRLP exists since v0.1.1** — bdae2c84 — and must NOT be shown as a 3.6 addition; only the router-fallback auth anchoring is 3.6-dev.)
- `request-guard`/`intelligent-model-selection`/`response-guard` (nemo): keep `soon` styling, relabel "opt-in: compiled in, not in default profile" (registered in the binary, absent from the ConfigMap — ipp-ga §1). Remove `base-model-to-header` from default-chain visuals (same status).

**Terminology addendum (from review):** the same k8s object names (`payload-processing`, `payload-pre-processing`, `payload-processing-plugins`, EnvoyFilter `payload-processing-{tenant}`) persist across both eras with **different owners** (maas-controller vs AGC). To prevent visualizer↔cluster correlation confusion, every version overlay includes a **label→resource-name mapping table** stating the actual object names and the owning field-manager for the depicted era.

- `tips.maas` CRD list fix and the migration flow rename below also apply this terminology.

**3.6 additions:**
- **praxis-extproc container** (replaces the Payload Processor container in the 3.6-praxis scene): two chains as AGC deploys them — pre: `model_to_header`, `llmisvc_model_provider_resolver`; post-auth: `intelligent_route`, `credential_inject`. Amber/TP styling; dashed border on TP nodes.
- **AGC (ai-gateway-controller) node** in control plane: renders praxis ExtProc manifests per tenant, SSA field manager, handshake annotations.
- **Migration state machine** (overlay content on AGC node): annotation `payload-processing-type` (absent=praxis default), status handshake (`cleanup-complete`/`steady`), one-shot cleanup of 14 legacy payload-processing operands, ownership race guard.

### B3. Flow set per version

| Version | Flow | Steps (outline) | Basis |
|---|---|---|---|
| 3.4 | External (Anthropic) | client → gw → auth (validate+select) → Payload Processor ext_proc (4 plugins, single stage) → anthropic → response passthrough → wasm token report → Limitador | v0.1.1 |
| 3.4 | Internal (llm-d) | same, via InferencePool EPP in natural position | v0.1.1 |
| 3.4 | Auth Failure / Rate Limit | unchanged mechanics, per-HTTPRoute auth context | v0.1.1 |
| 3.5 | External (Anthropic) | client → gw → `ipp-pre` (model-extractor, model-provider-resolver) → auth (validate+select) → `ipp` (maas-headers-guard, stream-usage-enforcer, model-provider-resolver, api-translation, apikey-injection) → anthropic → **response api-translation** → wasm token report → usage-logs (FILTER_STATE identity) — v0.2.1 shape; odh-3.5.0 variance in overlay | v0.2.1 |
| 3.5 | Internal (llm-d) | 3.5 chain + EPP in natural position; **no** InferenceObjectives; gateway-default-deny TRLP present (since 3.4) | v0.2.1 |
| 3.5 | Auth Failure / Rate Limit | updated headers per 3.5 auth rules | v0.2.1 |
| 3.6 | **Legacy payload-processing tenant (upgraded from 3.5)** | identical to the 3.5 flow (ConfigMap preserved via managed=false stamp), plus EPP reorder and InferenceObjectives (3.6-dev) | praxis-inv §1 |
| 3.6 | **Praxis tenant** (default) | client → gw → auth (Authorino unchanged) → praxis pre (`model_to_header`, `llmisvc_model_provider_resolver`) → praxis post (`intelligent_route` → provider hop; `credential_inject`) → provider; response: token accounting per praxis filters **as deployed** (none in AGC chain — metering via Kuadrant TRLP unchanged) | praxis-inv §3 |
| 3.6 | **Payload-processing → praxis migration** (**automatic on upgrade**, not operator-initiated) | 3.6 upgrade lands, annotation absent → praxis is default → reconcilePayloadProcessingSwitch runs: gate (ConfigMap fingerprint: default / default+response-api-translation / odh-3.5.0 baselines pass) → api-translation compat check (openai/anthropic pass; azure/vertex/bedrock block) → **failure states shown**: `migration=blocked` marker + blockedReason, risk markers (`explicit-false`/`forced`), pending "waiting for praxis cleanup" on legacy opt-back → one-shot cleanup (14 legacy operands, HTTPRoutes, transport services) → `cleanup-complete` → AGC claims (`steady`) → praxis dataplane live. Operator actions are only: set `"ipp"` to opt back, or `force-payload-processing-migration=true` to unblock | praxis-inv §2,§4 |
| 3.6 | ~~Chat Completions + fallback~~ | **NOT INCLUDED** — not implemented in code | praxis-inv §5 |
| 3.6 | ~~Responses API end-to-end~~ | **NOT INCLUDED as runnable flow** — see B4 | praxis-inv §6 |

Auth-failure/RL flows exist per version only where mechanics differ (3.4 per-route auth vs 3.5+ gateway auth) — otherwise reuse.

### B4. Responses API treatment (honest)

- No runnable MaaS-level flow (NOT IMPLEMENTED in MaaS/AGC).
- Add a **"Responses API — runtime status" info card** in the 3.6 scene (ghost node with dashed border + info icon, not in any step sequence). Sharpened per review: "The Responses core (request kernel, store/rehydrate via cert-auth Postgres, agentic loop, Responses→Chat Completions translation) **is compiled into the deployed odh-praxis-extproc image (FIPS build)** — unused. The gap is purely AGC config/CRD wiring. MCP tools, compaction, Conversations, file-resolve are **not** in the FIPS build (excluded features)." Overlay links: praxis-ai repo, `responses-api/index.html` (labeled "design draft, May 2026"), relevant docs.
- `responses-api/index.html` itself: add a provenance banner ("plan-derived draft; runtime status per research/facts.md") — content update out of scope here.

### B5. Node overlay content (tips)

- `praxis-extproc` node: what AGC deploys (chain names), praxis-ai v0.6.0 pin, 4 phases, 10 MiB cap; links to praxis-extproc + praxis-ai repos.
- **Praxis capability inventory** as a separate overlay section on the praxis container, split into **four** buckets (per review — "available in runtime" is not one coherent bucket): (1) **Deployed by AGC** (the thin chain); (2) **In the deployed FIPS image, unused** — responses core (request, store/rehydrate via cert-auth Postgres, agentic loop, Responses→CC), aws-sigv4, stream_usage_inject (present and ungated at the v0.6.0 pin — corrects praxis-cap.md); (3) **In praxis-ai source but NOT compiled into the deployed image** — MCP tools/compact/conversations/file-resolve (excluded from FIPS features), token_rate_limit/token_ceiling (experimental, not in defaults or FIPS set), policy-engine; (4) **Fork-only (redhat-et/praxis-ai), not upstream v0.6.0** — api_key_auth; and post-v0.6.0 upstream filters (e.g. vertex rawPredict, #1695) noted as "newer than deployed pin".
- Migration mechanics on AGC node (B2).
- api-translation parity note: under praxis only openai passthrough + anthropic messages; Anthropic rejects unmappable CC fields (`response_format`, `frequency_penalty`, `presence_penalty`, `logprobs`) with 400 vs 3.5's silent drop — cited to models-as-a-service release notes ("Unreleased (RHOAI 3.6)" section, docs/content/release-notes/index.md) and praxis-ai `anthropic_messages_request` validation; azure/vertex/bedrock block migration.
- Usage-logs node: per-version identity mechanism.

### B6. Visual conventions

- Port `enmaas-flow.html`'s **activePathColor** (request blue / response green frames on active nodes) into `drawBox` — visualizer inventory §4.3, small self-contained change.
- TP styling: amber badge + dashed borders for 3.6-only nodes; "3.6-dev" small tag for EPP reorder/InferenceObjectives (post-v0.2.1) when shown.
- Legend gains: version colors, TP styling, ghost/planned styling.
- Mobile splash stats recomputed per version (fix current inconsistency).

### B7. What we deliberately do NOT do

- No "praxis handles all filters" claim (AGC chain is thin); no use of the term "IPP" in any user-facing label (B2 terminology rule); no enmaas-flow merge (cross-link only, it models a different deployment); no changes to `responses-api/` content beyond the provenance banner.

**Output:** this section — approved before coding.

## Phase C — Implementation (revised per adversarial review)

### C0 — Layout draft (slot-based scene reuse)

Key insight from the engine study: **flow-driven visibility + slot reuse** keeps every scene within the current canvas (LW=1250, LH=1050 — no growth, no rescale). Each version×flow combination populates fixed slots; nodes not in the scene are hidden.

**Slots (current coordinates, reused across scenes):**

| Slot | Rect (x, y, w, h) | Contents per scene |
|---|---|---|
| S1 dataplane | 740, 260, 380, 500 (current `ipp`) | 3.4: single-stage Payload Processing (4 plugins, response section empty/dashed) · 3.5 & 3.6-legacy: post-auth container with deployed chain · 3.6-praxis: **praxis-extproc** container (pre chain: `model_to_header`, `llmisvc_model_provider_resolver`; post-auth chain: `intelligent_route`, `credential_inject`; ghost Responses card docked bottom, dashed, non-step) |
| S1a pre-auth | 510, 280, 210, 300 (gap between Kuadrant and S1) | 3.5/3.6-legacy: "Payload Pre-Processing (ext_proc)" container, 2 plugins (`model-extractor`, `model-provider-resolver`) · 3.4/3.6-praxis: hidden |
| S2 Kuadrant | 190, 305, 300, 280 | unchanged all scenes (auth shows two callback hops to maas) |
| S3 MaaS API | 230, 640, 220, 55 | unchanged; new tips (two endpoints, real CRD set) |
| S3a usage-logs | 230, 715, 220, 55 (below maas) | 3.5+: "OTel Usage Logs" node; 3.4 hidden |
| S4 EPP | 460, 770, 260, 70 | 3.4/3.5 natural position; 3.6: same slot, overlay notes the reorder |
| S5 InferencePool | 200, 870, 1000, 175 | data-plane flows (all versions) · **migration flow: hidden, replaced by control-plane strip** |
| S5′ control-plane strip | 200, 855, 1000, 190 (reuses S5 area) | migration flow only: maas-controller → gate (ConfigMap fingerprint) → compat-check → [blocked/risk/pending ghost states] → cleanup → AGC claim → steady; AGC node also docked in 3.6-praxis scenes as owner of praxis-extproc |
| S6 providers | -40, 300, 140, 55 ×5 | unchanged; hidden in migration flow |

**Node budget per scene:** 3.4 ≈ 30 · 3.5 ≈ 36 · 3.6-legacy ≈ 38 (+InferenceObjective docked at epp slot) · 3.6-praxis ≈ 36 · migration ≈ 28. All within current density (33 today).

**drawBounds changes:** the two hard-coded IPP section rects (:497–527) become functions of the active scene (which container is in S1, whether S1a exists). `.viz-title` gains a `#version-badge` span; splash badge (:118) becomes dynamic.

**Chain-order fix inside S1 (all payload-processing scenes):** plugin nodes re-ordered to the deployed chain: maas-headers-guard → stream-usage-enforcer → model-provider-resolver → api-translation → apikey-injection (3.5/3.6-legacy; 3.4 drops headers-guard + stream-usage-enforcer); nemo guards move to a dashed "opt-in (compiled in, not in default profile)" sub-section; `base-model-to-header` moves there too.

**Colors:** S1 praxis variant uses amber container (#f0883e) + dashed border (TP); legacy payload processing keeps purple (#d2a8ff). Migration strip nodes neutral blue; failure-state ghosts red-dashed.

- C1: version toggle + **version-aware inspector dispatch refactor** (composite `version:flow` key, extract per-flow inspector functions from the inlined switch) + per-version flowMaps + badges
- C2: 3.4/3.5 scene corrections: two-stage Payload Processor (3.5) / single stage (3.4), plugin chains per B2-decided shapes, dual auth callbacks, CRD fixes, usage-logs path, EPP positioning, gateway-default-deny in all versions
- C3: 3.6 scene: legacy tenant flow (upgraded-from-3.5), praxis tenant flow, migration flow with failure states (blocked/risk/pending) as control-plane strip, ghost Responses card, AGC node
- C4: overlay content (four-bucket praxis inventory, label→resource-name mapping tables, version-change summaries) + activePathColor port + TP styling + legend + splash stats
- C5: accuracy pass — every step, filter name, header mutation traceable to a research citation or corrected fact base
- C6: visual QA (both themes, mobile, all version×flow combinations incl. loop mode), commit to `rhoai-3.6-flow`

## Out of scope

- Post-3.6 plugin-by-plugin migration states; Files API / Vector Store / code_interpreter (deferred in plan docs); changes to the 3.6-plan folder itself.

---

## Status

- [x] Branch created, remotes configured
- [x] Research runner + task charters (`research/run-research.sh`, `research/tasks/`)
- [x] A1–A5 research fact files (`research/out/`) — run clean, all cited
- [x] facts.md consolidated + 3.4/3.5/3.6 code-validated matrix (git tags)
- [ ] Phase B design decisions — **drafted (B1–B7 above), awaiting approval**
- [ ] C1–C6 implementation
