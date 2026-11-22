"""Unit tests for the OSCAL converter. Run from the repo root:

    python3 -m unittest discover -s tools/oscal_convert/tests -v
"""

from __future__ import annotations

import io
import json
import pathlib
import sys
import unittest
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import common  # noqa: E402
import editorial  # noqa: E402
import frameworks  # noqa: E402
import mappings  # noqa: E402
import validate  # noqa: E402
import xlsxlite  # noqa: E402
from fetch_sources import extract_cprt_references  # noqa: E402

FIXTURES = HERE / "fixtures"
SOURCE = {"url": "https://example.test/catalog.json", "sha256": "0" * 64, "retrieved": "2026-11-22T00:00:00Z",
          "title": "Fixture", "version": "1"}


def load_fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text())


class TextTests(unittest.TestCase):
    def test_insert_tokens_are_normalized(self):
        self.assertEqual(common.clean_text("Review {{ insert: param, ac-01_odp.05 }} annually."),
                         "Review {{param:ac-01_odp.05}} annually.")

    def test_markdown_links_become_text(self):
        self.assertEqual(common.clean_text("Addressed by [AC-11](#ac-11)."), "Addressed by AC-11.")

    def test_empty_cprt_link_uses_element_id(self):
        s = "see [](#/cprt/framework/version/SP_800_171_3_0_0/home?element=03.01.02) for details"
        self.assertEqual(common.clean_text(s), "see 03.01.02 for details")

    def test_empty_link_followed_by_id_is_not_doubled(self):
        base = "[](#/cprt/framework/version/SP_800_171_3_0_0/home?element=03.01.02)"
        self.assertEqual(common.clean_text(f"addressed in {base}03.01.02."), "addressed in 03.01.02.")
        self.assertEqual(common.clean_text(f"addressed by {base} 03.01.02."), "addressed by 03.01.02.")

    def test_whitespace_and_paragraphs(self):
        self.assertEqual(common.clean_text("  one\ntwo   three\n\n  four "), "one two three\n\nfour")

    def test_emphasis_removed(self):
        self.assertEqual(common.clean_text("Title 32, *Controlled Unclassified Information*"),
                         "Title 32, Controlled Unclassified Information")

    def test_param_tokens(self):
        self.assertEqual(common.param_tokens("a {{param:x}} b {{param:y.1}}"), ["x", "y.1"])


class IdentifierTests(unittest.TestCase):
    def test_display_and_padded(self):
        self.assertEqual(common.sp80053_display_id("ac-2"), "AC-2")
        self.assertEqual(common.sp80053_display_id("ac-2.13"), "AC-2(13)")
        self.assertEqual(common.sp80053_padded_id("si-4.5"), "SI-04(05)")

    def test_from_label(self):
        self.assertEqual(common.sp80053_id_from_label("AC-02(03)"), "ac-2.3")
        self.assertEqual(common.sp80053_id_from_label("PM-11"), "pm-11")
        self.assertIsNone(common.sp80053_id_from_label("PT"))
        self.assertIsNone(common.sp80053_id_from_label("SP 800-53"))

    def test_171_labels(self):
        self.assertEqual(frameworks._171_item_label("SR-03.01.01.c.02"), "2.")
        self.assertEqual(frameworks._171_item_label("SR-03.01.01.a"), "a.")
        self.assertEqual(frameworks._171_id("SP_800_171_03.01.01"), "03.01.01")


