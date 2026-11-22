#!/usr/bin/env python3
"""Print NIST source text for requirements that need editorial content, in a compact form for writers.

    python3 tools/oscal_convert/editorial_worklist.py csf-2.0 --groups GV,ID
    python3 tools/oscal_convert/editorial_worklist.py sp800-53r5 --baseline low --groups ac,at,au
    python3 tools/oscal_convert/editorial_worklist.py sp800-171r3 --missing-only

Reads the generated content in App/Resources/Content, so run convert.py first if sources changed.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTENT = ROOT / "App" / "Resources" / "Content" / "frameworks"
TOKEN = re.compile(r"\{\{param:([^}]+)\}\}")


def render(text: str, params: dict[str, dict]) -> str:
    def sub(m: re.Match) -> str:
        p = params.get(m.group(1), {})
        if p.get("choices"):
            return "[" + ("one or more of: " if p.get("howMany") == "one-or-more" else "one of: ") + "; ".join(
                TOKEN.sub(lambda x: f"[{params.get(x.group(1), {}).get('label', 'value')}]", c) for c in p["choices"]) + "]"
        return f"[organization-defined {p.get('label') or p.get('usage') or 'value'}]"
    return TOKEN.sub(sub, text or "")


def lines(items: list[dict], params: dict, depth: int = 0) -> list[str]:
    out = []
    for it in items:
        label = (it.get("label", "") + " ").lstrip() if it.get("label") else ""
        if it.get("text"):
            out.append("  " * depth + f"- {label}{render(it['text'], params)}")
        out += lines(it.get("items", []), params, depth + 1)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("framework")
    ap.add_argument("--groups", help="comma-separated top-level group ids (CSF function, 800-53 family, 800-171 family)")
    ap.add_argument("--baseline", help="SP 800-53 baseline id to restrict to")
    ap.add_argument("--missing-only", action="store_true", help="skip requirements that already have editorial")
    ap.add_argument("--objectives", action="store_true", help="include assessment objectives")
    args = ap.parse_args()

    fw = json.loads((CONTENT / f"{args.framework}.framework.json").read_text())
    top_of = {}
    for g in fw["groups"]:
        top_of[g["id"]] = g["id"]
        for sub in g.get("groups", []):
            top_of[sub["id"]] = g["id"]
    wanted = {x.strip() for x in args.groups.split(",")} if args.groups else None
    by_id = {r["id"]: r for r in fw["requirements"]}

    count = 0
    for r in fw["requirements"]:
        if wanted and top_of.get(r["groupId"]) not in wanted:
            continue
        if args.baseline and args.baseline not in r.get("baselines", []):
            continue
        if args.missing_only and r.get("editorial"):
            continue
        root = r.get("parentId") or r["id"]
        params = {}
        for x in [by_id[root]] + [c for c in fw["requirements"] if c.get("parentId") == root]:
            for p in x.get("parameters", []):
                params[p["id"]] = p
                if p.get("altId"):
                    params[p["altId"]] = p
        count += 1
        print(f"=== {r['id']}  ({r['displayId']})  {r['title']}")
        if r.get("parentId"):
            print(f"Enhancement of {by_id[r['parentId']]['displayId']} {by_id[r['parentId']]['title']}")
        print("Statement:")
        print("\n".join(lines(r["statement"], params)))
        if r.get("discussion"):
            print("Discussion: " + r["discussion"])
        if r.get("examples"):
            print("Implementation examples:")
            print("\n".join(f"- {e['text']}" for e in r["examples"]))
        editable = [p for p in r.get("parameters", []) if not p.get("aggregates")]
        if editable:
            print("Organization-defined parameters: " + "; ".join(
                p.get("label") or p.get("usage") or ("selection: " + " / ".join(p.get("choices", []))) for p in editable))
        if args.objectives and r.get("objectives"):
            print("Assessment objectives:")
            print("\n".join(lines(r["objectives"], params)))
        print()
    print(f"# {count} requirement(s)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
