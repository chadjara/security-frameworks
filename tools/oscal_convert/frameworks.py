"""Builders that turn each NIST OSCAL catalog into the app's framework schema (v1)."""

from __future__ import annotations

import re
from typing import Any

from common import (
    SCHEMA_VERSION,
    clean_text,
    convert_param,
    first_part,
    is_withdrawn,
    links,
    nist_references,
    parts,
    prop,
    prune,
    resource_index,
    sp80053_display_id,
    sp80053_padded_id,
    statement_items,
)

CPRT_ELEMENT_URL = "https://csrc.nist.gov/projects/cprt/catalog#/cprt/framework/version/{doc}/home?element={element}"

BASELINE_ORDER = ["low", "moderate", "high", "privacy"]


def source_record(source: dict, extra: dict | None = None) -> dict:
    rec = {
        "oscalUrl": source["url"],
        "oscalBrowseUrl": source.get("browseUrl"),
        "catalogTitle": source.get("title"),
        "catalogVersion": source.get("version"),
        "oscalVersion": source.get("oscalVersion"),
        "lastModified": source.get("lastModified"),
        "sha256": source.get("sha256"),
        "retrieved": source.get("retrieved"),
    }
    rec.update(extra or {})
    return prune(rec)


def framework_header(fid: str, info: dict, source: dict, content_version: str) -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "id": fid,
        "shortName": info["shortName"],
        "title": info["title"],
        "publisher": "National Institute of Standards and Technology",
        "publicationId": info["publicationId"],
        "version": info["version"],
        "contentVersion": content_version,
        "source": source_record(source, info.get("sourceExtra")),
    }


# =============================================================================== CSF 2.0

CSF_INFO = {
    "shortName": "CSF 2.0",
    "title": "The NIST Cybersecurity Framework (CSF) 2.0",
    "publicationId": "NIST CSWP 29",
    "version": "2.0",
    "sourceExtra": {
        "publicationUrl": "https://doi.org/10.6028/NIST.CSWP.29",
        "referenceToolUrl": "https://csrc.nist.gov/projects/cprt/catalog#/cprt/framework/version/CSF_2_0_0/home",
    },
}


def build_csf(catalog: dict, source: dict, content_version: str) -> dict:
    fw = framework_header("csf-2.0", CSF_INFO, source, content_version)
    fw["kinds"] = [{"id": "subcategory", "singular": "Subcategory", "plural": "Subcategories"}]
    fw["groupLevels"] = [
        {"singular": "Function", "plural": "Functions"},
        {"singular": "Category", "plural": "Categories"},
    ]
    groups, reqs, withdrawn = [], [], []

    def by_sort(items):
        return sorted(items or [], key=lambda x: prop(x, "sort-id") or "")

    for fn in by_sort(catalog["groups"]):
        overview = first_part(fn, "overview")
        fgroup = {
            "id": fn["id"],
            "displayId": fn["id"],
            "title": fn["title"].title(),
            "description": clean_text(overview.get("prose")) if overview else None,
            "groups": [],
        }
        for cat in by_sort(fn.get("controls")):
            if is_withdrawn(cat):
                withdrawn.append(_csf_withdrawn(cat))
                for sub in cat.get("controls", []) or []:
                    withdrawn.append(_csf_withdrawn(sub))
                continue
            st = first_part(cat, "statement")
            cgroup = {
                "id": cat["id"],
                "displayId": cat["id"],
                "title": cat["title"],
                "description": clean_text(st.get("prose")) if st else None,
                "requirementIds": [],
            }
            for sub in by_sort(cat.get("controls")):
                if is_withdrawn(sub):
                    withdrawn.append(_csf_withdrawn(sub))
                    continue
                statement = clean_text(first_part(sub, "statement")["prose"])
                examples = [
                    {"label": f"Ex{i}", "text": clean_text(p["prose"])}
                    for i, p in enumerate(parts(sub, "guidance", "example"), start=1)
                ]
                reqs.append(prune({
                    "id": sub["id"],
                    "displayId": sub["id"],
                    "kind": "subcategory",
                    "title": statement,
                    "groupId": cat["id"],
                    "sortKey": prop(sub, "sort-id"),
                    "statement": [{"text": statement}],
                    "examples": examples,
                    "sourceUrl": CPRT_ELEMENT_URL.format(doc="CSF_2_0_0", element=sub["id"]),
                }))
                cgroup["requirementIds"].append(sub["id"])
            fgroup["groups"].append(prune(cgroup))
        groups.append(prune(fgroup))

    fw["groups"] = groups
    fw["requirements"] = reqs
    fw["withdrawn"] = withdrawn
    return fw


