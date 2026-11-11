# Task: Visualizer current-state inventory

Repo: `clones/ai-gateway-docs` (read-only, record its HEAD commit). Files: `ai-gateway-flow.html` (main), `responses-api/index.html`, `responses-api/01-overview.md` … `05-plan.md`, `responses-api/phases/`.

Goal: map the exact structure and extension points of the flow visualizer so 3.5/3.6 updates can be planned precisely.

Answer:
1. `ai-gateway-flow.html` architecture: node definitions (N), overlay tips (tips), flow definitions (flowExt/flowInc/flowAuth/flowRL, flowMap, flowLabels), step-array format (what each step entry does: glow, animate line, inspector content), metering/hooks steps, filter/path coloring. Give the line ranges of each block and the minimal recipe to add (a) a new node, (b) a new flow, (c) version-dependent badges.
2. Version claims in both HTML files: where "3.4"/GA badges appear, and any other release-related claims.
3. `responses-api/index.html`: what flows/steps it visualizes; is its content code-grounded or derived from the planning docs in responses-api/*.md? Flag specific claims that would need verification against praxis-ai code (list them — do not verify here).
4. Stale-vs-current: which filter names, plugin behaviors, or steps in `ai-gateway-flow.html` reference things that noyitz/main recently changed ("live EnMaaS filters", metering hooks, path colors) — summarize what the latest state claims.
5. Duplication/reuse assessment: what content in responses-api/index.html could be reused or cross-linked if the main visualizer adds a compact Responses API flow.

Output: markdown fact sheet with file:line citations, ending with a short "extension recipe" section. Mark anything not found as NOT IMPLEMENTED IN CODE.
