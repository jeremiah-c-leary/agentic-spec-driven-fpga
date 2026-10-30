#!/usr/bin/env bash
# ==============================================================================
# tool_versions.sh - report the versions of the project's tools.
#
#   tools/tool_versions.sh                 print the report
#   tools/tool_versions.sh <output-file>   also save it (directories created)
#
# Exit status: 0 if every required tool is present, 1 otherwise, so the script
# can be used as a check (e.g. an M0 exit criterion or a CI step).
#
# To add a tool, add a line to TOOLS below:  "label|required|command"
#   required  yes = must be installed now; no = optional or a later milestone
#   command   the command that prints the version; its first line is reported.
#             It must exit with status 0 when the tool works: a tool whose
#             version command fails is reported as not available.
# ==============================================================================
set -u

TOOLS=(
  "Claude Code|yes|claude --version"
  "Python|yes|python_check"
  "GHDL|yes|ghdl --version"
  "VSG|yes|vsg --version"
  "Git|yes|git --version"
  "GitHub CLI|yes|gh --version"
  "Forgejo|yes|forgejo --version"
  "Forgejo runner|yes|forgejo-runner --version"
  "Node.js|yes|node --version"
  "Mermaid CLI|yes|mmdc --version"
  "WaveDrom|yes|wavedrom_check"
  "Java|yes|java -version"
  "PlantUML|yes|plantuml -version"
  "Vivado|no|vivado -version"
)

# Python must be 3.11 or later (the tools use the built-in TOML reader).
python_check() {
  command -v python3 >/dev/null 2>&1 || { echo "NOT INSTALLED"; return 1; }
  python3 -c 'import sys; v=sys.version.split()[0]; ok=sys.version_info >= (3, 11); print(v if ok else v + " - MISSING: need 3.11 or later"); sys.exit(0 if ok else 1)'
}

# WaveDromPy: PyPI package "wavedrom", command "wavedrompy". The version
# comes from the package metadata, read with the Python interpreter that
# wavedrompy itself runs with (it may be a pipx or virtual environment).
wavedrom_check() {
  local exe line py
  exe=$(command -v wavedrompy) || { echo "NOT INSTALLED"; return 1; }
  line=$(head -n 1 "$exe")
  line=${line#\#!}
  set -- $line
  if [ "$(basename "${1:-}")" = "env" ]; then py=${2:-python3}; else py=${1:-python3}; fi
  command -v "$py" >/dev/null 2>&1 || py=python3
  "$py" -c 'import importlib.metadata as m; print("WaveDromPy " + m.version("wavedrom"))' 2>/dev/null \
    || echo "wavedrompy present (version unknown)"
}

MISSING_REQUIRED=()

report() {
  echo "# Tool versions"
  echo "# Date:   $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "# Host:   $(hostname)"
  echo "# Kernel: $(uname -sr)"
  echo "#"
  printf '%-18s %-9s %-10s %s\n' "# Tool" "Required" "Available" "Version"
  for entry in "${TOOLS[@]}"; do
    IFS='|' read -r label required cmd <<< "$entry"
    exe=${cmd%% *}
    if command -v "$exe" >/dev/null 2>&1; then
      # The commands come only from the TOOLS list in this file.
      output=$(eval "$cmd" 2>&1)
      status=$?
      version=$(printf '%s\n' "$output" | head -n 1)
      [ -z "$version" ] && version="(no version output)"
    else
      version="NOT INSTALLED"
      status=127
    fi
    # Available = found AND its version command succeeded. A broken file,
    # missing library or crash makes the command fail, so the tool is not
    # available; the first line of its output is shown as the reason.
    if [ "$status" -ne 0 ]; then
      available="no"
    else
      case "$version" in
        *"NOT INSTALLED"*|*MISSING*) available="no" ;;
        *)                           available="yes" ;;
      esac
    fi
    [ "$available" = "no" ] && [ "$version" = "NOT INSTALLED" ] && version="-"
    if [ "$available" = "no" ] && [ "$required" = "yes" ]; then
      MISSING_REQUIRED+=("$label")
    fi
    printf '%-18s %-9s %-10s %s\n' "$label" "$required" "$available" "$version"
  done
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
report > "$tmp"     # runs in this shell, so MISSING_REQUIRED is kept

if [ $# -ge 1 ]; then
  mkdir -p "$(dirname "$1")"
  cp "$tmp" "$1"
fi
cat "$tmp"

if [ ${#MISSING_REQUIRED[@]} -gt 0 ]; then
  echo
  echo "Missing required tools:"
  printf '  - %s\n' "${MISSING_REQUIRED[@]}"
  exit 1
fi
exit 0
