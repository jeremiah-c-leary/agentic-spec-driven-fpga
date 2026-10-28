# Agentic Spec-Driven FPGA Development - project overview (shared by every session)

Spec-driven FPGA development with independent agents. The flow (agents,
tools, phases) is reusable; the current design is declared in
`spec/project_layout.toml`. The work happens in
three phases, recorded in `spec/PHASE` and changed only with
`tools/set_phase.sh` and the user's approval.

| Phase | Session | What happens | Code allowed? |
|---|---|---|---|
| `spec` | `claude --agent spec-architect` | Interview, artifacts, architecture review, definition of ready | No |
| `review` | `claude --agent spec-architect` | Readiness review by the three build agents; questions resolved into the spec | No |
| `build` | `claude --agent build-orchestrator` | Design, verification, gates, review | Yes (rtl/, tb/) |

## Key files
- `spec/` - the specification, owned by the spec-architect; decisions by the user.
- `spec/project_layout.toml` - directory structure of rtl/ and tb/.
- `spec/CHECKLIST.md` - definition of ready; `tools/spec_check.py` checks it.
- `tools/run_gates.sh` - the only source of pass/fail in the build phase.
- `reports/` - gate results and the readiness review.

## Rules for every session
- Only the spec-architect edits `spec/`, and only with the user's agreement.
- Every answer the user gives about the design is recorded in the spec.
- The rtl-designer never sees tests; the verification-engineer never sees RTL.
- No session decides that something passed without running the tools.
