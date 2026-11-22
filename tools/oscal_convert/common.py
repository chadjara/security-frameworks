"""Shared helpers for converting NIST OSCAL catalogs into the app's framework schema."""

from __future__ import annotations

import json
import pathlib
import re
from typing import Any, Callable, Iterable

SCHEMA_VERSION = 1

INSERT_RE = re.compile(r"\{\{\s*insert:\s*param,\s*([^\s}]+)\s*\}\}")
PARAM_TOKEN_RE = re.compile(r"\{\{param:([^}]+)\}\}")
MD_LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]*)\)")
MD_EMPHASIS_RE = re.compile(r"(?<!\w)\*([^*\n]+)\*(?!\w)")

# Reference titles kept in the bundle: NIST publications only. Everything else (ISO, IETF,
# OMB, executive orders, and so on) is dropped so that no third-party standard is bundled
# or implied. See docs/CONTENT_SOURCES.md.
NIST_REFERENCE_RE = re.compile(r"^(SP|FIPS|IR|NISTIR|CSWP|NIST)\s+\S")
SP80053_CONTROL_RE = re.compile(r"^([A-Z]{2})-(\d{2})(?:\((\d{2})\))?$")


# ----------------------------------------------------------------------------- text

def clean_text(s: str | None) -> str | None:
    """Normalize OSCAL prose: parameter inserts become {{param:ID}}, markdown links become
    their link text (or the CPRT element ID when the text is empty), whitespace is tidied."""
    if s is None:
        return None
    s = INSERT_RE.sub(lambda m: "{{param:%s}}" % m.group(1), s)

    def link(m: re.Match) -> str:
        text, href = m.group(1).strip(), m.group(2).strip()
        if text:
            return text
        el = re.search(r"element=([^&]+)$", href)
        return el.group(1) if el else href.lstrip("#")

    s = MD_LINK_RE.sub(link, s)
    s = MD_EMPHASIS_RE.sub(r"\1", s)
    s = s.replace("\r\n", "\n")
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\s*\n\s*\n\s*", "\n\n", s)
    s = re.sub(r"(?<!\n)\n(?!\n)", " ", s)
    return s.strip()


def param_tokens(s: str | None) -> list[str]:
    return PARAM_TOKEN_RE.findall(s or "")


# ----------------------------------------------------------------------------- OSCAL access

def props(obj: dict, name: str) -> list[dict]:
    return [p for p in obj.get("props", []) or [] if p.get("name") == name]


def prop(obj: dict, name: str, cls: str | None = None, default: Any = None) -> Any:
    for p in props(obj, name):
        if cls is None or p.get("class") == cls:
            return p.get("value")
    return default


def is_withdrawn(obj: dict) -> bool:
    return prop(obj, "status") == "withdrawn"


def parts(obj: dict, name: str, cls: str | None = None) -> list[dict]:
    return [
        p for p in obj.get("parts", []) or []
        if p.get("name") == name and (cls is None or p.get("class") == cls)
    ]


def first_part(obj: dict, name: str) -> dict | None:
    found = parts(obj, name)
    return found[0] if found else None


def links(obj: dict, *rels: str) -> list[str]:
    return [l["href"] for l in obj.get("links", []) or [] if l.get("rel") in rels]


# ----------------------------------------------------------------------------- statements

def _item(part: dict, child_name: str, label_fn: Callable[[str | None], str | None]) -> dict:
    out: dict[str, Any] = {}
    label = label_fn(prop(part, "label"))
    if label:
        out["label"] = label
    text = clean_text(part.get("prose"))
    if text:
        out["text"] = text
    children = [_item(p, child_name, label_fn) for p in part.get("parts", []) or [] if p.get("name") == child_name]
    if children:
        out["items"] = children
    return out


