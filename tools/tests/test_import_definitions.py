"""Tests für tools/import_definitions.py.

Aufruf im Projektordner:  python -m unittest discover -s tools/tests -v
Arbeitet nur mit Kopien der Excel in einem temporären Ordner; die Original-Excel bleibt unverändert.
"""
import hashlib
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import import_definitions as imp  # noqa: E402
import openpyxl  # noqa: E402

EXCEL = ROOT / "design" / "Pflanzenwesen_Voxel_Datenbasis.xlsx"


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.out = self.tmp / "out"
        self.report = self.tmp / "report.md"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def modified_copy(self, edits):
        """edits: list of (sheet, cell, value). Gibt Pfad einer veränderten Kopie zurück."""
        dst = self.tmp / "copy.xlsx"
        shutil.copy(EXCEL, dst)
        wb = openpyxl.load_workbook(dst)
        for sheet, cell, value in edits:
            wb[sheet][cell] = value
        wb.save(dst)
        return dst

    def run_imp(self, excel, write=True):
        return imp.run_import(excel, self.out, self.report, write, quiet=True)

    def test_original_untouched_and_import_runs(self):
        before = sha(EXCEL)
        code, issues, outputs = self.run_imp(EXCEL)
        self.assertEqual(sha(EXCEL), before, "Original-Excel darf nicht verändert werden")
        self.assertIn(code, (0, 1))
        self.assertTrue((self.out / "species.json").exists())
        ids = [e["id"] for e in outputs["species.json"]["entries"]]
        self.assertIn("KR001", ids)
        self.assertIn("KR002", ids)

    def test_reimport_keeps_ids_and_reports_no_diff(self):
        self.run_imp(EXCEL)
        first = {f.name: json.loads(f.read_text(encoding="utf-8")) for f in self.out.glob("*.json") if not f.name.startswith("_manifest")}
        code, _, outputs = self.run_imp(EXCEL)
        second = {f.name: json.loads(f.read_text(encoding="utf-8")) for f in self.out.glob("*.json") if not f.name.startswith("_manifest")}
        self.assertEqual(first, second, "Wiederholter Import muss identische Definitionen (inkl. IDs) erzeugen")
        gen = [e["id"] for e in second["genetics.json"]["entries"]]
        self.assertIn("groesse", gen)
        self.assertIn("kopfblaetter_anzahl", gen)

    def test_generated_ids_stable_after_row_reorder(self):
        self.run_imp(EXCEL)
        before = {e["name"]: e["id"] for e in json.loads((self.out / "genetics.json").read_text(encoding="utf-8"))["entries"]}
        # Zeilen 2 und 3 vertauschen
        wb = openpyxl.load_workbook(EXCEL)
        ws = wb["13_Vererbung_Genetik"]
        r2 = [c.value for c in ws[2]]
        r3 = [c.value for c in ws[3]]
        dst = self.tmp / "reordered.xlsx"
        wb.save(dst)
        wb = openpyxl.load_workbook(dst)
        ws = wb["13_Vererbung_Genetik"]
        for i, v in enumerate(r3, start=1):
            ws.cell(row=2, column=i, value=v)
        for i, v in enumerate(r2, start=1):
            ws.cell(row=3, column=i, value=v)
        wb.save(dst)
        self.run_imp(dst)
        after = {e["name"]: e["id"] for e in json.loads((self.out / "genetics.json").read_text(encoding="utf-8"))["entries"]}
        self.assertEqual(before, after)

    def test_duplicate_id_detected(self):
        x = self.modified_copy([("06_Kreaturen", "A4", "KR002")])
        code, issues, outputs = self.run_imp(x)
        msgs = [f"{i.where()} {i.message}" for i in issues if i.severity == "ERROR"]
        self.assertTrue(any("Doppelte ID 'KR002'" in m and "06_Kreaturen" in m for m in msgs), msgs[:5])
        self.assertEqual(code, 1)

    def test_invalid_id_format_detected(self):
        x = self.modified_copy([("07_Pflanzen_Bäume", "A3", "Pflanze-2")])
        _, issues, outputs = self.run_imp(x)
        self.assertTrue(any(i.severity == "ERROR" and i.sheet == "07_Pflanzen_Bäume" and i.row == 3 and "Muster" in i.message for i in issues))
        self.assertNotIn("Pflanze-2", [e["id"] for e in outputs["plants.json"]["entries"]])
        self.assertIn("Pflanze-2", [r["id"] for r in outputs["plants.json"]["rejected"]])

    def test_invalid_reference_detected_with_cell(self):
        x = self.modified_copy([("06_Kreaturen", "P3", "KT001,KT999")])
        _, issues, outputs = self.run_imp(x)
        hit = [i for i in issues if i.severity == "ERROR" and "KT999" in i.message]
        self.assertTrue(hit)
        self.assertEqual((hit[0].sheet, hit[0].row, hit[0].col), ("06_Kreaturen", 3, "P"))
        self.assertNotIn("KR002", [e["id"] for e in outputs["species.json"]["entries"]])

    def test_text_in_number_column_rejected(self):
        x = self.modified_copy([("06_Kreaturen", "F3", "fünfundachtzig")])
        _, issues, _ = self.run_imp(x)
        self.assertTrue(any(i.severity == "ERROR" and i.sheet == "06_Kreaturen" and i.col == "F" and i.row == 3 for i in issues))

    def test_missing_vs_not_applicable(self):
        x = self.modified_copy([("01_Elemente", "G2", None)])  # Siedepunkt von H leer
        _, _, outputs = self.run_imp(x)
        h = [e for e in outputs["elements.json"]["entries"] if e["id"] == "H"][0]
        self.assertIn("boiling_point_c", h.get("missing_fields", []))
        he = [e for e in outputs["elements.json"]["entries"] if e["id"] == "He"][0]
        self.assertIn("electronegativity", he.get("not_applicable_fields", []))

    def test_dry_run_writes_nothing_but_reports_diff(self):
        self.run_imp(EXCEL)
        before = (self.out / "species.json").read_text(encoding="utf-8")
        x = self.modified_copy([("06_Kreaturen", "F3", 90)])
        code, _, _ = self.run_imp(x, write=False)
        self.assertEqual((self.out / "species.json").read_text(encoding="utf-8"), before)
        self.assertIn("KR002", self.report.read_text(encoding="utf-8"))
        self.assertIn("size_cm", self.report.read_text(encoding="utf-8"))

    def test_status_comes_only_from_config(self):
        _, _, outputs = self.run_imp(EXCEL)
        st = {e["id"]: e["game_status"] for e in outputs["species.json"]["entries"]}
        self.assertEqual(st["KR002"], "partial")
        self.assertEqual(st["KR003"], "data_only")


if __name__ == "__main__":
    unittest.main()
