#!/usr/bin/env bash
# ==============================================================================
# set_phase.sh <spec|review|build> "<approver name>"
#
# Moves the project between phases and records who approved it.
#   spec   - spec being written; no code may be written
#   review - spec_check passes; readiness review in progress; no code
#   build  - spec frozen; agents may write rtl/ and tb/
# Entering review requires tools/spec_check.py to pass.
# Entering build requires tools/spec_check.py --for-build to pass and is
# tagged in git (spec-frozen-N) when the project is a git repository.
# Only run "build" after the user has explicitly approved the spec.
# ==============================================================================
set -u
cd "$(dirname "$0")/.."
NEW="${1:-}"; WHO="${2:-}"
case "$NEW" in spec|review|build) ;; *) echo "usage: $0 <spec|review|build> \"<approver>\""; exit 2;; esac
[ -z "$WHO" ] && { echo "An approver name is required."; exit 2; }
OLD=$(cat spec/PHASE 2>/dev/null || echo spec)

if [ "$NEW" = "review" ]; then
  python3 tools/spec_check.py || { echo "Not moving to review: spec check failed."; exit 1; }
elif [ "$NEW" = "build" ]; then
  python3 tools/spec_check.py --for-build || { echo "Not moving to build: spec check failed."; exit 1; }
fi

echo "$NEW" > spec/PHASE
STAMP=$(date '+%Y-%m-%d %H:%M')
[ -f spec/phase_history.md ] || printf '# Phase history\n\n| When | From | To | Approved by |\n|---|---|---|---|\n' > spec/phase_history.md
echo "| $STAMP | $OLD | $NEW | $WHO |" >> spec/phase_history.md

if [ "$NEW" = "build" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  N=$(( $(git tag -l 'spec-frozen-*' | wc -l) + 1 ))
  git add spec pkg && git commit -qm "Spec frozen for build (approved by $WHO)" || true
  git tag "spec-frozen-$N" && echo "Tagged spec-frozen-$N"
fi
echo "Phase: $OLD -> $NEW (approved by $WHO)"
