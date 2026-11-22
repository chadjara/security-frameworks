"""Checks on the committed, generated content in App/Resources/Content."""

from __future__ import annotations

import json
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import convert  # noqa: E402

ROOT = HERE.parents[2]
CONTENT = ROOT / "App" / "Resources" / "Content"
SCHEMAS = ROOT / "schema"

try:
    import jsonschema  # type: ignore
except ImportError:  # pragma: no cover
    jsonschema = None


def load(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


class GeneratedContentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.outputs, cls.errors, cls.warnings = convert.build_all(ROOT)

    def test_no_validation_errors(self):
        self.assertEqual(self.errors, [])

    def test_committed_content_is_current(self):
        for rel, doc in self.outputs.items():
            path = CONTENT / rel
            self.assertTrue(path.exists(), f"missing {rel}")
            self.assertEqual(path.read_text(encoding="utf-8"), convert.serialize(doc),
                             f"{rel} is out of date; run tools/oscal_convert/convert.py")

    @unittest.skipIf(jsonschema is None, "jsonschema not installed")
    def test_files_match_json_schema(self):
        fw_schema = load(SCHEMAS / "framework.schema.json")
        map_schema = load(SCHEMAS / "mapping.schema.json")
        for path in sorted((CONTENT / "frameworks").glob("*.framework.json")):
            jsonschema.validate(load(path), fw_schema)
        for path in sorted((CONTENT / "mappings").glob("*.mapping.json")):
            jsonschema.validate(load(path), map_schema)

    def test_expected_counts(self):
        """Counts published by NIST: CSF 2.0 has 106 subcategories in 22 categories and 6 functions;
        SP 800-171 Rev 3 has 97 requirements in 17 families; SP 800-53B baselines contain 149 (Low),
        287 (Moderate), 370 (High), and 96 (Privacy) controls and enhancements."""
        index = load(CONTENT / "index.json")
        fws = {f["id"]: f for f in index["frameworks"]}
        self.assertEqual(fws["csf-2.0"]["counts"]["requirements"], 106)
        self.assertEqual(fws["csf-2.0"]["counts"]["groups"], [6, 22])
        self.assertEqual(fws["sp800-171r3"]["counts"]["requirements"], 97)
        self.assertEqual(fws["sp800-171r3"]["counts"]["groups"], [17])
        b = fws["sp800-53r5"]["counts"]["byBaseline"]
        totals = {k: sum(v.values()) for k, v in b.items()}
        self.assertEqual(totals, {"low": 149, "moderate": 287, "high": 370, "privacy": 96})
        self.assertEqual(fws["sp800-53r5"]["counts"]["groups"], [20])

    def test_no_third_party_reference_titles(self):
        banned = ("ISO", "IEC", "CIS ", "COBIT", "PCI", "IETF", "CCM", "SCF")
        for path in (CONTENT / "frameworks").glob("*.framework.json"):
            for r in load(path)["requirements"]:
                for ref in r.get("references", []):
                    self.assertFalse(ref["title"].startswith(banned), f"{path.name}: {r['id']} -> {ref['title']}")

    def test_mapping_sources_are_nist(self):
        for path in (CONTENT / "mappings").glob("*.mapping.json"):
            m = load(path)
            self.assertEqual(m["source"]["publisher"], "NIST")
            self.assertTrue(m["source"]["url"].startswith(("https://csrc.nist.gov/", "https://raw.githubusercontent.com/usnistgov/")))


if __name__ == "__main__":
    unittest.main()
