# Visualizer Current-State Inventory — Fact Sheet

**Repo analyzed:** `ai-gateway-docs` @ `1ddbe07` (branch `rhoai-3.6-flow`; identical to remote `noyitz/main` @ `1ddbe07`, "Color all active filters by path"). Working tree has only untracked files (`flow-visualizer-3.6-plan.md`, `research/`); no modifications to tracked HTML. No other repos were read for this task (praxis-ai / maas / IPP verification is out of charter — flagged claims are listed, not verified).

---

## 1. `ai-gateway-flow.html` architecture (1718 lines)

### Block map (line ranges)

| Block | Lines | Contents |
|---|---|---|
| CSS | 6–103 | Right panel (380px), steps panel, inspector, overlay, legend, mobile splash |
| Mobile splash HTML | 107–130 | Badge **"RHOAI 3.4 GA"** (:118), stats "4 Flows / 5 Providers / 35 Steps / 30+ Components" (:121–125) |
| Chrome HTML | 132–205 | Branding, theme toggle, title + `#flow-label`, flow bar with `#flow-select` (4 options, :149–154), steps/inspector containers, overlay card, legend, canvas |
| Script state | 208–222 | `dots, activeNodes, badges, lines, glowing, fading, runStepIndex, playbackSpeed, loopMode, insp*, snapshots`; logical canvas `LW=1250, LH=1050` (:221) |
| **`N` node definitions** | **209–253** | 33 entries (see below) |
| **`tips` overlay content** | **255–280** | One entry per clickable key: `{t: title, d: desc, dt: [[label,value]...], links: [[label,url]...], logo?}` |
| Overlay logic | 283–340 | `showOverlay` (pauses run, positions card + `#highlight-box`), `closeOverlay` (resumes) |
| Drawing | 342–711 | `resize` :344, `drawBox` :359–448 (glow/badge styling, dashed stroke for `type:'plugin'`, "COMING SOON" for `soon:true`, badge circles stacked top-left), `drawContainer` :450, `drawBounds` :470–568 (cluster/AI-GW/Kuadrant/IPP/EPP/InferencePool boundaries; **hard-coded IPP "Request Plugins →"/"← Response Plugins" section rects** :497–527), `edgePt` :589, `drawArrowLine` :605, `drawLines` :637 (renders `lines[]`), `resolveEdge` :693 (picks node edge from `fromLeft/fromRight/.../toXOff/waypoints` flags) |
| Click/hover | 713–731 | Hit-test against `Object.keys(tips)` |
| **`Dot` class** | **736–858** | Pentagon packet + trailing dots; path = `[fromEdge, ...waypoints, toEdge]`; speed normalized to px/frame; `cb()` fires on arrival |
| Draw loop | 861–886 | `draw()`, `animate()`; redraws bounds, lines, boxes, dots, overlay highlight |
| Steps panel | 888–905 | `initSteps()` builds clickable list from active `flow`; click → `jumpToStep(i)` |
| Inspector | 908–1270 | `setInspPhase` :910, `initInspector` :917 (initial `POST /llm/ext-anthropic/v1/chat/completions`), `renderInsp` :935, `resetStyles` :949, **per-flow functions** `inspStepAuth` :955, `inspStepRL` :989, `inspStepInc` :1017, dispatcher `inspStep` :1128 (ext-flow cases 1–24 inline :1140–1269) |
| **Flow definitions** | **1273–1376** | `activeFlow='ext'` :1275, `flowExt` :1276–1306 (24 steps), `flowInc` :1308–1348 (35 steps), `flowAuth` :1350–1359 (8 steps), `flowRL` :1361–1371 (9 steps), `flowMap` :1373, `flowLabels` :1374, `flowOrder` :1375 |
| Run/reset engine | 1383–1646 | `updatePlayBtn` :1385, `cycleSpeed` :1392 (0.5/1/2x), `toggleLoop` :1399, `stepOpts` :1407 / `stepLine` :1415 (copy step-edge opts into Dot/line), `stepOnce` :1426, `run` :1447, **`execStep` :1474–1539**, `saveSnapshot` :1541, `restoreSnapshot` :1550, `simulateUpTo` :1563, `jumpToStep` :1587, `doReset` :1612, flow-select listener :1636 |
| Auto-start + mobile anim | 1648–1716 | Loop mode auto-on after 500ms (:1649); mobile splash particle animation |