class StatementAndParameterTests(unittest.TestCase):
    def test_nested_items(self):
        st = {"name": "statement", "parts": [
            {"name": "item", "props": [{"name": "label", "value": "a."}], "prose": "Do this:", "parts": [
                {"name": "item", "props": [{"name": "label", "value": "1."}], "prose": "first"}]},
            {"name": "item", "props": [{"name": "label", "value": "b."}], "prose": "Then that."}]}
        self.assertEqual(common.statement_items(st), [
            {"label": "a.", "text": "Do this:", "items": [{"label": "1.", "text": "first"}]},
            {"label": "b.", "text": "Then that."}])

    def test_prose_root_holds_children(self):
        st = {"name": "statement", "prose": "Specify:", "parts": [{"name": "item", "prose": "x"}]}
        self.assertEqual(common.statement_items(st), [{"text": "Specify:", "items": [{"text": "x"}]}])

    def test_select_param(self):
        p = {"id": "x_odp", "props": [{"name": "label", "value": "X_ODP"}, {"name": "alt-identifier", "value": "x_prm_1"}],
             "label": "SELECTED PARAMETER VALUES", "select": {"how-many": "one-or-more", "choice": ["a", "b"]}}
        self.assertEqual(common.convert_param(p), {"id": "x_odp", "displayLabel": "X_ODP", "choices": ["a", "b"],
                                                   "howMany": "one-or-more", "altId": "x_prm_1"})

    def test_aggregate_param(self):
        p = {"id": "ac-1_prm_1", "label": "organization-defined personnel or roles",
             "props": [{"name": "aggregates", "value": "ac-01_odp.01"}, {"name": "aggregates", "value": "ac-01_odp.02"}]}
        self.assertEqual(common.convert_param(p)["aggregates"], ["ac-01_odp.01", "ac-01_odp.02"])


class ReferenceWhitelistTests(unittest.TestCase):
    def test_only_nist_publications_are_kept(self):
        resources = {
            "a": {"title": "SP 800-63-3", "rlinks": [{"href": "https://doi.org/10.6028/NIST.SP.800-63-3"}]},
            "b": {"title": "ISO 15408-1", "rlinks": [{"href": "https://www.iso.org/x"}]},
            "c": {"title": "FIPS 199"},
            "d": {"title": "OMB A-130"},
            "e": {"title": "IR 7874"},
            "f": {"title": "IR-04"},
        }
        control = {"links": [{"rel": "reference", "href": f"#{k}"} for k in resources]}
        titles = [r["title"] for r in common.nist_references(control, resources)]
        self.assertEqual(titles, ["SP 800-63-3", "FIPS 199", "IR 7874"])


class BuilderTests(unittest.TestCase):
    def test_csf_fixture(self):
        fw = frameworks.build_csf(load_fixture("csf_mini.json")["catalog"], SOURCE, "2026.11.0")
        self.assertEqual([r["id"] for r in fw["requirements"]], ["GV.OC-01", "GV.RM-01"])  # sorted by sort-id
        self.assertEqual([w["id"] for w in fw["withdrawn"]], ["ID.AM-06"])
        self.assertEqual(fw["requirements"][0]["examples"][0]["label"], "Ex1")
        self.assertEqual(fw["groups"][0]["title"], "Govern")
        errors, _ = validate.validate_framework(fw)
        self.assertEqual(errors, [])

    def test_sp80053_fixture(self):
        cat = load_fixture("sp80053_mini.json")["catalog"]
        profiles = {b: {"profile": {"imports": [{"include-controls": [{"with-ids": ids}]}]}}
                    for b, ids in {"low": ["ac-1"], "moderate": ["ac-1", "ac-2", "ac-2.1"],
                                   "high": ["ac-1", "ac-2", "ac-2.1"], "privacy": ["ac-1"]}.items()}
        fw = frameworks.build_sp80053(cat, profiles, SOURCE, {b: SOURCE for b in profiles}, "2026.11.0")
        ids = [r["id"] for r in fw["requirements"]]
        self.assertEqual(ids, ["ac-1", "ac-2", "ac-2.1"])
        self.assertEqual([w["id"] for w in fw["withdrawn"]], ["ac-2.10"])
        by_id = {r["id"]: r for r in fw["requirements"]}
        self.assertEqual(by_id["ac-2.1"]["parentId"], "ac-2")
        self.assertEqual(by_id["ac-2.1"]["baselines"], ["moderate", "high"])
        self.assertEqual(by_id["ac-1"]["baselines"], ["low", "moderate", "high", "privacy"])
        self.assertEqual(by_id["ac-2.1"]["displayId"], "AC-2(1)")
        self.assertTrue(by_id["ac-2"]["sourceUrl"].endswith("element=AC-02"))
        self.assertEqual(fw["groups"][0]["requirementIds"], ["ac-1", "ac-2"])
        errors, _ = validate.validate_framework(fw)
        self.assertEqual(errors, [])

    def test_sp800171_fixture_and_source_controls(self):
        cat = load_fixture("sp800171_mini.json")["catalog"]
        fw = frameworks.build_sp800171(cat, SOURCE, "2026.11.0")
        self.assertEqual([r["id"] for r in fw["requirements"]], ["03.01.01"])
        self.assertEqual(fw["withdrawn"][0]["addressedBy"], ["03.13.08"])
        st = fw["requirements"][0]["statement"]
        self.assertEqual(st[0]["label"], "a.")
        self.assertEqual(st[1]["items"][0]["label"], "2.")
        self.assertEqual(frameworks.sp800171_source_controls(cat), {"03.01.01": ["AC-02", "AC-02(03)"]})
        self.assertEqual([r["title"] for r in fw["requirements"][0]["references"]], ["SP 800-46"])
        self.assertEqual(fw["requirements"][0]["objectives"],
                         [{"text": "types of system accounts allowed for use are defined.", "label": "a[01]"},
                          {"text": "system accounts are created in accordance with policy.", "label": "b[01]"}])
        errors, _ = validate.validate_framework(fw)
        self.assertEqual(errors, [])


