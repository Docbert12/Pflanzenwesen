"""Tests für tools/import_inventions.py (Ideenkatalog aus der Erfindungs-Excel)."""
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import import_inventions as ii  # noqa: E402

EXCEL = ii.DEFAULT_EXCEL


def h(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


@unittest.skipUnless(EXCEL.exists(), "Erfindungs-Excel fehlt")
class TestImportInventions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls.tmp.name) / "c.json"
        cls.rep = Path(cls.tmp.name) / "r.md"
        cls.before = h(EXCEL)
        cls.rc = ii.main(["--write", "--out", str(cls.out), "--report", str(cls.rep)])
        cls.cat = json.loads(cls.out.read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_excel_unchanged_and_ok(self):
        self.assertEqual(self.rc, 0)
        self.assertEqual(h(EXCEL), self.before)
        self.assertEqual(self.cat["source"]["sha256"], self.before)

    def test_counts_match_overview(self):
        self.assertEqual(len(self.cat["eras"]), 24)
        self.assertEqual(len(self.cat["categories"]), 12)
        self.assertEqual(len(self.cat["entries"]), 5498)
        self.assertNotIn("Abweichungen\n\n-", self.rep.read_text(encoding="utf-8"))

    def test_nothing_active(self):
        for e in self.cat["entries"]:
            self.assertEqual(e["game_status"], "idea_only")
            self.assertNotIn("effect", e)            # nur excel_effect_text als Originaltext
        self.assertIn("nichts davon ist im Spiel aktiv", self.cat["_note"])

    def test_concepts_and_ids(self):
        ids = [e["id"] for e in self.cat["entries"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(ii.concept_of("Flug (Frühe Steinzeit 1)"), ("Flug", ""))
        self.assertEqual(ii.concept_of("Fortgeschrittene Analyse 12"), ("Analyse", "fortgeschritten"))
        self.assertEqual(ii.concept_of("Zukunfts-Sprache 25"), ("Sprache", "zukunft"))
        self.assertEqual(len(self.cat["concepts"]), 96)

    def test_deterministic(self):
        out2 = Path(self.tmp.name) / "c2.json"
        ii.main(["--write", "--out", str(out2), "--report", str(Path(self.tmp.name) / "r2.md")])
        self.assertEqual(out2.read_bytes(), self.out.read_bytes())


if __name__ == "__main__":
    unittest.main()