### Node inventory (`N`, :209–253)
- `user` (icon, :210), `cluster` (boundary, :212), `aigw` (container "AI Inference Gateway / OpenShift AI", :213), `gw` Istio Gateway (Envoy) (:215)
- `wasm` container "Kuadrant / RHCL" (:217) with `auth` (Authorino, :218) and `rlimit` (Limitador, :219)
- `ipp` container "Payload Processor / IPP (ext_proc)" (:221); request plugins `p_rguard` (nemo, `soon`), `p_ims` (`soon`), `p_mpr`, `p_bfth`, `p_bmth`, `p_at_req`, `p_aki` (:222–228); response plugins `p_at_resp`, `p_resp_guard` (nemo, `soon`) (:230–231)
- External providers `openai/anthropic/azure/bedrock/vertex` (:234–238), `maas` "MaaS API / key validation" (:241), `epp`+`sched` llm-d Scheduler/EPP (:244–245), `pool` InferencePool boundary + `sidecar`/`decode`/`nixl`/`prefill` (:247–251)

### Step-array entry semantics (`execStep`, :1474–1539)
Two modes:
- **`mode:'arrow'`** — `{t, f, to, c, num, glow, fromLeft/Right/Bottom/Top, fromXOff, toLeft/..., toXOff, yOff, xOff, waypoints}`. Spawns a `Dot`; on arrival the line is pushed to `lines[]` (permanent), `f`/`to` added to `activeNodes`, optional `glow` container key added to `glowing` set (:1488–1496).
- **`mode:'lightup'`** — `{t, target, badge, errColor}`. Flashes node (`fading`), adds to `activeNodes`, appends numbered badge (badges stack as array); `errColor` temporarily swaps node color (restored in `doReset` :1613) (:1497–1514).
- **Inspector content is NOT in the step array** — it is keyed separately by 1-based step number in `inspStep*()` functions, dispatched by `activeFlow` (:1128–1136). Adding a flow therefore requires both a step array and an inspector function.

### Metering / hooks steps (current visualizer)
- ext flow steps 22–23: "Wasm reads usage.total_tokens from response" / "Wasm reports token count to Limitador" (:1303–1304) — lightups on `rlimit`.
- inc flow steps 33–34 (:1345–1346) — same pattern.
- Model: token metering via Kuadrant Wasm → Limitador `TokenRateLimitPolicy` (`tips.rlimit`, :266). **No external metering service / PriceTag / CloudEvents concept exists in this file.**

### Filter / path coloring
- Colors are hard-coded per step (`c`): request blue `#58a6ff`, response green `#3fb950`, error red `#f85149`, NIXL grey `#8b949e`; legend at :180–190. Plugin nodes are pre-colored blue (request) / green (response) in `N`. In `drawBox`, an active/badged node's stroke uses the node's **own** `n.color` (:384–397) — there is no "active frame follows path direction" logic (contrast: enmaas-flow, see §4).

### Minimal recipes

**(a) New node**
1. Add an entry to `N` (ai-gateway-flow.html:209–253): `{x, y, w, h, label, sublabel?, color, fs, type?: 'icon'|'boundary'|'container'|'plugin', inner?, soon?}`.
2. Add a matching `tips` entry (:255–280) to make it clickable (hit-test iterates `tips` keys, :713–719).
3. If it's a container/boundary, wire it into `drawBounds` (:470–568) or a `drawContainer(...)` call (:478–482). If it lives inside the IPP plugin sections, note the section rects are hard-coded coordinates (:497–527) and must be extended manually.

**(b) New flow**
1. Define `const flowXxx = [...]` (arrow/lightup entries) next to flowExt (:1276).
2. Register in `flowMap` (:1373), `flowLabels` (:1374), and `flowOrder` (:1375 — only needed for loop-mode cycling, :1480–1481).
3. Add `<option>` to `#flow-select` (:149–154).
4. Add `inspStepXxx(n)` and a dispatch branch in `inspStep` (:1128–1136).
5. Optionally update the mobile-splash stats (:121–125) — manually maintained, already inconsistent (says "35 Steps", true only for `flowInc`; `flowExt`=24, `flowAuth`=8, `flowRL`=9).

