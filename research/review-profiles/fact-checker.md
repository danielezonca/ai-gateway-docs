# Charter: Fact-checker

Verify every factual claim in the Phase B design against the attached fact base and, where needed, the underlying research fact sheets and source checkouts. You are checking the DESIGN's accuracy, not re-doing the research.

Specifically:
- B3 flow table: is each step outline consistent with the code-verified per-version matrix in facts.md? Any step that implies behavior not present in the cited tag (v0.1.1 / v0.2.1 / HEAD)?
- B2 node/chain claims: plugin names, chain order, pre/post-auth split, usage-logs identity mechanism per version, EPP positioning per version — verify against maas-3.5.md, ipp-ga.md, praxis-inv.md and the git tags if needed (`git -C clones/models-as-a-service show v0.2.1:...`).
- B4/B5: praxis runtime claims (deployed-by-AGC chain vs praxis-ai capabilities) — verify against praxis-inv.md §3 and praxis-cap.md.
- B1 version matrix summary — verify against facts.md's code-validated matrix.
- Flag any claim in the design that contradicts the fact base or overstates implementation status.
Also flag the opposite: places where the design is more conservative than the facts support (features implemented in code but hidden).
