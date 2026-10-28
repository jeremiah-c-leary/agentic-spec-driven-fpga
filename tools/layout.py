#!/usr/bin/env python3
"""
layout.py - read and enforce spec/project_layout.toml (Python 3.11+).

    python3 tools/layout.py top          print the top entity name
    python3 tools/layout.py rtl-files    print RTL files in compile-import order
    python3 tools/layout.py tb-dirs      print declared testbench directories
    python3 tools/layout.py check-build  verify rtl/ and tb/ obey the layout

check-build prints one "PASS ..." / "FAIL ..." line per finding and exits
non-zero if anything failed.
"""
import pathlib
import re
import sys
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LAYOUT = ROOT / "spec" / "project_layout.toml"

ENT_RE = re.compile(r"^\s*entity\s+(\w+)\s+is\b", re.I | re.M)
PKG_RE = re.compile(r"^\s*package\s+(\w+)\s+is\b", re.I | re.M)
COMMENT_RE = re.compile(r"--.*$", re.M)


def load():
    with open(LAYOUT, "rb") as f:
        return tomllib.load(f)


def units(lay):
    """Top plus subsystems as uniform dicts."""
    top = dict(lay["top"])
    top.update(name="top", kind="top", internal_entities=[])
    out = [top]
    for s in lay.get("subsystem", []):
        u = dict(s)
        u.setdefault("internal_entities", [])
        u["kind"] = "subsystem"
        out.append(u)
    return out


def vhdl_units(path):
    text = COMMENT_RE.sub("", path.read_text(errors="replace"))
    return ([e.lower() for e in ENT_RE.findall(text)],
            [p.lower() for p in PKG_RE.findall(text)])


def rel(p):
    return p.relative_to(ROOT).as_posix()


def check_build(lay):
    results = []
    ok = lambda m: results.append(("PASS", m))
    bad = lambda m: results.append(("FAIL", m))

    us = units(lay)
    shared = lay["project"].get("shared_dir", "")
    rtl_dirs = {u["rtl_dir"]: u for u in us}
    allowed_rtl = set(rtl_dirs) | ({shared} if shared else set())
    declared = {}
    for u in us:
        for e in [u["entity"]] + list(u["internal_entities"]):
            declared[e.lower()] = u

    # --- every RTL file in a declared directory, one entity per file
    found = {}
    for f in sorted((ROOT / "rtl").rglob("*.vhd")):
        d = rel(f.parent)
        if d not in allowed_rtl:
            bad(f"{rel(f)}: directory {d}/ is not declared in project_layout.toml")
            continue
        ents, pkgs = vhdl_units(f)
        if len(ents) > 1:
            bad(f"{rel(f)}: {len(ents)} entities in one file (one entity per file)")
        for e in ents:
            if f.stem.lower() != e:
                bad(f"{rel(f)}: entity {e} must be in a file named {e}.vhd")
            found[e] = d
            if e in declared:
                want = declared[e]["rtl_dir"]
                if d != want:
                    bad(f"{rel(f)}: entity {e} belongs in {want}/")
            elif d != shared:
                bad(f"{rel(f)}: entity {e} is not declared in the layout "
                    f"(declare it, or place generic blocks in {shared}/)")
        if d == lay["top"]["rtl_dir"]:
            extra = [e for e in ents if e != lay["top"]["entity"].lower()]
            if extra or pkgs:
                bad(f"{rel(f)}: top directory may contain only the top entity "
                    f"(found {', '.join(extra + pkgs)})")

    # --- every declared entity present
    for e, u in declared.items():
        if e in found:
            ok(f"entity {e} present in {u['rtl_dir']}/")
        else:
            bad(f"entity {e} missing: expected {u['rtl_dir']}/{e}.vhd")

    # --- testbenches only in declared dirs; each unit with a feature has tests
    tb_dirs = {u["tb_dir"]: u for u in us}
    tb_tops = {d: 0 for d in tb_dirs}
    for f in sorted((ROOT / "tb").rglob("*.vhd")):
        d = rel(f.parent)
        if d not in tb_dirs:
            bad(f"{rel(f)}: directory {d}/ is not a declared tb_dir")
            continue
        ents, _ = vhdl_units(f)
        tb_tops[d] += sum(1 for e in ents if e.startswith("tb_"))
    for d, u in tb_dirs.items():
        if u.get("feature"):
            if tb_tops[d]:
                ok(f"{d}/: {tb_tops[d]} test top(s) for {u['name']}")
            else:
                bad(f"{d}/: no tb_* test top for {u['name']} (feature {u['feature']})")
    return results


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    lay = load()
    cmd = sys.argv[1]
    if cmd == "top":
        print(lay["top"]["entity"])
    elif cmd == "tb-dirs":
        for u in units(lay):
            print(u["tb_dir"])
    elif cmd == "rtl-files":
        dirs = [lay["project"].get("shared_dir", "")] + \
               [u["rtl_dir"] for u in units(lay)[1:]] + [lay["top"]["rtl_dir"]]
        for d in dirs:
            if d:
                for f in sorted((ROOT / d).glob("*.vhd")):
                    print(rel(f))
    elif cmd == "check-build":
        results = check_build(lay)
        for status, msg in results:
            print(f"{status} {msg}")
        return 1 if any(s == "FAIL" for s, _ in results) else 0
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