**(c) Version-dependent badges**
- The only version claim is the static mobile-splash string "RHOAI 3.4 GA" (:118). There is **no version selector, no conditional flow map, no per-version badge mechanism — NOT IMPLEMENTED IN CODE** (planned per `flow-visualizer-3.6-plan.md` Phase B/C2: "version selector + 3.6 flows").
- Recipe: introduce a `version` state; split `flowMap` per version (e.g. `flowMaps = {'3.5': {...}, '3.6': {...}}`); add a version toggle to `.flow-bar` (:144–158) mirroring the flow-select listener (:1636); derive the splash badge text (:118) and possibly `flowLabels` from it. Note the desktop UI currently shows no version badge at all — one would have to be added to `.viz-title` (:137) or the legend.

---

## 2. Version claims in both HTML files

- **ai-gateway-flow.html:118** — `<div class="badge"><span>RHOAI 3.4</span> GA</div>` (mobile splash only).
- **ai-gateway-flow.html:121–125** — "4 Flows / 5 Providers / 35 Steps / 30+ Components" (release-adjacent stats; step count matches only `flowInc`).
- **responses-api/index.html:124** — badge `<span>Responses API</span> Pipeline` — **no version number**. No "3.4"/"3.5"/"3.6"/"GA" strings occur anywhere in `responses-api/index.html`.
- Other release-related claims live only in the planning docs: `responses-api/02-components.md:14` (IPP old upstream "GA (v1.5.0)"), `:16` (MaaS "Pre-GA (v0.1.1)"), `responses-api/05-plan.md:45` and `:292` ("GA" = Phase 5 milestone, months 9–15).
- Both files carry a "Built with FlowStory" attribution (ai-gateway-flow.html:184, responses-api/index.html:193).

---

## 3. `responses-api/index.html` — what it visualizes, and provenance

### Structure (same engine, duplicated from the main visualizer)
- **16 stage nodes** (`N`, :215–246): `conn_locker`, `mcp_list`, `hydrate`, `gp_input`, `input_guard` (hydration row), `client`, `responses` (POST /v1/responses), `auth`, `input_limit` (request row), `convert` ("Connect to Model Router"), `inference`, `gp_output`, `guardrails`, `output_limit` (processing row), `loop_area` (hidden node for loop lightups, :237), `tool_invoke`, `assemble` (agentic tools row), `dehydrate`, `client_resp` (final row).
- **3 flows**: `flowSimple` (:1110–1184, 32 steps, agentic loop with tool call), `flowAgentic` (:1187–1237, 28 steps), `flowBlocked` (:1240–1259, 13 steps, input guardrails 403). `flowMap`/`flowLabels`/`flowOrder` at :1261–1263.
- **UI inconsistency:** the `<select>` offers only `simple` and `blocked` (:146–148) — the `agentic` flow is unreachable from the UI, and `flowOrder` (:1266) is dead code (no loop mode in this file; auto-start is plain `run()` at :1528–1530).
- Inspector: `inspStepSimple` :868, `inspStepAgentic` :951, `inspStepBlocked` :1053, dispatcher :1097; extra line styles `guard`/`blocked` (:57–61) not present in the main visualizer.
- Legend color semantics differ: Request / Hydration / Inference / Guardrails / Agentic Loop / Tools / Utility (:180–189).

### Code-grounded or plan-derived? → **Plan-derived.**
The stage vocabulary maps to the planning docs, not to any implementation:
- "Hydrate / Dehydrate" ← `responses-api/01-overview.md:58–62`.
- The intake→loop→completion pipeline concept ← `responses-api/04-plugins.md:74–110` (unified pipeline: auth, rate-limit, request-validator, hydrate-prompt, conversation-manager, tool-registry, guardrails, model-provider-resolver, …, response-assembler, response-store).
- All docs are dated May 15, 2026, **Status: Draft** (`responses-api/01-overview.md:5–7`).
- Notably, the visualizer's stage names (`Conn Locker`, `GP (Input/Output)`, `Connect to Model Router`, `Assemble`, `Input/Output Limit`) do **not** match the plugin names in `04-plugins.md` either — they are an idealized intermediate rendering of the plan.

