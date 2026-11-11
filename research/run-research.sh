#!/usr/bin/env bash
# Research runner — spawns one headless pi subagent per task charter.
# Modeled on spare-notes/ai-gateway-control-plane-evolution/reviews/run-review.sh.
#
# Usage:
#   ./run-research.sh <task> [task...]      # e.g. ./run-research.sh maas-3.5 praxis-inv
#   ./run-research.sh all
#
# Tasks (files in tasks/): maas-3.5  praxis-inv  praxis-cap  visualizer  ipp-ga
#
# Environment:
#   RESEARCH_MODEL    — model spec passed to pi --model (default: pi default)
#   RESEARCH_THINKING — thinking level (default: high)
#
# Output: out/<task>.md (raw subagent output), out/<task>.err (stderr)

set -uo pipefail

HERE="$(cd "$(dirname "${0}")" && pwd)"
RESEARCH_DIR="$(cd "${HERE}/.." && pwd)"   # ai-gateway-docs/
WORKSPACE="$(cd "${RESEARCH_DIR}/.." && pwd)"  # GIT/ — source checkouts are workspace-relative
OUT_DIR="${HERE}/out"
TASKS_DIR="${HERE}/tasks"
mkdir -p "${OUT_DIR}"

if [ $# -lt 1 ]; then
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

if [ "$1" = "all" ]; then
  set -- $(ls "${TASKS_DIR}" | sed 's/\.md$//')
fi

PI_ARGS=(--print --no-session --thinking "${RESEARCH_THINKING:-high}")
if [ -n "${RESEARCH_MODEL:-}" ]; then
  PI_ARGS+=(--model "${RESEARCH_MODEL}")
fi

INVOCATION_MSG="You are a research subagent with fresh context, working
headless (one-shot). Workspace root is ${WORKSPACE} — the source checkouts
are workspace-relative paths under it. Follow your charter exactly.
Read-only analysis: do not edit, commit, or create files in the source
checkouts. Write your findings to stdout only, as complete markdown.

Non-negotiable rules:
- Every claim must cite file:line (workspace-relative) from code or config
  you actually read. No claims from memory or general knowledge.
- Anything you cannot find in code must be marked NOT IMPLEMENTED IN CODE
  (optionally: 'planned per <doc path>') — never presented as fact.
- Record the commit (git rev-parse --short HEAD) of each repo you analyzed
  at the top of your output."

pids=()
run_task() {
  local task="$1" charter out
  charter="${TASKS_DIR}/${task}.md"
  if [ ! -f "${charter}" ]; then
    echo "ERROR: unknown task '${task}' (no ${charter})" >&2
    exit 1
  fi
  out="${OUT_DIR}/${task}.md"

  echo "▶ ${task}"
  ( cd "${WORKSPACE}" && pi "${PI_ARGS[@]}" "@${charter}" "${INVOCATION_MSG}" ) \
    > "${out}" 2>"${out}.err" &
  pids+=($!)
}

for task in "$@"; do
  run_task "$task"
done

fail=0
for pid in "${pids[@]}"; do
  wait "${pid}" || fail=1
done

echo
echo "Research written to ${OUT_DIR}/:"
for task in "$@"; do
  f="${OUT_DIR}/${task}.md"
  if [ -s "${f}" ]; then
    notimpl=$(grep -c "NOT IMPLEMENTED IN CODE" "${f}" 2>/dev/null || true)
    echo "  ${task}.md  ($(wc -l < "${f}") lines, NOT-IMPLEMENTED items: ${notimpl:-0})"
    [ -s "${f}.err" ] && echo "    stderr: see ${f}.err"
  else
    echo "  ${task}.md  EMPTY — check ${task}.err"
    fail=1
  fi
done

exit "${fail}"
