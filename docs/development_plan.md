# Development Plan: Agentic Spec-Driven FPGA Development

**Status:** covers milestones M0 and M1. Later milestones are listed in the
overview but are planned in detail only when the previous milestone is
complete (see section 2).

**Audience:** the owner, and every agent working in this repository. Agents
must follow this plan; where an agent definition and this plan disagree, stop
and ask the owner.

---

## 1. Purpose

This project tests a claim:

> A design can be specified as an executable Gherkin specification and then
> designed, verified, built and proven on hardware by independent AI agents,
> with the owner making every decision and writing no design or test code.

The end goal is a live demonstration: change one rule in a feature file, and
about ten minutes later the change is running on a development board and
proven by tests on live Ethernet traffic.

The experiment is only credible if its rules and success criteria are fixed
before the results are known. This plan records both.

## 2. How this plan evolves

The plan grows with the project, the same way the design does: a *walking
skeleton*. Each milestone adds only the process it needs.

- Only the current and next milestone are planned in detail.
- Every milestone ends with a short retrospective: what worked, where the
  process creaked, what to change.
- The retrospective's conclusions are written into this plan before the next
  milestone starts.

## 3. Operating principles

These apply from M0 onward. They are project policy; changing one is a flow
change (section 7.4) and needs the owner's approval and a decision-log entry.

1. **The owner is the gate.** The owner makes every design decision, and
   personally performs every gate: entering review, freezing the spec, and
   merging to `main`. Agents may request a gate; they never pass one.
2. **Every answer goes into the spec.** Anything agreed in conversation that
   matters to design or verification is recorded in `spec/`. Nothing exists
   only in a conversation.
3. **The spec has a single writer.** Only the spec-architect edits `spec/`,
   and only with the owner's agreement.
4. **Design and verification are independent.** The rtl-designer never sees
   tests; the verification-engineer never sees RTL. Failure reports between
   them describe behaviour only (scenario, stimulus, expected, observed).
5. **Scripts decide pass or fail.** No agent declares that something passed.
   Gates are run by tools, locally and in CI.
6. **Infrastructure belongs to the owner.** No agent may modify `tools/`,
   `.claude/`, CI workflows or policy files.
7. **Every intervention is recorded.** Each time the owner steps in, it is
   logged by category (section 13). The log is part of the result.
8. **Every change is a commit.** No change to the repository is left
   uncommitted, and each commit holds one logical change. Agents commit their
   own work under their own names. Changes made from the Claude chat
   (planning and documentation) are written by the chat and committed by the
   owner, with the chat recorded as author
   (`--author="Claude (chat) <claude-chat@localhost>"`, trailer
   `Agent: claude-chat`). The chat cannot run git; it writes files, and the
   owner reviews and commits them.

## 4. Roles

| Role | Kind | Active from | Writes | Cannot access |
|---|---|---|---|---|
| Owner | Human | M0 | Decisions, gates, infrastructure | - |
| spec-architect | Main session | M1 | `spec/`, `pkg/`, `reports/` | Writes to `rtl/`, `tb/` |
| build-orchestrator | Main session | M1 | Nothing (delegates) | - |
| rtl-designer | Subagent | M1 | `rtl/` (build phase only) | `tb/` |
| verification-engineer | Subagent | M1 | `tb/` (build phase only) | `rtl/` |
| reviewer | Subagent | M1 | Nothing (read-only) | - |
| physical-engineer | Subagent | M2 | Constraints, Vivado build, release package | `tb/`, `hwtest/` |
| integration-engineer | Subagent | M2 | `hwtest/`, programs the board | `rtl/`, `tb/` |
| Claude (chat) | Chat assistant | M0 | `docs/`, with the owner's review | Never commits; does not edit `spec/` |

**Spec-architect.** Interviews the owner and turns the answers into the
specification: feature files, block diagram, interface contracts, project
layout, decision log. Presents options with trade-offs; never decides.

**Build-orchestrator.** Coordinates the build phase: delegates to the build
agents, runs the gates, routes findings. Writes no code and no spec.

**Rtl-designer.** Implements synthesizable VHDL-2008 from the frozen spec,
following the style guide and the project layout.

**Verification-engineer.** Writes black-box, self-checking testbenches from
the feature files, one result line per scenario example row.

**Reviewer.** Read-only. Reviews the spec for consistency in the review
phase; in the build phase, reviews RTL, tests and traceability, and triages
every failure as an RTL bug, a test bug or a spec gap.

