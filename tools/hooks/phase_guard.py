#!/usr/bin/env python3
"""
PreToolUse hook: restrict where an agent may write, and when.

Usage (in an agent's frontmatter):
    command: "python3 tools/hooks/phase_guard.py rtl"          (rtl-designer)
    command: "python3 tools/hooks/phase_guard.py tb"           (verification-engineer)
    command: "python3 tools/hooks/phase_guard.py spec pkg reports"  (spec-architect)

Rules:
  - Write / Edit / NotebookEdit: the target must be inside one of the listed
    directories, otherwise the call is blocked (exit code 2).
  - Writes into rtl/ or tb/ are additionally blocked unless spec/PHASE says
    "build", so no code can be written before the user approves the spec.
  - Bash: commands that appear to write (redirection, tee, sed -i, cp, mv, rm,
    touch, mkdir) into rtl/, tb/, spec/ or pkg/ are checked the same way.
    Running the project's own tools (tools/*.sh, tools/*.py) is always allowed.

A guardrail against mistakes, not a security boundary.
"""
import json
import os
import re
import sys

CODE_DIRS = ("rtl", "tb")
PROTECTED = ("rtl", "tb", "spec", "pkg")


def phase(root):
    try:
        with open(os.path.join(root, "spec", "PHASE")) as f:
            return f.read().strip()
    except OSError:
        return "spec"


def top_dir(path, root):
    p = os.path.normpath(os.path.join(root, path))
    r = os.path.relpath(p, root)
    return None if r.startswith("..") else r.split(os.sep)[0]


def block(msg):
    print(f"Blocked: {msg}", file=sys.stderr)
    return 2


def main():
    allowed = [a.strip("/") for a in sys.argv[1:]]
    try:
        ev = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    tool = ev.get("tool_name", "")
    args = ev.get("tool_input", {}) or {}
    root = ev.get("cwd", os.getcwd())
    ph = phase(root)

    def check_target(d, what):
        if d not in allowed:
            return block(f"this agent may only write to {', '.join(a + '/' for a in allowed)} "
                         f"({what} targets {d}/).")
        if d in CODE_DIRS and ph != "build":
            return block(f"phase is '{ph}'. Writing to {d}/ is only allowed in the build "
                         f"phase, after the user approves the spec.")
        return 0

    if tool in ("Write", "Edit", "NotebookEdit", "MultiEdit"):
        path = args.get("file_path") or args.get("notebook_path") or ""
        d = top_dir(path, root)
        if d is None:
            return block("writes outside the project are not allowed.")
        return check_target(d, tool)

    if tool == "Bash":
        cmd = args.get("command", "")
        if re.match(r"^\s*(\./)?tools/|^\s*python3\s+tools/|^\s*bash\s+tools/", cmd):
            return 0
        writes = re.search(r">|\btee\b|\bsed\s+-i|\b(cp|mv|rm|touch|mkdir|rmdir)\b", cmd)
        if writes:
            for d in PROTECTED:
                if re.search(rf"(^|[\s'\"=>(]|\./){d}(/|\s|$)", cmd):
                    rc = check_target(d, "a shell command")
                    if rc:
                        return rc
    return 0


if __name__ == "__main__":
    sys.exit(main())
