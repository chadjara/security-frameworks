"""Editorial overlays: plain-language content written for this app, kept separate from NIST data.

Each framework has data/editorial/<framework-id>.json:

    {
      "frameworkId": "csf-2.0",
      "summary": {plainDescription, audience, covers, typicalEffort, whenToChoose},
      "notices": [{id, title, body}],
      "requirements": {
        "<requirement id>": {question, whyItMatters, doneLooksLike, nextSteps: [..], reviewed: false}
      }
    }

The converter merges these into the generated framework files. Regenerating NIST data never
touches the overlay files.
"""

from __future__ import annotations

import pathlib
import re
from typing import Any

from common import load_json

SUMMARY_FIELDS = ["plainDescription", "audience", "covers", "typicalEffort", "whenToChoose"]
REQUIREMENT_FIELDS = ["question", "whyItMatters", "doneLooksLike", "nextSteps"]

# Copy rules from the product brief: calm, precise, plain language; no marketing tone.
BANNED_PHRASES = [
    "supercharge", "game-changer", "game changer", "revolutionize", "unlock the power", "seamless",
    "cutting-edge", "cutting edge", "next-level", "world-class", "best-in-class", "effortless",
    "lorem ipsum", "todo", "tbd", "placeholder",
]
EMOJI_RE = re.compile(
    "[\U0001F000-\U0001FAFF\U00002600-\U000027BF\U0001F900-\U0001F9FF\U0000FE0F\U00002B50\U00002B55]"
)


def load_overlay(directory: pathlib.Path, framework_id: str) -> dict[str, Any]:
    """Load data/editorial/<id>.json plus any batch files in data/editorial/<id>/*.json.

    Batch files hold only {"requirements": {...}} and keep large overlays reviewable in pieces.
    """
    path = directory / f"{framework_id}.json"
    data = load_json(path) if path.exists() else {"frameworkId": framework_id}
    data.setdefault("requirements", {})
    duplicates: list[str] = []
    batch_dir = directory / framework_id
    if batch_dir.is_dir():
        for batch in sorted(batch_dir.glob("*.json")):
            for rid, entry in load_json(batch).get("requirements", {}).items():
                if rid in data["requirements"]:
                    duplicates.append(f"{rid} ({batch.name})")
                data["requirements"][rid] = entry
    data["_duplicates"] = duplicates
    return data


def lint_text(where: str, text: str) -> list[str]:
    errors = []
    if EMOJI_RE.search(text):
        errors.append(f"{where}: contains an emoji")
    if "!" in text:
        errors.append(f"{where}: contains an exclamation mark")
    lowered = text.lower()
    for phrase in BANNED_PHRASES:
        if re.search(r"\b" + re.escape(phrase) + r"\b", lowered):
            errors.append(f"{where}: contains banned phrase '{phrase}'")
    if text != text.strip() or "  " in text:
        errors.append(f"{where}: has stray whitespace")
    return errors


def lint_overlay(overlay: dict, framework: dict) -> list[str]:
    fid = overlay.get("frameworkId")
    errors: list[str] = []
    if fid != framework["id"]:
        errors.append(f"editorial/{fid}: frameworkId does not match {framework['id']}")
    summary = overlay.get("summary") or {}
    for f in SUMMARY_FIELDS:
        if not summary.get(f):
            errors.append(f"editorial/{fid}: summary.{f} is missing")
        else:
            errors += lint_text(f"editorial/{fid}: summary.{f}", summary[f])
    for n in overlay.get("notices", []):
        for f in ("id", "title", "body"):
            if not n.get(f):
                errors.append(f"editorial/{fid}: notice missing {f}")
        errors += lint_text(f"editorial/{fid}: notice {n.get('id')}", n.get("body", ""))
    for dup in overlay.get("_duplicates", []):
        errors.append(f"editorial/{fid}: {dup} is defined more than once")
    known = {r["id"] for r in framework["requirements"]}
    for rid, entry in overlay.get("requirements", {}).items():
        if rid not in known:
            errors.append(f"editorial/{fid}: {rid} is not an active requirement")
            continue
        for f in REQUIREMENT_FIELDS:
            value = entry.get(f)
            if not value:
                errors.append(f"editorial/{fid}: {rid}.{f} is missing")
                continue
            for i, text in enumerate(value if isinstance(value, list) else [value]):
                errors += lint_text(f"editorial/{fid}: {rid}.{f}[{i}]" if isinstance(value, list) else
                                    f"editorial/{fid}: {rid}.{f}", text)
    return errors


def merge_overlay(framework: dict, overlay: dict) -> None:
    if overlay.get("summary"):
        framework["summary"] = {k: overlay["summary"][k] for k in SUMMARY_FIELDS if k in overlay["summary"]}
    if overlay.get("notices"):
        framework["notices"] = overlay["notices"]
    entries = overlay.get("requirements", {})
    for req in framework["requirements"]:
        entry = entries.get(req["id"])
        if entry:
            req["editorial"] = {
                "question": entry["question"],
                "whyItMatters": entry["whyItMatters"],
                "doneLooksLike": entry["doneLooksLike"],
                "nextSteps": list(entry["nextSteps"]),
                "reviewed": bool(entry.get("reviewed", False)),
            }


def in_scope_ids(framework: dict) -> list[str]:
    """Requirements that must have editorial content: all of them, except SP 800-53 items
    that are in no baseline (those fall back to NIST's own text)."""
    if framework["id"] == "sp800-53r5":
        return [r["id"] for r in framework["requirements"] if r.get("baselines")]
    return [r["id"] for r in framework["requirements"]]
