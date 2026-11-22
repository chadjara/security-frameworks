"""Minimal .xlsx reader (standard library only): enough to read text cells from one sheet."""

from __future__ import annotations

import io
import re
import zipfile
import xml.etree.ElementTree as ET

_NS = {
    "m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "pr": "http://schemas.openxmlformats.org/package/2006/relationships",
}
_COL = re.compile(r"[A-Z]+")


def _shared_strings(z: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in z.namelist():
        return []
    root = ET.fromstring(z.read("xl/sharedStrings.xml"))
    t_tag = "{%s}t" % _NS["m"]
    return ["".join(t.text or "" for t in si.iter(t_tag)) for si in root.findall("m:si", _NS)]


def _sheet_path(z: zipfile.ZipFile, sheet_name: str) -> str:
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    targets = {r.get("Id"): r.get("Target") for r in rels.findall("pr:Relationship", _NS)}
    for sheet in wb.findall("m:sheets/m:sheet", _NS):
        if sheet.get("name") == sheet_name:
            target = targets[sheet.get("{%s}id" % _NS["r"])]
            target = target.lstrip("/")
            return target if target.startswith("xl/") else "xl/" + target
    raise KeyError(f"Sheet {sheet_name!r} not found")


def read_sheet_rows(data: bytes, sheet_name: str) -> list[dict[str, str]]:
    """Return one dict per row, mapping column letters to cell text. Empty cells are omitted."""
    z = zipfile.ZipFile(io.BytesIO(data))
    strings = _shared_strings(z)
    root = ET.fromstring(z.read(_sheet_path(z, sheet_name)))
    rows: list[dict[str, str]] = []
    for row in root.findall(".//m:sheetData/m:row", _NS):
        cells: dict[str, str] = {}
        for c in row.findall("m:c", _NS):
            col = _COL.match(c.get("r", "")).group()
            kind = c.get("t")
            if kind == "inlineStr":
                cells[col] = "".join(t.text or "" for t in c.iter("{%s}t" % _NS["m"]))
                continue
            v = c.find("m:v", _NS)
            if v is None or v.text is None:
                continue
            cells[col] = strings[int(v.text)] if kind == "s" else v.text
        rows.append(cells)
    return rows