def _csf_withdrawn(obj: dict) -> dict:
    st = first_part(obj, "statement")
    return prune({
        "id": obj["id"],
        "displayId": obj["id"],
        "title": clean_text(st.get("prose")) if st and st.get("prose") else obj.get("title"),
        "incorporatedInto": links(obj, "incorporated_into"),
        "movedTo": links(obj, "moved_to"),
    })


# =============================================================================== SP 800-53 Rev 5

SP80053_INFO = {
    "shortName": "SP 800-53 Rev. 5",
    "title": "Security and Privacy Controls for Information Systems and Organizations",
    "publicationId": "NIST SP 800-53 Rev. 5",
    "version": "5.2.0",
    "sourceExtra": {
        "publicationUrl": "https://doi.org/10.6028/NIST.SP.800-53r5",
        "baselinesPublicationUrl": "https://doi.org/10.6028/NIST.SP.800-53B",
        "referenceToolUrl": "https://csrc.nist.gov/projects/cprt/catalog#/cprt/framework/version/SP_800_53_5_2_0/home",
    },
}

SP80053_BASELINES = [
    {"id": "low", "title": "Low", "additive": False,
     "summary": "For systems where a loss of confidentiality, integrity, or availability would have a limited adverse effect."},
    {"id": "moderate", "title": "Moderate", "additive": False,
     "summary": "For systems where a loss would have a serious adverse effect. The most commonly selected baseline."},
    {"id": "high", "title": "High", "additive": False,
     "summary": "For systems where a loss would have a severe or catastrophic adverse effect."},
    {"id": "privacy", "title": "Privacy", "additive": True,
     "summary": "Added on top of a security baseline when a system processes personally identifiable information."},
]


def baseline_ids(profile: dict) -> list[str]:
    ids: list[str] = []
    for imp in profile["profile"].get("imports", []):
        for inc in imp.get("include-controls", []):
            ids.extend(inc.get("with-ids", []))
    return ids


def build_sp80053(catalog: dict, profiles: dict[str, dict], source: dict, profile_sources: dict[str, dict],
                  content_version: str) -> dict:
    fw = framework_header("sp800-53r5", SP80053_INFO, source, content_version)
    fw["source"]["baselineProfiles"] = {
        bid: prune({"oscalUrl": s["url"], "version": s.get("version"), "sha256": s.get("sha256")})
        for bid, s in profile_sources.items()
    }
    fw["kinds"] = [
        {"id": "control", "singular": "Control", "plural": "Controls"},
        {"id": "enhancement", "singular": "Control Enhancement", "plural": "Control Enhancements"},
    ]
    fw["groupLevels"] = [{"singular": "Family", "plural": "Families"}]
    fw["baselines"] = SP80053_BASELINES
    membership: dict[str, list[str]] = {}
    for bid in BASELINE_ORDER:
        for cid in baseline_ids(profiles[bid]):
            membership.setdefault(cid, []).append(bid)

    resources = resource_index(catalog)
    groups, reqs, withdrawn = [], [], []

    def add(control: dict, kind: str, family: str, parent: str | None) -> None:
        cid = control["id"]
        if is_withdrawn(control):
            withdrawn.append(prune({
                "id": cid,
                "displayId": sp80053_display_id(cid),
                "title": control["title"],
                "incorporatedInto": [h.lstrip("#") for h in links(control, "incorporated-into")],
                "movedTo": [h.lstrip("#") for h in links(control, "moved-to")],
            }))
            return
        guidance = first_part(control, "guidance")
        objective = first_part(control, "assessment-objective")
        reqs.append(prune({
            "id": cid,
            "displayId": sp80053_display_id(cid),
            "kind": kind,
            "title": control["title"],
            "groupId": family,
            "parentId": parent,
            "sortKey": prop(control, "sort-id"),
            "statement": statement_items(first_part(control, "statement")),
            "discussion": clean_text(guidance.get("prose")) if guidance else None,
            "objectives": statement_items(objective, child_name="assessment-objective"),
            "parameters": [convert_param(p) for p in control.get("params", []) or []],
            "baselines": membership.get(cid, []),
            "implementationLevels": [p["value"] for p in control.get("props", []) if p.get("name") == "implementation-level"],
            "related": [h.lstrip("#") for h in links(control, "related")],
            "references": nist_references(control, resources),
            "sourceUrl": CPRT_ELEMENT_URL.format(doc="SP_800_53_5_2_0", element=sp80053_padded_id(cid)),
        }))

    for fam in catalog["groups"]:
        group = {"id": fam["id"], "displayId": prop(fam, "label") or fam["id"].upper(), "title": fam["title"],
                 "requirementIds": []}
        for control in fam.get("controls", []):
            add(control, "control", fam["id"], None)
            if not is_withdrawn(control):
                group["requirementIds"].append(control["id"])
            for enh in control.get("controls", []) or []:
                add(enh, "enhancement", fam["id"], control["id"])
        groups.append(group)

    fw["groups"] = groups
    fw["requirements"] = reqs
    fw["withdrawn"] = withdrawn
    return fw


