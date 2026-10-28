#!/usr/bin/env python3
"""
PreToolUse hook: block a subagent from touching forbidden directories.

Usage (in a subagent's frontmatter):
    command: "python3 tools/hooks/deny_paths.py tb"

Claude Code passes the pending tool call as JSON on stdin. If any path-like
argument (file_path, path, pattern, glob, or a Bash command line) refers to a
forbidden directory, the hook exits with code 2, which blocks the call and
shows the message on stderr to the agent.

This is a guardrail against accidental access, not a security boundary: a
determined agent could still reach the files indirectly. For an airtight
barrier, keep the forbidden files in a separate checkout.
"""
import json
import os
import re
import sys


def main() -> int:
    denied = [d.strip("/") for d in sys.argv[1:] if d.strip("/")]
    if not denied:
        return 0

    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0  # not our business; let the call through

    tool = event.get("tool_name", "")
    args = event.get("tool_input", {}) or {}
    cwd = event.get("cwd", os.getcwd())

    # Collect every string argument that could name a path.
    candidates = []
    for key in ("file_path", "path", "pattern", "glob", "notebook_path", "command"):
        value = args.get(key)
        if isinstance(value, str):
            candidates.append(value)

    # Grep/Glob with no path search the whole project, which includes the
    # forbidden directories.
    if tool in ("Grep", "Glob") and not args.get("path"):
        print(
            f"Blocked: {tool} without an explicit 'path' would search forbidden "
            f"directories ({', '.join(denied)}/). Give a path such as rtl/ or spec/.",
            file=sys.stderr,
        )
        return 2

    for text in candidates:
        for d in denied:
            abs_dir = os.path.join(cwd, d)
            # Match "tb", "tb/...", "./tb/...", ".../<project>/tb/..." as a path
            # component, but not e.g. "tb_top" or "rtl/tbx".
            pattern = rf"(^|[\s'\"=:(]|\./){re.escape(d)}(/|$|[\s'\")])"
            if re.search(pattern, text) or abs_dir in text:
                print(
                    f"Blocked: this agent may not access {d}/ "
                    f"(keeps design and verification independent).",
                    file=sys.stderr,
                )
                return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