### Claims that need verification against praxis-ai code (flagged, not verified here)
Every behavioral claim below is asserted by `responses-api/index.html` tips/steps with no code citation in this repo; **all are NOT IMPLEMENTED IN CODE as far as ai-gateway-docs shows (planned per responses-api/01–05.md)** until praxis-cap research confirms otherwise:
1. A `responses` stage that parses `POST /v1/responses` (index.html:216, :249).
2. `Conn Locker` — per-conversation connection locking / request isolation (:217, :253).
3. `MCP List Tools` — MCP server tool discovery with allow/deny filtering (:218, :254).
4. `Hydrate Prompt` — expansion of `previous_response_id` into full context + function-tool schema resolution (:219, :255).
5. `Guardrails Prep` / `Input Guardrails` — input content filtering, PII detection, pass/block with 403 (:220–221, :256–257).
6. `Input Limit` — 400 Bad Request on over-long input (:231, :251).
7. `Connect to Model Router` — format translation + routing to OpenAI/Anthropic/Azure backends (:234, :258).
8. `Inference` returning `tool_use` items that trigger a server-side loop (:235, :259).
9. Output `Guardrails` with pass/modify/redact actions (:233, :260).
10. `Output Limit (Hard)` truncation on `max_output_tokens` (:234, :261).
11. `Tool Invocation` executing MCP / File / Web-Search tools (:240, :262).
12. `Assemble` + agentic re-inference loop; `Dehydrate` producing clean Responses API output (:241–243, :263–264).
13. Inspector specifics: `resolved_tools` CycleState, `routed_to: openai/gpt-4o`, `function_call`/`function_call_output` items, `status: "incomplete"` (:881–883, :913, :986–991, :1017).

---

## 4. Stale vs. current (noyitz/main latest state)

**What noyitz/main actually changed recently:** the commits named in the charter ("live EnMaaS filters", "metering hooks", "path colors") all modified **`enmaas-flow.html`**, not `ai-gateway-flow.html`. `ai-gateway-flow.html` itself received only earlier noyitz commits (verified via `git diff origin/main..noyitz/main -- ai-gateway-flow.html`): inspector `pre-wrap` (:47), FlowStory attribution (:181), and renames — `aigw` label → "AI Inference Gateway / OpenShift AI" (:213), `wasm` → "Kuadrant / RHCL" (:217), "kubernetes cluster" → "OCP cluster" (:484). Those renames are **already current** in the checked-out file.

**What the latest enmaas-flow state claims** (from commits `48e2b01` "Align flow visualizer with live EnMaaS filters", `674ec25` "Clarify metering request and response hooks", `9960077` + `1ddbe07` path-color commits — all on `enmaas-flow.html`):
- **Live EnMaaS (Praxis) request filter chain:** `api_key_auth` (client key → MaaS API validate, 300s cache), `reject_upgrade`, `model_catalog`, `identity_header_guard`, `model_to_header`, `intelligent_route` (hot-reloaded routing overlay), `vertex` (unified-only Anthropic⇄Vertex), `path_rewrite`, `gcp_adc`, `external_metering (preflight)`, `stream_usage_inject`, `time_to_first_token`, `headers + credential_injection`, `load_balancer`; **response hooks:** `token_count`, `token_usage_headers`, `external_metering (response hook)` (commit 48e2b01 diff, enmaas-flow.html `N`/`tips`).
- **Metering:** a **single** PriceTag preflight `GET /api/v1/customers/{user}/entitlements/{feature}/value?model={model}` combining quota (`hasAccess` → 429) and model policy (`model_allowed` → 403, fail-closed), plus a post-response CloudEvents v1.0 usage event `POST /api/v1/events` — same `external_metering` filter in both hook roles (commits 48e2b01, 674ec25).
- **Path coloring:** active filter cards are stroked by path direction — blue for request-path filters, green for response hooks / green-accented infrastructure — while idle ET-added filters keep the purple frame (`activePathColor` logic, commits 9960027/1ddbe07).