**Physical-engineer and integration-engineer** join in M2. Their roles, the
release package and its hand-off checklist will be planned in detail in the
M2 section.

**Claude (chat).** Planning, documentation and design discussion with the
owner, from the Claude desktop app. Reads the repository to review real
files; writes only what the owner asks for, mainly in `docs/`. Does not edit
`spec/`, which stays the spec-architect's: if a discussion changes the
design, the decision goes to the spec-architect. Cannot run git; the owner
commits its changes (principle 8).

**How agents communicate.** In this project the agents run as *subagents*,
which never message each other directly. Information flows through a main
session (the spec-architect or the build-orchestrator), which delegates tasks
and receives each agent's report, or through files one agent writes and
another reads. This is deliberate. A failing test is a disagreement between
the design and the test, so it goes first to the reviewer for triage; only a
confirmed RTL bug reaches the rtl-designer, described as behaviour. Direct
messaging between agents (Claude Code's experimental *agent teams*) is not
used in the build phase, because it would let design and verification
converge on a shared answer instead of checking each other.

## 5. Phases and gates

Work on each change moves through three phases, recorded in `spec/PHASE`.

| Phase | Main session | What happens | Code allowed |
|---|---|---|---|
| `spec` | `claude --agent spec-architect` | Interview, artifacts, definition of ready | No |
| `review` | `claude --agent spec-architect` | Readiness review; questions resolved into the spec | No |
| `build` | `claude --agent build-orchestrator` | Design, verification, gates, review | Yes |

### 5.1 Spec and review process map

![Spec and review phase process map](img/spec_review_process_map.svg)

Dashed boxes are tool runs, drawn in the lane of whoever runs the tool.

- **Both gates are in the owner's lane.** The owner runs `set_phase review`
  and `set_phase build` personally. Each writes the phase file; the freeze
  also creates a tag.
- **The architect starts the review after the gate.** The arrow from the
  owner's `set_phase review` to "Start review" is the owner telling the
  architect, in the conversation, that the gate is open. The architect may
  confirm by reading the phase file, but does not proceed on its own.
- **The architect only requests the gates.** "Request review" and "Request
  freeze" are in its lane; the decision is the owner's.
- **The reviewer runs its own `spec_check.py`** in the readiness review, as an
  independent check of the architect's claim that the spec is complete.

### 5.2 Making the gates real

Agents run commands as the owner's Linux user, so a name on a commit does not
by itself prove the owner made the decision. M0 adds these protections:

1. Agents cannot run `set_phase` (blocked by hooks).
2. Agents cannot write `spec/PHASE` or `spec/phase_history.md` directly.
3. `set_phase` refuses to run unless attached to an interactive terminal, and
   asks the owner to type the phase name to confirm.
4. Optionally, `set_phase build` creates a signed tag (open decision O-2).

## 6. Build phase in M1 (simulation only)

M1 has no hardware stages. The build phase is:

1. The orchestrator delegates to the rtl-designer and the
   verification-engineer **in parallel**, both working from the frozen spec.
2. The orchestrator runs the gates: layout, compile, VSG `jcl` style, GHDL
   synthesis check (synthesizable, no inferred latches), and simulation tests.
3. The orchestrator asks the reviewer for a build review and triage.
4. Findings are routed:
   - RTL bug, or architecture/layout/style must-fix: to the rtl-designer;
   - test bug: to the verification-engineer;
   - spec gap: **stop**. The owner takes it to the spec-architect in a new
     session, and the phase returns to review.
5. Steps 2 to 4 repeat, at most five iterations; then the orchestrator stops
   and reports what is blocking.

**Failure reports are structured files**, not prose (an M0 task): fixed fields
for scenario, stimulus, expected and observed, passed between agents unchanged.
This limits what the orchestrator can leak between the independent agents.

The build-phase process map will be drawn in the same style as section 5.1
once M1 has been run.

## 7. Configuration management

### 7.1 Repositories

- **Forgejo, on the owner's machine, is the working server.** Agents push
  change branches to it, CI runs there, and merges happen there.
- **GitHub is the archive and the place progress is published.** The owner
  decides when to publish, through a push mirror from Forgejo. Agents never
  communicate with GitHub.

### 7.2 Branches and merging

- **`main` is always green**: it only contains work that passed every stage
  required for its change class (7.4) at that milestone.
- **One short-lived branch per change**, e.g. `cr/001-m1-build-id-uart`. The
  whole life of a change (spec, freeze, build, review) happens on its branch.
- **Merging is the owner's acceptance gate.** Only the owner merges.
- **Fast-forward merges only.** `main` moves to exactly the commit that was
  tested. If `main` has moved, the branch is rebased and re-verified.
- **No squashing.** Every iteration (failed attempts, findings, fixes) stays
  in the history; it is experiment data.

### 7.3 Tags and commits

| Tag | Created by | Meaning |
|---|---|---|
| `spec-frozen-N` | Owner, via `set_phase build` | The exact spec a build was made from |
| `mN-complete` | Owner | The merged state that met milestone N's exit criteria |

- **Each agent commits under its own name** (e.g. author `rtl-designer`), with
  trailers recording the role and the frozen spec it worked from:
  `Agent: rtl-designer`, `Spec-Tag: spec-frozen-1`.
- **The owner's commits carry the owner's name.** `git log` alone then shows
  which work was human and which was agent.

### 7.4 Change classes and merge requirements

Each change is classified by the files it touches; when several areas are
touched, the strictest class applies. **This table is the initial proposal.
The final policy is decided by the owner with the spec-architect in M0 and
recorded in the decision log; agents cannot change it.**

| Class | Typical paths | Required before merging |
|---|---|---|
| Design | `spec/`, `rtl/`, `pkg/`, constraints | All stages for the milestone |
| Verification | `tb/`, `hwtest/` | The changed tests run (simulation or hardware); no rebuild |
| Flow and infrastructure | `tools/`, `.claude/`, workflows, policy | CI, owner review, and a flow regression run on the last accepted design |
| Documentation | `docs/`, README, presentation material | Owner approval; links and diagrams render |

A flow change does not touch the design, but it changes how the design is
judged; hence the regression run.

### 7.5 Design ID

From M2, each bitstream carries a **design ID**: a hash of the design inputs
only (`rtl/`, `pkg/`, constraints, design-relevant spec files), not of the
whole commit. Documentation or flow changes leave it unchanged, so earlier
hardware results stay valid; any design change produces a new ID. The release
manifest records both the design ID and the commit it was built from.

### 7.6 Exceptions

A change may be merged without a required stage only by a stated, logged
exception. Every exception records:

1. what was skipped;
2. why;
3. what risk that leaves;
4. how and when it will be closed.

The pull request template contains these fields; CI refuses a pull request
that lacks a required result unless they are filled in. Every exception is
copied to `docs/exceptions.md`.

## 8. Continuous integration

CI exists from M0, before any design work, so every milestone is built under it.

- **Server:** Forgejo, running in WSL. It is not started automatically: the
  owner starts it at the beginning of a session with `forgejo-ctl start`
  (section 9.1).
- **Workflows:** in `.forgejo/workflows/`. They only call the project's own
  gate scripts, so all gate logic lives in one place.
- **Runner:** the Forgejo runner, registered with a `host` label so jobs run
  directly on the machine with the locally installed tools (Vivado from M2).
  It runs as its own Linux user, so agents cannot alter its workspace or
  results.
- **Checkout:** common actions such as `actions/checkout` need Node.js; with a
  host runner, either install Node.js for the runner user or check out with
  plain `git` in the workflow.
- **Branch protection on `main`:** required CI checks, linear history, no
  force pushes, merging restricted to the owner.
- **Publishing:** a push mirror to GitHub, triggered by the owner.
- **Backups:** the Forgejo data directory (pull requests, reviews, CI history)
  is backed up periodically; the GitHub mirror only preserves git history.

## 9. Tools and environment

Versions are recorded in M0 and pinned; every result names the versions that
produced it.

| Tool | Purpose | Used by | Runs in | From | Version |
|---|---|---|---|---|---|
| Claude Code | Runs the agents | All agents | WSL | M0 | 2.1.312 |
| Python 3.11+ | Spec check, layout check, hooks | Gates, hooks | WSL | M0 | 3.14.4 |
| GHDL | VHDL-2008 compile, simulation, and synthesis check (no latches) | Gates | WSL | M0 | 5.0.1 (Ubuntu package) |
| VSG 3.35 | Style check, `jcl` style | Gates | WSL | M0 | 3.35.0 |
| Git, GitHub CLI | Version control; owner's publishing | Owner | WSL | M0 | 2.53.0 / 2.46.0 |
| Forgejo, Forgejo runner | Local git server and CI | CI | WSL | M0 | 17.0.1 / v13.1.0 |
| Node.js | Runs the Mermaid CLI; CI checkout actions | CI, docs | WSL | M0 | v22.23.2 |
| Mermaid (+ CLI) | Diagrams in Markdown; export for slides | Architect, docs | WSL | M0 | 11.12.0 |
| WaveDrom (WaveDromPy, Python) | Timing diagrams and register bit-field maps; rendered to SVG with `wavedrompy` | Architect, docs | WSL | M0 | WaveDromPy 2.0.3.post3 |
| PlantUML (needs Java) | Text diagrams, including swimlane process maps; rendered to SVG | Architect, docs | WSL | M0 | 1.2026.9 (Java 25.0.4.1) |
| Vivado (free edition) | Synthesis, implementation, bitstream | Physical-engineer | WSL | M2 | 2026.1 (installed early) |
| Vivado hardware server | Programming over JTAG | Integration-engineer | Windows | M2 | - |
| ELFWS | Warning suppression with justifications; gate on new warnings | Physical-engineer | WSL | M2 | - |
| stacv | External interface constraints and validation | Physical-engineer | WSL | M2 | - |
| Python + Npcap | Lab watcher, raw Ethernet tests | Lab | Windows | M2/M3 | - |
| GitHub Releases | Milestone release packages | Owner | GitHub | M2 | - |

To record versions, run `tools/tool_versions.sh`; it lists every tool, marks
the required ones, and exits with an error if any required tool is missing.
The versions above are from `docs/evidence/m0/tool_versions.txt`
(2026-10-30), on Ubuntu 26.04 in WSL2, on a dedicated NVMe drive.

**Yosys is not used** (decided 2026-10-30). GHDL's own synthesis covers the
synthesizability and latch checks; resource estimates are not useful in this
flow, and real utilization comes from Vivado in M2. Removing Yosys also
removes its GHDL plugin, which proved fragile to install. Formal
verification (e.g. SymbiYosys) would bring both back; see O-11.

**Artifact storage.** Releases (from M2) are kept in a local `releases/`
directory and published per milestone as GitHub Releases. The release
manifest (design ID, versions, file hashes) is designed so that moving to an
artifact repository such as Artifactory later would change only where
releases are stored, not the process.

### 9.1 Starting a session

Two things are not started automatically. At the start of every session,
from the root of the working copy:

```bash
cd ~/projects/agentic-spec-driven-fpga
source .venv/bin/activate     # the project's Python tools (VSG, WaveDromPy, ...)
forgejo-ctl start             # start the local Forgejo server and its runner
forgejo-ctl status            # confirm both are running and healthy
```

Then read the latest entry in `docs/journal/` (section 13.1) to pick up where
the last session left off.

- **Python environment.** The project's Python tools are installed in a
  virtual environment, `.venv`, at the root of the working copy (not
  committed). It must be activated **before** Claude Code is started, because
  the agents' commands inherit the environment of the shell that started it.
- **Forgejo and its runner.** Started by hand rather than on every WSL
  session, with `forgejo-ctl`: `start`, `stop`, `restart`, `status` and
  `logs [forgejo|runner]`. `status` checks that Forgejo answers over HTTP and
  that the runner is running. Without them, pushes to `origin` and CI do not
  work. The script's source is `tools/forgejo-ctl`, installed to
  `/usr/local/bin` from there; the full setup is in `docs/setup/forgejo.md`.
- **CI must not depend on the owner's session.** The runner runs as its own
  user and does not inherit the owner's shell, so CI workflows activate the
  project's Python environment themselves.

### 9.2 Development environment

The project runs on one Windows PC with WSL2. `tools/env_report.sh` records
the machine's details; the current report is
`docs/evidence/m0/environment.txt` (2026-10-30).

| Item | Value |
|---|---|
| Processor | AMD Ryzen 7 3700X: 8 cores, 16 logical processors |
| RAM | 16 GB physical; 7.7 GiB available to Linux (no `.wslconfig`, so WSL defaults to half) |
| Drive 1 | Samsung 970 EVO, 500 GB NVMe: Windows only |
| Drive 2 | Samsung 990, 1 TB NVMe: Ubuntu 26.04 (WSL2), the working copy, Vivado |
| Drive 3 | WD, 2 TB SATA hard drive: additional storage |
| Windows | 10.0.26200 |
| WSL | 3.0.3.0, distribution `Ubuntu-26.04` |
| Linux | Ubuntu 26.04.1 LTS, kernel 6.18.54.1-microsoft-standard-WSL2 |

**Under consideration:**

- **Memory for Vivado.** With 7.7 GiB available to Linux, Vivado will share
  little memory with everything else from M2. Options: give WSL more of the
  current 16 GB with a `memory=` setting in `.wslconfig`, or upgrade the RAM
  (32 GB or more). Decide after measuring memory use during a real build.
- **GitLab instead of Forgejo**, if the company adopts it and the RAM allows.

## 10. Directories and ownership

Directories are named after what they contain, not after agents. Ownership
is declared in one place, an ownership map (introduced in M0), which the hooks
and CI read:

- which agent may write each area, and in which phase;
- which agents may not read it;
- which flow stages each agent may run;
- the change class of each area (7.4).

Agents never call vendor tools directly; they run named stages of the shared
gate scripts, and a per-agent hook permits only that agent's stages plus
read-only commands. A separate local Linux user for the agents (true
isolation rather than guardrails) is a later hardening option.

## 11. Diagrams

| Tool | Use for | Source |
|---|---|---|
| **Mermaid** (default) | Block diagrams, flowcharts, state machines, sequences | Inside the Markdown document |
| **WaveDrom** | Timing diagrams (e.g. UART framing) and register bit-field maps in the spec | `.json` file next to its SVG |
| **PlantUML** | Diagrams Mermaid lays out poorly, especially swimlane process maps | `.puml` file next to its SVG |
| **Hand-drawn SVG** | Only where exact layout carries meaning and no text tool can express it | The SVG itself |

- **Text first.** Diagram sources are text so they are versioned, diffable
  and editable by agents. WaveDrom matters most here: timing and register
  diagrams in `spec/` are part of the specification the agents read, not
  just illustrations.
- **Rendering.** GitHub and Forgejo display Mermaid directly. WaveDrom and
  PlantUML sources are rendered to SVG by a script; the source and its SVG are
  committed together, with the same base name. CI re-renders every diagram
  and fails if a committed SVG is out of date.
- **Location.** Diagrams live next to the document that uses them:
  `spec/` diagrams in `spec/`, plan and other document diagrams in `docs/img/`.
- The spec and review process map (section 5.1) is currently hand-drawn SVG;
  it may later be converted to PlantUML.

## 12. Milestones

| Milestone | Slice | New risk it retires |
|---|---|---|
| **M0** | Environment, tools, process tooling, local CI | Tooling and process infrastructure |
| **M1** | Board reports its build ID over UART, simulation only | Spec-to-RTL with independent agents, on the first real design |
| M2 | The M1 design on the board: build, program, hardware test | The whole chain on hardware |
| M3 | Ethernet pass-through, port A to port B | PHY interfaces, clocking, I/O timing |
| M4 | One filter rule, then the red-to-green demonstration | The spec-change loop on hardware |
| M5 | Timed rehearsals of the ten-minute loop | Speed and repeatability |

M2 onward will also need the development board (trade study in progress), the
Windows lab and the test bench; they are planned when M1 is complete.

### 12.1 M0: Environment and process tooling

**Goal:** everything M1 needs exists and is verified, including CI.

**Status** (updated as tasks finish; the task list below is the plan as
originally fixed)

| Task | Status |
|---|---|
| 1. Tools installed, versions recorded | Done: `tools/tool_versions.sh`, `docs/evidence/m0/tool_versions.txt` |
| 2. Gate protections | Not started |
| 3. Structured failure reports | Not started |
| 4. Ownership map and merge policy file | Not started |
| 5. Policy interview | Not started |
| 6. Local CI | In progress: Forgejo, control script and runner done (`docs/setup/forgejo.md`); accounts, repository, branch protection, workflow, mirror and `origin` still to do |
| 7. Verify early (runner user reaches the Windows side) | Not started |
| 8. Backups | Not started |

**Added during M0** (work the original task list did not foresee):

- Development environment recorded: `tools/env_report.sh`, section 9.2. Done.
- Moved to Ubuntu 26.04 on a dedicated NVMe drive. Done.
- Yosys dropped from the toolchain (section 9). Done.
- `requirements.txt` pinning the Python tools, for CI and for rebuilding
  `.venv`. Not started.
- Diagram render script and CI check for out-of-date SVGs (section 11). Not
  started.
- Quick latch test on GHDL 5.0.1, confirming the synthesis gate. Not started.

**Tasks**

1. **Tools.** Install the M0 tools (section 9) and record their versions.
2. **Gate protections** (section 5.2):
   - `set_phase.sh`: interactive-terminal check and typed confirmation;
   - hooks: protect `spec/PHASE`, `spec/phase_history.md`, `tools/`,
     `.claude/`, workflows and policy files from every agent; block
     `set_phase`, `git push` to GitHub and the GitHub CLI for every agent;
   - spec-architect instructions: ask the owner to run `set_phase`, never run it.
3. **Structured failure reports:** a fixed-field file format for findings
   passed between agents, and the agent instructions to use it.
4. **Ownership map and merge policy file**, machine-readable, read by hooks
   and CI.
5. **Policy interview.** The owner and the spec-architect settle the merge
   policy and change classes (7.4), the exception rules (7.6) and the open
   decisions needed for M1 (section 15), recorded as decisions.
6. **Local CI** (section 8):
   1. a control script, `forgejo-ctl` (start, status, stop), so Forgejo runs
      on demand rather than on every WSL session (section 9.1); keep WSL
      running while working;
   2. install Forgejo, reachable from Windows on `localhost`;
   3. create the owner's account, the agents' push account if chosen (O-6),
      and the repository, imported from GitHub;
   4. branch protection on `main`;
   5. install the runner as its own Linux user, `host` label;
   6. first workflow: run the existing gates on every push to a change branch;
   7. configure the GitHub push mirror;
   8. repoint the local clone's `origin` to Forgejo.
7. **Verify early** what M2 will need: the runner user can reach the Windows
   exchange folder (`/mnt/c/...`) and the network.
8. **Backups** of the Forgejo data directory.

**Bootstrapping:** M0 changes infrastructure before CI exists, so M0 work is
committed by the owner directly. Branch protection and the change-branch
workflow apply from the end of M0.

**Exit criteria**

- All M0 tools installed; versions recorded in this plan.
- An agent attempting to write `spec/PHASE`, edit `tools/` or `.claude/`, run
  `set_phase`, or push to GitHub is blocked (each attempted once, logged).
- `set_phase` refuses to run non-interactively.
- Pushing a change branch triggers CI; results appear on the pull request.
- A deliberately failing gate blocks the merge.
- Only the owner can merge to `main`; fast-forward only.
- The runner runs as its own user; agents cannot modify its workspace.
- The owner can publish to GitHub on demand, and GitHub matches local `main`.
- The policy decisions are in the decision log.
- M0 retrospective written; this plan updated.

### 12.2 M1: Build ID over UART, simulation only

**Goal:** take the first real design of the project through the whole flow
(spec, review, freeze, build) in simulation. The same design goes onto the
board in M2, so M1 produces both the design and the first evidence that the
process works.

**Design scope.** A minimal design that reports, over a UART, the build ID
it was built with. The details are settled in the spec phase interview, not
in this plan. Topics the spec-architect must cover with the owner include:

- what the build ID is (commit or design ID, length, format);
- how it enters the design (e.g. a top-level generic set at build time, and
  by the testbench in simulation);
- when it is sent (at reset, periodically, or on request);
- the UART format (baud rate, framing);
- the clock frequency (a generic until the board is chosen, O-9);
- whether a UART-to-register bridge is included now, as the base for the
  observability later milestones need (counters, status).

**Inputs:** the owner's answers in the interview.

**Steps**

1. Create the change branch `cr/001-m1-build-id-uart`.
2. **Spec phase** with the spec-architect: interview, artifacts, checklist.
3. **Review phase:** readiness review until no blockers or majors remain.
4. **Freeze:** the owner runs `set_phase build` (`spec-frozen-1`).
5. **Build phase** with the build-orchestrator (section 6), pushing to Forgejo
   so CI runs on every change.
6. **Pull request** on Forgejo with CI green and the reviewer's verdict.
7. **Owner's code review** of the generated VHDL, recorded as an assessment
   in the evidence folder: quality, style, anything a human designer would
   have done differently.
8. **Merge** by the owner (fast-forward), tag `m1-complete`, publish to GitHub.
9. **Retrospective**, and plan M2 in this document.

**Exit criteria (fixed before the run)**

- All gates pass, locally and in CI; VSG `jcl` reports zero violations.
- The reviewer's verdict is READY.
- Every scenario example row is covered by a passing test (traceability
  complete).
- Every entry in `rtl/ASSUMPTIONS.md` is resolved or accepted by the owner.
- **No rule breaks:** the owner wrote no design or test code. (If one becomes
  unavoidable, it is logged as a rule break, not hidden.)
- Owner's code review recorded.
- Interventions logged; metrics recorded (section 13).
- Retrospective written; M2 planned in this document.

## 13. Evidence and metrics

Recorded for every milestone, in `docs/evidence/mN/`:

- **Intervention log:** one row per owner intervention.

  | # | When | Phase | Category | Trigger | What the owner did | Time |
  |---|---|---|---|---|---|---|

  Categories: **decision** (expected: the owner deciding), **clarification**
  (answering an agent's question), **correction** (fixing an agent's
  mistake), **rule break** (stepping outside the rules), **infrastructure**
  (fixing tools or setup).
- **Time:** elapsed time per phase, and owner time spent.
- **Iterations:** build-phase loops, and what each fixed.
- **Gate results:** the CI history for the change.
- **Resources:** Vivado utilization (from M2).
- **Tool versions** for every result.

### 13.1 Daily journal

A short entry for each day worked on the project, in
`docs/journal/YYYY-MM-DD.md`, following `docs/journal/TEMPLATE.md`.

**Why:** each Claude session (chat or Claude Code) starts without memory of
the last, so the journal carries continuity between sessions. It also
records what the plan and git do not: what the work took, what went wrong and
how it was fixed. That is evidence for the experiment (how hard is this,
really?) and the raw material for retrospectives and the presentation.

**Template sections:** milestone and time spent; goal for the day; what was
done; problems and fixes; decisions made; interventions (brief); next steps.

**Rules:**

- **The journal points, it does not duplicate.** It is the narrative, not the
  source of truth. Decisions are recorded in the plan or decision log, fixes
  in the setup notes, changes in git; the journal refers to them.
- **Lessons that belong nowhere else are kept here** (for example, a test
  environment that could not reproduce the real machine's behaviour).
- **Interventions** are mentioned in passing and recorded in the intervention
  log (section 13), which stays the structured record.
- **Who writes it:** at the end of a session, Claude (chat) drafts the entry
  from the conversation; the owner reviews and commits it (principle 8). The
  owner may also write or amend entries by hand.
- One file per day; a second session on the same day extends that day's file.

## 14. Risks (M0 and M1)

| Risk | Effect | Mitigation |
|---|---|---|
| Agents ignore or work around instructions | Independence or gates compromised | Hooks, CI as independent judge, reviewer, intervention log |
| Hooks are guardrails, not walls | A determined agent could reach forbidden files | Logged as known limit; separate Linux user for agents as later hardening |
| Same model, same blind spots | Design and tests share a misreading | Different models for designer and verifier; reviewer triage; owner's code review |
| Spec ambiguity | Agents guess | Readiness review; `ASSUMPTIONS.md`; spec gaps stop the build |
| Forgejo not started, or stopped when WSL shuts down | Pushes and CI fail | `forgejo-ctl status` at the start of every session (section 9.1) |
| Forgejo data loss | Pull-request and CI history lost | Periodic backups of the data directory |
| Orchestrator leaks details between agents | Independence weakened | Structured failure reports passed unchanged |

## 15. Open decisions

| # | Decision | Needed by |
|---|---|---|
| O-1 | Does the owner approve each spec diff explicitly (an "Approve diff" step), or is answering the question enough? | M1 |
| O-2 | Must the freeze tag be signed? | M1 |
| O-3 | Add an early architecture review (readiness review on the block diagram alone)? | M1 |
| O-4 | Keep each agent's raw question table as an appendix to the readiness log? | M1 |
| O-5 | Must the reviewer's verdict be recorded on the pull request before merging? | M1 |
| O-6 | A single local Forgejo account for agent pushes, or agents push as the owner? | M0 |
| O-7 | Final change classes and merge policy (7.4) | M0 |
| O-8 | Who approves warning waivers, and how (ELFWS is the mechanism) | M2 |
| O-9 | Development board selection (trade study) | M2 |
| O-10 | Try agent teams (direct messaging) for the readiness review, as a later experiment? | After M1 |
| O-11 | Add formal verification (e.g. SymbiYosys) for protocol and clock-domain-crossing logic? It would bring back Yosys and its GHDL plugin. | Later |
