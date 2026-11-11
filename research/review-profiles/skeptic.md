# Charter: Skeptic

Attack the design on coherence, completeness, and honesty — assume it will be shown to engineers and customers as documentation of record.

- Is the version-toggle (B1) the right primary dimension, given the facts say backend selection is per-tenant *within* 3.6? Does hiding that behind a version switch misrepresent 3.6?
- Does anything in the design still smuggle in plan-level claims as implemented behavior?
- The 3.6 praxis flow shows a very thin chain — will readers wrongly conclude praxis is weak, or wrongly assume the rich filter inventory is active? Is the B5 "deployed vs available" split enough?
- Is the migration flow (B3) a sensible animation, or does it blur control-plane mechanics into a data-plane visualizer? Would a control-plane diagram be more honest?
- Missing audiences/stakeholders: does the design serve someone debugging 3.5 GA vs someone evaluating 3.6?
- Anything over-engineered, unnecessary, or impossible to maintain (e.g., three versions × flows of hand-curated steps — maintenance burden when 3.7 lands)?
- The "don't use IPP" terminology rule (B2): is it applied consistently and is the replacement terminology unambiguous? Any places where "Payload Processor" vs "praxis-extproc" could still confuse?