**Stale items in `ai-gateway-flow.html` relative to that state:**
1. **Filter set:** the IPP plugin chain `p_rguard…p_aki` / `p_at_resp` / `p_resp_guard` (ai-gateway-flow.html:222–231) is the 3.4/3.5 IPP pipeline; it shares essentially no names with the live EnMaaS Praxis chain above. If 3.6 swaps IPP→praxis for some filters, this node set and all `tips` (:255–280) need a parallel praxis variant.
2. **Metering model:** steps 22–23 / 33–34 (:1303–1304, :1345–1346) + `tips.rlimit` (:266) model token accounting through Kuadrant Wasm → Limitador (`TokenRateLimitPolicy`). The live EnMaaS state instead claims an `external_metering` filter → PriceTag service (preflight + CloudEvents usage event). Two different architectures; the main visualizer has **no external-metering representation — NOT IMPLEMENTED IN CODE** in `ai-gateway-flow.html` (it exists in `enmaas-flow.html`).
3. **Path coloring:** `drawBox` (:384–397) strokes active nodes with their own `n.color`; there is no equivalent of enmaas-flow's `activePathColor` (active-frame-follows-path). Adopting it in the main visualizer is a small, self-contained change to `drawBox`.
4. **Plan-only plugins:** `request-guard`, `intelligent-model-selection`, `response-guard` are still rendered with "COMING SOON" (:1287–1288, :1300, :1343) — claims to re-verify against 3.5/3.6 facts, not code-verifiable from this repo.

---

## 5. Duplication / reuse assessment (`responses-api/index.html` ↔ main visualizer)

- **Engine duplication:** `responses-api/index.html` is a ~95% copy of the main visualizer engine (same CSS :7–103, same `Dot`/snapshot/`execStep`/`jumpToStep` machinery, :736+/:1474+/...). Any engine fix must currently be applied twice.
- **Reusable content if the main visualizer adds a compact Responses API flow:**
  - The 16 stage-node definitions + `tips` (:215–280) can be lifted into `N`/`tips` of the main file (or a scene-switch) — the shapes are the same schema.
  - The 3 flow step arrays (:1110–1259), especially the `loop_area` hidden-node + red loop arrow with waypoints (flowSimple step 27, :1167–1170) — a compact pattern for rendering an agentic loop on canvas.
  - The `inspStep*` functions (:868–1095) already show Responses-API-shaped payloads (`input`/`tools`, `function_call`/`function_call_output` items, 403 block) — directly portable as inspector content.
  - Extra inspector styles `guard`/`blocked` (:57–61) — small CSS addition to the main file.
- **Cross-link points:** `tips[].links` renders arbitrary URLs in overlays (ai-gateway-flow.html:294), so a compact Responses flow's node overlays can deep-link to the full `responses-api/index.html`, the 6 phase visualizers (`responses-api/phases/phase1.html`–`phase6.html`), and the 5 planning docs (linked from `responses-api/phases/index.html:55–61`). The root `index.html` already has a responses-API card (per commit 5c6bd26).
- **Caveat:** per §3, all of this content is plan-derived (Draft, May 2026). Reuse should wait for the praxis-cap fact base; anything not confirmed should be labeled planned/ghost rather than shipped as a runnable flow (consistent with `flow-visualizer-3.6-plan.md` Phase B principle).

---

## Extension recipe (summary)

1. **Re-badge for 3.5:** change ai-gateway-flow.html:118 ("RHOAI 3.4 GA") and audit the stats (:121–125) against the 3.5 fact base (A1/A5).
2. **New/changed node:** edit `N` (:209–253) + `tips` (:255–280); extend `drawBounds` (:470–568) for containers; remember IPP section rects are hard-coded (:497–527).
3. **New flow (e.g. praxis/3.6 or compact Responses):** step array near :1276 → register in `flowMap`/`flowLabels`/`flowOrder` (:1373–1375) → `<option>` in `#flow-select` (:149–154) → `inspStepXxx` + dispatcher branch (:1128–1136). For Responses API, prefer porting nodes/steps/inspector from `responses-api/index.html:215–280`, `:1110–1259`, `:868–1095` and cross-link (not duplicate) the phase visualizers via `tips[].links`.
4. **Version-dependent flows:** introduce a version key with per-version `flowMap`s + a version toggle in `.flow-bar`; mechanism currently NOT IMPLEMENTED IN CODE (planned per flow-visualizer-3.6-plan.md Phase B/C2).
5. **Path coloring for active filters:** port enmaas-flow's `activePathColor` rule (request-path blue / response-hook green) into `drawBox` (:384–397) if 3.6 adds filter-type nodes.
6. **Metering hooks:** if 3.6 includes external metering, model it as preflight + response-hook steps on a metering-service node (pattern exists only in `enmaas-flow.html`; NOT IMPLEMENTED IN CODE in `ai-gateway-flow.html`).
