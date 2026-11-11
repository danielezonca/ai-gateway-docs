# Task: IPP GA filter set

Repos (read-only, record HEAD commit of each):
- `clones/ai-gateway-payload-processing` (opendatahub-io downstream)
- `clones/llm-d-inference-payload-processor` (llm-d upstream)

Goal: document the GA IPP ext_proc plugin set and exact per-plugin behavior — this grounds the 3.5 side of a flow visualizer and an IPP↔praxis parity comparison.

Answer:
1. Full plugin list in the GA pipeline (build tags, plugin registry, deployment manifests): names, order, and per plugin: request behavior (path rewrites, header mutations, body transformations) and response behavior.
2. Per-plugin detail for: auth (Authorino interaction), rate limiting, api-translation (per provider: which are path-rewrite-only vs body translation — Anthropic, OpenAI, Azure, Bedrock, Vertex), apikey/credential injection (incl. SigV4), model-provider-resolver (CRDs watched, weighted selection, config merge, CycleState), body-field-to-header, base-model-to-header, maas-headers-guard.
3. Streaming support per plugin (which handle streaming responses).
4. Differences between the downstream fork and upstream llm-d IPP (which plugins are downstream-only).
5. Test coverage signals: which plugins have e2e tests proving end-to-end behavior.

Output: markdown fact sheet with a plugin table (name | provider/scope | request behavior | response behavior | streaming | citation) plus sections per question. Mark anything not found in code as NOT IMPLEMENTED IN CODE.
