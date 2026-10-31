# Agentic Spec-Driven FPGA Development

*An attempt to create an FPGA binary using BDD and agents.*

A specification phase run by an interviewing **spec-architect**, followed by a
build phase in which independent agents design, verify and review the RTL.

| Phase (`spec/PHASE`) | Start with | What happens | Code allowed |
|---|---|---|---|
| `spec` | `claude --agent spec-architect` | Interview, artifacts, architecture review, checklist | No |
| `review` | (same session) | rtl-designer, verification-engineer and reviewer read the spec and return questions; answers go into the spec | No |
| `build` | `claude --agent build-orchestrator` | Design, verification, gates, review | Yes |

Phases change only through `tools/set_phase.sh`, which runs the spec check
and records who approved. A hook stops agents writing `rtl/` or `tb/` before
the build phase, so you can try the whole specification flow safely.

## Agents (.claude/agents/)
| Agent | Role | Writes | Cannot access |
|---|---|---|---|
| spec-architect | Interviews you, writes the spec, runs the readiness review | `spec/`, `pkg/`, `reports/` | writes to `rtl/`, `tb/` |
| build-orchestrator | Coordinates the build phase | nothing | - |
| rtl-designer | RTL from the spec | `rtl/` (build phase only) | `tb/` |
| verification-engineer | Black-box tests from the spec | `tb/` (build phase only) | `rtl/` |
| reviewer | Spec review, then build review and triage | nothing | - |

## Layout
```
CLAUDE.md                  project overview, shared by every session
.claude/agents/            the five agent definitions
spec/
  PHASE                    spec | review | build
  features/                Gherkin: one for the top level, one per subsystem
  interface/               exact entity of the top and of each subsystem
  project_layout.toml      directory structure of rtl/ and tb/   <- edit to taste
  block_diagram.md         partitioning, CDC, internal contracts, decisions
  style_guide.md           coding rules
  decisions.md             decision log (D-001 ...)
  CHECKLIST.md             definition of ready
pkg/                       shared interface packages
rtl/top  rtl/<subsystem>  rtl/common      (as declared in the layout)
tb/top   tb/<subsystem>                   (as declared in the layout)
tools/
  spec_check.py            mechanical definition-of-ready checks
  set_phase.sh             phase changes, approval record, git tag on freeze
  layout.py                reads and enforces project_layout.toml
  run_gates.sh             layout, compile, VSG jcl, synthesis, tests
  hooks/deny_paths.py      keeps designer and verifier apart
  hooks/phase_guard.py     where and when each agent may write
reports/                   gate output, readiness_review.md
```

## Defining the directory structure
Edit `spec/project_layout.toml` (or ask the spec-architect to, during the
interview). Each subsystem declares its entity, any internal entities, its
`rtl_dir` and `tb_dir`, its feature file (or a waiver decision) and its
interface contract. The top level has its own directory and may contain only
the structural top entity. Generic blocks go in the shared directory.
In the build phase the **layout** gate fails on any file in an undeclared
directory, any entity in the wrong unit's directory, more than one entity per
file, or a unit with a feature file but no tests.

## One-time setup
1. Install Claude Code (macOS / Linux / WSL):
   `curl -fsSL https://claude.ai/install.sh | bash`
   (Windows PowerShell: `irm https://claude.ai/install.ps1 | iex`)
2. Install the tools: Python 3.11+, GHDL, VSG (`pip install vsg`), and
   optionally Yosys with the GHDL plugin for resource estimates.
3. `chmod +x tools/*.sh tools/*.py tools/hooks/*.py`
4. Commit the initial structure:
   `git add -A && git commit -m "Initial flow and spec" && git push`
5. Start Claude Code in this folder once (`claude`) and accept the workspace
   trust prompt. Hooks in the agent files only run in a trusted folder.

## Starting a session
Two things are not started automatically. At the start of every session,
from the root of the working copy:

```bash
cd ~/projects/agentic-spec-driven-fpga
source .venv/bin/activate     # the project's Python tools (VSG, WaveDromPy, ...)
forgejo-ctl start             # start the local Forgejo server
forgejo-ctl status            # confirm it is running
```

- **Activate `.venv` before starting Claude Code.** The agents' commands
  inherit the environment of the shell Claude Code was started from, so this
  is how they get the same Python tools as you.
- **`forgejo-ctl`** (`/usr/local/bin/forgejo-ctl`) has three commands:
  `start`, `status` and `stop`. Forgejo is started by hand rather than on
  every WSL session. Without it, pushes to `origin` and CI do not work.
- At the end of a session, `forgejo-ctl stop` shuts Forgejo down (optional).

## Trying the specification phase
    claude --agent spec-architect

Then, for example: *"Start a new design: interview me."* At any point,
`python3 tools/spec_check.py` reports what is still missing (feature files,
interface contracts, decisions, unticked checklist items), which is what the
architect will work through with you.

The architect stops before the freeze if you tell it you only want to try
the specification phase. Nothing can be written to `rtl/` or `tb/` until
`tools/set_phase.sh build` has been run with your approval.

## Checks you can run yourself at any time
    python3 tools/spec_check.py              # ready to leave the spec phase?
    python3 tools/spec_check.py --for-build  # ready to freeze?
    ./tools/run_gates.sh all                 # build-phase gates

## Notes
- The hooks are guardrails against mistakes, not security boundaries. For an
  airtight separation, run the verification agent in a separate checkout.
- `omitClaudeMd` (in the build agents) needs a recent Claude Code version;
  older versions ignore it harmlessly.
- Models: architect, rtl-designer, reviewer and orchestrator use `opus`; the
  verification-engineer uses `sonnet` so design and tests come from different
  models. Change the `model:` lines to suit.
- Yosys numbers are estimates; Vivado is the reference for timing and area.

## License
GPL-2.0 - see [LICENSE](LICENSE).
