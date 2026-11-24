#!/usr/bin/env python3
"""Erfindungs-Excel → inaktiver Ideenkatalog (Entwicklungswerkzeug).

Liest design/Erfindungen_nach_Kategorien_und_Stufen.xlsx NUR LESEND und erzeugt
data/generated/ideas/inventions_catalog.json sowie reports/inventions_import_report.md.

WICHTIG – der Katalog aktiviert NICHTS:
- Jeder Eintrag hat game_status "idea_only".
- Die Excel-Effekte („+75 % Produktion“, „Schaltet Wunder frei“ …) werden nur als
  Originaltext (excel_effect_text) aufbewahrt und nie ausgewertet. Es gibt im Spiel keine
  globalen Prozentboni, keine Zeitalter-Freischaltung und keine Forschungspunkte.
- Eine Erfindung „existiert“ im Spiel erst, wenn Wesen sie tatsächlich mit Materialien,
  Werkzeugen und Arbeitsschritten herstellen (spätere Prompts).
Der Katalog ist eine Ideenliste für die Entwicklung (Kategorien, Zeitalter, Grundbegriffe).

Aufruf (im Projektordner):
    python tools/import_inventions.py            # prüfen, Bericht schreiben, Katalog NICHT schreiben
    python tools/import_inventions.py --write    # zusätzlich Katalog schreiben

Exit-Code: 0 = in Ordnung, 2 = Datei/Blatt unbrauchbar.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

try:
    import openpyxl
except ImportError:  # pragma: no cover
    print("Fehler: openpyxl fehlt. Installation: python -m pip install -r tools/requirements.txt", file=sys.stderr)
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_EXCEL = ROOT / "design" / "Erfindungen_nach_Kategorien_und_Stufen.xlsx"
DEFAULT_OUT = ROOT / "data" / "generated" / "ideas" / "inventions_catalog.json"
DEFAULT_REPORT = ROOT / "reports" / "inventions_import_report.md"
SCHEMA_VERSION = 1
OVERVIEW = "Übersicht"
HEADERS = {"Stufe": "stage", "Stufe-Name": "stage_name", "Erfindung": "name", "Effekt": "effect",
           "Beschreibung": "description", "Forschungskosten": "research_cost"}
TEMPLATE_RE = re.compile(r"^.+ in der Kategorie .+ für .+\. Verbessert die Zivilisation signifikant\.$")
PREFIXES = [("Fortgeschrittene ", "fortgeschritten"), ("Zukunfts-", "zukunft"), ("Industrielle ", "industriell"), ("Moderne ", "modern")]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def concept_of(name: str) -> tuple[str, str]:
    """Grundbegriff ohne Zeitalter-Klammer, laufende Nummer und Vorsilben.
    'Flug (Frühe Steinzeit 1)' → ('Flug', ''); 'Fortgeschrittene Analyse 12' → ('Analyse', 'fortgeschritten')."""
    base = re.sub(r"\s*\([^)]*\)\s*$", "", name).strip()
    base = re.sub(r"\s+\d+$", "", base).strip()
    marker = ""
    for pre, m in PREFIXES:
        if base.startswith(pre):
            base = base[len(pre):].strip()
            marker = m
    return base, marker


def slug(s: str) -> str:
    t = s.lower()
    for a, b in (("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")):
        t = t.replace(a, b)
    return re.sub(r"[^a-z0-9]+", "_", t).strip("_")


def read(excel: Path) -> dict:
    wb = openpyxl.load_workbook(excel, data_only=True, read_only=True)
    if OVERVIEW not in wb.sheetnames:
        raise ValueError(f"Blatt '{OVERVIEW}' fehlt.")
    problems: list[str] = []
    # Übersicht: Zeitalter + Sollanzahl je Kategorie
    rows = list(wb[OVERVIEW].iter_rows(values_only=True))
    head_i = next((i for i, r in enumerate(rows) if r and r[0] == "Stufe"), None)
    if head_i is None:
        raise ValueError("Übersicht: Kopfzeile 'Stufe' nicht gefunden.")
    head = [c for c in rows[head_i]]
    cat_cols = [(i, c) for i, c in enumerate(head) if i >= 2 and c not in (None, "Gesamt")]
    eras, expected = [], {}
    for r in rows[head_i + 1:]:
        if r[0] is None:
            continue
        eras.append({"stage": int(r[0]), "name": str(r[1])})
        for i, c in cat_cols:
            expected[(c, int(r[0]))] = int(r[i] or 0)
    era_name = {e["stage"]: e["name"] for e in eras}
    categories = [c for _, c in cat_cols]
    entries, counts = [], {}
    template_hits = 0
    effects: dict[str, int] = {}
    for cat in categories:
        if cat not in wb.sheetnames:
            problems.append(f"Kategorieblatt '{cat}' fehlt.")
            continue
        it = wb[cat].iter_rows(values_only=True)
        hdr = next(it)
        col = {HEADERS[h]: i for i, h in enumerate(hdr) if h in HEADERS}
        missing = [k for k in HEADERS.values() if k not in col]
        if missing:
            raise ValueError(f"Blatt '{cat}': Spalten fehlen: {missing}")
        n = 0
        for rn, r in enumerate(it, start=2):
            if r[col["name"]] is None:
                continue
            n += 1
            stage = int(r[col["stage"]])
            name = str(r[col["name"]]).strip()
            if era_name.get(stage) != str(r[col["stage_name"]]):
                problems.append(f"{cat} Zeile {rn}: Stufenname '{r[col['stage_name']]}' passt nicht zu Stufe {stage}.")
            desc = str(r[col["description"]] or "")
            if TEMPLATE_RE.match(desc):
                template_hits += 1
            eff = str(r[col["effect"]] or "")
            effects[eff] = effects.get(eff, 0) + 1
            concept, marker = concept_of(name)
            counts[(cat, stage)] = counts.get((cat, stage), 0) + 1
            entries.append(OrderedDict([
                ("id", f"INV_{slug(cat)}_{stage:02d}_{counts[(cat, stage)]:02d}"),
                ("category", cat), ("stage", stage), ("stage_name", era_name.get(stage, "")),
                ("name", name), ("concept", concept), ("variant_marker", marker),
                ("excel_effect_text", eff), ("excel_research_cost", r[col["research_cost"]]),
                ("description_is_template", bool(TEMPLATE_RE.match(desc))),
                ("source", {"sheet": cat, "row": rn}),
                ("game_status", "idea_only"),
            ]))
    for key, want in expected.items():
        got = counts.get(key, 0)
        if got != want:
            problems.append(f"Übersicht {key[0]}/Stufe {key[1]}: {want} erwartet, {got} gefunden.")
    # Grundbegriffe je Kategorie
    concepts: dict[tuple, dict] = {}
    for e in entries:
        k = (e["category"], e["concept"])
        c = concepts.setdefault(k, {"category": e["category"], "concept": e["concept"], "first_stage": e["stage"],
                                    "last_stage": e["stage"], "entries": 0, "markers": set(), "examples": []})
        c["first_stage"] = min(c["first_stage"], e["stage"])
        c["last_stage"] = max(c["last_stage"], e["stage"])
        c["entries"] += 1
        if e["variant_marker"]:
            c["markers"].add(e["variant_marker"])
        if len(c["examples"]) < 3:
            c["examples"].append(e["name"])
    concept_list = []
    for c in sorted(concepts.values(), key=lambda x: (categories.index(x["category"]), x["first_stage"], x["concept"])):
        c["first_stage_name"] = era_name.get(c["first_stage"], "")
        c["markers"] = sorted(c["markers"])
        concept_list.append(c)
    return {"eras": eras, "categories": categories, "entries": entries, "concepts": concept_list,
            "problems": problems, "template_hits": template_hits, "effects": effects}


def build_catalog(data: dict, excel: Path) -> dict:
    return OrderedDict([
        ("schema_version", SCHEMA_VERSION),
        ("_note", "IDEENKATALOG – nichts davon ist im Spiel aktiv. Effekte sind nur Originaltext der Excel; "
                  "es gibt keine globalen Boni, keine Zeitalter-Freischaltung und keine Forschungspunkte. "
                  "Eine Erfindung existiert erst, wenn Wesen sie real herstellen."),
        ("source", OrderedDict([("file", excel.name), ("sha256", sha256(excel))])),
        ("eras", data["eras"]),
        ("categories", data["categories"]),
        ("concepts", data["concepts"]),
        ("entries", data["entries"]),
    ])


def report(data: dict, excel: Path, wrote: bool) -> str:
    L = ["# Import Erfindungs-Excel → Ideenkatalog", "",
         f"Quelle: `design/{excel.name}` (SHA-256 `{sha256(excel)[:16]}…`, nur gelesen)",
         f"Katalog: `data/generated/ideas/inventions_catalog.json` – {'geschrieben' if wrote else 'NICHT geschrieben (Prüflauf)'}", "",
         "## Ergebnis",
         f"- Zeitalter: {len(data['eras'])} ({data['eras'][0]['name']} … {data['eras'][-1]['name']})",
         f"- Kategorien: {len(data['categories'])} ({', '.join(data['categories'])})",
         f"- Einträge: {len(data['entries'])}",
         f"- Grundbegriffe (ohne Klammer, Nummer, Vorsilbe): {len(data['concepts'])}",
         f"- Beschreibungen nach demselben Schablonensatz: {data['template_hits']} von {len(data['entries'])}",
         f"- Verschiedene Effekttexte: {len(data['effects'])} – **keiner wird übernommen** (nur Originaltext)",
         f"- Abweichungen von der Übersichtstabelle: {len(data['problems'])}", ""]
    if data["problems"]:
        L += ["## Abweichungen", ""] + [f"- {p}" for p in data["problems"][:50]] + [""]
    L += ["## Bewertung", "",
          "- Die Namen sind überwiegend generisch nummeriert. Viele Begriffe tauchen in unpassend frühen Zeitaltern auf "
          "(siehe Tabelle: erste Stufe je Begriff). Die Datei taugt als **Ideenliste für Kategorien und Begriffe**, "
          "nicht als Daten für Spielmechanik.",
          "- Globale Prozentboni und Freischaltungen widersprechen dem Grundsatz des Projekts "
          "(keine automatischen Epochen, keine globalen Freischaltungen). Sie werden nicht verwendet.", "",
          "## Grundbegriffe je Kategorie (erste Stufe)", ""]
    for cat in data["categories"]:
        items = [c for c in data["concepts"] if c["category"] == cat]
        L.append(f"**{cat}** ({len(items)}): " + ", ".join(f"{c['concept']} ({c['first_stage']})" for c in items))
        L.append("")
    first_marker: dict[str, int] = {}
    for e in data["entries"]:
        m = e["variant_marker"]
        if m:
            first_marker[m] = min(first_marker.get(m, 99), e["stage"])
    L += ["Spätere Zeitalter wiederholen dieselben Grundbegriffe mit Vorsilbe (erstes Auftreten): " +
          ", ".join(f"{m} ab Stufe {st}" for m, st in sorted(first_marker.items(), key=lambda x: x[1])) + ".", ""]
    L += ["## Häufigste Effekttexte (nicht übernommen)", ""]
    for eff, n in sorted(data["effects"].items(), key=lambda x: -x[1])[:15]:
        L.append(f"- {eff}: {n}")
    return "\n".join(L) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--excel", type=Path, default=DEFAULT_EXCEL)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args(argv)
    if not a.excel.exists():
        print(f"Fehler: {a.excel} nicht gefunden.", file=sys.stderr)
        return 2
    try:
        data = read(a.excel)
    except ValueError as e:
        print(f"Fehler: {e}", file=sys.stderr)
        return 2
    if a.write:
        a.out.parent.mkdir(parents=True, exist_ok=True)
        text = json.dumps(build_catalog(data, a.excel), ensure_ascii=False, separators=(",", ":"))
        a.out.write_text(text + "\n", encoding="utf-8")
    a.report.parent.mkdir(parents=True, exist_ok=True)
    a.report.write_text(report(data, a.excel, a.write), encoding="utf-8")
    print(f"{len(data['entries'])} Einträge, {len(data['concepts'])} Grundbegriffe, "
          f"{len(data['problems'])} Abweichungen; Katalog {'geschrieben' if a.write else 'nicht geschrieben'}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
