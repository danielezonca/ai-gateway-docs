#!/usr/bin/env bash
# Adversarial design review — one headless pi subagent per review profile.
# Reviews the Phase B design in flow-visualizer-3.6-plan.md against the research fact base.
#
# Usage: ./run-design-review.sh [profile...]   # default: all
# Profiles: fact-checker  skeptic  visualizer  maas-maintainer  praxis-maintainer
# Env: REVIEW_MODEL, REVIEW_THINKING (default high)
# Output: out/design.<profile>.md

set -uo pipefail

HERE="$(cd "$(dirname "${0}")" && pwd)"
RESEARCH_DIR="$(cd "${HERE}/.." && pwd)"
WORKSPACE="$(cd "${RESEARCH_DIR}/.." && pwd)"
OUT_DIR="${HERE}/out"
PROFILES_DIR="${HERE}/review-profiles"
mkdir -p "${OUT_DIR}"

PROFILES=("$@")
[ $# -eq 0 ] && PROFILES=(fact-checker skeptic visualizer maas-maintainer praxis-maintainer)

PI_ARGS=(--print --no-session --thinking "${REVIEW_THINKING:-high}")
if [ -n "${REVIEW_MODEL:-}" ]; then
  PI_ARGS+=(--model "${REVIEW_MODEL}")
fi

PLAN="${RESEARCH_DIR}/flow-visualizer-3.6-plan.md"
FACTS="${RESEARCH_DIR}/research/facts.md"

INVOCATION_MSG="You are an adversarial reviewer with fresh context, working headless.
Workspace root is ${WORKSPACE}. The design document and the consolidated fact base
are attached. The detailed research fact sheets it cites live in
ai-gateway-docs/research/out/ (maas-3.5.md, praxis-inv.md, praxis-cap.md,
visualizer.md, ipp-ga.md) — read them (and the source checkouts under clones/)
when your charter asks for verification. The visualizer being redesigned is
ai-gateway-docs/ai-gateway-flow.html.
Follow your charter exactly. Be adversarial: your job is to find flaws, not to
approve. Write findings to stdout only, as markdown:

## Verdict
APPROVE / APPROVE WITH CHANGES / REJECT — one line why.
## Critical
(numbered; each with evidence)
## Important
## Minor
## Suggestions

Do not edit any file."

pids=()
for profile in "${PROFILES[@]}"; do
  charter="${PROFILES_DIR}/${profile}.md"
  if [ ! -f "${charter}" ]; then
    echo "ERROR: no charter ${charter}" >&2; exit 1
  fi
  out="${OUT_DIR}/design.${profile}.md"
  echo "▶ design ← ${profile}"
  ( cd "${WORKSPACE}" && pi "${PI_ARGS[@]}" "@${charter}" "@${PLAN}" "@${FACTS}" "${INVOCATION_MSG}" ) \
    > "${out}" 2>"${out}.err" &
  pids+=($!)
done

fail=0
for pid in "${pids[@]}"; do wait "${pid}" || fail=1; done

echo
for profile in "${PROFILES[@]}"; do
  f="${OUT_DIR}/design.${profile}.md"
  if [ -s "${f}" ]; then
    echo "── design.${profile}.md"
    sed -n '/^## Verdict/,+2p' "${f}"
    [ -s "${f}.err" ] && echo "   stderr: see ${f}.err"
  else
    echo "── design.${profile}.md EMPTY — check ${f}.err"; fail=1
  fi
done
exit "${fail}"
