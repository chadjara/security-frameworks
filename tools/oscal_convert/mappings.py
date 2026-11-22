"""Build cross-framework mapping files from NIST-published data only.

* SP 800-171 Rev 3 -> SP 800-53 Rev 5: the source controls each 800-171 requirement cites
  (reference links in the 800-171 Rev 3 OSCAL catalog).
* CSF 2.0 -> SP 800-53 Rev 5 and CSF 2.0 -> SP 800-171 Rev 3: NIST's CSF 2.0 informative
  references, exported from the CSF 2.0 Reference Tool in CPRT.

No mapping is inferred, chained, or edited by hand.
"""

from __future__ import annotations

import re

from common import SCHEMA_VERSION, prune, sp80053_id_from_label


def _active_ids(fw: dict) -> set[str]:
    return {r["id"] for r in fw["requirements"]}


def _withdrawn_ids(fw: dict) -> set[str]:
    return {w["id"] for w in fw.get("withdrawn", [])}


def _resolve(raw_ids: list[str], target_fw: dict, normalize) -> tuple[list[str], list[dict]]:
    active, withdrawn = _active_ids(target_fw), _withdrawn_ids(target_fw)
    resolved, unresolved = [], []
    for raw in raw_ids:
        tid = normalize(raw)
        if tid in active:
            if tid not in resolved:
                resolved.append(tid)
        else:
            if tid in withdrawn:
                reason = "withdrawn in target"
            elif re.fullmatch(r"[A-Z]{2}", raw.strip()):
                reason = "family-level reference, not a single control"
            else:
                reason = "not found in target"
            unresolved.append({"sourceValue": raw, "reason": reason})
    return resolved, unresolved


def _mapping(mid: str, title: str, from_fw: dict, to_fw: dict, relationship: dict, source: dict,
             entries: list[dict], unresolved: list[dict], content_version: str) -> dict:
    return prune({
        "schemaVersion": SCHEMA_VERSION,
        "id": mid,
        "title": title,
        "fromFramework": from_fw["id"],
        "toFramework": to_fw["id"],
        "contentVersion": content_version,
        "relationship": relationship,
        "source": source,
        "entries": entries,
        "unresolved": unresolved,
    })


def build_sp800171_to_sp80053(source_controls: dict[str, list[str]], fw171: dict, fw53: dict,
                              source171: dict, content_version: str) -> dict:
    entries, unresolved = [], []
    order = [r["id"] for r in fw171["requirements"]]
    for rid in order:
        targets, missing = _resolve(source_controls.get(rid, []), fw53, lambda s: sp80053_id_from_label(s) or s)
        if targets:
            entries.append({"from": rid, "to": targets})
        for m in missing:
            unresolved.append({"from": rid, **m})
    return _mapping(
        "sp800-171r3_to_sp800-53r5",
        "SP 800-171 Rev. 3 source controls in SP 800-53 Rev. 5",
        fw171, fw53,
        {
            "type": "source-control",
            "description": (
                "SP 800-171 Rev. 3 lists the SP 800-53 controls each security requirement was derived from. "
                "A source control covers the requirement's intent but may contain more than the requirement asks for."
            ),
        },
        prune({
            "publisher": "NIST",
            "description": "Reference links to SP 800-53 controls in the SP 800-171 Rev. 3 OSCAL catalog. "
                           "NIST cites SP 800-53 Release 5.1.1; identifiers are unchanged in Release 5.2.0.",
            "url": source171["url"],
            "sha256": source171.get("sha256"),
            "retrieved": source171.get("retrieved"),
        }),
        entries, unresolved, content_version,
    )


def build_csf_to(target_key: str, cprt_doc: dict, fw_csf: dict, target_fw: dict, cprt_source: dict,
                 content_version: str) -> dict:
    normalize = (lambda s: sp80053_id_from_label(s) or s) if target_key == "sp800-53r5" else (lambda s: s)
    refs = cprt_doc["references"]
    entries, unresolved = [], []
    for req in fw_csf["requirements"]:
        raw = refs.get(req["id"], {}).get(target_key, [])
        targets, missing = _resolve(raw, target_fw, normalize)
        if targets:
            entries.append({"from": req["id"], "to": targets})
        for m in missing:
            unresolved.append({"from": req["id"], **m})
    target_name = target_fw["shortName"]
    return _mapping(
        f"csf-2.0_to_{target_fw['id']}",
        f"CSF 2.0 informative references to {target_name}",
        fw_csf, target_fw,
        {
            "type": "informative-reference",
            "description": (
                f"NIST lists these {target_name} items as informative references for the CSF 2.0 subcategory: "
                "they help achieve the outcome, but the relationship is not necessarily one-to-one."
            ),
        },
        prune({
            "publisher": "NIST",
            "description": "CSF 2.0 informative references from the CSF 2.0 Reference Tool (CPRT).",
            "url": cprt_source["url"],
            "browseUrl": cprt_source.get("browseUrl"),
            "file": cprt_source.get("file"),
            "originalSha256": cprt_source.get("originalSha256"),
            "retrieved": cprt_source.get("retrieved"),
        }),
        entries, unresolved, content_version,
    )
