"""Prüft die Quellen der Leitlinie „Steinzeit → Zukunft“ und die daraus erzeugte Excel.

Die Leitlinie ist kein Technologiebaum: Geprüft wird nur, dass die Einträge vollständig, eindeutig und physikalisch
eingeordnet sind – nicht, dass etwas freigeschaltet wird.
"""
import re
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path

HIER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HIER))
import build_leitlinie as B  # noqa: E402
from leitlinie import katalog_abgleich as K  # noqa: E402
from leitlinie import quellen as Q  # noqa: E402
from leitlinie import vokabular as V  # noqa: E402

BLAETTER = ["Anleitung", "Zeitalter", "Alpha-Plan", "Alpha-Zeitalter", "Erfindungen", "Zwischenschritte", "Lücken",
            "Prompt-Abgleich", "Verfahren", "Materialien", "Katalogabgleich"]
MASSENVERNICHTUNG = re.compile(r"atom(bombe|waffe)|kernwaffe|wasserstoffbombe|neutronenbombe|nervengas|nervenkampf|"
                               r"senfgas|giftgas|chemiewaffe|biowaffe|kampfstoff|sarin|milzbrand|anthrax", re.I)
BONUS = re.compile(r"[+\-±]\s*\d+([.,]\d+)?\s*%")


class LeitlinieQuellenTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.erf, cls.fehler = Q.lies_quellen(B.QUELLEN)
        cls.alt = B.lade_alten_katalog()
        B.bereite_vor(cls.erf, cls.alt)
        cls.nach_name = {e["name"]: e for e in cls.erf}

    def test_quellen_ohne_fehler(self):
        self.assertEqual(self.fehler, [], "\n".join(self.fehler[:20]))

    def test_24_zeitalter_mit_50_bis_500_erfindungen(self):
        je = Counter(e["zeitalter"] for e in self.erf)
        self.assertEqual(sorted(je), list(range(1, 25)))
        self.assertEqual(len(V.ZEITALTER), 24)
        for nr, anzahl in je.items():
            self.assertGreaterEqual(anzahl, Q.MIN_JE_ZEITALTER, "Zeitalter %d" % nr)
            self.assertLessEqual(anzahl, Q.MAX_JE_ZEITALTER, "Zeitalter %d" % nr)

    def test_namen_und_ids_eindeutig(self):
        self.assertEqual(len({Q.norm(e["name"]) for e in self.erf}), len(self.erf))
        self.assertEqual(len({e["id"] for e in self.erf}), len(self.erf))

    def test_vorlaeufer_existieren_und_sind_nicht_spaeter(self):
        for e in self.erf:
            self.assertEqual(len(e["vorlaeufer"]), len(e["vorlaeufer_namen"]), e["name"])
            for v in e["vorlaeufer"]:
                self.assertIsNot(v, e, e["name"])
                self.assertLessEqual(v["zeitalter"], e["zeitalter"], "%s ← %s" % (e["name"], v["name"]))

    def test_jede_erfindung_hat_physikalische_kette(self):
        for e in self.erf:
            self.assertTrue(e["funktion"].strip(), e["name"])
            self.assertTrue(e["verfahren"], e["name"])
            self.assertIn(e["kategorie"], V.KATEGORIEN, e["name"])
            self.assertIn(e["status"], V.STATUS_ORDER, e["name"])
            self.assertTrue(e["energie"], e["name"])
            self.assertIn(" → ", e["t_kette"] if len(e["verfahren"]) > 1 else e["t_kette"] + " → ", e["name"])

    def test_keine_boni(self):
        for e in self.erf:
            for feld in ("funktion", "hinweis", "name"):
                self.assertIsNone(BONUS.search(e[feld] or ""), "%s: %s" % (e["name"], feld))

    def test_spielstand_stichproben(self):
        self.assertEqual(self.nach_name["Gediegenes Kupfer hämmern"]["status"], "A")
        self.assertFalse(self.nach_name["Gediegenes Kupfer hämmern"]["testbereich"])
        kupfer = self.nach_name["Kupfer schmelzen"]
        self.assertEqual(kupfer["status"], "L")
        self.assertTrue(kupfer["testbereich"], "Kupfer schmelzen ist im Testofen vorführbar")
        self.assertIn("Schmelzpunkt Kupfer 1.085 °C", kupfer["energie"])
        self.assertTrue(self.nach_name["Kupferguss"]["testbereich"])
        self.assertEqual(self.nach_name["Ackerbau"]["status"], "P8")
        self.assertEqual(self.nach_name["Tongefäß"]["status"], "L")
        self.assertFalse(self.nach_name["Tongefäß"]["testbereich"])
        # Die Test-Keramik ist nur Tiegel und Gussform: kein Vorrats- oder Wasserkrug im Testbereich
        self.assertFalse(self.nach_name["Vorratskrug"]["testbereich"])
        self.assertFalse(self.nach_name["Wassergefäß tragen"]["testbereich"])
        test = [e for e in self.erf if e["testbereich"]]
        self.assertTrue(test)
        for e in test:
            self.assertTrue({"schmelzen", "giessen"} & set(e["verfahren"]), e["name"])

    def _vorfahren(self, name):
        gesehen, stapel = set(), [self.nach_name[name]]
        while stapel:
            for v in stapel.pop()["vorlaeufer"]:
                if v["name"] not in gesehen:
                    gesehen.add(v["name"])
                    stapel.append(v)
        return gesehen

    def test_entwicklungslinie_steinhammer_bis_abbauwerkzeug(self):
        # Wunsch des Nutzers: Steinhammer → Schmelzen → Legieren → Abbauwerkzeuge – über Vorläufer verbunden
        bronze = self._vorfahren("Bronzepickel")
        for name in ("Hammerstein", "Kupfer schmelzen", "Zinnbronze", "Geweihpicke"):
            self.assertIn(name, bronze)
        eisen = self._vorfahren("Spitzhacke aus Eisen")
        for name in ("Hammerstein", "Kupferverhüttung", "Geweihpicke"):
            self.assertIn(name, eisen)
        self.assertEqual(self.nach_name["Bronzepickel"]["zeitalter"], 7)
        self.assertEqual(set(self.nach_name["Bronzepickel"]["gruppen"]), set(B.VORGESCHLAGEN))

    def test_alpha_plan(self):
        ids = [vid for vid, _t in V.ALPHA_VERSIONEN]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(ids[0], "0.6.1")
        self.assertIn("1.16", ids)
        for plan, tabelle in ((V.ALPHA_PLAN_VERFAHREN, V.VERFAHREN), (V.ALPHA_PLAN_MATERIALIEN, V.MATERIALIEN)):
            for code, vid in plan.items():
                self.assertIn(code, tabelle, code)
                self.assertIn(vid, ids, code)
                self.assertNotEqual(tabelle[code][3], "A", "%s ist schon im Spiel und braucht keinen Plan" % code)
        # Alles, was ein vorliegender Prompt (WA, P7–P12) bringt, ist eingeplant
        for art, tabelle in (("v", V.VERFAHREN), ("m", V.MATERIALIEN)):
            for code, eintrag in tabelle.items():
                if eintrag[3] not in ("A", "L"):
                    self.assertNotIn(V.alpha_von(art, code), ("offen", "nie"), code)
        self.assertEqual(V.alpha_von("v", "sprengen"), "nie")
        erwartet = {"Gediegenes Kupfer hämmern": "0.6.1", "Malachit erkennen": "1.4", "Faustkeil": "1.8",
                    "Ackerbau": "1.11", "Tongefäß": "1.13", "Kupfer schmelzen": "1.13", "Bronzepickel": "1.15",
                    "Sonnenkalender": "1.16", "Spitzhacke aus Eisen": "1.19", "Schwarzpulver": "nie"}
        for name, vid in erwartet.items():
            self.assertEqual(self.nach_name[name]["alpha"], vid, name)
        for e in self.erf:
            self.assertEqual(e["alpha_rang"], V.ALPHA_RANG[e["alpha"]], e["name"])
            if e["status"] == "A":
                self.assertEqual(e["alpha"], "0.6.1", e["name"])

    def test_spielstand_ist_spaetester_teil(self):
        for e in self.erf:
            codes = [V.VERFAHREN[v][3] for v in e["verfahren"]] + [V.MATERIALIEN[m][3] for m in e["materialien"]]
            self.assertEqual(e["status"], max(codes, key=V.STATUS_ORDER.index), e["name"])
            self.assertEqual(bool(e["luecken"]), e["status"] == "L", e["name"])
            if e["testbereich"]:
                self.assertNotEqual(e["status"], "A", e["name"])

    def test_zeitalter_24_ist_spekulativ(self):
        for e in self.erf:
            if e["zeitalter"] == 24:
                self.assertEqual(e["stand"], "spek", e["name"])
        self.assertTrue(any(e["stand"] == "spek" for e in self.erf))

    def test_projektregel_sprengstoffe(self):
        sprengen = [e for e in self.erf if "sprengen" in e["verfahren"]]
        self.assertTrue(sprengen)
        for e in sprengen:
            self.assertEqual(e["materialien"], [], "%s: keine Stoffangaben" % e["name"])
            self.assertEqual(e["status"], "L", e["name"])
        for e in self.erf:
            text = " ".join([e["name"], e["funktion"], e["hinweis"] or ""])
            self.assertIsNone(MASSENVERNICHTUNG.search(text), e["name"])

    def test_luecken_gehoeren_zu_genau_einem_zwischenschritt(self):
        alle_v = [c for g in V.LUECKEN_GRUPPEN for c in g[1]]
        alle_m = [c for g in V.LUECKEN_GRUPPEN for c in g[2]]
        self.assertEqual(len(alle_v), len(set(alle_v)))
        self.assertEqual(len(alle_m), len(set(alle_m)))
        for c, v in V.VERFAHREN.items():
            self.assertEqual(v[3] == "L", c in alle_v, "Verfahren %s" % c)
            if v[3] == "L":
                self.assertTrue(V.gruppe_von("v", c), c)
        for c, m in V.MATERIALIEN.items():
            self.assertEqual(m[3] == "L", c in alle_m, "Material %s" % c)
        for e in self.erf:
            self.assertEqual(bool(e["gruppen"]), e["status"] == "L", e["name"])

    def test_alter_katalog_vollstaendig_zugeordnet(self):
        self.assertTrue(self.alt, "alter Katalog fehlt")
        namen = {Q.norm(e["name"]) for e in self.erf}
        for a in self.alt:
            neu = K.neuer_name(a["concept"], a["category"])
            if neu is None:
                self.assertIn(a["concept"], K.OHNE_ENTSPRECHUNG, a["name"])
            else:
                self.assertIn(Q.norm(neu), namen, "%s → %s" % (a["name"], neu))


class LeitlinieExcelTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.pfad = Path(cls.tmp.name) / "leitlinie.xlsx"
        cls.rueck = B.main(["--out", str(cls.pfad)])
        cls.erf, _ = Q.lies_quellen(B.QUELLEN)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_excel_wird_gebaut(self):
        from openpyxl import load_workbook
        self.assertEqual(self.rueck, 0)
        wb = load_workbook(self.pfad)
        self.assertEqual(wb.sheetnames, BLAETTER)
        we = wb["Erfindungen"]
        self.assertEqual(we.max_row, len(self.erf) + 1)
        self.assertEqual(we["A2"].value, "Z01-001")
        self.assertTrue(str(we["N2"].value).startswith("=IFERROR(INDEX('Prompt-Abgleich'"))
        wz = wb["Zeitalter"]
        self.assertEqual([wz.cell(r, 1).value for r in range(2, 26)], list(range(1, 25)))
        self.assertEqual(wz["G2"].value, "=COUNTIF('Erfindungen'!$B:$B,$A2)")
        self.assertEqual(wz["B26"].value, "Summe")
        self.assertEqual(len(wz._charts), 1)
        self.assertEqual(len(wb["Zwischenschritte"]._charts), 1)
        self.assertEqual(wz["O2"].value, "=SUMIFS('Erfindungen'!$X:$X,'Erfindungen'!$B:$B,$A2)")
        wp = wb["Prompt-Abgleich"]
        self.assertEqual([wp.cell(r, 1).value for r in range(2, 11)], V.STATUS_ORDER)
        # Auswahl zum Ausprobieren: einzige Eingabespalte, vorausgewählt sind die vorgeschlagenen Zwischenschritte
        wsz = wb["Zwischenschritte"]
        zeilen = range(2, len(V.LUECKEN_GRUPPEN) + 2)
        self.assertEqual(sorted(wsz.cell(r, 1).value for r in zeilen), sorted(g[0] for g in V.LUECKEN_GRUPPEN))
        gewaehlt = sorted(wsz.cell(r, 1).value for r in zeilen if wsz.cell(r, 2).value == "x")
        self.assertEqual(gewaehlt, sorted(B.VORGESCHLAGEN))
        self.assertIn("SEARCH(", str(we["X2"].value))
        self.assertIn("'Zwischenschritte'!$B$2:$B$%d" % (len(V.LUECKEN_GRUPPEN) + 1), str(we["X2"].value))
        self.assertEqual(we.auto_filter.ref, "A1:Y%d" % (len(self.erf) + 1))
        # Alpha-Plan: Spalte O (Text) und Y (Rang), eigene Blätter mit Zählformeln
        self.assertEqual(we["O1"].value, "geplant möglich ab (Alpha-Plan)")
        self.assertEqual(we["O2"].value, "heute (v0.6.1)")
        self.assertEqual(we["Y2"].value, 0)
        wap = wb["Alpha-Plan"]
        self.assertEqual([wap.cell(r, 8).value for r in range(2, len(V.ALPHA_VERSIONEN) + 2)],
                         list(range(len(V.ALPHA_VERSIONEN))))
        self.assertEqual(wap["D2"].value, "=COUNTIF('Erfindungen'!$Y:$Y,$H2)")
        self.assertTrue(str(wb["Alpha-Zeitalter"]["D3"].value).startswith("=IF($C3=0,0,COUNTIFS("))
        # Zählformeln statt fester Zahlen
        for blatt, zelle in (("Zwischenschritte", "C2"), ("Zwischenschritte", "D2"), ("Lücken", "F2"), ("Verfahren", "J2"),
                             ("Materialien", "J2"), ("Zeitalter", "P2")):
            if zelle:
                self.assertTrue(str(wb[blatt][zelle].value).startswith("="), "%s!%s" % (blatt, zelle))

    def test_nur_pruefen_schreibt_nichts(self):
        ziel = Path(self.tmp.name) / "nicht_da.xlsx"
        self.assertEqual(B.main(["--pruefen", "--out", str(ziel)]), 0)
        self.assertFalse(ziel.exists())


if __name__ == "__main__":
    unittest.main()