def statement_items(
    statement: dict | None,
    child_name: str = "item",
    label_fn: Callable[[str | None], str | None] = lambda l: l,
) -> list[dict]:
    """Convert a statement (or assessment-objective) part into a list of nested items.
    Top-level prose becomes an unlabeled item that holds the sub-items."""
    if not statement:
        return []
    children = [
        _item(p, child_name, label_fn)
        for p in statement.get("parts", []) or []
        if p.get("name") == child_name
    ]
    text = clean_text(statement.get("prose"))
    if text:
        root: dict[str, Any] = {"text": text}
        if children:
            root["items"] = children
        return [root]
    return children


def iter_items(items: Iterable[dict]) -> Iterable[dict]:
    for it in items:
        yield it
        yield from iter_items(it.get("items", []))


# ----------------------------------------------------------------------------- parameters

SELECT_PLACEHOLDER_LABELS = {"SELECTED PARAMETER VALUES"}


def convert_param(p: dict) -> dict:
    out: dict[str, Any] = {"id": p["id"]}
    display = prop(p, "label")
    if display:
        out["displayLabel"] = display
    label = clean_text(p.get("label"))
    if label and label not in SELECT_PLACEHOLDER_LABELS:
        out["label"] = label
    usage = clean_text(p.get("usage"))
    if usage:
        out["usage"] = usage
    guidance = [clean_text(g.get("prose")) for g in p.get("guidelines", []) or []]
    guidance = [g for g in guidance if g]
    if guidance:
        out["guidance"] = " ".join(guidance)
    sel = p.get("select")
    if sel:
        out["choices"] = [clean_text(c) for c in sel.get("choice", [])]
        out["howMany"] = sel.get("how-many", "one")
    aggregates = [x["value"] for x in props(p, "aggregates")]
    if aggregates:
        out["aggregates"] = aggregates
    alt = prop(p, "alt-identifier")
    if alt:
        out["altId"] = alt
    return out


# ----------------------------------------------------------------------------- references

def nist_references(obj: dict, resources: dict[str, dict]) -> list[dict]:
    """Return NIST-publication references for a control; drop everything else."""
    out = []
    seen = set()
    for href in links(obj, "reference"):
        res = resources.get(href.lstrip("#"))
        if not res:
            continue
        title = (res.get("title") or "").strip()
        if not NIST_REFERENCE_RE.match(title) or title in seen:
            continue
        url = next((r.get("href") for r in res.get("rlinks", []) or [] if r.get("href", "").startswith("http")), None)
        ref = {"title": title}
        if url:
            ref["url"] = url
        out.append(ref)
        seen.add(title)
    return out


def resource_index(catalog: dict) -> dict[str, dict]:
    return {r["uuid"]: r for r in catalog.get("back-matter", {}).get("resources", [])}


# ----------------------------------------------------------------------------- SP 800-53 IDs

def sp80053_display_id(control_id: str) -> str:
    """'ac-2.1' -> 'AC-2(1)'"""
    base, _, enh = control_id.partition(".")
    fam, _, num = base.partition("-")
    out = f"{fam.upper()}-{int(num)}"
    return f"{out}({int(enh)})" if enh else out


def sp80053_padded_id(control_id: str) -> str:
    """'ac-2.1' -> 'AC-02(01)' (the form used by CPRT and SP 800-171 Rev 3)."""
    base, _, enh = control_id.partition(".")
    fam, _, num = base.partition("-")
    out = f"{fam.upper()}-{int(num):02d}"
    return f"{out}({int(enh):02d})" if enh else out


def sp80053_id_from_label(label: str) -> str | None:
    """'AC-02(03)' or 'AC-2(3)' -> 'ac-2.3'; None if it is not an 800-53 control label."""
    m = re.match(r"^([A-Z]{2})-(\d{1,2})(?:\((\d{1,2})\))?$", label.strip())
    if not m:
        return None
    fam, num, enh = m.groups()
    out = f"{fam.lower()}-{int(num)}"
    return f"{out}.{int(enh)}" if enh else out


# ----------------------------------------------------------------------------- output

def write_json(path: pathlib.Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def load_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def prune(d: dict) -> dict:
    """Remove keys whose values are None, empty lists, or empty dicts."""
    return {k: v for k, v in d.items() if v not in (None, [], {}, "")}
