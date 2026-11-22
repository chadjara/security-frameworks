"""Structural validation for generated framework, mapping, and index files (standard library only).

The same rules are enforced again at app level by FrameworkKit's validator and tests.
"""

from __future__ import annotations

import re
from collections import Counter

from common import SCHEMA_VERSION, iter_items, param_tokens

ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._()-]*$")
REQUIRED_FRAMEWORK_KEYS = ["schemaVersion", "id", "shortName", "title", "publisher", "version", "contentVersion",
                           "source", "kinds", "groupLevels", "groups", "requirements"]
REQUIRED_REQUIREMENT_KEYS = ["id", "displayId", "kind", "title", "groupId", "sortKey", "statement", "sourceUrl"]


def _walk_groups(groups: list[dict], depth: int = 0):
    for g in groups:
        yield g, depth
        yield from _walk_groups(g.get("groups", []), depth + 1)


def validate_framework(fw: dict) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    fid = fw.get("id", "?")

    for k in REQUIRED_FRAMEWORK_KEYS:
        if k not in fw:
            errors.append(f"{fid}: missing key {k}")
    if errors:
        return errors, warnings
    if fw["schemaVersion"] != SCHEMA_VERSION:
        errors.append(f"{fid}: schemaVersion {fw['schemaVersion']} != {SCHEMA_VERSION}")
    for k in ("oscalUrl", "sha256", "retrieved"):
        if not fw["source"].get(k):
            errors.append(f"{fid}: source.{k} is missing")

    kinds = {k["id"] for k in fw["kinds"]}
    reqs = fw["requirements"]
    ids = [r.get("id") for r in reqs]
    dupes = [i for i, n in Counter(ids).items() if n > 1]
    if dupes:
        errors.append(f"{fid}: duplicate requirement ids {dupes[:5]}")
    by_id = {r["id"]: r for r in reqs}

    group_ids: list[str] = []
    grouped_reqs: list[str] = []
    max_depth = 0
    for g, depth in _walk_groups(fw["groups"]):
        group_ids.append(g["id"])
        max_depth = max(max_depth, depth)
        if not g.get("title"):
            errors.append(f"{fid}: group {g['id']} has no title")
        if g.get("groups") and g.get("requirementIds"):
            errors.append(f"{fid}: group {g['id']} has both subgroups and requirements")
        for rid in g.get("requirementIds", []):
            grouped_reqs.append(rid)
            if rid not in by_id:
                errors.append(f"{fid}: group {g['id']} lists unknown requirement {rid}")
            elif by_id[rid].get("groupId") != g["id"]:
                errors.append(f"{fid}: {rid} is listed in group {g['id']} but has groupId {by_id[rid].get('groupId')}")
    if max_depth + 1 != len(fw["groupLevels"]):
        errors.append(f"{fid}: group depth {max_depth + 1} does not match groupLevels ({len(fw['groupLevels'])})")
    if len(set(group_ids)) != len(group_ids):
        errors.append(f"{fid}: duplicate group ids")

    baseline_ids = {b["id"] for b in fw.get("baselines", [])}
    family_tree: dict[str, list[dict]] = {}
    for r in reqs:
        family_tree.setdefault(r.get("parentId") or r["id"], []).append(r)
    for r in reqs:
        rid = r.get("id", "?")
        for k in REQUIRED_REQUIREMENT_KEYS:
            if not r.get(k):
                errors.append(f"{fid}: {rid} missing {k}")
        if not ID_RE.match(rid):
            errors.append(f"{fid}: invalid id {rid!r}")
        if r.get("kind") not in kinds:
            errors.append(f"{fid}: {rid} has unknown kind {r.get('kind')}")
        if r.get("groupId") not in group_ids:
            errors.append(f"{fid}: {rid} has unknown groupId {r.get('groupId')}")
        parent = r.get("parentId")
        if parent:
            if parent not in by_id:
                errors.append(f"{fid}: {rid} has unknown parent {parent}")
        elif rid not in grouped_reqs:
            errors.append(f"{fid}: top-level requirement {rid} is not listed in any group")
        for b in r.get("baselines", []):
            if b not in baseline_ids:
                errors.append(f"{fid}: {rid} has unknown baseline {b}")
        for rel in r.get("related", []):
            if rel not in by_id:
                warnings.append(f"{fid}: {rid} related -> {rel} is not an active requirement")
        # Parameter tokens must resolve to a parameter of this requirement.
        # SP 800-53 enhancements may use parameters defined on their base control or on a sibling
        # enhancement (for example SC-42(2) uses SC-42(1)'s parameter), so resolve within the family tree.
        param_ids = set()
        root = parent or rid
        scope = [p for x in family_tree.get(root, [r]) for p in x.get("parameters", [])]
        for p in scope:
            param_ids.add(p["id"])
            if p.get("altId"):
                param_ids.add(p["altId"])
        texts = [it.get("text") for it in iter_items(r.get("statement", []))]
        for p in r.get("parameters", []):
            texts += p.get("choices", [])
        for t in texts:
            for tok in param_tokens(t):
                if tok not in param_ids:
                    errors.append(f"{fid}: {rid} references unknown parameter {tok}")
        for p in r.get("parameters", []):
            for agg in p.get("aggregates", []):
                if agg not in param_ids:
                    errors.append(f"{fid}: {rid} parameter {p['id']} aggregates unknown {agg}")
        if not r.get("sourceUrl", "").startswith("https://csrc.nist.gov/"):
            errors.append(f"{fid}: {rid} sourceUrl is not a csrc.nist.gov URL")
        ed = r.get("editorial")
        if ed:
            for k in ("question", "whyItMatters", "doneLooksLike", "nextSteps"):
                if not ed.get(k):
                    errors.append(f"{fid}: {rid} editorial.{k} is empty")

    sort_keys = [r.get("sortKey") for r in reqs]
    if sort_keys != sorted(sort_keys):
        errors.append(f"{fid}: requirements are not in sortKey order")
    return errors, warnings


def validate_mapping(m: dict, frameworks: dict[str, dict]) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    mid = m.get("id", "?")
    src, dst = frameworks.get(m.get("fromFramework")), frameworks.get(m.get("toFramework"))
    if not src or not dst:
        return [f"{mid}: unknown framework(s) {m.get('fromFramework')} -> {m.get('toFramework')}"], warnings
    src_ids = {r["id"] for r in src["requirements"]}
    dst_ids = {r["id"] for r in dst["requirements"]}
    seen = set()
    for e in m.get("entries", []):
        if e["from"] in seen:
            errors.append(f"{mid}: duplicate entry for {e['from']}")
        seen.add(e["from"])
        if e["from"] not in src_ids:
            errors.append(f"{mid}: unknown source {e['from']}")
        if not e.get("to"):
            errors.append(f"{mid}: {e['from']} has no targets")
        for t in e.get("to", []):
            if t not in dst_ids:
                errors.append(f"{mid}: {e['from']} -> unknown target {t}")
    for u in m.get("unresolved", []):
        warnings.append(f"{mid}: {u['from']} -> {u['sourceValue']} skipped ({u['reason']})")
    if not m.get("source", {}).get("url"):
        errors.append(f"{mid}: source.url is missing")
    return errors, warnings
