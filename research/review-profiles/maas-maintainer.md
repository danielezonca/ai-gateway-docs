# Charter: MaaS maintainer

Review the design as someone who owns models-as-a-service (check out clones/models-as-a-service, including tags v0.1.1/v0.2.1) and will be blamed if the visualizer misrepresents the product.

- 3.4 vs 3.5 vs 3.6 framing: would you sign off on this as an accurate representation of what each release ships? Anything the version matrix misses that a maintainer would consider significant (e.g., auth behavior changes, TRLP changes, error-body format, Kserve/llm-d version coupling)?
- The migration flow: does the step outline (fingerprint gate → compat check → cleanup → AGC claim → steady) match reconcilePayloadProcessingSwitch well enough to animate? Any state missing (blocked marker, risk markers, pending reasons)? Is showing only the happy path dishonest?
- Per-tenant backend selection in 3.6: is the design's treatment (legacy tenant flow vs praxis tenant flow) faithful to platform_context.go semantics (annotation absent = praxis default)?
- Anything in the design that describes behavior that only exists on main but will NOT be in the shipped RHOAI 3.6 (given 3.6 is in dev and cut dates)? How should the visualizer label not-yet-released behavior?
- Terminology: as a maintainer, do the replacement terms ("Payload Processor (ext_proc)", "praxis-extproc", "legacy payload processing") match how the team actually talks? Better suggestions?