class MappingTests(unittest.TestCase):
    def setUp(self):
        self.fw53 = {"id": "sp800-53r5", "shortName": "SP 800-53 Rev. 5",
                     "requirements": [{"id": "ac-2"}, {"id": "ac-2.3"}, {"id": "pm-9"}],
                     "withdrawn": [{"id": "ra-4"}]}
        self.fw171 = {"id": "sp800-171r3", "shortName": "SP 800-171 Rev. 3",
                      "requirements": [{"id": "03.01.01"}, {"id": "03.01.02"}]}
        self.csf = {"id": "csf-2.0", "requirements": [{"id": "GV.OC-01"}, {"id": "DE.AE-06"}]}

    def test_171_to_53(self):
        m = mappings.build_sp800171_to_sp80053({"03.01.01": ["AC-02", "AC-02(03)", "AC-02(03)"], "03.01.02": []},
                                               self.fw171, self.fw53, SOURCE, "2026.11.0")
        self.assertEqual(m["entries"], [{"from": "03.01.01", "to": ["ac-2", "ac-2.3"]}])
        self.assertEqual(m["relationship"]["type"], "source-control")

    def test_csf_to_53_skips_family_and_withdrawn(self):
        cprt = {"references": {"GV.OC-01": {"sp800-53r5": ["PM-09", "PT"]}, "DE.AE-06": {"sp800-53r5": ["RA-04"]}}}
        m = mappings.build_csf_to("sp800-53r5", cprt, self.csf, self.fw53, {"url": "https://x.test"}, "2026.11.0")
        self.assertEqual(m["entries"], [{"from": "GV.OC-01", "to": ["pm-9"]}])
        reasons = {u["sourceValue"]: u["reason"] for u in m["unresolved"]}
        self.assertEqual(reasons["PT"], "family-level reference, not a single control")
        self.assertEqual(reasons["RA-04"], "withdrawn in target")

    def test_validate_mapping_rejects_unknown_targets(self):
        m = {"id": "a_to_b", "fromFramework": "csf-2.0", "toFramework": "sp800-53r5", "source": {"url": "x"},
             "entries": [{"from": "GV.OC-01", "to": ["zz-1"]}]}
        errors, _ = validate.validate_mapping(m, {"csf-2.0": self.csf, "sp800-53r5": self.fw53})
        self.assertTrue(any("unknown target zz-1" in e for e in errors))


