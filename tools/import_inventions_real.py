#!/usr/bin/env python3
"""Erfindungs-Excel „echte Namen“ → Erfindungskatalog (Prompt 6B, Entwicklungswerkzeug).

Liest design/Erfindungen_Echt_nach_Kategorien.xlsx NUR LESEND und erzeugt
data/generated/ideas/inventions_real_catalog.json sowie reports/inventions_real_import_report.md.
Der ältere Ideenkatalog (tools/import_inventions.py, Erfindungen_nach_Kategorien_und_Stufen.xlsx)
bleibt unverändert als eigene Datei erhalten.

Regeln (Prompt 6B, Abschnitt 2):
- Übernommen werden Name, Kategorie, Quellenzeile(n), Beschreibung und die Stufe (Zeitalter) – die Stufe
  NUR als Metadatum. Sie erzeugt keine Entwicklungsreihenfolge, keine Freischaltung, keine Voraussetzung.
- Effekte („+15 % Militärstärke“ …) werden nur als Originaltext je Quellenzeile aufbewahrt und nie angewendet.
- Zusammengefasst werden nur GLEICHWERTIGE Einträge: gleicher Name UND gleiche Kategorie (dieselbe Erfindung,
  in mehreren Zeitaltern wiederholt). Jede Quellenzeile bleibt mit Blatt, Zeile, Stufe und Effekttext erhalten.
  Gleiche Namen in verschiedenen Kategorien werden NICHT zusammengefasst (gleicher Name ≠ gleiches Verfahren),
  sondern nur gegenseitig verwiesen.
- Erzeugte Fantasienamen („Quanten- Feuer 16“) und redaktionelle Varianten („… (verbessert)“) werden
  gekennzeichnet (name_kind) und ihrem Grundbegriff zugeordnet; sie bleiben eigene Katalogeinträge.
- Jeder Eintrag hat game_status „catalog“. Nur Einträge, die in data/config/inventions_activated.json
  ausdrücklich mit einer umgesetzten Definition verknüpft sind, werden im Bericht als „verwandt mit
  aktivierter Definition“ ausgewiesen. Der Katalog ist KEIN Startwissen der Wesen.

Aufruf (im Projektordner):
    python tools/import_inventions_real.py            # prüfen + Bericht, Katalog NICHT schreiben
    python tools/import_inventions_real.py --write    # zusätzlich Katalog schreiben
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
DEFAULT_EXCEL = ROOT / "design" / "Erfindungen_Echt_nach_Kategorien.xlsx"
DEFAULT_OUT = ROOT / "data" / "generated" / "ideas" / "inventions_real_catalog.json"
DEFAULT_REPORT = ROOT / "reports" / "inventions_real_import_report.md"
ACTIVATED = ROOT / "data" / "config" / "inventions_activated.json"
SCHEMA_VERSION = 1
OVERVIEW = "Übersicht"
HEADERS = {"Stufe": "stage", "Stufe-Name": "stage_name", "Erfindung": "name", "Effekt": "effect", "Beschreibung": "description"}
TEMPLATE_RE = re.compile(r"^(?P<n>.+) – konkrete Erfindung in der Kategorie (?P<c>.+) \((?P<s>.+)\)\.$")
GEN_PREFIXES = ["Fusions-", "Präzisions-", "fortgeschritten", "Nano-", "KI-gestützt", "verbessert", "Quanten-", "Hochleistungs-"]
GEN_RE = re.compile(r"^(?P<p>" + "|".join(re.escape(p) for p in GEN_PREFIXES) + r")\s+(?P<b>.+?)\s+(?P<n>\d+)$")
VARIANT_RE = re.compile(r"^(?P<b>.+?)\s*\(verbessert\)$")
# Historische Einordnung (redaktionell, nur für den Bericht): früheste plausible Stufe einzelner Begriffe.
# Abweichung = Hinweis auf eine Zeitalter-Angabe, die nicht als Reihenfolge taugt. Keine Spielwirkung.
HISTORIC_MIN_STAGE = {"Dampfmaschine": 16, "Hochofen": 9, "Buchdruck": 11, "Rad": 6, "Kalender": 6, "Bronzelegierung": 7,
                      "Eisenverhüttung": 8, "Schrift": 6, "Münzen": 8, "Elektrizität": 17, "Eisenbahn": 17, "Telegraf": 17}
# Für das Werkzeug-/Materialthema wichtige Begriffe, die im Katalog FEHLEN (Bericht).
EXPECTED_MISSING = ["Hammer", "Töpferei", "Keramik", "Blasebalg", "Seil", "Schnur", "Guss", "Lager", "Korb", "Tiegel", "Gussform"]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def slug(s: str) -> str:
    t = s.lower()
    for a, b in (("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")):
        t = t.replace(a, b)
    return re.sub(r"[^a-z0-9]+", "_", t).strip("_")


def classify(name: str) -> tuple[str, str, str]:
    """(Art, Grundbegriff, Kennzeichen): real | variant (… (verbessert)) | generated (Vorsilbe + Grundbegriff + Nummer)."""
    m = GEN_RE.match(name)
    if m:
        return "generated", m.group("b").strip(), m.group("p").strip()
    m = VARIANT_RE.match(name)
    if m:
        return "variant", m.group("b").strip(), "verbessert"
    return "real", name, ""


def read(excel: Path) -> dict:
    wb = openpyxl.load_workbook(excel, data_only=True, read_only=True)
    if OVERVIEW not in wb.sheetnames:
        raise ValueError(f"Blatt '{OVERVIEW}' fehlt.")
    rows = list(wb[OVERVIEW].iter_rows(values_only=True))
    head_i = next((i for i, r in enumerate(rows) if r and r[0] == "Stufe"), None)
    if head_i is None:
        raise ValueError("Übersicht: Kopfzeile 'Stufe' nicht gefunden.")
    head = list(rows[head_i])
    cat_cols = [(i, c) for i, c in enumerate(head) if i >= 2 and c not in (None, "Gesamt")]
    eras, expected = [], {}
    for r in rows[head_i + 1:]:
        if r[0] is None or not isinstance(r[0], (int, float)):
            continue
        eras.append({"stage": int(r[0]), "name": str(r[1])})
        for i, c in cat_cols:
            expected[(c, int(r[0]))] = int(r[i] or 0)
    era_name = {e["stage"]: e["name"] for e in eras}
    categories = [c for _, c in cat_cols]
    problems: list[str] = []
    rows_out = []
    counts: dict = {}
    effects: dict[str, int] = {}
    template_hits = 0
    template_mismatch = []
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
        for rn, r in enumerate(it, start=2):
            if r[col["name"]] is None:
                continue
            stage = int(r[col["stage"]])
            name = str(r[col["name"]]).strip()
            if era_name.get(stage) != str(r[col["stage_name"]]):
                problems.append(f"{cat} Zeile {rn}: Stufenname '{r[col['stage_name']]}' passt nicht zu Stufe {stage}.")
            desc = str(r[col["description"]] or "")
            m = TEMPLATE_RE.match(desc)
            if m:
                template_hits += 1
                if m.group("n") != name or m.group("c") != cat or m.group("s") != era_name.get(stage):
                    template_mismatch.append(f"{cat} Zeile {rn}")
            eff = str(r[col["effect"]] or "")
            effects[eff] = effects.get(eff, 0) + 1
            counts[(cat, stage)] = counts.get((cat, stage), 0) + 1
            rows_out.append({"category": cat, "stage": stage, "stage_name": era_name.get(stage, ""), "name": name,
                             "effect": eff, "description": desc, "row": rn})
    for key, want in expected.items():
        got = counts.get(key, 0)
        if got != want:
            problems.append(f"Übersicht {key[0]}/Stufe {key[1]}: {want} erwartet, {got} gefunden.")
    # Gleichwertige Einträge zusammenfassen: gleicher Name UND gleiche Kategorie
    merged: "OrderedDict[tuple, dict]" = OrderedDict()
    for r in rows_out:
        k = (r["category"], r["name"])
        e = merged.get(k)
        if e is None:
            kind, concept, marker = classify(r["name"])
            e = OrderedDict([
                ("id", f"INVR_{slug(r['category'])}_{slug(r['name'])}"),
                ("name", r["name"]), ("category", r["category"]),
                ("name_kind", kind), ("concept", concept), ("variant_marker", marker),
                ("description", r["description"]),
                ("description_is_template", bool(TEMPLATE_RE.match(r["description"]))),
                ("stages", []), ("first_stage", r["stage"]), ("first_stage_name", r["stage_name"]),
                ("sources", []),
                ("same_name_other_categories", []),
                ("game_status", "catalog"),
            ])
            merged[k] = e
        e["stages"].append(r["stage"])
        if r["stage"] < e["first_stage"]:
            e["first_stage"] = r["stage"]
            e["first_stage_name"] = r["stage_name"]
        e["sources"].append(OrderedDict([("sheet", r["category"]), ("row", r["row"]), ("stage", r["stage"]),
                                         ("stage_name", r["stage_name"]), ("excel_effect_text", r["effect"])]))
    by_name: dict[str, list] = {}
    for (cat, name), e in merged.items():
        by_name.setdefault(name, []).append(cat)
    for (cat, name), e in merged.items():
        e["stages"] = sorted(set(e["stages"]))
        e["same_name_other_categories"] = sorted(c for c in by_name[name] if c != cat)
        e["merged_rows"] = len(e["sources"])
        h = HISTORIC_MIN_STAGE.get(e["concept"])
        if h is not None and e["first_stage"] < h:
            e["era_note"] = f"Erste Stufe {e['first_stage']} ({e['first_stage_name']}) liegt vor der frühestens plausiblen Stufe {h} – Stufe ist nur Metadatum."
    inventions = list(merged.values())
    return {"eras": eras, "categories": categories, "rows": rows_out, "inventions": inventions, "problems": problems,
            "template_hits": template_hits, "template_mismatch": template_mismatch, "effects": effects, "by_name": by_name}


def activated_refs() -> dict:
    """Katalog-IDs, die eine aktivierte Definition ausdrücklich nennt (nur für den Bericht)."""
    if not ACTIVATED.exists():
        return {}
    d = json.loads(ACTIVATED.read_text(encoding="utf-8"))
    out: dict[str, list] = {}
    for inv in d.get("inventions", []):
        for ref in inv.get("catalog_refs", []):
            out.setdefault(ref["id"], []).append(f"{inv['id']} ({ref.get('relation', '')})")
    return out


def build_catalog(data: dict, excel: Path) -> dict:
    return OrderedDict([
        ("schema_version", SCHEMA_VERSION),
        ("_note", "ERFINDUNGSKATALOG (echte Namen) – Ideen, kein Spielinhalt. Stufe = Metadatum ohne Reihenfolge; "
                  "Effekte nur Originaltext, nie angewendet; nur gleicher Name + gleiche Kategorie zusammengefasst "
                  "(Herkunft je Quellenzeile erhalten). Kein Startwissen der Wesen. Umgesetzte Verfahren stehen in "
                  "data/config/inventions_activated.json."),
        ("source", OrderedDict([("file", excel.name), ("sha256", sha256(excel))])),
        ("rules", OrderedDict([("merge", "gleicher Name UND gleiche Kategorie"), ("stage", "nur Metadatum"),
                               ("effects", "nur Originaltext je Quellenzeile, nicht angewendet"), ("start_knowledge", False)])),
        ("eras", data["eras"]),
        ("categories", data["categories"]),
        ("inventions", data["inventions"]),
    ])


def report(data: dict, excel: Path, wrote: bool) -> str:
    inv = data["inventions"]
    kinds = {k: sum(1 for e in inv if e["name_kind"] == k) for k in ("real", "variant", "generated")}
    cross = sorted((n, cats) for n, cats in data["by_name"].items() if len(cats) > 1)
    act = activated_refs()
    names_all = {e["name"] for e in inv} | {e["concept"] for e in inv}
    missing = [m for m in EXPECTED_MISSING if not any(m.lower() in n.lower() for n in names_all)]
    era_notes = [e for e in inv if e.get("era_note") and e["name_kind"] == "real"]
    L = ["# Import Erfindungs-Excel „echte Namen“ → Erfindungskatalog (Prompt 6B)", "",
         f"Quelle: `design/{excel.name}` (SHA-256 `{sha256(excel)[:16]}…`, nur gelesen, unverändert)",
         f"Katalog: `data/generated/ideas/inventions_real_catalog.json` – {'geschrieben' if wrote else 'NICHT geschrieben (Prüflauf)'}",
         "Älterer Ideenkatalog (`inventions_catalog.json`, andere Excel) bleibt unverändert erhalten.", "",
         "## Ergebnis",
         f"- Zeitalter (Stufen): {len(data['eras'])} ({data['eras'][0]['name']} … {data['eras'][-1]['name']}) – **nur Metadatum, keine Reihenfolge**",
         f"- Kategorien: {len(data['categories'])} ({', '.join(data['categories'])})",
         f"- Quellenzeilen: {len(data['rows'])}",
         f"- Katalogeinträge nach Zusammenfassung (gleicher Name + gleiche Kategorie): {len(inv)}",
         f"  - echte Namen: {kinds['real']} · redaktionelle Varianten „(verbessert)“: {kinds['variant']} · erzeugte Fantasienamen (Vorsilbe + Nummer): {kinds['generated']}",
         f"- Gleiche Namen in mehreren Kategorien (NICHT zusammengefasst, nur verwiesen): {len(cross)}",
         f"- Beschreibungen nach demselben Schablonensatz „<Name> – konkrete Erfindung in der Kategorie …“: {data['template_hits']} von {len(data['rows'])}"
         + (f" ({len(data['template_mismatch'])} mit abweichendem Inhalt)" if data["template_mismatch"] else ""),
         f"- Verschiedene Effekttexte: {len(data['effects'])} – **keiner wird angewendet** (nur Originaltext je Quellenzeile)",
         f"- Abweichungen von der Übersichtstabelle: {len(data['problems'])}", ""]
    if data["problems"]:
        L += ["## Abweichungen", ""] + [f"- {p}" for p in data["problems"][:50]] + [""]
    L += ["## Zusammenfassen (Herkunft bleibt erhalten)", "",
          "Dieselbe Erfindung steht oft in vielen Zeitaltern hintereinander (z. B. „Feuer“ in Wissenschaft). Diese Zeilen "
          "werden zu EINEM Eintrag mit allen Quellenzeilen (Blatt, Zeile, Stufe, Effekttext) zusammengefasst. "
          "Gleiche Namen in verschiedenen Kategorien bleiben getrennt – ein gleicher Name beweist kein gleiches Verfahren.", ""]
    top = sorted(inv, key=lambda e: -e["merged_rows"])[:12]
    L += ["| Eintrag | Kategorie | Quellenzeilen | Stufen |", "|---|---|---|---|"]
    for e in top:
        L.append(f"| {e['name']} | {e['category']} | {e['merged_rows']} | {e['stages'][0]}–{e['stages'][-1]} |")
    L += ["", "Beispiele gleicher Namen in mehreren Kategorien: " + "; ".join(f"{n} ({', '.join(c)})" for n, c in cross[:12]) + ".", ""]
    L += ["## Zeitalter-Angaben (Stufe nur Metadatum)", "",
          "Einige Stufen liegen historisch deutlich zu früh. Das bestätigt, dass die Stufe keine Entwicklungsreihenfolge "
          "vorgeben darf (Leitlinie: Die Wesen entwickeln sich selbst, die Excel ist eine Leitlinie).", ""]
    for e in era_notes[:15]:
        L.append(f"- {e['name']} ({e['category']}): {e['era_note']}")
    L += ["", "## Für die Werkzeug- und Materialkette fehlende Begriffe", "",
          ("Im Katalog fehlen: " + ", ".join(missing) + ". Die in Prompt 6/6B umgesetzten Verfahren (Hammer aus Stiel, "
           "Steinkopf und Fasern; Umwickeln; Lager; Gießen im Tiegel) sind daher eigene Definitionen ohne Katalogeintrag "
           "bzw. nur „verwandt“ mit Katalogeinträgen.") if missing else "Keine.", ""]
    L += ["## Verknüpfung mit aktivierten Definitionen (`data/config/inventions_activated.json`)", ""]
    if act:
        ids = {e["id"]: e for e in inv}
        for cid, by in sorted(act.items()):
            e = ids.get(cid)
            L.append(f"- `{cid}` {e['name'] + ' (' + e['category'] + ')' if e else '**NICHT IM KATALOG**'} ← {', '.join(by)}")
    else:
        L.append("- (keine)")
    L += ["", "Alle übrigen Einträge bleiben **Katalogeinträge** (game_status „catalog“): keine Freischaltung, kein "
          "Startwissen, keine Effekte. Eine Erfindung existiert im Spiel erst, wenn Wesen sie mit realen Materialien, "
          "Werkzeugen und Arbeitsschritten herstellen.", "",
          "## Häufigste Effekttexte (nicht angewendet)", ""]
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
        a.out.write_text(json.dumps(build_catalog(data, a.excel), ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    a.report.parent.mkdir(parents=True, exist_ok=True)
    a.report.write_text(report(data, a.excel, a.write), encoding="utf-8")
    kinds = {k: sum(1 for e in data["inventions"] if e["name_kind"] == k) for k in ("real", "variant", "generated")}
    print(f"{len(data['rows'])} Quellenzeilen → {len(data['inventions'])} Katalogeinträge (echt {kinds['real']}, Variante {kinds['variant']}, "
          f"erzeugt {kinds['generated']}), {len(data['problems'])} Abweichungen; Katalog {'geschrieben' if a.write else 'nicht geschrieben'}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
