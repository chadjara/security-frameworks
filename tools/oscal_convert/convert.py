#!/usr/bin/env python3
"""Generate the app's bundled framework content from the pinned NIST sources.

    python3 tools/oscal_convert/convert.py            # write App/Resources/Content
    python3 tools/oscal_convert/convert.py --check    # fail if committed content is out of date
    python3 tools/oscal_convert/convert.py --require-editorial   # fail if in-scope items lack editorial

Inputs:  data/sources/SOURCES.json (+ files it lists), data/editorial/*.json, data/content.json
Outputs: App/Resources/Content/frameworks/<id>.framework.json
         App/Resources/Content/mappings/<id>.mapping.json
         App/Resources/Content/index.json

Standard library only.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from common import SCHEMA_VERSION, load_json  # noqa: E402
from editorial import in_scope_ids, lint_overlay, load_overlay, merge_overlay  # noqa: E402
from frameworks import (  # noqa: E402
    BASELINE_ORDER,
    build_csf,
    build_sp80053,
    build_sp800171,
    sp800171_source_controls,
)
from mappings import build_csf_to, build_sp800171_to_sp80053  # noqa: E402
from validate import validate_framework, validate_mapping  # noqa: E402

REPO_ROOT = HERE.parents[1]
DEFAULT_OUT = REPO_ROOT / "App" / "Resources" / "Content"


def load_sources(root: pathlib.Path) -> dict[str, dict]:
    manifest = load_json(root / "data" / "sources" / "SOURCES.json")
    out = {}
    for s in manifest["sources"]:
        s = dict(s)
        s["oscalCommit"] = manifest.get("oscalCommit")
        out[s["id"]] = s
    return out


def build_all(root: pathlib.Path) -> tuple[dict[str, dict], list[str], list[str]]:
    """Return ({relative output path: document}, errors, warnings)."""
    sources = load_sources(root)
    content_version = load_json(root / "data" / "content.json")["contentVersion"]

    def src_doc(sid: str) -> dict:
        return load_json(root / sources[sid]["file"])

    def src_meta(sid: str) -> dict:
        meta = dict(sources[sid])
        if meta.get("oscalCommit"):
            meta["browseUrl"] = meta.get("browseUrl")
        return meta

    csf_cat = src_doc("csf-2.0-catalog")["catalog"]
    c53 = src_doc("sp800-53r5-catalog")["catalog"]
    c171 = src_doc("sp800-171r3-catalog")["catalog"]
    profiles = {b: src_doc(f"sp800-53r5-{b}-profile") for b in BASELINE_ORDER}

    fw_csf = build_csf(csf_cat, src_meta("csf-2.0-catalog"), content_version)
    fw_53 = build_sp80053(c53, profiles, src_meta("sp800-53r5-catalog"),
                          {b: src_meta(f"sp800-53r5-{b}-profile") for b in BASELINE_ORDER}, content_version)
    fw_171 = build_sp800171(c171, src_meta("sp800-171r3-catalog"), content_version)
    for fw in (fw_csf, fw_53, fw_171):
        fw["source"]["oscalCommit"] = sources["csf-2.0-catalog"]["oscalCommit"]
    add_csf_tiers(fw_csf, root)

    errors: list[str] = []
    warnings: list[str] = []
    editorial_dir = root / "data" / "editorial"
    frameworks = {fw["id"]: fw for fw in (fw_csf, fw_53, fw_171)}
    for fw in frameworks.values():
        overlay = load_overlay(editorial_dir, fw["id"])
        errors += lint_overlay(overlay, fw)
        merge_overlay(fw, overlay)

    cprt_doc = src_doc("cprt-csf-2.0-informative-references")
    cprt_src = src_meta("cprt-csf-2.0-informative-references")
    maps = [
        build_sp800171_to_sp80053(sp800171_source_controls(c171), fw_171, fw_53, src_meta("sp800-171r3-catalog"),
                                  content_version),
        build_csf_to("sp800-53r5", cprt_doc, fw_csf, fw_53, cprt_src, content_version),
        build_csf_to("sp800-171r3", cprt_doc, fw_csf, fw_171, cprt_src, content_version),
    ]

    for fw in frameworks.values():
        e, w = validate_framework(fw)
        errors += e
        warnings += w
    for m in maps:
        e, w = validate_mapping(m, frameworks)
        errors += e
        warnings += w

    outputs: dict[str, dict] = {}
    for fw in frameworks.values():
        outputs[f"frameworks/{fw['id']}.framework.json"] = fw
    for m in maps:
        outputs[f"mappings/{m['id']}.mapping.json"] = m
    outputs["index.json"] = build_index(frameworks, maps, content_version)
    return outputs, errors, warnings


def add_csf_tiers(fw: dict, root: pathlib.Path) -> None:
    """CSF 2.0 Tiers, transcribed from CSWP 29 Appendix B (not in OSCAL). See data/sources/manual/."""
    path = root / "data" / "sources" / "manual" / "csf-2.0-tiers.json"
    if not path.exists():
        return
    doc = load_json(path)
    fw["tiers"] = [
        {"id": f"tier-{t['number']}", "number": t["number"], "title": t["title"],
         "governance": t["governance"], "management": t["management"]}
        for t in doc["tiers"]
    ]
    fw["tiersSource"] = {"url": doc["sourceUrl"], "pages": doc["pages"], "sha256": doc["pdfSha256"],
                         "introduction": doc["introduction"]}


def framework_counts(fw: dict) -> dict:
    reqs = fw["requirements"]
    counts = {
        "requirements": len(reqs),
        "byKind": dict(Counter(r["kind"] for r in reqs)),
        "groups": [len(fw["groups"])] + ([sum(len(g.get("groups", [])) for g in fw["groups"])]
                                         if any(g.get("groups") for g in fw["groups"]) else []),
        "withdrawn": len(fw.get("withdrawn", [])),
        "parameters": sum(len([p for p in r.get("parameters", []) if not p.get("aggregates")]) for r in reqs),
        "withEditorial": sum(1 for r in reqs if r.get("editorial")),
    }
    if fw.get("baselines"):
        counts["byBaseline"] = {
            b["id"]: dict(Counter(r["kind"] for r in reqs if b["id"] in r.get("baselines", [])))
            for b in fw["baselines"]
        }
    return counts


def build_index(frameworks: dict[str, dict], maps: list[dict], content_version: str) -> dict:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "contentVersion": content_version,
        "frameworks": [
            {
                "id": fw["id"],
                "file": f"frameworks/{fw['id']}.framework.json",
                "shortName": fw["shortName"],
                "title": fw["title"],
                "publicationId": fw["publicationId"],
                "version": fw["version"],
                "summary": fw.get("summary"),
                "kinds": fw["kinds"],
                "groupLevels": fw["groupLevels"],
                "baselines": fw.get("baselines", []),
                "notices": fw.get("notices", []),
                "counts": framework_counts(fw),
            }
            for fw in frameworks.values()
        ],
        "mappings": [
            {
                "id": m["id"],
                "file": f"mappings/{m['id']}.mapping.json",
                "fromFramework": m["fromFramework"],
                "toFramework": m["toFramework"],
                "relationshipType": m["relationship"]["type"],
                "entries": len(m.get("entries", [])),
                "pairs": sum(len(e["to"]) for e in m.get("entries", [])),
            }
            for m in maps
        ],
    }


def serialize(doc: dict) -> str:
    return json.dumps(doc, indent=1, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=pathlib.Path, default=DEFAULT_OUT)
    parser.add_argument("--check", action="store_true", help="verify committed output is current; write nothing")
    parser.add_argument("--require-editorial", action="store_true",
                        help="fail if any in-scope requirement has no editorial overlay")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    outputs, errors, warnings = build_all(REPO_ROOT)

    if args.require_editorial:
        index = outputs["index.json"]
        for entry in index["frameworks"]:
            fw = outputs[entry["file"]]
            missing = [rid for rid in in_scope_ids(fw)
                       if not next(r for r in fw["requirements"] if r["id"] == rid).get("editorial")]
            if missing:
                errors.append(f"{fw['id']}: {len(missing)} in-scope requirements lack editorial "
                              f"(first: {', '.join(missing[:5])})")

    if not args.quiet:
        for w in warnings:
            print(f"warning: {w}", file=sys.stderr)
    for e in errors:
        print(f"error: {e}", file=sys.stderr)
    if errors:
        print(f"{len(errors)} error(s); nothing written.", file=sys.stderr)
        return 1

    if args.check:
        stale = []
        for rel, doc in outputs.items():
            path = args.out / rel
            if not path.exists() or path.read_text(encoding="utf-8") != serialize(doc):
                stale.append(rel)
        existing = {str(p.relative_to(args.out)) for p in args.out.rglob("*.json")} if args.out.exists() else set()
        extra = sorted(existing - set(outputs))
        if stale or extra:
            for rel in stale:
                print(f"out of date: {rel}", file=sys.stderr)
            for rel in extra:
                print(f"unexpected file: {rel}", file=sys.stderr)
            print("Run: python3 tools/oscal_convert/convert.py", file=sys.stderr)
            return 1
        print("Content is up to date.")
        return 0

    for rel, doc in outputs.items():
        path = args.out / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(serialize(doc), encoding="utf-8")

    index = outputs["index.json"]
    for entry in index["frameworks"]:
        print(f"{entry['shortName']}: {json.dumps(entry['counts'])}")
    for m in index["mappings"]:
        print(f"{m['id']}: {m['entries']} entries, {m['pairs']} pairs")
    print(f"{len(warnings)} warning(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
