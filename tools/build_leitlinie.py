#!/usr/bin/env python3
"""Erzeugt die Leitlinien-Excel „Steinzeit → Zukunft“ aus design/leitlinie/zeitalter_XX.txt.

    python3 tools/build_leitlinie.py               # prüfen und design/Leitlinie_Steinzeit_bis_Zukunft.xlsx schreiben
    python3 tools/build_leitlinie.py --pruefen     # nur prüfen (Anzahl je Zeitalter, Codes, Vorläufer, Namen)
    python3 tools/build_leitlinie.py --out X.xlsx  # anderer Zielpfad

Die Excel ist eine LEITLINIE, kein Technologiebaum: Nichts wird freigeschaltet, es gibt keine Boni.
Die Original-Excel-Dateien des Nutzers in design/ werden nicht verändert.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(HIER)
sys.path.insert(0, HIER)

from leitlinie import vokabular as V  # noqa: E402
from leitlinie import quellen as Q  # noqa: E402
from leitlinie import katalog_abgleich as K  # noqa: E402

QUELLEN = os.path.join(WURZEL, "design", "leitlinie")
ZIEL = os.path.join(WURZEL, "design", "Leitlinie_Steinzeit_bis_Zukunft.xlsx")
ALTER_KATALOG = os.path.join(WURZEL, "data", "generated", "ideas", "inventions_real_catalog.json")
STAND_DATUM = "25.11.2026"

# Spalten des Blatts „Erfindungen“ (Buchstabe, Überschrift, Breite, umbrechen)
SPALTEN = [
    ("A", "ID", 9, False),
    ("B", "Zeitalter-Nr", 9, False),
    ("C", "Zeitalter", 22, True),
    ("D", "Kategorie", 14, True),
    ("E", "Erfindung", 30, True),
    ("F", "Funktion (was sie physikalisch leistet)", 44, True),
    ("G", "Materialien", 24, True),
    ("H", "Verfahren / Arbeitsschritte", 28, True),
    ("I", "Energie / Temperatur", 30, True),
    ("J", "Physikalische Kette (Kurzform)", 56, True),
    ("K", "Vorläufer (physisch vorher nötig)", 30, True),
    ("L", "Vorläufer-IDs", 15, True),
    ("M", "Spielstand-Code", 10, False),
    ("N", "Im normalen Spiel möglich ab", 22, True),
    ("O", "Heute im Testbereich vorführbar", 11, False),
    ("P", "Was fehlt (Lücken)", 38, True),
    ("Q", "Stand", 16, True),
    ("R", "Im alten Excel", 24, True),
    ("S", "Hinweis", 34, True),
    ("T", "Verfahren-Codes (Hilfsspalte)", 22, False),
    ("U", "Material-Codes (Hilfsspalte)", 22, False),
    ("V", "Lücken-Gruppen (Hilfsspalte)", 28, False),
    ("W", "mit gewählten Zwischenschritten möglich (Hilfsspalte)", 16, False),
]
# Vorausgewählte Zwischenschritte (Vorschlag aus docs/plan_prompt_06b.md Abschnitt 8) – im Blatt änderbar
VORGESCHLAGEN = ["Feuer, Ton und eigener Ofen", "Erz und Legierungen"]
E = "'Erfindungen'!"


def lade_alten_katalog():
    if not os.path.exists(ALTER_KATALOG):
        return []
    with open(ALTER_KATALOG, encoding="utf-8") as f:
        d = json.load(f)
    return [i for i in d.get("inventions", []) if i.get("name_kind") in ("real", "variant")]


def bereite_vor(erfindungen, alt):
    """Ergänzt jede Erfindung um die Textfelder für die Excel."""
    nach_name = {Q.norm(e["name"]): e for e in erfindungen}
    alt_zu = {}
    for a in alt:
        n = K.neuer_name(a["concept"], a["category"])
        if n:
            ziel = nach_name.get(Q.norm(n))
            if ziel is not None:
                alt_zu.setdefault(ziel["id"], []).append("%s (alt: %s)" % (a["name"], a["first_stage_name"]))
    for e in erfindungen:
        mats = [V.MATERIALIEN[m][0] for m in e["materialien"]]
        verf = [V.VERFAHREN[v][0] for v in e["verfahren"]]
        e["t_kategorie"] = V.KATEGORIEN[e["kategorie"]]
        e["t_materialien"] = ", ".join(mats) if mats else "—"
        e["t_verfahren"] = " → ".join(verf)
        e["t_kette"] = "%s → %s ⇒ %s" % (" + ".join(mats) if mats else "ohne Material", " → ".join(verf),
                                          e["funktion"])
        e["t_vorl"] = "; ".join(v["name"] for v in e["vorlaeufer"]) if e["vorlaeufer"] else "—"
        e["t_vorl_ids"] = "; ".join(v["id"] for v in e["vorlaeufer"]) if e["vorlaeufer"] else ""
        e["t_luecken"] = "; ".join(e["luecken"]) if e["luecken"] else "—"
        e["t_stand"] = {"": "historisch belegt", "entw": "in Entwicklung", "spek": "spekulativ"}[e["stand"]]
        e["t_alt"] = "; ".join(alt_zu.get(e["id"], [])) or ""
        e["h_verf"] = ";" + ";".join(e["verfahren"]) + ";"
        e["h_mat"] = (";" + ";".join(e["materialien"]) + ";") if e["materialien"] else ""
        gruppen = set()
        for v in e["verfahren"]:
            if V.VERFAHREN[v][3] == "L":
                gruppen.add(V.gruppe_von("v", v))
        for m in e["materialien"]:
            if V.MATERIALIEN[m][3] == "L":
                gruppen.add(V.gruppe_von("m", m))
        e["gruppen"] = sorted(g for g in gruppen if g)
        e["h_gruppen"] = (";" + ";".join(e["gruppen"]) + ";") if e["gruppen"] else ""
    return erfindungen


# ---------------------------------------------------------------- Excel
def zeilen_noetig(text, breite, fett=False):
    """Schätzt, wie viele Zeilen ein umbrochener Text in einer Spalte der Breite `breite` braucht."""
    if not isinstance(text, str) or not text:
        return 1
    platz = max(4, int(breite * (1.0 if fett else 1.15)) - 1)
    zeilen = 0
    for absatz in text.split("\n"):
        laenge = 0
        zeilen += 1
        for wort in absatz.split(" "):
            w = len(wort)
            if laenge and laenge + 1 + w > platz:
                zeilen += 1
                laenge = w
            else:
                laenge += (1 if laenge else 0) + w
            while laenge > platz:  # überlanges Wort bricht hart um
                zeilen += 1
                laenge -= platz
    return zeilen


def schreibe_excel(erfindungen, alt, pfad):
    from openpyxl import Workbook
    from openpyxl.chart import BarChart, Reference
    from openpyxl.formatting.rule import FormulaRule
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter
    from openpyxl.worksheet.datavalidation import DataValidation

    arial = Font(name="Arial", size=10)
    arial_b = Font(name="Arial", size=10, bold=True)
    arial_i = Font(name="Arial", size=10, italic=True, color="555555")
    kopf_font = Font(name="Arial", size=10, bold=True, color="FFFFFF")
    kopf_fill = PatternFill("solid", fgColor="2E5E3A")
    titel_font = Font(name="Arial", size=16, bold=True, color="2E5E3A")
    abschnitt_font = Font(name="Arial", size=12, bold=True, color="2E5E3A")
    hilfs_font = Font(name="Arial", size=9, color="808080")
    duenn = Side(style="thin", color="C8D3C0")
    rahmen = Border(bottom=duenn)
    oben = Alignment(vertical="top", wrap_text=False)
    oben_wrap = Alignment(vertical="top", wrap_text=True)
    status_fill = {
        "A": PatternFill("solid", fgColor="C6EFCE"), "WA": PatternFill("solid", fgColor="E2F0D9"),
        "P": PatternFill("solid", fgColor="FFF2CC"), "L": PatternFill("solid", fgColor="F8CBAD"),
    }

    def kopfzeile(ws, titel, breiten, zeile=1):
        hoehe = 1
        for i, (t, b) in enumerate(zip(titel, breiten), start=1):
            c = ws.cell(row=zeile, column=i, value=t)
            c.font = kopf_font
            c.fill = kopf_fill
            c.alignment = Alignment(vertical="center", wrap_text=True)
            ws.column_dimensions[get_column_letter(i)].width = b
            hoehe = max(hoehe, zeilen_noetig(t, b, fett=True))
        ws.row_dimensions[zeile].height = max(30, 13 * hoehe + 6)

    def zelle(ws, r, c, wert, font=arial, wrap=False, fmt=None):
        z = ws.cell(row=r, column=c, value=wert)
        z.font = font
        z.alignment = oben_wrap if wrap else oben
        if fmt:
            z.number_format = fmt
        return z

    n = len(erfindungen)
    letzte = n + 1
    wb = Workbook()

    # ------------------------------------------------------------ Anleitung
    wa = wb.active
    wa.title = "Anleitung"
    wa.column_dimensions["A"].width = 46
    wa.column_dimensions["B"].width = 100
    r = 1
    zelle(wa, r, 1, "Leitlinie Steinzeit → Zukunft für die Pflanzenwesen", titel_font)
    r += 1
    zelle(wa, r, 1, "24 Zeitalter, je 50–500 Erfindungen, mit physikalischer Kette und Spielstand je Prompt. "
                    "Stand %s, Spielversion 0.6.1." % STAND_DATUM, arial_i)
    r += 2
    texte = [
        ("Wozu diese Datei?", None),
        ("Zweck", "Leitlinie dafür, wie sich die Pflanzenwesen selbst von der Steinzeit bis in die Zukunft entwickeln "
                  "könnten. Je Erfindung steht, aus welchen Materialien und mit welchen Arbeitsschritten sie physikalisch "
                  "entsteht, welche Energie oder Temperatur nötig ist und ab welchem Prompt das Spiel sie überhaupt "
                  "zulässt."),
        ("Was sie NICHT ist", "Kein Technologiebaum: Nichts wird freigeschaltet, es gibt keine Boni und keine "
                              "Prozentwerte. Das Zeitalter ist nur eine Einordnung. Die Wesen können eine Erfindung erst "
                              "machen, wenn Physik und Handlungen im Spiel vorhanden sind, und nur, wenn sie sie selbst "
                              "entdecken, ausprobieren oder lernen. Niemand muss sie je machen."),
        ("Vorläufer", "Was physikalisch vorher da sein muss (z. B. ein Schmelztiegel vor dem Kupferguss) – keine "
                      "Voraussetzung im Sinne eines Baums."),
        ("Quelle der Einträge", "Zusammengestellt nach allgemeinem historischem und technischem Wissen; ohne "
                                "Einzelquellen geprüft. Jahreszahlen sind bewusst weggelassen, die Zeiträume der "
                                "Zeitalter sind Richtwerte. Zeitalter 24 ist vollständig spekulativ; „in Entwicklung“ "
                                "meint den Stand 2026."),
        ("Zeitalter und Kategorien", "Namen der 24 Zeitalter und 12 Kategorien wie in deiner Datei "
                                     "Erfindungen_Echt_nach_Kategorien.xlsx (unverändert). Zeiträume, Kennzeichen, "
                                     "Energiequellen und Temperaturen sind neu ergänzt."),
        ("Spielstand", "Aus den Prompt-Texten in design/prompts/ (Stand %s) und dem Code von v0.6.1 abgeleitet: "
                       "Jedes Verfahren und jedes Material hat einen Spielstand; eine Erfindung ist ab dem spätesten "
                       "davon möglich. Blatt „Prompt-Abgleich“ erklärt die Stufen." % STAND_DATUM),
        ("Temperaturen", "Gerundete reale Richtwerte (Lehrbuchwerte), keine Spielparameter."),
        ("Projektregeln", "Für Sprengstoffe und Pulverwaffen stehen nur Name und Funktion, keine Stoffe oder Rezepte. "
                          "Massenvernichtungswaffen sind bewusst nicht aufgenommen."),
        ("Pflegen und ändern", "Quelle sind die Textdateien design/leitlinie/zeitalter_01.txt … zeitalter_24.txt. "
                               "Nach Änderungen: python3 tools/build_leitlinie.py – das Werkzeug prüft 50–500 Einträge je "
                               "Zeitalter, eindeutige Namen, bekannte Codes, Vorläufer (nicht später als die Erfindung) "
                               "und dass keine Prozent-Boni vorkommen, und schreibt diese Excel neu. Änderungen direkt in "
                               "der Excel gehen beim nächsten Erzeugen verloren."),
        ("Blätter", None),
        ("Zeitalter", "24 Zeitalter mit Zeitraum, Kennzeichen, Energiequellen, Temperatur und Zählungen (Formeln), "
                      "dazu ein Diagramm."),
        ("Erfindungen", "Alle Erfindungen, eine je Zeile, mit Filtern. Graue Hilfsspalten T–W dienen den Zählformeln."),
        ("Zwischenschritte", "Fehlende Grundlagen nach möglichem Zwischenschritt gebündelt: wie viele Erfindungen jeweils "
                             "betroffen sind und wie viele allein an diesem Schritt hängen. Mit Auswahl zum "
                             "Ausprobieren (Spalte B)."),
        ("Ausprobieren (Eingabe)", "Einzige Eingabezellen: Spalte B im Blatt „Zwischenschritte“ (gelb). Ein x heißt: "
                                   "Dieser Zwischenschritt kommt ins Spiel. Die Blätter „Zeitalter“ (Spalten O/P) und "
                                   "„Zwischenschritte“ zeigen dann, wie viele Erfindungen zusätzlich möglich wären. "
                                   "Vorausgewählt sind die beiden vorgeschlagenen Schritte „Feuer, Ton und eigener "
                                   "Ofen“ und „Erz und Legierungen“."),
        ("Lücken", "Jedes fehlende Verfahren und Material mit Zahl der betroffenen Erfindungen."),
        ("Prompt-Abgleich", "Was jeder Prompt physikalisch bringt und wie viele Erfindungen damit möglich werden."),
        ("Verfahren / Materialien", "Das kontrollierte Vokabular mit Physik, Spielstand und Häufigkeit."),
        ("Katalogabgleich", "Die echten Namen aus deiner alten Erfindungs-Excel und wo sie in der Leitlinie stehen "
                            "(früher/später eingeordnet). Die 2.608 erzeugten Fantasienamen sind nicht übernommen."),
        ("Spielstand-Codes", None),
    ]
    for code in V.STATUS_ORDER:
        texte.append(("%s – %s" % (code, V.STATUS_TEXT[code]), V.STATUS_BESCHREIBUNG[code]))
    texte += [
        ("Testbereich", "„ja“ = heute in einem Testbereich vorführbar (Testofen, Testausrüstung), aber nicht im normalen "
                        "Spiel."),
        ("Stand", None),
        ("historisch belegt", "Die Erfindung gab es wirklich in diesem Zeitalter (Einordnung nach dem ersten "
                              "verbreiteten Auftreten; „zuerst in China/Indien/Persien“ steht im Hinweis)."),
        ("in Entwicklung", "Erst teilweise verwirklicht oder im Versuch (Stand 2026)."),
        ("spekulativ", "Physikalisch begründete Annahme über die Zukunft, keine Tatsache."),
    ]
    for kopf, text in texte:
        if text is None:
            r += 1
            zelle(wa, r, 1, kopf, abschnitt_font)
        else:
            zelle(wa, r, 1, kopf, arial_b, wrap=True)
            zelle(wa, r, 2, text, arial, wrap=True)
            wa.row_dimensions[r].height = max(15, 13 * math.ceil(len(text) / 112) + 2)
        r += 1
    r += 1
    zelle(wa, r, 1, "Kennzahlen (Formeln)", abschnitt_font)
    r += 1
    kz_zeile = {}
    kennzahlen = [
        ("gesamt", "Erfindungen gesamt", "=COUNTA(%s$A:$A)-1" % E, "#,##0"),
        ("zeitalter", "Zeitalter", "=COUNTA('Zeitalter'!$A$2:$A$25)", "0"),
        ("min", "Kleinstes Zeitalter (Anzahl Erfindungen)", "=MIN('Zeitalter'!$G$2:$G$25)", "#,##0"),
        ("max", "Größtes Zeitalter (Anzahl Erfindungen)", "=MAX('Zeitalter'!$G$2:$G$25)", "#,##0"),
        ("a", "Heute im Spiel möglich (v0.6.1)", '=COUNTIF(%s$M:$M,"A")' % E, "#,##0"),
        ("spaeter", "Später möglich (Weltarchitektur bis Prompt 12)", "=B{gesamt}-B{a}-B{l}", "#,##0"),
        ("l", "Lücke – in keinem Prompt vorgesehen", '=COUNTIF(%s$M:$M,"L")' % E, "#,##0"),
        ("anteil", "Anteil bis Prompt 12 möglich", "=IF(B{gesamt}=0,0,(B{a}+B{spaeter})/B{gesamt})", "0.0%"),
        ("auswahl", "Mit den gewählten Zwischenschritten zusätzlich möglich", "=SUM(%s$W:$W)" % E, "#,##0"),
        ("anteil_auswahl", "Anteil bis Prompt 12 + gewählte Zwischenschritte",
         "=IF(B{gesamt}=0,0,(B{a}+B{spaeter}+B{auswahl})/B{gesamt})", "0.0%"),
        ("test", "Heute im Testbereich vorführbar", '=COUNTIF(%s$O:$O,"ja")' % E, "#,##0"),
        ("spek", "Spekulativ", '=COUNTIF(%s$Q:$Q,"spekulativ")' % E, "#,##0"),
        ("entw", "In Entwicklung", '=COUNTIF(%s$Q:$Q,"in Entwicklung")' % E, "#,##0"),
    ]
    for j, (schluessel, _k, _f, _fmt) in enumerate(kennzahlen):
        kz_zeile[schluessel] = r + j
    for schluessel, kopf, formel, fmt in kennzahlen:
        zelle(wa, r, 1, kopf, arial_b)
        zelle(wa, r, 2, formel.format(**kz_zeile), arial, fmt=fmt).alignment = Alignment(horizontal="left")
        r += 1
    wa.freeze_panes = "A4"

    # ------------------------------------------------------------ Zeitalter
    wz = wb.create_sheet("Zeitalter")
    kopf = ["Nr", "Zeitalter", "Zeitraum (ca.)", "Kennzeichen", "Energiequellen", "Höchste nutzbare Temperatur",
            "Erfindungen", "heute im Spiel", "später möglich (WA–P12)", "Lücke", "Anteil bis Prompt 12 möglich",
            "im Testbereich vorführbar", "spekulativ", "in Entwicklung",
            "mit Auswahl zusätzlich möglich", "Anteil bis Prompt 12 mit Auswahl"]
    kopfzeile(wz, kopf, [5, 24, 30, 46, 26, 22, 11, 10, 12, 9, 12, 12, 10, 11, 13, 13])
    for i, (nr, name, zeitraum, kennz, energie, temp) in enumerate(V.ZEITALTER, start=2):
        zelle(wz, i, 1, nr, fmt="0")
        zelle(wz, i, 2, name, arial_b, wrap=True)
        zelle(wz, i, 3, zeitraum, wrap=True)
        zelle(wz, i, 4, kennz, wrap=True)
        zelle(wz, i, 5, energie, wrap=True)
        zelle(wz, i, 6, temp, wrap=True)
        zelle(wz, i, 7, "=COUNTIF(%s$B:$B,$A%d)" % (E, i), fmt="#,##0")
        zelle(wz, i, 8, '=COUNTIFS(%s$B:$B,$A%d,%s$M:$M,"A")' % (E, i, E), fmt="#,##0")
        zelle(wz, i, 10, '=COUNTIFS(%s$B:$B,$A%d,%s$M:$M,"L")' % (E, i, E), fmt="#,##0")
        zelle(wz, i, 9, "=G%d-H%d-J%d" % (i, i, i), fmt="#,##0")
        zelle(wz, i, 11, "=IF(G%d=0,0,(H%d+I%d)/G%d)" % (i, i, i, i), fmt="0.0%")
        zelle(wz, i, 12, '=COUNTIFS(%s$B:$B,$A%d,%s$O:$O,"ja")' % (E, i, E), fmt="#,##0")
        zelle(wz, i, 13, '=COUNTIFS(%s$B:$B,$A%d,%s$Q:$Q,"spekulativ")' % (E, i, E), fmt="#,##0")
        zelle(wz, i, 14, '=COUNTIFS(%s$B:$B,$A%d,%s$Q:$Q,"in Entwicklung")' % (E, i, E), fmt="#,##0")
        zelle(wz, i, 15, "=SUMIFS(%s$W:$W,%s$B:$B,$A%d)" % (E, E, i), fmt="#,##0")
        zelle(wz, i, 16, "=IF(G%d=0,0,(H%d+I%d+O%d)/G%d)" % (i, i, i, i, i), fmt="0.0%")
        wz.row_dimensions[i].height = 40
    s = len(V.ZEITALTER) + 2
    zelle(wz, s, 2, "Summe", arial_b)
    for col in "GHIJLMNO":
        c = "%s%d" % (col, s)
        wz[c] = "=SUM(%s2:%s%d)" % (col, col, s - 1)
        wz[c].font = arial_b
        wz[c].number_format = "#,##0"
    wz["K%d" % s] = "=IF(G%d=0,0,(H%d+I%d)/G%d)" % (s, s, s, s)
    wz["K%d" % s].font = arial_b
    wz["K%d" % s].number_format = "0.0%"
    wz["P%d" % s] = "=IF(G%d=0,0,(H%d+I%d+O%d)/G%d)" % (s, s, s, s, s)
    wz["P%d" % s].font = arial_b
    wz["P%d" % s].number_format = "0.0%"
    zelle(wz, s + 1, 2, "Zählungen sind Formeln über das Blatt „Erfindungen“. Zeiträume sind Richtwerte; "
                        "„später möglich“ = Erfindungen – heute im Spiel – Lücke. Spalten O/P hängen von der Auswahl "
                        "im Blatt „Zwischenschritte“ ab (Spalte B).", arial_i)
    wz.freeze_panes = "C2"
    ch = BarChart()
    ch.type = "col"
    ch.grouping = "stacked"
    ch.overlap = 100
    ch.title = "Erfindungen je Zeitalter nach Spielstand"
    ch.y_axis.title = "Anzahl Erfindungen"
    ch.x_axis.title = "Zeitalter"
    ch.add_data(Reference(wz, min_col=8, max_col=10, min_row=1, max_row=s - 1), titles_from_data=True)
    ch.set_categories(Reference(wz, min_col=2, min_row=2, max_row=s - 1))
    for serie, farbe in zip(ch.series, ["70AD47", "FFC000", "E07B5A"]):
        serie.graphicalProperties.solidFill = farbe
        serie.graphicalProperties.line.solidFill = farbe
    ch.height = 11
    ch.width = 32
    ch.roundedCorners = False
    ch.legend.position = "b"
    ch.legend.overlay = False
    ch.title.overlay = False
    ch.x_axis.title.overlay = False
    ch.y_axis.title.overlay = False
    ch.x_axis.delete = False
    ch.y_axis.delete = False
    wz.add_chart(ch, "B%d" % (s + 3))

    # ------------------------------------------------------------ Erfindungen
    we = wb.create_sheet("Erfindungen")
    kopfzeile(we, [t for _, t, _, _ in SPALTEN], [b for _, _, b, _ in SPALTEN])
    for idx in range(len(SPALTEN)):
        if SPALTEN[idx][0] in ("T", "U", "V", "W"):
            we.cell(row=1, column=idx + 1).fill = PatternFill("solid", fgColor="808080")
    g_ende = len(V.LUECKEN_GRUPPEN) + 1
    for i, e in enumerate(erfindungen, start=2):
        mit_auswahl = ("=IF($M{i}=\"L\",IF(SUMPRODUCT(--ISNUMBER(SEARCH(\";\"&'Zwischenschritte'!$A$2:$A${g}&\";\","
                       "$V{i})),--('Zwischenschritte'!$B$2:$B${g}<>\"x\"))=0,1,0),0)").format(i=i, g=g_ende)
        werte = [e["id"], e["zeitalter"], e["zeitalter_name"], e["t_kategorie"], e["name"], e["funktion"],
                 e["t_materialien"], e["t_verfahren"], e["energie"], e["t_kette"], e["t_vorl"], e["t_vorl_ids"],
                 e["status"],
                 "=IFERROR(INDEX('Prompt-Abgleich'!$B$2:$B$10,MATCH(M%d,'Prompt-Abgleich'!$A$2:$A$10,0)),\"?\")" % i,
                 "ja" if e["testbereich"] else "nein", e["t_luecken"], e["t_stand"], e["t_alt"], e["hinweis"],
                 e["h_verf"], e["h_mat"], e["h_gruppen"], mit_auswahl]
        zeilen = 1
        for j, (wert, (buchst, _t, breite, wrap)) in enumerate(zip(werte, SPALTEN), start=1):
            font = arial
            if buchst == "E":
                font = arial_b
            elif buchst in ("T", "U", "V", "W"):
                font = hilfs_font
            elif buchst == "Q" and e["stand"] == "spek":
                font = arial_i
            z = zelle(we, i, j, wert, font, wrap=wrap, fmt="0" if buchst == "B" else None)
            z.border = rahmen
            if wrap and isinstance(wert, str) and not wert.startswith("="):
                zeilen = max(zeilen, zeilen_noetig(wert, breite, fett=(buchst == "E")))
        we.row_dimensions[i].height = min(120, 13 * zeilen + 3)
    we.freeze_panes = "F2"
    we.auto_filter.ref = "A1:W%d" % letzte
    for code, fill in [("A", status_fill["A"]), ("WA", status_fill["WA"]), ("L", status_fill["L"])]:
        we.conditional_formatting.add("M2:N%d" % letzte, FormulaRule(formula=['$M2="%s"' % code], fill=fill))
    we.conditional_formatting.add("M2:N%d" % letzte, FormulaRule(formula=['LEFT($M2,1)="P"'], fill=status_fill["P"]))
    we.conditional_formatting.add("O2:O%d" % letzte, FormulaRule(formula=['$O2="ja"'], fill=status_fill["WA"]))
    dv_kat = DataValidation(type="list", formula1='"%s"' % ",".join(V.KATEGORIEN.values()), allow_blank=False)
    dv_status = DataValidation(type="list", formula1='"%s"' % ",".join(V.STATUS_ORDER), allow_blank=False)
    dv_test = DataValidation(type="list", formula1='"ja,nein"', allow_blank=False)
    dv_stand = DataValidation(type="list", formula1='"historisch belegt,in Entwicklung,spekulativ"', allow_blank=False)
    for dv, rng in [(dv_kat, "D2:D%d" % letzte), (dv_status, "M2:M%d" % letzte), (dv_test, "O2:O%d" % letzte),
                    (dv_stand, "Q2:Q%d" % letzte)]:
        we.add_data_validation(dv)
        dv.add(rng)

    # ------------------------------------------------------------ Zwischenschritte
    wsz = wb.create_sheet("Zwischenschritte")
    kopf = ["Zwischenschritt (gebündelte Lücke)", "auswählen (x)", "betroffene Erfindungen",
            "hängen nur an diesem Schritt", "frühestes Zeitalter (Nr)", "frühestes Zeitalter", "fehlende Verfahren",
            "fehlende Materialien", "Erläuterung"]
    kopfzeile(wsz, kopf, [34, 11, 12, 14, 10, 22, 46, 40, 60])
    eingabe_fill = PatternFill("solid", fgColor="FFF59D")
    gruppen_zahl = {}
    for g, _v, _m, _h in V.LUECKEN_GRUPPEN:
        gruppen_zahl[g] = (sum(1 for e in erfindungen if g in e["gruppen"]),
                           sum(1 for e in erfindungen if e["gruppen"] == [g]))
    reihenfolge = sorted(V.LUECKEN_GRUPPEN, key=lambda x: (-gruppen_zahl[x[0]][1], -gruppen_zahl[x[0]][0]))
    for i, (g, verf, mats, hinweis) in enumerate(reihenfolge, start=2):
        zelle(wsz, i, 1, g, arial_b, wrap=True)
        auswahl = zelle(wsz, i, 2, "x" if g in VORGESCHLAGEN else None, arial_b)
        auswahl.fill = eingabe_fill
        auswahl.alignment = Alignment(horizontal="center", vertical="top")
        zelle(wsz, i, 3, '=COUNTIF(%s$V:$V,"*;"&$A%d&";*")' % (E, i), fmt="#,##0")
        zelle(wsz, i, 4, '=COUNTIF(%s$V:$V,";"&$A%d&";")' % (E, i), fmt="#,##0")
        zelle(wsz, i, 5, '=IF(C%d=0,"",_xlfn.MINIFS(%s$B:$B,%s$V:$V,"*;"&$A%d&";*"))' % (i, E, E, i), fmt="0")
        zelle(wsz, i, 6, "=IF(E%d=\"\",\"\",INDEX('Zeitalter'!$B$2:$B$25,E%d))" % (i, i))
        zelle(wsz, i, 7, ", ".join(V.VERFAHREN[c][0] for c in verf) or "—", wrap=True)
        zelle(wsz, i, 8, ", ".join(V.MATERIALIEN[c][0] for c in mats) or "—", wrap=True)
        zelle(wsz, i, 9, hinweis, wrap=True)
        wsz.row_dimensions[i].height = 52
    s = len(reihenfolge) + 2
    dv_x = DataValidation(type="list", formula1='"x"', allow_blank=True)
    wsz.add_data_validation(dv_x)
    dv_x.add("B2:B%d" % (s - 1))
    zelle(wsz, s + 1, 1, "Auswahl ausprobieren", abschnitt_font)
    zelle(wsz, s + 2, 1, "In Spalte B (gelb) mit x markieren, welche Zwischenschritte ins Spiel kommen sollen. Vorausgewählt "
                         "sind die beiden vorgeschlagenen Schritte. Gezählt wird, was dann zusammen mit den geplanten "
                         "Prompts bis 12 möglich wäre.", arial_i)
    summe = [
        ("ausgewählte Zwischenschritte", '=COUNTIF($B$2:$B$%d,"x")' % (s - 1), "0"),
        ("mit der Auswahl zusätzlich möglich", "=SUM(%s$W:$W)" % E, "#,##0"),
        ("dann insgesamt möglich (bis Prompt 12 + Auswahl)",
         '=COUNTA(%s$A:$A)-1-COUNTIF(%s$M:$M,"L")+C%d' % (E, E, s + 4), "#,##0"),
        ("Anteil aller Erfindungen", "=IF(COUNTA(%s$A:$A)-1=0,0,C%d/(COUNTA(%s$A:$A)-1))" % (E, s + 5, E), "0.0%"),
    ]
    for j, (text, formel, fmt) in enumerate(summe, start=s + 3):
        zelle(wsz, j, 1, text, arial_b)
        zelle(wsz, j, 3, formel, arial_b, fmt=fmt)
    s_notiz = s + 8
    zelle(wsz, s_notiz, 1, "„hängen nur an diesem Schritt“ = Erfindungen, deren einzige fehlende Grundlage dieser "
                           "Zwischenschritt ist; sie würden mit ihm (und den geplanten Prompts) möglich. "
                           "Eine Erfindung kann an mehreren Schritten hängen.", arial_i)
    wsz.freeze_panes = "C2"
    ch2 = BarChart()
    ch2.type = "bar"
    ch2.title = "Erfindungen, die nur an einem Zwischenschritt hängen"
    ch2.add_data(Reference(wsz, min_col=4, min_row=1, max_row=s - 1), titles_from_data=True)
    ch2.set_categories(Reference(wsz, min_col=1, min_row=2, max_row=s - 1))
    ch2.series[0].graphicalProperties.solidFill = "2E5E3A"
    ch2.x_axis.scaling.orientation = "maxMin"
    ch2.height = 12
    ch2.width = 26
    ch2.roundedCorners = False
    ch2.legend = None
    ch2.title.overlay = False
    ch2.x_axis.delete = False
    ch2.y_axis.delete = False
    wsz.add_chart(ch2, "A%d" % (s_notiz + 2))

    # ------------------------------------------------------------ Lücken
    wl = wb.create_sheet("Lücken")
    kopf = ["Art", "Code", "fehlende Grundlage", "was fehlt", "Zwischenschritt", "betroffene Erfindungen",
            "frühestes Zeitalter (Nr)", "Beispiele"]
    kopfzeile(wl, kopf, [10, 16, 32, 52, 32, 12, 11, 60])
    luecken = []
    for c, v in V.VERFAHREN.items():
        if v[3] == "L":
            betroffen = [e for e in erfindungen if c in e["verfahren"]]
            luecken.append(("Verfahren", c, v[0], v[4], V.gruppe_von("v", c), betroffen))
    for c, m in V.MATERIALIEN.items():
        if m[3] == "L":
            betroffen = [e for e in erfindungen if c in e["materialien"]]
            luecken.append(("Material", c, m[0], m[4], V.gruppe_von("m", c), betroffen))
    luecken.sort(key=lambda x: (-len(x[5]), x[2]))
    for i, (art, code, name, was, gruppe, betroffen) in enumerate(luecken, start=2):
        spalte = "T" if art == "Verfahren" else "U"
        zelle(wl, i, 1, art)
        zelle(wl, i, 2, code, hilfs_font)
        zelle(wl, i, 3, name, arial_b, wrap=True)
        zelle(wl, i, 4, was, wrap=True)
        zelle(wl, i, 5, gruppe, wrap=True)
        zelle(wl, i, 6, '=COUNTIF(%s$%s:$%s,"*;"&$B%d&";*")' % (E, spalte, spalte, i), fmt="#,##0")
        zelle(wl, i, 7, '=IF(F%d=0,"",_xlfn.MINIFS(%s$B:$B,%s$%s:$%s,"*;"&$B%d&";*"))' % (i, E, E, spalte, spalte, i),
              fmt="0")
        zelle(wl, i, 8, "; ".join(e["name"] for e in betroffen[:5]) or "—", wrap=True)
        wl.row_dimensions[i].height = 30
    wl.freeze_panes = "D2"
    wl.auto_filter.ref = "A1:H%d" % (len(luecken) + 1)

    # ------------------------------------------------------------ Prompt-Abgleich
    wp = wb.create_sheet("Prompt-Abgleich")
    kopf = ["Code", "Stufe", "Was dieser Schritt physikalisch bringt", "Erfindungen mit diesem Spielstand",
            "kumuliert", "Anteil", "Anteil kumuliert"]
    kopfzeile(wp, kopf, [8, 26, 90, 14, 11, 9, 11])
    for i, code in enumerate(V.STATUS_ORDER, start=2):
        zelle(wp, i, 1, code, arial_b)
        zelle(wp, i, 2, V.STATUS_TEXT[code], wrap=True)
        zelle(wp, i, 3, V.STATUS_BESCHREIBUNG[code], wrap=True)
        zelle(wp, i, 4, "=COUNTIF(%s$M:$M,$A%d)" % (E, i), fmt="#,##0")
        zelle(wp, i, 5, "=SUM($D$2:D%d)" % i, fmt="#,##0")
        zelle(wp, i, 6, "=IF($D$11=0,0,D%d/$D$11)" % i, fmt="0.0%")
        zelle(wp, i, 7, "=IF($D$11=0,0,E%d/$D$11)" % i, fmt="0.0%")
        wp.row_dimensions[i].height = 42
        fill = status_fill["P"] if code.startswith("P") else status_fill.get(code)
        if fill is not None:
            wp.cell(row=i, column=1).fill = fill
    zelle(wp, 11, 2, "Summe", arial_b)
    wp["D11"] = "=SUM(D2:D10)"
    wp["D11"].font = arial_b
    wp["D11"].number_format = "#,##0"
    zelle(wp, 13, 2, "Reihenfolge = frühester Zeitpunkt. Die Einordnung des Zusatzes Weltarchitektur (hier direkt nach "
                     "v0.6.1) ist noch nicht entschieden. „kumuliert“ zählt alle Erfindungen, die spätestens mit "
                     "dieser Stufe möglich wären.", arial_i)
    wp.freeze_panes = "C2"

    # ------------------------------------------------------------ Verfahren
    wv = wb.create_sheet("Verfahren")
    kopf = ["Code", "Verfahren", "Physik / Ablauf", "Energie / Temperatur", "Spielstand-Code",
            "im normalen Spiel möglich ab", "Lücke / Hinweis", "heute im Testbereich", "Zwischenschritt",
            "verwendet in Erfindungen"]
    kopfzeile(wv, kopf, [16, 30, 52, 30, 9, 22, 46, 11, 30, 12])
    for i, (code, (name, phys, en, st, luecke, test)) in enumerate(sorted(
            V.VERFAHREN.items(), key=lambda kv: (V.STATUS_ORDER.index(kv[1][3]), kv[1][0])), start=2):
        zelle(wv, i, 1, code, hilfs_font)
        zelle(wv, i, 2, name, arial_b, wrap=True)
        zelle(wv, i, 3, phys, wrap=True)
        zelle(wv, i, 4, en, wrap=True)
        zelle(wv, i, 5, st)
        zelle(wv, i, 6, "=IFERROR(INDEX('Prompt-Abgleich'!$B$2:$B$10,MATCH(E%d,'Prompt-Abgleich'!$A$2:$A$10,0)),\"?\")"
              % i, wrap=True)
        zelle(wv, i, 7, luecke or "—", wrap=True)
        zelle(wv, i, 8, "ja (Testofen)" if test else "nein")
        zelle(wv, i, 9, V.gruppe_von("v", code) if st == "L" else "—", wrap=True)
        zelle(wv, i, 10, '=COUNTIF(%s$T:$T,"*;"&$A%d&";*")' % (E, i), fmt="#,##0")
        wv.row_dimensions[i].height = 30
    lv = len(V.VERFAHREN) + 1
    for code, fill in [("A", status_fill["A"]), ("WA", status_fill["WA"]), ("L", status_fill["L"])]:
        wv.conditional_formatting.add("E2:F%d" % lv, FormulaRule(formula=['$E2="%s"' % code], fill=fill))
    wv.conditional_formatting.add("E2:F%d" % lv, FormulaRule(formula=['LEFT($E2,1)="P"'], fill=status_fill["P"]))
    wv.freeze_panes = "C2"
    wv.auto_filter.ref = "A1:J%d" % lv

    # ------------------------------------------------------------ Materialien
    wm = wb.create_sheet("Materialien")
    kopf = ["Code", "Material", "Art", "Spielmaterial (v0.6.1)", "Spielstand-Code", "im normalen Spiel verfügbar ab",
            "Gewinnung / Hinweis", "Schmelzpunkt (°C, Richtwert)", "Zwischenschritt", "verwendet in Erfindungen"]
    kopfzeile(wm, kopf, [14, 32, 12, 16, 9, 22, 56, 13, 30, 12])
    for i, (code, (name, art, spiel, st, gew, smp)) in enumerate(sorted(
            V.MATERIALIEN.items(), key=lambda kv: (V.STATUS_ORDER.index(kv[1][3]), kv[1][0])), start=2):
        zelle(wm, i, 1, code, hilfs_font)
        zelle(wm, i, 2, name, arial_b, wrap=True)
        zelle(wm, i, 3, art)
        zelle(wm, i, 4, spiel or "—")
        zelle(wm, i, 5, st)
        zelle(wm, i, 6, "=IFERROR(INDEX('Prompt-Abgleich'!$B$2:$B$10,MATCH(E%d,'Prompt-Abgleich'!$A$2:$A$10,0)),\"?\")"
              % i, wrap=True)
        zelle(wm, i, 7, gew or "—", wrap=True)
        zelle(wm, i, 8, smp if smp is not None else "—", fmt="#,##0")
        zelle(wm, i, 9, V.gruppe_von("m", code) if st == "L" else "—", wrap=True)
        zelle(wm, i, 10, '=COUNTIF(%s$U:$U,"*;"&$A%d&";*")' % (E, i), fmt="#,##0")
        wm.row_dimensions[i].height = 28
    lm = len(V.MATERIALIEN) + 1
    for code, fill in [("A", status_fill["A"]), ("WA", status_fill["WA"]), ("L", status_fill["L"])]:
        wm.conditional_formatting.add("E2:F%d" % lm, FormulaRule(formula=['$E2="%s"' % code], fill=fill))
    wm.conditional_formatting.add("E2:F%d" % lm, FormulaRule(formula=['LEFT($E2,1)="P"'], fill=status_fill["P"]))
    zelle(wm, lm + 2, 2, "Schmelzpunkte: gerundete Lehrbuchwerte (Bronze, Messing, Stahl: typische Werte je nach "
                         "Zusammensetzung). Spielmaterial = Materialdefinition in data/materials/ (v0.6.1).", arial_i)
    wm.freeze_panes = "C2"
    wm.auto_filter.ref = "A1:J%d" % lm

    # ------------------------------------------------------------ Katalogabgleich
    wk = wb.create_sheet("Katalogabgleich")
    kopf = ["Alte ID", "Alter Name", "Art", "Kategorie", "Zeitalter alt (Nr)", "Zeitalter alt", "Entspricht in der "
            "Leitlinie", "Neue ID", "Zeitalter neu (Nr)", "Zeitalter neu", "Verschiebung", "Bemerkung"]
    kopfzeile(wk, kopf, [34, 30, 9, 13, 9, 22, 34, 10, 9, 22, 24, 50])
    alt_sortiert = sorted(alt, key=lambda a: (a["first_stage"], a["name"]))
    for i, a in enumerate(alt_sortiert, start=2):
        neu = K.neuer_name(a["concept"], a["category"])
        zelle(wk, i, 1, a["id"], hilfs_font)
        zelle(wk, i, 2, a["name"], arial_b, wrap=True)
        zelle(wk, i, 3, "echt" if a["name_kind"] == "real" else "Variante")
        zelle(wk, i, 4, a["category"])
        zelle(wk, i, 5, a["first_stage"], fmt="0")
        zelle(wk, i, 6, a["first_stage_name"], wrap=True)
        zelle(wk, i, 7, neu or "", wrap=True)
        zelle(wk, i, 8, "=IF(G%d=\"\",\"\",IFERROR(INDEX(%s$A:$A,MATCH(G%d,%s$E:$E,0)),\"nicht gefunden\"))"
              % (i, E, i, E))
        zelle(wk, i, 9, "=IF(G%d=\"\",\"\",IFERROR(INDEX(%s$B:$B,MATCH(G%d,%s$E:$E,0)),\"\"))" % (i, E, i, E), fmt="0")
        zelle(wk, i, 10, "=IF(I%d=\"\",\"\",INDEX('Zeitalter'!$B$2:$B$25,I%d))" % (i, i), wrap=True)
        zelle(wk, i, 11, "=IF(I%d=\"\",\"\",IF(I%d>E%d,\"später eingeordnet (+\"&(I%d-E%d)&\")\",IF(I%d<E%d,"
                         "\"früher eingeordnet (\"&(I%d-E%d)&\")\",\"gleiches Zeitalter\")))"
              % (i, i, i, i, i, i, i, i, i), wrap=True)
        bem = K.OHNE_ENTSPRECHUNG.get(a["concept"], "")
        if a["name_kind"] == "variant":
            bem = (bem + "; " if bem else "") + "Variante „(verbessert)“ – in der Leitlinie keine eigene Erfindung"
        zelle(wk, i, 12, bem, wrap=True)
    lk = len(alt_sortiert) + 1
    zelle(wk, lk + 2, 2, "Zusammenfassung (Formeln)", abschnitt_font)
    zus = [("Einträge (echte Namen und Varianten)", "=COUNTA(A2:A%d)" % lk),
           ("später eingeordnet", '=COUNTIF(K2:K%d,"später*")' % lk),
           ("früher eingeordnet", '=COUNTIF(K2:K%d,"früher*")' % lk),
           ("gleiches Zeitalter", '=COUNTIF(K2:K%d,"gleiches Zeitalter")' % lk),
           ("ohne Entsprechung", '=COUNTIF(G2:G%d,"")' % lk)]
    for j, (t, f) in enumerate(zus, start=lk + 3):
        zelle(wk, j, 2, t, arial_b)
        zelle(wk, j, 3, f, fmt="#,##0")
    zelle(wk, lk + 9, 2, "Die 2.608 erzeugten Fantasienamen der alten Datei (z. B. „Quanten- Kupferaxt 6“) und ihre "
                         "Zufallsboni sind nicht übernommen.", arial_i)
    wk.freeze_panes = "C2"
    wk.auto_filter.ref = "A1:L%d" % lk

    # Druckeinstellungen: quer, eine Seite breit, Kopfzeile auf jeder Seite wiederholen
    for blatt in wb.worksheets:
        blatt.page_setup.orientation = "portrait" if blatt.title == "Anleitung" else "landscape"
        blatt.page_setup.paperSize = blatt.PAPERSIZE_A4
        if blatt.title == "Erfindungen":
            # zu breit für eine Seite: in Originalgröße über mehrere Seiten, ohne die grauen Hilfsspalten
            blatt.print_area = "A1:S%d" % letzte
        else:
            blatt.page_setup.fitToWidth = 1
            blatt.page_setup.fitToHeight = 0
            blatt.sheet_properties.pageSetUpPr.fitToPage = True
        blatt.print_options.gridLines = False
        blatt.page_margins.left = blatt.page_margins.right = 0.4
        blatt.page_margins.top = blatt.page_margins.bottom = 0.5
        if blatt.title != "Anleitung":
            blatt.print_title_rows = "1:1"
        blatt.oddFooter.center.text = "&A – Seite &P von &N"
        blatt.oddFooter.center.font = "Arial"
        blatt.oddFooter.center.size = 8
    # Excel und LibreOffice rechnen beim Öffnen alle Formeln neu (openpyxl speichert keine Ergebniswerte)
    wb.calculation.fullCalcOnLoad = True
    wb.save(pfad)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pruefen", action="store_true", help="nur prüfen, keine Excel schreiben")
    ap.add_argument("--out", default=ZIEL, help="Zielpfad der Excel")
    args = ap.parse_args(argv)
    erfindungen, fehler = Q.lies_quellen(QUELLEN)
    if fehler:
        print("FEHLER in den Quellen (%d):" % len(fehler))
        for f in fehler:
            print("  - " + f)
        return 1
    alt = lade_alten_katalog()
    bereite_vor(erfindungen, alt)
    from collections import Counter
    je = Counter(e["zeitalter"] for e in erfindungen)
    st = Counter(e["status"] for e in erfindungen)
    print("Erfindungen: %d in %d Zeitaltern (je %d–%d)" % (len(erfindungen), len(je), min(je.values()),
                                                            max(je.values())))
    print("Spielstand: " + ", ".join("%s %d" % (c, st.get(c, 0)) for c in V.STATUS_ORDER))
    print("Testbereich: %d, spekulativ: %d, in Entwicklung: %d" % (
        sum(1 for e in erfindungen if e["testbereich"]), sum(1 for e in erfindungen if e["stand"] == "spek"),
        sum(1 for e in erfindungen if e["stand"] == "entw")))
    if args.pruefen:
        print("Prüfung bestanden.")
        return 0
    schreibe_excel(erfindungen, alt, args.out)
    print("geschrieben: " + args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
