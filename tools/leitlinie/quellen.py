"""Liest und prüft die Quelldateien design/leitlinie/zeitalter_XX.txt.

Ergebnis: Liste von Erfindungen (dict) mit abgeleiteten Feldern (Spielstand, Lücken, Energie/Temperatur).
Fehler werden gesammelt, nicht stillschweigend übergangen.
"""
from __future__ import annotations

import os
import re
import unicodedata

from . import vokabular as V

MIN_JE_ZEITALTER = 50
MAX_JE_ZEITALTER = 500
STAND_TEXT = {"": "historisch belegt", "entw": "in Entwicklung / teilweise verwirklicht", "spek": "spekulativ"}


def norm(name: str) -> str:
    """Vergleichsschlüssel für Namen: Kleinbuchstaben, Umlaute vereinheitlicht, nur Buchstaben/Ziffern."""
    s = unicodedata.normalize("NFKC", name).lower().strip()
    s = s.replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
    return re.sub(r"[^a-z0-9]+", "", s)


def _status_max(codes):
    worst = 0
    for c in codes:
        worst = max(worst, V.STATUS_ORDER.index(c))
    return V.STATUS_ORDER[worst]


def lies_quellen(ordner: str):
    """Gibt (erfindungen, fehler) zurück."""
    erfindungen = []
    fehler = []
    for nr, name, *_ in V.ZEITALTER:
        pfad = os.path.join(ordner, "zeitalter_%02d.txt" % nr)
        if not os.path.exists(pfad):
            fehler.append("Zeitalter %d: Datei fehlt (%s)" % (nr, pfad))
            continue
        with open(pfad, encoding="utf-8") as f:
            zeilen = f.read().splitlines()
        lfd = 0
        for zn, zeile in enumerate(zeilen, start=1):
            z = zeile.strip()
            if not z or z.startswith("#"):
                continue
            teile = [t.strip() for t in z.split("|")]
            wo = "Zeitalter %d, Zeile %d" % (nr, zn)
            if len(teile) < 5:
                fehler.append("%s: zu wenige Felder (%d)" % (wo, len(teile)))
                continue
            while len(teile) < 8:
                teile.append("")
            if len(teile) > 8:
                fehler.append("%s: zu viele Felder (%d)" % (wo, len(teile)))
                continue
            name_e, kat, mats, verf, funktion, vorl, stand, hinweis = teile
            if not name_e:
                fehler.append("%s: Name fehlt" % wo)
            if kat not in V.KATEGORIEN:
                fehler.append("%s: unbekannte Kategorie %r" % (wo, kat))
            mat_codes = [] if mats in ("", "-") else [m.strip() for m in mats.split(",") if m.strip()]
            for m in mat_codes:
                if m not in V.MATERIALIEN:
                    fehler.append("%s (%s): unbekanntes Material %r" % (wo, name_e, m))
            verf_codes = [v.strip() for v in verf.split(",") if v.strip()]
            if not verf_codes:
                fehler.append("%s (%s): kein Verfahren" % (wo, name_e))
            for v in verf_codes:
                if v not in V.VERFAHREN:
                    fehler.append("%s (%s): unbekanntes Verfahren %r" % (wo, name_e, v))
            if not funktion:
                fehler.append("%s (%s): Funktion fehlt" % (wo, name_e))
            if re.search(r"[+-]\s*\d+\s*%", funktion):
                fehler.append("%s (%s): Funktion enthält einen Prozent-Bonus" % (wo, name_e))
            if stand not in STAND_TEXT:
                fehler.append("%s (%s): unbekannter Stand %r" % (wo, name_e, stand))
            if nr == 24 and stand == "":
                stand = "spek"
            lfd += 1
            erfindungen.append({
                "id": "Z%02d-%03d" % (nr, lfd), "zeitalter": nr, "zeitalter_name": name, "kategorie": kat,
                "name": name_e, "funktion": funktion, "materialien": mat_codes, "verfahren": verf_codes,
                "vorlaeufer_namen": [v.strip() for v in vorl.split(";") if v.strip()], "stand": stand,
                "hinweis": hinweis, "zeile": zn,
            })
    # Eindeutige Namen
    gesehen = {}
    for e in erfindungen:
        k = norm(e["name"])
        if k in gesehen:
            fehler.append("Name doppelt: %r (%s und %s)" % (e["name"], gesehen[k]["id"], e["id"]))
        else:
            gesehen[k] = e
    # Vorläufer auflösen (gleiches oder früheres Zeitalter)
    for e in erfindungen:
        e["vorlaeufer"] = []
        for vn in e["vorlaeufer_namen"]:
            ziel = gesehen.get(norm(vn))
            if ziel is None:
                fehler.append("%s %r: Vorläufer %r unbekannt" % (e["id"], e["name"], vn))
            elif ziel["zeitalter"] > e["zeitalter"]:
                fehler.append("%s %r: Vorläufer %r liegt später (Zeitalter %d)" % (
                    e["id"], e["name"], vn, ziel["zeitalter"]))
            elif ziel is e:
                fehler.append("%s %r: verweist auf sich selbst" % (e["id"], e["name"]))
            else:
                e["vorlaeufer"].append(ziel)
    # Anzahl je Zeitalter
    for nr, name, *_ in V.ZEITALTER:
        n = sum(1 for e in erfindungen if e["zeitalter"] == nr)
        if n and not (MIN_JE_ZEITALTER <= n <= MAX_JE_ZEITALTER):
            fehler.append("Zeitalter %d (%s): %d Erfindungen – erlaubt %d–%d" % (
                nr, name, n, MIN_JE_ZEITALTER, MAX_JE_ZEITALTER))
    for e in erfindungen:
        leite_ab(e)
    return erfindungen, fehler


