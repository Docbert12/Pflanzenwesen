"""Tests für tools/import_inventions_real.py (Erfindungskatalog „echte Namen“, Prompt 6B)
und die Importkonfiguration der Datenbasis (design/import_config/datenbasis_korrekturen.json)."""
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import import_inventions_real as ir  # noqa: E402
import import_definitions as idf  # noqa: E402

EXCEL = ir.DEFAULT_EXCEL


def h(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


@unittest.skipUnless(EXCEL.exists(), "Erfindungs-Excel (echte Namen) fehlt")
class TestImportInventionsReal(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls.tmp.name) / "c.json"
        cls.rep = Path(cls.tmp.name) / "r.md"
        cls.before = h(EXCEL)
        cls.rc = ir.main(["--write", "--out", str(cls.out), "--report", str(cls.rep)])
        cls.cat = json.loads(cls.out.read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_excel_unchanged_and_all_rows_kept(self):
        self.assertEqual(self.rc, 0)
        self.assertEqual(h(EXCEL), self.before)
        self.assertEqual(self.cat["source"]["sha256"], self.before)
        self.assertEqual(sum(len(e["sources"]) for e in self.cat["inventions"]), 5862)

    def test_merge_only_same_name_and_category(self):
        keys = [(e["category"], e["name"]) for e in self.cat["inventions"]]
        self.assertEqual(len(keys), len(set(keys)))
        feuer = [e for e in self.cat["inventions"] if e["name"] == "Feuer"]
        self.assertEqual(sorted(e["category"] for e in feuer), ["Energie", "Wissenschaft"])
        for e in feuer:
            self.assertEqual(len(e["same_name_other_categories"]), 1)
        w = next(e for e in feuer if e["category"] == "Wissenschaft")
        self.assertEqual(w["merged_rows"], len(w["sources"]))
        self.assertGreater(w["merged_rows"], 1)

    def test_nothing_active_no_order_no_effects(self):
        self.assertFalse(self.cat["rules"]["start_knowledge"])
        for e in self.cat["inventions"]:
            self.assertEqual(e["game_status"], "catalog")
            self.assertNotIn("effect", e)
            self.assertNotIn("requires", e)
        self.assertIn("kein Spielinhalt", self.cat["_note"])

    def test_name_kinds(self):
        self.assertEqual(ir.classify("Quanten- Feuer 16"), ("generated", "Feuer", "Quanten-"))
        self.assertEqual(ir.classify("Spinning Jenny (verbessert)"), ("variant", "Spinning Jenny", "verbessert"))
        self.assertEqual(ir.classify("Kupferaxt"), ("real", "Kupferaxt", ""))

    def test_activated_refs_exist(self):
        act = json.loads(ir.ACTIVATED.read_text(encoding="utf-8"))
        ids = {e["id"] for e in self.cat["inventions"]}
        for inv in act["inventions"]:
            for ref in inv["catalog_refs"]:
                self.assertIn(ref["id"], ids, inv["id"])


class TestImportCorrections(unittest.TestCase):
    def test_corrections_applied_and_marked(self):
        with tempfile.TemporaryDirectory() as t:
            out = Path(t) / "gen"
            rep = Path(t) / "r.md"
            code, issues, outputs = idf.run_import(idf.DEFAULT_EXCEL, out, rep, True, quiet=True)
            vox = {e["id"]: e for e in outputs["voxel_types.json"]["entries"]}
            self.assertEqual(vox["V007"]["material_ref"], "MAT111")
            self.assertEqual(vox["V004"]["material_ref"], "MAT206")
            for vid, pm in (("V002", "soil"), ("V003", "plant_tissue"), ("V005", "wood")):
                self.assertIsNone(vox[vid]["material_ref"])
                self.assertEqual(vox[vid]["physics_material_id"], pm)
                self.assertTrue(vox[vid]["import_corrections"])
            self.assertEqual(outputs["voxel_types.json"]["rejected"], [])
            gp = {e["id"]: e for e in outputs["generator_parameters.json"]["entries"]}
            self.assertEqual(gp["voxel_groesse"]["project_decision"]["decision"], "überstimmt")
            text = rep.read_text(encoding="utf-8")
            self.assertIn("Importkonfiguration (Prompt 6B)", text)
            self.assertNotIn("NEIN –", text)


if __name__ == "__main__":
    unittest.main()
