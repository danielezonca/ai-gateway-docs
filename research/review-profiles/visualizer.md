# Charter: Visualizer engineer

Review feasibility and quality of the design against the actual single-file visualizer implementation (ai-gateway-docs/ai-gateway-flow.html, engine map in research/out/visualizer.md).

- B1 version toggle + per-version flowMaps + version-driven node visibility: is this implementable cleanly given how N, tips, drawBounds (hard-coded section rects), flowMap/flowLabels, and the inspector dispatch (per-flow inspStep* functions keyed by step number) actually work? What breaks?
- Node count explosion: 3.4/3.5 need a split two-stage Payload Processor + usage-logs path + EPP variants; 3.6 needs praxis chains + AGC node + ghost card. Is one canvas viable at LW=1250/LH=1050? Concrete layout risks?
- Inspector content: the design triples the number of flows; each needs an inspStep function with per-step payloads. Realistic effort and risk of drift?
- The migration flow is a control-plane state machine, not a request packet flow — does the Dot/arrow engine (request/response packet animation) even express it well? Propose alternatives if not.
- activePathColor port, TP dashed styling, ghost nodes, version badges: check the specific code sites named in the design (drawBox ~:384-397, splash :118, flow-select :140-154) — are the recipes correct?
- Mobile splash stats recomputation and the duplicated engine in responses-api/index.html: anything the design ignores?
- Suggest the cheapest implementation order (which C-step first) and any scope cuts that preserve the design's intent.