def leite_ab(e: dict) -> None:
    """Spielstand, Lücken, Testbereich und Energie/Temperatur aus Verfahren und Materialien."""
    codes = []
    luecken = []
    e["verfahren"] = [v for v in e["verfahren"] if v in V.VERFAHREN]
    e["materialien"] = [m for m in e["materialien"] if m in V.MATERIALIEN]
    for v in e["verfahren"]:
        name, _phys, _en, st, luecke, _test = V.VERFAHREN[v]
        codes.append(st)
        if st == "L":
            luecken.append("Verfahren: " + name)
    for m in e["materialien"]:
        mname, _art, _spiel, st, _gew, _smp = V.MATERIALIEN[m]
        codes.append(st)
        if st == "L":
            luecken.append("Material: " + mname)
    e["status"] = _status_max(codes) if codes else "A"
    e["luecken"] = luecken
    # Heute im Testbereich vorführbar: alle Verfahren vorhanden oder mit Testausrüstung, alle Materialien vorhanden
    # oder als Testausrüstung. Die Keramik gibt es in v0.6.1 nur als Tiegel und Gussform der Testwerkstatt –
    # sie zählt deshalb nur dort, wo geschmolzen oder gegossen wird (kein Vorratskrug, kein Wasserkrug).
    # Wo der Testofen das Schmelzen übernimmt, ersetzt er auch Brennstoff und Luftzufuhr.
    testofen = any(V.VERFAHREN[v][5] for v in e["verfahren"])
    ersetzt_v = {"luftzufuhr", "feuer_nutzen", "feuer_machen"} if testofen else set()
    ersetzt_m = {"holzkohle", "keramik"} if testofen else set()
    ok = True
    for v in e["verfahren"]:
        st = V.VERFAHREN[v][3]
        if not (st == "A" or V.VERFAHREN[v][5] or v in ersetzt_v):
            ok = False
    for m in e["materialien"]:
        st = V.MATERIALIEN[m][3]
        if not (st == "A" or m in ersetzt_m):
            ok = False
    e["testbereich"] = ok and e["status"] != "A"
    # Energie/Temperatur: gleiche Angaben zusammenfassen („Muskelkraft“ statt „Schlagen: Muskelkraft; Binden: …“)
    je_energie: dict[str, list[str]] = {}
    for v in e["verfahren"]:
        name, _phys, en, *_ = V.VERFAHREN[v]
        if v in ("schmelzen", "giessen", "legieren"):
            temps = ["%s %s °C" % (V.MATERIALIEN[m][0], _zahl(V.MATERIALIEN[m][5])) for m in e["materialien"]
                     if V.MATERIALIEN[m][5] is not None and V.MATERIALIEN[m][1] in ("Metall", "Legierung")]
            if temps:
                en = "Schmelzpunkt " + ", ".join(temps)
        if en and en != "—":
            je_energie.setdefault(en, []).append(name)
    if not je_energie:
        e["energie"] = "—"
    elif len(je_energie) == 1:
        e["energie"] = next(iter(je_energie))
    else:
        e["energie"] = "; ".join("%s (%s)" % (en, ", ".join(namen)) for en, namen in je_energie.items())


def _zahl(x: float) -> str:
    s = ("%d" % x) if float(x).is_integer() else ("%.1f" % x).replace(".", ",")
    # Tausenderpunkt
    neg = s.startswith("-")
    s = s.lstrip("-")
    if "," not in s and len(s) > 3:
        s = s[:-3] + "." + s[-3:]
    return ("−" if neg else "") + s
