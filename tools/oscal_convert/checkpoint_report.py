#!/usr/bin/env python3
"""Print a Markdown report of bundled content counts plus a reproducible random sample of
requirements per framework, with links to the matching NIST CPRT pages for spot-checking.

    python3 tools/oscal_convert/checkpoint_report.py [--seed 2026] [--per-framework 5]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import random

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTENT = ROOT / "App" / "Resources" / "Content"


def load(rel: str) -> dict:
    return json.loads((CONTENT / rel).read_text(encoding="utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--per-framework", type=int, default=5)
    args = parser.parse_args()
    rng = random.Random(args.seed)

    index = load("index.json")
    out = [f"Content version {index['contentVersion']} · sample seed {args.seed}", ""]

    out += ["## Counts", "", "| Framework | Requirements | Groups | Withdrawn (excluded) | ODPs |", "|---|---|---|---|---|"]
    for f in index["frameworks"]:
        c = f["counts"]
        kinds = ", ".join(f"{c['byKind'].get(k['id'], 0)} {k['plural'].lower()}" for k in f["kinds"])
        groups = ", ".join(f"{n} {lvl['plural'].lower()}" for lvl, n in zip(f["groupLevels"], c["groups"]))
        out.append(f"| {f['shortName']} | {c['requirements']} ({kinds}) | {groups} | {c['withdrawn']} | {c['parameters']} |")
    out.append("")

    sp53 = next(f for f in index["frameworks"] if f["id"] == "sp800-53r5")
    out += ["### SP 800-53B baselines", "", "| Baseline | Controls | Enhancements | Total |", "|---|---|---|---|"]
    for b in sp53["baselines"]:
        k = sp53["counts"]["byBaseline"][b["id"]]
        out.append(f"| {b['title']} | {k.get('control', 0)} | {k.get('enhancement', 0)} | {sum(k.values())} |")
    out.append("")

    out += ["### Mappings (NIST-published only)", "", "| Mapping | Source requirements with links | Pairs |", "|---|---|---|"]
    for m in index["mappings"]:
        out.append(f"| {m['id']} | {m['entries']} | {m['pairs']} |")
    out.append("")

    out += ["## Random samples", ""]
    for f in index["frameworks"]:
        fw = load(f["file"])
        sample = sorted(rng.sample(fw["requirements"], args.per_framework), key=lambda r: r["sortKey"])
        out += [f"### {f['shortName']}", "", "| ID | Title | NIST source |", "|---|---|---|"]
        for r in sample:
            title = r["title"].replace("|", "\\|")
            extra = f" ({', '.join(r['baselines'])})" if r.get("baselines") else ""
            out.append(f"| `{r['displayId']}` | {title}{extra} | [CPRT]({r['sourceUrl']}) |")
        out.append("")

    print("\n".join(out))


if __name__ == "__main__":
    main()
