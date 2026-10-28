#!/usr/bin/env python3
"""
spec_check.py - the mechanical half of the definition of ready.

    python3 tools/spec_check.py              checks for leaving the spec phase
    python3 tools/spec_check.py --for-build  also requires a clean readiness review

The judgement half is spec/CHECKLIST.md, which the spec-architect works
through with the user; this script only confirms every box there is ticked.
Prints PASS/FAIL per check; exit code 0 only if everything passes.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import layout  # noqa: E402

ROOT = layout.ROOT
SPEC = ROOT / "spec"
results = []


def ok(msg):
    results.append(("PASS", msg))


def bad(msg):
    results.append(("FAIL", msg))


def check_phase():
    p = SPEC / "PHASE"
    phase = p.read_text().strip() if p.exists() else ""
    if phase in ("spec", "review", "build"):
        ok(f"phase file: {phase}")
    else:
        bad("spec/PHASE must contain spec, review or build")


def check_documents():
    for name in ("block_diagram.md", "style_guide.md", "decisions.md",
                 "CHECKLIST.md", "project_layout.toml"):
        if (SPEC / name).exists():
            ok(f"spec/{name} exists")
        else:
            bad(f"spec/{name} missing")


def check_layout_and_contracts(lay):
    us = layout.units(lay)
    names = [u["entity"].lower() for u in us] + \
            [e.lower() for u in us for e in u["internal_entities"]]
    if len(names) == len(set(names)):
        ok("entity names unique across layout")
    else:
        bad("duplicate entity names in project_layout.toml")
    dirs = [u["rtl_dir"] for u in us] + [u["tb_dir"] for u in us]
    if len(dirs) == len(set(dirs)):
        ok("rtl_dir / tb_dir entries unique")
    else:
        bad("two units share an rtl_dir or tb_dir")

    decisions = (SPEC / "decisions.md").read_text() if (SPEC / "decisions.md").exists() else ""
    diagram = (SPEC / "block_diagram.md").read_text().lower() if (SPEC / "block_diagram.md").exists() else ""

    for u in us:
        tag = f"[{u['name']}]"
        # interface contract
        icf = ROOT / u.get("interface", "")
        if u.get("interface") and icf.is_file():
            ents, _ = layout.vhdl_units(icf)
            if ents == [u["entity"].lower()]:
                ok(f"{tag} interface contract declares {u['entity']}")
            else:
                bad(f"{tag} {u['interface']} must declare exactly entity {u['entity']} (found {ents})")
        else:
            bad(f"{tag} interface contract missing: {u.get('interface', '(not set)')}")
        # feature file or waiver
        if u.get("feature"):
            if (ROOT / u["feature"]).is_file():
                check_feature(ROOT / u["feature"], tag)
            else:
                bad(f"{tag} feature file missing: {u['feature']}")
        elif u.get("feature_waiver"):
            if re.search(rf"^##\s+{re.escape(u['feature_waiver'])}\b", decisions, re.M):
                ok(f"{tag} feature waived by {u['feature_waiver']}")
            else:
                bad(f"{tag} feature_waiver {u['feature_waiver']} not found in decisions.md")
        else:
            bad(f"{tag} needs a feature file or a feature_waiver")
        # block diagram mentions the unit
        if u["entity"].lower() in diagram:
            ok(f"{tag} appears in block_diagram.md")
        else:
            bad(f"{tag} {u['entity']} not mentioned in block_diagram.md")


def check_feature(path, tag):
    text = path.read_text()
    name = path.relative_to(ROOT).as_posix()
    if not re.search(r"^\s*Feature:", text, re.M):
        bad(f"{tag} {name}: no 'Feature:' line")
        return
    n_scen = len(re.findall(r"^\s*Scenario( Outline)?:", text, re.M))
    if n_scen == 0:
        bad(f"{tag} {name}: no scenarios")
        return
    # every Scenario Outline needs an Examples table with a header and >= 1 row
    blocks = re.split(r"^\s*(?=Scenario|Rule:|Background:)", text, flags=re.M)
    broken = []
    for b in blocks:
        m = re.match(r"Scenario Outline:\s*(.*)", b)
        if m:
            rows = re.findall(r"^\s*\|.*\|\s*$", b.split("Examples:", 1)[1], re.M) \
                if "Examples:" in b else []
            if len(rows) < 2:
                broken.append(m.group(1).strip())
    if broken:
        bad(f"{tag} {name}: outlines without example rows: {'; '.join(broken)}")
    else:
        ok(f"{tag} {name}: {n_scen} scenarios, all outlines have examples")


def check_open_markers():
    pat = re.compile(r"#\s*REVIEW:|\bTODO\b|\bTBD\b|\?\?\?")
    hits = []
    for f in sorted(SPEC.rglob("*")):
        if f.is_file() and f.suffix in (".feature", ".md", ".toml", ".vhd") \
                and f.name != "CHECKLIST.md":
            for i, line in enumerate(f.read_text(errors="replace").splitlines(), 1):
                if pat.search(line):
                    hits.append(f"{f.relative_to(ROOT).as_posix()}:{i}")
    if hits:
        bad(f"{len(hits)} open markers (REVIEW/TODO/TBD): " + ", ".join(hits[:8]) +
            (" ..." if len(hits) > 8 else ""))
    else:
        ok("no open markers in spec/")


def check_checklist():
    p = SPEC / "CHECKLIST.md"
    if not p.exists():
        return
    text = p.read_text()
    done = len(re.findall(r"^\s*- \[[xX]\]", text, re.M))
    todo = re.findall(r"^\s*- \[ \]\s*(.*)$", text, re.M)
    if todo:
        bad(f"CHECKLIST.md: {len(todo)} of {done + len(todo)} items not confirmed, "
            f"first: {todo[0][:70]}")
    else:
        ok(f"CHECKLIST.md: all {done} items confirmed")


def check_decisions():
    p = SPEC / "decisions.md"
    if not p.exists():
        return
    secs = re.split(r"^##\s+(?=D-\d+)", p.read_text(), flags=re.M)[1:]
    incomplete = [s.split()[0] for s in secs
                  if not all(k in s for k in ("Decision:", "Rationale:", "Decided by:"))]
    if incomplete:
        bad(f"decisions.md: entries missing Decision/Rationale/Decided by: {', '.join(incomplete)}")
    else:
        ok(f"decisions.md: {len(secs)} decisions, all complete")


def check_readiness():
    p = ROOT / "reports" / "readiness_review.md"
    if not p.exists():
        bad("reports/readiness_review.md missing (run the readiness review)")
        return
    text = p.read_text()
    counts = {k: re.search(rf"Open {k}:\s*(\d+)", text) for k in ("blockers", "majors")}
    if not all(counts.values()):
        bad("readiness_review.md must contain 'Open blockers: N' and 'Open majors: N'")
    elif int(counts["blockers"].group(1)) or int(counts["majors"].group(1)):
        bad(f"readiness review not clean: {counts['blockers'].group(1)} blockers, "
            f"{counts['majors'].group(1)} majors open")
    else:
        ok("readiness review: 0 open blockers, 0 open majors")


def main():
    for_build = "--for-build" in sys.argv
    check_phase()
    check_documents()
    try:
        lay = layout.load()
        ok("project_layout.toml parses")
        check_layout_and_contracts(lay)
    except Exception as exc:  # noqa: BLE001
        bad(f"project_layout.toml: {exc}")
    check_open_markers()
    check_decisions()
    check_checklist()
    if for_build:
        check_readiness()

    for status, msg in results:
        print(f"{status}  {msg}")
    failed = sum(1 for s, _ in results if s == "FAIL")
    print(f"\nSPEC CHECK: {'PASS' if not failed else f'FAIL ({failed} findings)'}"
          f"{' [for build]' if for_build else ''}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