# =============================================================================== SP 800-171 Rev 3

SP800171_INFO = {
    "shortName": "SP 800-171 Rev. 3",
    "title": "Protecting Controlled Unclassified Information in Nonfederal Systems and Organizations",
    "publicationId": "NIST SP 800-171 Rev. 3",
    "version": "3",
    "sourceExtra": {
        "publicationUrl": "https://doi.org/10.6028/NIST.SP.800-171r3",
        "referenceToolUrl": "https://csrc.nist.gov/projects/cprt/catalog#/cprt/framework/version/SP_800_171_3_0_0/home",
    },
}

_171_PREFIX = "SP_800_171_"


def _171_id(raw: str) -> str:
    return raw[len(_171_PREFIX):] if raw.startswith(_171_PREFIX) else raw


def _171_item_label(label: str | None) -> str | None:
    """'SR-03.01.01.c.02' -> '2.'; 'SR-03.01.01.a' -> 'a.'"""
    if not label:
        return None
    last = label.rsplit(".", 1)[-1]
    if last.isdigit():
        return f"{int(last)}."
    if re.fullmatch(r"[a-z]", last):
        return f"{last}."
    return None


def _171_objective_label(label: str | None) -> str | None:
    """'A.03.01.01.a' -> '03.01.01.a'; 'A.03.01.01.c.01[02]' kept without the 'A.' prefix."""
    if not label:
        return None
    return label[2:] if label.startswith("A.") else label


def sp800171_source_controls(catalog: dict) -> dict[str, list[str]]:
    """{'03.01.01': ['AC-02', 'AC-02(03)', ...]} from the requirement reference links."""
    resources = resource_index(catalog)
    out: dict[str, list[str]] = {}
    for fam in catalog["groups"]:
        for req in fam.get("controls", []):
            if is_withdrawn(req):
                continue
            labels = []
            for href in links(req, "reference"):
                res = resources.get(href.lstrip("#"))
                title = (res or {}).get("title", "").strip()
                if re.fullmatch(r"[A-Z]{2}-\d{2}(\(\d{2}\))?", title):
                    labels.append(title)
            out[_171_id(req["id"])] = labels
    return out


def build_sp800171(catalog: dict, source: dict, content_version: str) -> dict:
    fw = framework_header("sp800-171r3", SP800171_INFO, source, content_version)
    fw["kinds"] = [{"id": "requirement", "singular": "Security Requirement", "plural": "Security Requirements"}]
    fw["groupLevels"] = [{"singular": "Family", "plural": "Families"}]
    resources = resource_index(catalog)
    groups, reqs, withdrawn = [], [], []

    for fam in catalog["groups"]:
        gid = _171_id(fam["id"])
        group = {"id": gid, "displayId": gid, "title": fam["title"], "requirementIds": []}
        for req in fam.get("controls", []):
            rid = _171_id(req["id"])
            if is_withdrawn(req):
                withdrawn.append(prune({
                    "id": rid,
                    "displayId": rid,
                    "title": req["title"] if req.get("title") != rid else None,
                    "incorporatedInto": [_171_id(h) for h in links(req, "incorporated_into")],
                    "addressedBy": [_171_id(h) for h in links(req, "addressed_by")],
                }))
                continue
            guidance = first_part(req, "guidance")
            objective = first_part(req, "assessment-objective")
            reqs.append(prune({
                "id": rid,
                "displayId": rid,
                "kind": "requirement",
                "title": req["title"],
                "groupId": gid,
                "sortKey": prop(req, "sort-id"),
                "statement": statement_items(first_part(req, "statement"), label_fn=_171_item_label),
                "discussion": clean_text(guidance.get("prose")) if guidance else None,
                "objectives": statement_items(objective, child_name="assessment-objective",
                                              label_fn=_171_objective_label),
                "parameters": [convert_param(p) for p in req.get("params", []) or []],
                "references": nist_references(req, resources),
                "sourceUrl": CPRT_ELEMENT_URL.format(doc="SP_800_171_3_0_0", element=rid),
            }))
            group["requirementIds"].append(rid)
        groups.append(group)

    fw["groups"] = groups
    fw["requirements"] = reqs
    fw["withdrawn"] = withdrawn
    return fw
