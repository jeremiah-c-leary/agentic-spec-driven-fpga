# Definition of ready

The spec-architect works through every item **with the user** and ticks it
(`- [x]`) only when the user has confirmed it. `tools/spec_check.py` refuses
to leave the spec phase while any box is unticked. Mechanical checks (files
exist, contracts match the layout, outlines have examples, no open markers)
are done by `spec_check.py` itself and are not repeated here.

Each ticked item should name where it is satisfied, e.g.
`- [x] ... (feature: Rule "Frame length"; D-004)`.

## A. Purpose and scope
- [ ] One-paragraph statement of what the design does and does not do.
- [ ] Everything out of scope is listed explicitly (e.g. other message types, TLVs).
- [ ] Standards and revisions the design follows are named.

## B. Interfaces
- [ ] Every port of every unit is in an interface contract (spec/interface/).
- [ ] Each interface's protocol rules are stated (valid/ready, back-pressure, gaps, TKEEP).
- [ ] Byte/bit ordering and endianness are defined.
- [ ] Every internal interface between units has a written contract (block diagram).
- [ ] Register map complete: offsets, access, reset values, side effects of reads/writes.

## C. Clocks and resets
- [ ] Every clock: frequency, source, relationship to other clocks.
- [ ] Every reset: polarity, synchronous/asynchronous, which domain, release behaviour.
- [ ] Behaviour when one domain is reset and another is not.
- [ ] Behaviour when a clock stops (e.g. accesses that depend on it).

## D. Behaviour
- [ ] Every rule in the feature files has boundary example rows (below, at, above limits).
- [ ] A default rule covers every input not described by a scenario.
- [ ] Every "Then" is observable at a unit's ports.
- [ ] Timing conventions are defined once and every timed "Then" uses them.
- [ ] Error handling: malformed, truncated, over-long and back-to-back inputs.
- [ ] Counters/state: width, wrap-around, clear, and what happens on reset.
- [ ] Fields deliberately not checked are listed as such.

## E. Performance and resources
- [ ] Throughput target and worst-case input pattern (e.g. minimum gaps).
- [ ] Latency requirement, if any, stated as a cycle count.
- [ ] Resource targets or limits (LUTs, FFs, BRAM, DSP), or "no limit" recorded.
- [ ] Target device family and clock frequencies for timing closure.

## F. Architecture (block diagram review)
- [ ] Partitioning into subsystems agrees with project_layout.toml.
- [ ] Every clock-domain crossing names its mechanism (synchroniser, handshake, FIFO).
- [ ] No multi-bit value crosses domains without qualification.
- [ ] Location of every significant state element is decided (which unit, which domain).
- [ ] Rate check: no event stream crosses a domain faster than its mechanism can carry.
- [ ] Data-path structure decisions recorded (e.g. pipeline vs multiplexer).

## G. Verification readiness
- [ ] Each unit has a feature file, or a recorded waiver (decision ID).
- [ ] Unit-level features do not duplicate top-level rules (each rule lives once).
- [ ] Things simulation cannot prove (CDC, timing) are listed for reviewer/tool checks.

## H. Implementation constraints
- [ ] Style guide applies unchanged, or deviations are recorded as decisions.
- [ ] Project layout agreed: directories, one entity per file, shared blocks.
- [ ] Tools and versions named (simulator, style checker, synthesis).

## I. Decisions and open issues
- [ ] Every choice made during the interview is in decisions.md, decided by the user.
- [ ] Readiness review has been run and no blocker or major question is open.
