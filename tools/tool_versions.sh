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
#   command   the command that prints the version; its first line is reported
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
  command -v python3 >/dev/null 2>&1 || { echo "NOT INSTALLED"; return; }
  python3 -c 'import sys; v=sys.version.split()[0]; print(v if sys.version_info >= (3, 11) else v + " - MISSING: need 3.11 or later")'
}

# WaveDromPy: PyPI package "wavedrom", command "wavedrompy". The version
# comes from the package metadata, since the command has no version option.
wavedrom_check() {
  command -v wavedrompy >/dev/null 2>&1 || { echo "NOT INSTALLED"; return; }
  python3 -c 'import importlib.metadata as m; print("WaveDromPy " + m.version("wavedrom"))' 2>/dev/null \
    || echo "wavedrompy present (version unknown)"
}

report() {
  echo "# Tool versions"
  echo "# Date:   $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "# Host:   $(hostname)"
  echo "# Kernel: $(uname -sr)"
  echo "#"
  printf '%-18s %-9s %s\n' "# Tool" "Required" "Version"
  for entry in "${TOOLS[@]}"; do
    IFS='|' read -r label required cmd <<< "$entry"
    exe=${cmd%% *}
    if command -v "$exe" >/dev/null 2>&1; then
      # The commands come only from the TOOLS list in this file.
      version=$(eval "$cmd" 2>&1 | head -n 1)
      [ -z "$version" ] && version="(no version output)"
    else
      version="NOT INSTALLED"
    fi
    printf '%-18s %-9s %s\n' "$label" "$required" "$version"
  done
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
report > "$tmp"

if [ $# -ge 1 ]; then
  mkdir -p "$(dirname "$1")"
  cp "$tmp" "$1"
fi
cat "$tmp"

# Required tools that are missing: required = yes and NOT INSTALLED / MISSING.
missing=$(awk '!/^#/ && $0 ~ /(NOT INSTALLED|MISSING)/ {
                 if (substr($0, 20, 3) == "yes") print }' "$tmp")
if [ -n "$missing" ]; then
  echo
  echo "Missing required tools:"
  echo "$missing" | awk '{ print "  - " substr($0, 1, 18) }'
  exit 1
fi
exit 0
