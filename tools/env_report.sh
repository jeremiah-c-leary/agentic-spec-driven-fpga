#!/usr/bin/env bash
# ==============================================================================
# env_report.sh - describe the development machine: hardware, Windows, WSL
# and Linux. Companion to tool_versions.sh (which reports the tools).
#
#   tools/env_report.sh                 print the report
#   tools/env_report.sh <output-file>   also save it (directories created)
#
# Inside WSL it also asks Windows (through WSL interop) for the Windows and
# WSL versions, the physical RAM, the physical disks and the WSL settings.
# Anything it cannot determine is reported as "unknown", never guessed.
# The report is informational: the exit status is always 0.
# ==============================================================================
set -u

# Run a Windows command from WSL with a time limit; strip CR and the NUL bytes
# that some Windows tools (e.g. wsl.exe) emit as UTF-16.
win() {
  command -v "$1" >/dev/null 2>&1 || return 1
  (cd /mnt/c 2>/dev/null || cd /; timeout 20 "$@" 2>/dev/null) | tr -d '\r\000'
}

winps() {
  win powershell.exe -NoProfile -NonInteractive -Command "$1"
}

field() {  # field <label> <value>
  printf '%-22s %s\n' "$1" "${2:-unknown}"
}

report() {
  echo "# Development environment"
  echo "# Date:   $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "# Host:   $(hostname)"
  echo

  # ---------------------------------------------------------------- processor
  echo "## Processor"
  model=$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
  sockets=$(lscpu 2>/dev/null | awk -F: '/^Socket\(s\)/ {gsub(/ /,"",$2); print $2}')
  cores=$(lscpu 2>/dev/null | awk -F: '/^Core\(s\) per socket/ {gsub(/ /,"",$2); print $2}')
  physical=""
  [ -n "$sockets" ] && [ -n "$cores" ] && physical=$((sockets * cores))
  field "Model" "$model"
  field "Physical cores" "${physical:-unknown} (visible to Linux)"
  field "Logical processors" "$(nproc 2>/dev/null) (visible to Linux)"
  echo

  # ------------------------------------------------------------------- memory
  echo "## Memory"
  mem_kb=$(awk '/^MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)
  swap_kb=$(awk '/^SwapTotal/ {print $2}' /proc/meminfo 2>/dev/null)
  [ -n "$mem_kb" ] && field "Available to Linux" "$(awk -v k="$mem_kb" 'BEGIN {printf "%.1f GiB", k/1048576}')"
  [ -n "$swap_kb" ] && field "Swap" "$(awk -v k="$swap_kb" 'BEGIN {printf "%.1f GiB", k/1048576}')"
  host_bytes=$(winps '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory')
  if [ -n "$host_bytes" ]; then
    field "Physical (Windows)" "$(awk -v b="$host_bytes" 'BEGIN {printf "%.1f GiB", b/1073741824}')"
  else
    field "Physical (Windows)" "unknown"
  fi
  echo

  # ------------------------------------------------------------------ storage
  echo "## Storage"
  root=$(df -h / 2>/dev/null | awk 'NR==2 {print $2 " total, " $4 " free"}')
  field "Linux root (/)" "$root"
  repo=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)
  if [ -n "$repo" ]; then
    field "Working copy" "$repo"
  fi
  disks=$(winps 'Get-PhysicalDisk | Sort-Object DeviceId | ForEach-Object { "{0} | {1} | {2:N0} GB" -f $_.FriendlyName, $_.BusType, ($_.Size/1GB) }')
  if [ -n "$disks" ]; then
    echo "Physical disks (Windows):"
    printf '%s\n' "$disks" | sed 's/^/  - /'
  else
    field "Physical disks" "unknown"
  fi
  echo

  # ------------------------------------------------------- operating systems
  echo "## Operating systems"
  distro=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
  field "Linux distribution" "$distro"
  field "Linux kernel" "$(uname -r)"
  field "WSL distribution" "${WSL_DISTRO_NAME:-not running in WSL}"
  if grep -qi microsoft /proc/version 2>/dev/null; then
    winver=$(win cmd.exe /c ver | grep -m1 -i 'version' | sed 's/^ *//')
    field "Windows" "$winver"
    wslver=$(win wsl.exe --version | grep -m1 -i 'WSL' | sed 's/^ *//')
    field "WSL" "$wslver"
    # WSL settings that limit memory and processors (.wslconfig in the
    # Windows user profile). No file means WSL defaults: half the RAM.
    profile=$(win cmd.exe /c 'echo %USERPROFILE%')
    cfg=""
    if [ -n "$profile" ] && command -v wslpath >/dev/null 2>&1; then
      cfg="$(wslpath "$profile" 2>/dev/null)/.wslconfig"
    fi
    if [ -n "$cfg" ] && [ -f "$cfg" ]; then
      settings=$(grep -Ei '^\s*(memory|processors|swap)\s*=' "$cfg" | tr -d '\r' | sed 's/^ *//' | paste -sd ',' -)
      field ".wslconfig" "${settings:-present, no memory/processor limits}"
    else
      field ".wslconfig" "none (WSL defaults: half of physical RAM)"
    fi
  else
    field "Windows" "not running in WSL"
  fi
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
report > "$tmp"

if [ $# -ge 1 ]; then
  mkdir -p "$(dirname "$1")"
  cp "$tmp" "$1"
fi
cat "$tmp"
exit 0