class EditorialTests(unittest.TestCase):
    FW = {"id": "csf-2.0", "requirements": [{"id": "GV.OC-01"}]}
    GOOD = {"question": "Does your organization write down its mission?", "whyItMatters": "Context.",
            "doneLooksLike": "A short, current statement.", "nextSteps": ["Write it down."]}
    SUMMARY = {k: "Text." for k in editorial.SUMMARY_FIELDS}

    def test_lint_rules(self):
        self.assertTrue(editorial.lint_text("x", "Great job!"))
        self.assertTrue(editorial.lint_text("x", "Supercharge your security"))
        self.assertTrue(editorial.lint_text("x", "Locked \U0001F512"))
        self.assertTrue(editorial.lint_text("x", "double  space"))
        self.assertEqual(editorial.lint_text("x", "Review access quarterly."), [])

    def test_unknown_requirement_and_missing_fields(self):
        overlay = {"frameworkId": "csf-2.0", "summary": self.SUMMARY,
                   "requirements": {"XX-01": self.GOOD, "GV.OC-01": {"question": "Q?"}}}
        errors = editorial.lint_overlay(overlay, self.FW)
        self.assertTrue(any("XX-01 is not an active requirement" in e for e in errors))
        self.assertTrue(any("GV.OC-01.whyItMatters is missing" in e for e in errors))

    def test_merge(self):
        fw = {"id": "csf-2.0", "requirements": [{"id": "GV.OC-01"}]}
        editorial.merge_overlay(fw, {"summary": self.SUMMARY, "requirements": {"GV.OC-01": self.GOOD}})
        self.assertEqual(fw["requirements"][0]["editorial"]["reviewed"], False)
        self.assertEqual(fw["summary"]["audience"], "Text.")

    def test_in_scope_excludes_unbaselined_80053(self):
        fw = {"id": "sp800-53r5", "requirements": [{"id": "ac-1", "baselines": ["low"]}, {"id": "ac-2.13"}]}
        self.assertEqual(editorial.in_scope_ids(fw), ["ac-1"])


def make_xlsx(rows: list[list[str]], sheet: str = "CSF 2.0") -> bytes:
    strings: list[str] = []

    def idx(s: str) -> int:
        if s not in strings:
            strings.append(s)
        return strings.index(s)

    cols = "ABCDE"
    sheet_rows = []
    for r, row in enumerate(rows, start=1):
        cells = "".join(f'<c r="{cols[c]}{r}" t="s"><v>{idx(v)}</v></c>' for c, v in enumerate(row) if v)
        sheet_rows.append(f'<row r="{r}">{cells}</row>')
    ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    rns = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
    from xml.sax.saxutils import escape
    sst = "".join(f"<si><t>{escape(s)}</t></si>" for s in strings)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("xl/workbook.xml", f'<workbook {ns} {rns}><sheets><sheet name="{sheet}" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr("xl/_rels/workbook.xml.rels",
                   '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rId1" Target="worksheets/sheet1.xml" Type="x"/></Relationships>')
        z.writestr("xl/sharedStrings.xml", f"<sst {ns}>{sst}</sst>")
        z.writestr("xl/worksheets/sheet1.xml", f"<worksheet {ns}><sheetData>{''.join(sheet_rows)}</sheetData></worksheet>")
    return buf.getvalue()


class CprtExtractionTests(unittest.TestCase):
    def test_reads_cells(self):
        rows = xlsxlite.read_sheet_rows(make_xlsx([["a", "b"], ["", "", "c"]]), "CSF 2.0")
        self.assertEqual(rows, [{"A": "a", "B": "b"}, {"C": "c"}])

    def test_only_nist_references_kept(self):
        data = make_xlsx([
            ["title"],
            ["Function", "Category", "Subcategory", "Implementation Examples", "Informative References"],
            ["GOVERN (GV): text", "", "", "", "ISO/IEC 27001:2022: 6.1"],
            ["", "", "GV.OC-01: The mission is understood", "Ex1: x",
             "CCMv4.0: BCR-01\nSP 800-53 Rev 5.1.1: PM-11\nSP 800-53 Rev 5.2.0: PM-11\nSP 800-171 Rev 3: 03.15.01\nPCI DSS: 12.1"],
        ])
        refs, info = extract_cprt_references(data)
        self.assertEqual(refs, {"GV.OC-01": {"sp800-53r5": ["PM-11"], "sp800-171r3": ["03.15.01"]}})
        self.assertEqual(info["discardedNonNistReferences"], 3)


if __name__ == "__main__":
    unittest.main()
