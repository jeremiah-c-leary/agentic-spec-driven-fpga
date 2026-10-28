#!/usr/bin/env bash
# ==============================================================================
# run_gates.sh - deterministic pass/fail gates. Agents run this; they never
# decide pass/fail themselves.
#
#   ./tools/run_gates.sh rtl     layout, compile + elaborate RTL, VSG jcl, synthesis
#   ./tools/run_gates.sh tests   compile RTL + testbenches, run all tests
#   ./tools/run_gates.sh all     everything (default)
#
# Results: reports/gates_summary.txt plus one log per gate in reports/.
# Exit code 0 only if every gate run in the chosen mode passed.
#
# Test result protocol (testbenches must follow it):
#   each test prints exactly one line per scenario example row:
#     RESULT: PASS | <rule> | <scenario> | <example>
#     RESULT: FAIL | <rule> | <scenario> | <example> | expected ... observed ...
# A test run fails if any FAIL line appears, if no RESULT lines appear, or if
# the simulator exits with an error.
# ==============================================================================
set -u
cd "$(dirname "$0")/.."

MODE="${1:-all}"
TOP=$(python3 tools/layout.py top) || { echo "cannot read spec/project_layout.toml"; exit 2; }
STD="--std=08"
WORK="build"
REP="reports"
SUMMARY="$REP/gates_summary.txt"

mkdir -p "$WORK" "$REP"
: > "$SUMMARY"
FAILED=0

say()  { echo "$*" | tee -a "$SUMMARY"; }
gate() {  # gate <name> <PASS|FAIL|SKIP> <detail>
  say "$(printf '%-12s %-5s %s' "$1" "$2" "$3")"
  [ "$2" = "FAIL" ] && FAILED=1
  return 0
}

shopt -s nullglob nocaseglob globstar
PKG=(pkg/*.vhd)
mapfile -t RTL < <(python3 tools/layout.py rtl-files)   # files in declared dirs
TB=()
for d in $(python3 tools/layout.py tb-dirs); do TB+=("$d"/*.vhd); done

say "Gate run: mode=$MODE  $(date '+%Y-%m-%d %H:%M:%S')"
say "------------------------------------------------------------"

compile_rtl() {
  rm -rf "$WORK"/*
  if [ ${#RTL[@]} -eq 0 ]; then
    gate "compile" FAIL "no RTL files in the directories declared in project_layout.toml"
    return 1
  fi
  if ghdl -i $STD --workdir="$WORK" "${PKG[@]}" "${RTL[@]}" >"$REP/compile.log" 2>&1 &&
     ghdl -m $STD --workdir="$WORK" "$TOP" >>"$REP/compile.log" 2>&1; then
    gate "compile" PASS "GHDL analyse + elaborate $TOP"
    return 0
  fi
  gate "compile" FAIL "see $REP/compile.log"
  return 1
}

# ------------------------------------------------------------------- RTL gates
if [ "$MODE" = "rtl" ] || [ "$MODE" = "all" ]; then
  if python3 tools/layout.py check-build >"$REP/layout.log" 2>&1; then
    gate "layout" PASS "matches spec/project_layout.toml"
  else
    gate "layout" FAIL "$(grep -c '^FAIL' "$REP/layout.log") findings, see $REP/layout.log"
  fi
  if compile_rtl; then
    # Style
    if command -v vsg >/dev/null 2>&1; then
      if vsg -f "${PKG[@]}" "${RTL[@]}" --style jcl >"$REP/vsg.log" 2>&1; then
        gate "vsg-jcl" PASS "zero violations"
      else
        gate "vsg-jcl" FAIL "$(grep -c '|' "$REP/vsg.log") lines of findings, see $REP/vsg.log"
      fi
    else
      gate "vsg-jcl" FAIL "vsg not installed (pip install vsg)"
    fi

    # Synthesis (Yosys + GHDL plugin; resource estimate, latch check)
    if command -v yosys >/dev/null 2>&1; then
      if yosys -m ghdl -p "ghdl $STD ${PKG[*]} ${RTL[*]} -e $TOP; \
           synth_xilinx -family xcup -flatten; tee -o $REP/synth_stat.txt stat" \
           >"$REP/synth.log" 2>&1; then
        LUTS=$(grep -E '^\s+LUT[1-6]\s' "$REP/synth_stat.txt" | awk '{s+=$2} END{print s+0}')
        FFS=$(grep -E '^\s+FD[A-Z]+\s' "$REP/synth_stat.txt" | awk '{s+=$2} END{print s+0}')
        LATCH=$(grep -cE '^\s+(LD[A-Z]+|\$_DLATCH)' "$REP/synth_stat.txt")
        if [ "$LATCH" -gt 0 ]; then
          gate "synthesis" FAIL "$LATCH latch cell types inferred, see $REP/synth_stat.txt"
        else
          gate "synthesis" PASS "~$LUTS LUTs, ~$FFS FFs, no latches (Yosys estimate)"
        fi
      else
        gate "synthesis" FAIL "see $REP/synth.log"
      fi
    else
      gate "synthesis" SKIP "yosys not installed"
    fi
  else
    gate "vsg-jcl" SKIP "compile failed"
    gate "synthesis" SKIP "compile failed"
  fi
fi

# ------------------------------------------------------------------ test gates
if [ "$MODE" = "tests" ] || [ "$MODE" = "all" ]; then
  if [ ${#TB[@]} -eq 0 ]; then
    gate "tests" FAIL "no testbenches in the declared tb directories"
  elif ! compile_rtl; then
    gate "tests" SKIP "RTL does not compile"
  elif ! ghdl -i $STD --workdir="$WORK" "${TB[@]}" >"$REP/tb_compile.log" 2>&1; then
    gate "tests" FAIL "testbench import failed, see $REP/tb_compile.log"
  else
    # Every entity in tb/ whose name starts with tb_ is a test top.
    TOPS=$(grep -hioE '^\s*entity\s+tb_[a-z0-9_]+' "${TB[@]}" | awk '{print tolower($2)}' | sort -u)
    : > "$REP/test_results.txt"
    for T in $TOPS; do
      if ! ghdl -m $STD --workdir="$WORK" "$T" >>"$REP/tb_compile.log" 2>&1; then
        gate "tests" FAIL "$T does not elaborate, see $REP/tb_compile.log"
        continue
      fi
      ghdl -r $STD --workdir="$WORK" "$T" --stop-time=10ms >"$REP/sim_$T.log" 2>&1
      RC=$?
      grep -E 'RESULT: (PASS|FAIL)' "$REP/sim_$T.log" | sed 's/.*RESULT:/RESULT:/' \
        >>"$REP/test_results.txt"
      NPASS=$(grep -c 'RESULT: PASS' "$REP/sim_$T.log")
      NFAIL=$(grep -c 'RESULT: FAIL' "$REP/sim_$T.log")
      if [ "$RC" -ne 0 ] || [ "$NFAIL" -gt 0 ] || [ "$NPASS" -eq 0 ]; then
        gate "test:$T" FAIL "$NPASS pass, $NFAIL fail, simulator exit $RC"
      else
        gate "test:$T" PASS "$NPASS pass"
      fi
    done
    [ -z "$TOPS" ] && gate "tests" FAIL "no entity named tb_* found in the tb directories"
    say "Per-scenario results: $REP/test_results.txt"
  fi
fi

say "------------------------------------------------------------"
if [ "$FAILED" -eq 0 ]; then say "OVERALL: PASS"; else say "OVERALL: FAIL"; fi
exit "$FAILED"
