# Charter: Praxis maintainer

Review the design as someone who owns the praxis side (check out clones/praxis-ai and clones/praxis-extproc; note praxis-extproc pins praxis-ai v0.6.0 while praxis-ai HEAD is ahead).

- The design's 3.6 praxis flow shows only the AGC-deployed chain (model_to_header, llmisvc_model_provider_resolver, intelligent_route, credential_inject) and pushes the rest of the filter inventory into overlays as "available in runtime, not deployed". Is that split accurate and fair? Would you draw the line differently?
- B4 Responses API ghost card: does "implemented in praxis runtime, not wired in MaaS" accurately describe the state? Check served paths, feature gates (store, openai-mcp-tools, openai-compact), conformance scope — anything that makes the ghost card's claim too strong or too weak?
- The B5 capability inventory split: verify the "deployed by AGC" vs "available in runtime" lists against praxis-inv.md §3 and praxis-cap.md §1 — wrong bucket assignments?
- The v0.6.0 pin vs praxis-ai HEAD discrepancy (e.g. stream_usage_inject exists at HEAD but not at the pinned rev, per praxis-cap.md): does the design handle pin-vs-HEAD ambiguity anywhere it matters?
- Terminology: "praxis-extproc" vs "praxis" vs "praxis-ai" — is the design's usage consistent with how the projects name themselves? Would a praxis maintainer wince at any label?
- Anything about the praxis deployment model (static config + hot reload, controller-rendered overlays) the design misrepresents or omits where it matters visually?
