#!/usr/bin/env python3
"""Download the pinned NIST source files into data/sources/ and record provenance.

Run from the repository root:

    python3 tools/oscal_convert/fetch_sources.py            # pin to the current OSCAL main commit
    python3 tools/oscal_convert/fetch_sources.py --ref <sha> # pin to a specific commit

Outputs:
  data/sources/oscal/*.json                         raw OSCAL files, byte-for-byte
  data/sources/cprt/csf-2.0-nist-references.json    NIST-only subset of the CPRT CSF 2.0
                                                    informative references (see below)
  data/sources/SOURCES.json                         URL, commit, sha256, size, retrieval date

The CPRT export is an Excel workbook that lists every informative reference for CSF 2.0,
including references to third-party standards (ISO, PCI DSS, CIS, and others). Only the
NIST references this app uses (SP 800-53 Rev 5.2.0 and SP 800-171 Rev 3) are extracted and
committed. The original workbook is not stored; its URL and sha256 are recorded instead.

Standard library only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import subprocess
import sys
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from xlsxlite import read_sheet_rows  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES_DIR = REPO_ROOT / "data" / "sources"

OSCAL_REPO = "usnistgov/oscal-content"
OSCAL_GIT_URL = f"https://github.com/{OSCAL_REPO}.git"
OSCAL_RAW = "https://raw.githubusercontent.com/" + OSCAL_REPO + "/{ref}/{path}"

OSCAL_FILES = {
    "csf-2.0-catalog": "nist.gov/CSF/v2.0/json/NIST_CSF_v2.0_catalog.json",
    "sp800-53r5-catalog": "nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_catalog.json",
    "sp800-53r5-low-profile": "nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_LOW-baseline_profile.json",
    "sp800-53r5-moderate-profile": "nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_MODERATE-baseline_profile.json",
    "sp800-53r5-high-profile": "nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_HIGH-baseline_profile.json",
    "sp800-53r5-privacy-profile": "nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_PRIVACY-baseline_profile.json",
    "sp800-171r3-catalog": "nist.gov/SP800-171/rev3/json/NIST_SP800-171_rev3_catalog.json",
}

CPRT_CSF_REFERENCES_URL = "https://csrc.nist.gov/extensions/nudp/services/json/csf/download?olirids=all"
CPRT_CSF_TOOL_URL = "https://csrc.nist.gov/Projects/Cybersecurity-Framework/Filters#/csf/filters"

# Informative-reference prefixes to keep from the CPRT workbook. Everything else is discarded.
NIST_REFERENCE_PREFIXES = {
    "SP 800-53 Rev 5.2.0": "sp800-53r5",
    "SP 800-171 Rev 3": "sp800-171r3",
}

USER_AGENT = "security-frameworks-content-fetcher/1.0"


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def resolve_ref(ref: str) -> str:
    if len(ref) == 40 and all(c in "0123456789abcdef" for c in ref):
        return ref
    out = subprocess.run(
        ["git", "ls-remote", OSCAL_GIT_URL, ref], check=True, capture_output=True, text=True
    ).stdout.split()
    if not out:
        raise SystemExit(f"Could not resolve ref {ref!r} in {OSCAL_GIT_URL}")
    return out[0]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def oscal_metadata(data: bytes) -> dict:
    doc = json.loads(data)
    root = doc.get("catalog") or doc.get("profile") or {}
    meta = root.get("metadata", {})
    return {
        "title": meta.get("title"),
        "version": meta.get("version"),
        "oscalVersion": meta.get("oscal-version"),
        "lastModified": meta.get("last-modified"),
    }


def extract_cprt_references(workbook: bytes) -> tuple[dict, dict]:
    """Return ({csfId: {targetFramework: [ids]}}, info) from the CPRT CSF 2.0 workbook."""
    import re

    rows = read_sheet_rows(workbook, sheet_name="CSF 2.0")
    header = rows[1] if len(rows) > 1 else {}
    if header.get("C") != "Subcategory" or header.get("E") != "Informative References":
        raise SystemExit(f"Unexpected CPRT workbook layout: header row = {header}")
    sub_re = re.compile(r"^([A-Z]{2}\.[A-Z]{2}-\d{2}):")
    out: dict[str, dict[str, list[str]]] = {}
    kept = {v: 0 for v in NIST_REFERENCE_PREFIXES.values()}
    discarded = 0
    for row in rows[2:]:
        m = sub_re.match(row.get("C", ""))
        if not m:
            continue
        csf_id = m.group(1)
        refs: dict[str, list[str]] = {}
        for line in (row.get("E") or "").splitlines():
            line = line.strip()
            if not line:
                continue
            prefix, _, ident = line.partition(": ")
            target = NIST_REFERENCE_PREFIXES.get(prefix)
            if target is None:
                discarded += 1
                continue
            refs.setdefault(target, [])
            if ident not in refs[target]:
                refs[target].append(ident)
                kept[target] += 1
        out[csf_id] = refs
    info = {"subcategoryRows": len(out), "keptReferences": kept, "discardedNonNistReferences": discarded}
    return out, info


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ref", default="main", help="oscal-content branch, tag, or commit (default: main)")
    args = parser.parse_args()

    commit = resolve_ref(args.ref)
    today = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    (SOURCES_DIR / "oscal").mkdir(parents=True, exist_ok=True)
    (SOURCES_DIR / "cprt").mkdir(parents=True, exist_ok=True)

    manifest = {
        "description": "Provenance for every NIST source file used to generate the app's framework content.",
        "oscalRepository": f"https://github.com/{OSCAL_REPO}",
        "oscalCommit": commit,
        "sources": [],
    }

    for source_id, path in OSCAL_FILES.items():
        url = OSCAL_RAW.format(ref=commit, path=path)
        print(f"Fetching {source_id} ...", file=sys.stderr)
        data = fetch(url)
        dest = SOURCES_DIR / "oscal" / pathlib.Path(path).name
        dest.write_bytes(data)
        manifest["sources"].append({
            "id": source_id,
            "publisher": "NIST",
            "url": url,
            "browseUrl": f"https://github.com/{OSCAL_REPO}/blob/{commit}/{path}",
            "file": str(dest.relative_to(REPO_ROOT)),
            "sha256": sha256(data),
            "bytes": len(data),
            "retrieved": today,
            **oscal_metadata(data),
        })

    print("Fetching CPRT CSF 2.0 informative references ...", file=sys.stderr)
    workbook = fetch(CPRT_CSF_REFERENCES_URL)
    refs, info = extract_cprt_references(workbook)
    cprt_dest = SOURCES_DIR / "cprt" / "csf-2.0-nist-references.json"
    cprt_doc = {
        "description": (
            "NIST-only subset of the CSF 2.0 informative references exported from NIST CPRT. "
            "Only SP 800-53 Rev 5.2.0 and SP 800-171 Rev 3 references are kept."
        ),
        "sourceUrl": CPRT_CSF_REFERENCES_URL,
        "toolUrl": CPRT_CSF_TOOL_URL,
        "originalSha256": sha256(workbook),
        "retrieved": today,
        "extraction": info,
        "references": refs,
    }
    cprt_dest.write_text(json.dumps(cprt_doc, indent=2, sort_keys=True) + "\n")
    manifest["sources"].append({
        "id": "cprt-csf-2.0-informative-references",
        "publisher": "NIST",
        "url": CPRT_CSF_REFERENCES_URL,
        "browseUrl": CPRT_CSF_TOOL_URL,
        "file": str(cprt_dest.relative_to(REPO_ROOT)),
        "originalSha256": sha256(workbook),
        "sha256": sha256(cprt_dest.read_bytes()),
        "retrieved": today,
        "title": "CSF 2.0 Reference Tool export: informative references (NIST subset)",
    })

    (SOURCES_DIR / "SOURCES.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(info, indent=2), file=sys.stderr)
    print(f"Pinned oscal-content commit {commit}", file=sys.stderr)


if __name__ == "__main__":
    main()
