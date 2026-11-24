#!/usr/bin/env python3
"""Excel → JSON-Importer für Pflanzenwesen (Entwicklungswerkzeug).

Liest design/Pflanzenwesen_Voxel_Datenbasis.xlsx NUR LESEND und erzeugt
Definitionen unter data/generated/excel/. Das Spiel lädt nur diese JSON-Dateien;
zum Spielen werden weder Python noch Excel benötigt.

Aufruf (im Projektordner):
    python tools/import_definitions.py            # Prüfen + Unterschiede melden (schreibt nichts außer dem Bericht)
    python tools/import_definitions.py --write    # Prüfen + Definitionen schreiben

Optionen:
    --excel PFAD       andere Excel-Datei
    --out ORDNER       Zielordner (Standard: data/generated/excel)
    --report DATEI     Bericht (Standard: reports/import_report.md)

Exit-Code: 0 = keine Fehler, 1 = Zeilen wurden wegen Fehlern abgewiesen, 2 = Abbruch (Datei/Blatt unbrauchbar).

Grundsätze:
- Spalten werden über ihre Kopfzeile gefunden, nicht über ihre Position.
- Leere Zelle  → "fehlend" (missing_fields), Zelle "-" → "nicht anwendbar" (Wert null, not_applicable_fields).
- Zeilen mit Fehlern werden NICHT übernommen, sondern unter "rejected" mit Begründung aufgeführt.
- IDs aus der Excel werden unverändert übernommen. Blätter ohne ID-Spalte erhalten
  stabile IDs aus dem Namen; einmal vergebene IDs werden in _id_registry.json festgehalten.
- Formeln: openpyxl berechnet keine Formeln. Gelesen werden die in der Datei
  gespeicherten Ergebnisse; Formeln ohne gespeichertes Ergebnis werden als Fehler gemeldet.
- Spielstatus (implementation_status) kommt ausschließlich aus der handgeschriebenen
  data/config/implementation_status.json. Ein Excel-Eintrag aktiviert nichts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

try:
    import openpyxl
    from openpyxl.utils import get_column_letter
except ImportError:  # pragma: no cover
    print("Fehler: openpyxl fehlt. Installation: python -m pip install -r tools/requirements.txt", file=sys.stderr)
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_EXCEL = ROOT / "design" / "Pflanzenwesen_Voxel_Datenbasis.xlsx"
DEFAULT_OUT = ROOT / "data" / "generated" / "excel"
DEFAULT_REPORT = ROOT / "reports" / "import_report.md"
CONFIG_DIR = ROOT / "data" / "config"
SCHEMA_VERSION = 1
NA = object()      # Marker "-"
MISSING = object() # Marker leere Zelle

# ───────────────────────── Spaltentypen ─────────────────────────
# (json_feld, typ, pflicht, extra)
#   typ: str, int, float, bool (Ja/Nein), hex, list_str, idlist:<blatt>, ref:<blatt>,
#        comp_elem, comp_ref:<blatt>, pct_variation, enum:a|b, text_or_num
S = {}

def spec(sheet, out, kind, id_col, cols, id_pattern=None, id_from=None, status_key=None, description=""):
    S[sheet] = dict(out=out, kind=kind, id_col=id_col, cols=cols, id_pattern=id_pattern,
                    id_from=id_from, status_key=status_key or kind, description=description)

spec("01_Elemente", "elements.json", "elements", "Symbol", {
    "Symbol": ("symbol", "str", True), "Name": ("name", "str", True), "Atomnummer": ("atomic_number", "int", True),
    "Atommasse_u": ("atomic_mass_u", "float", True), "Dichte_g_cm3": ("density_g_cm3", "float", True),
    "Schmelzpunkt_C": ("melting_point_c", "float", False), "Siedepunkt_C": ("boiling_point_c", "float", False),
    "Aggregatzustand_20C": ("state_20c", "enum:Fest|Flüssig|Gas", True), "Magnetismus": ("magnetism", "str", False),
    "Elektrische_Leitfähigkeit": ("electrical_conductivity_class", "str", False),
    "Wärmeleitfähigkeit_W_mK": ("thermal_conductivity_w_mk", "float", False), "Härte_Mohs": ("hardness_mohs", "float", False),
    "Spez_Wärmekapazität_J_gK": ("specific_heat_j_gk", "float", False), "Radioaktivität": ("radioactive", "bool", False),
    "Halbwertszeit": ("half_life", "str", False), "Elektronegativität": ("electronegativity", "float", False),
    "Reaktivität": ("reactivity", "str", False), "Kategorie": ("category", "str", False),
    "Farbe_Hex": ("color", "hex", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^[A-Z][a-z]?$", description="Chemische Elemente (Referenz-/Designdaten)")

spec("02_Rohstoffe", "raw_materials.json", "raw_materials", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Kategorie": ("category", "str", True),
    "Haupt_Elemente": ("main_elements", "list_str", True), "Zusammensetzung_%": ("composition_pct", "comp_elem", True),
    "Dichte": ("density_unspecified_unit", "float", True), "Härte": ("hardness", "float", False),
    "Schmelzpunkt_C": ("melting_point_c", "float", False), "Brennbar": ("combustible", "bool", False),
    "Magnetisch": ("magnetic", "bool", False), "Wärmeleitfähigkeit": ("thermal_conductivity_unspecified_unit", "float", False),
    "Verarbeitbarkeit": ("workability", "str", False), "Reinheit_typisch": ("typical_purity", "float", False),
    "Farbe_Hex": ("color", "hex", False), "Verwendung": ("usage", "str", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^R\d{3}$", description="Rohstoffe aus Elementen (Designdaten, keine Physikdaten)")

spec("03_Materialien", "material_catalog.json", "material_catalog", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Kategorie": ("category", "str", True),
    "Rohstoff_Basis": ("base_raw_materials", "idlist:02_Rohstoffe", True), "Zusammensetzung": ("composition", "comp_ref:02_Rohstoffe", True),
    "Dichte_kg_m3": ("density_kg_m3", "float", True), "Härte": ("hardness", "float", False),
    "Schmelzpunkt_C": ("melting_point_c", "float", False), "Glanz": ("gloss", "float", False),
    "Transparenz": ("transparency", "float", False), "Verformbarkeit": ("deformability", "float", False),
    "Wärmeleitfähigkeit": ("thermal_conductivity_unspecified_unit", "float", False),
    "Elektrische_Leitfähigkeit": ("electrical_conductivity_class", "str", False), "Magnetisch": ("magnetic", "bool", False),
    "Brennbar": ("combustible", "bool", False), "Farbe_Hex": ("color", "hex", False),
    "Verwendung": ("usage", "str", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^MAT\d{3}$", description="Materialkatalog (Designdaten). Physikalische Eigenschaften im Spiel kommen aus data/materials/.")

spec("04_Komponenten", "components.json", "components", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Typ": ("type", "str", True),
    "Material_ID": ("material_ref", "ref:03_Materialien", True), "Zusammensetzung": ("composition", "comp_ref:03_Materialien", True),
    "Voxel_Breite": ("voxels_x", "int", True), "Voxel_Höhe": ("voxels_y", "int", True), "Voxel_Tiefe": ("voxels_z", "int", True),
    "Anzahl_Voxel": ("voxel_count", "int", True), "Form": ("shape", "str", False), "Anschluss_Punkte": ("attach_points", "list_str", False),
    "Gewicht_kg": ("weight_kg_excel", "float", False), "Stabilität": ("stability", "float", False), "Flexibilität": ("flexibility", "float", False),
    "Beweglichkeit": ("mobility", "float", False), "Haltbarkeit": ("durability", "float", False),
    "Kann_beschädigt_werden": ("damageable", "bool", False), "Reparierbar": ("repairable", "bool", False),
    "Animations_Gelenk": ("animation_joint", "bool", False), "Leitfähig": ("conductive", "bool", False),
    "Magnetisch": ("magnetic", "bool", False), "Farbe_Hex": ("color", "hex", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^KMP\d{3}$", description="Komponenten (Designdaten)")

spec("05_Körperteile", "body_parts.json", "body_parts", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Typ": ("type", "str", True),
    "Komponenten_IDs": ("component_refs", "idlist:04_Komponenten", True), "Anzahl_Komponenten": ("component_count", "int", True),
    "Voxel_Breite": ("voxels_x", "int", True), "Voxel_Höhe": ("voxels_y", "int", True), "Voxel_Tiefe": ("voxels_z", "int", True),
    "Anschluss_Punkte": ("attach_points", "list_str", False), "Gewicht_kg": ("weight_kg_excel", "float", False),
    "Stabilität": ("stability", "float", False), "Beweglichkeit": ("mobility", "float", False),
    "Kann_ersetzt_werden": ("replaceable", "bool", False), "Prothese_fähig": ("prosthesis_capable", "bool", False),
    "Animations_relevant": ("animation_relevant", "bool", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^KT\d{3}$", description="Körperteile (Designdaten; Typen werden auf den Körperplan abgebildet)")

spec("06_Kreaturen", "species.json", "species", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Kategorie": ("category", "str", True), "Untertyp": ("subtype", "str", False),
    "Level": ("level", "int", False), "Größe_cm": ("size_cm", "float", True), "HP": ("hp", "float", False),
    "Angriff": ("attack", "float", False), "Verteidigung": ("defense", "float", False), "Geschwindigkeit": ("speed", "float", False),
    "Reitbar": ("rideable", "bool", False), "Tragfähigkeit_kg": ("carry_capacity_kg", "float", False),
    "XP_pro_Kill": ("xp_per_kill", "float", False), "XP_pro_Pflanze": ("xp_per_plant", "float", False),
    "Nahrungstyp": ("diet", "str", False), "Körperteile_IDs": ("body_part_refs", "idlist:05_Körperteile", True),
    "Kann_Prothese": ("prosthesis_capable", "bool", False), "Vererbt": ("inheritable", "bool", False),
    "Besonderheit": ("special", "str", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^KR\d{3}$", description="Arten/Kreaturen")

spec("07_Pflanzen_Bäume", "plants.json", "plants", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Typ": ("type", "str", True), "Level_Max": ("level_max", "int", False),
    "Basis_Höhe_Voxel": ("base_height_voxels", "float", True), "Wachstumsrate": ("growth_rate", "float", False),
    "Nährwert": ("nutrition", "float", False), "Wasserbedarf": ("water_need", "float", False), "Lichtbedarf": ("light_need", "float", False),
    "Härte": ("hardness", "float", False), "Upgrade_XP": ("upgrade_xp", "float", False), "Upgrade_Effekt": ("upgrade_effect", "str", False),
    "Ertrag": ("yield", "list_str", False), "Biome": ("biome_name", "str", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^P\d{3}$", description="Pflanzen, Bäume, Pilze")

spec("08_Animationen", "animations.json", "animations", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Körperform": ("body_form", "str", True),
    "Gelenke_benötigt": ("joints_required", "list_str", False), "Dauer_Sek": ("duration_s", "float", False),
    "Beschreibung": ("description", "str", False), "Voxel_Bewegung": ("motion", "str", False), "Sonderfall": ("special_case", "str", False),
}, id_pattern=r"^A\d{3}$", description="Animationen (Beschreibungen)")

spec("09_Generator_Parameter", "generator_parameters.json", "generator_parameters", None, {
    "Parameter": ("name", "str", True), "Wert": ("value", "float", True), "Einheit": ("unit", "str", False),
    "Beschreibung": ("description", "str", False), "Verwendung": ("usage", "str", False),
}, id_from="Parameter", description="Generatorparameter")

spec("10_Biome_Gelände", "biomes.json", "biomes", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Höhe_Min": ("height_min_unspecified_unit", "float", True),
    "Höhe_Max": ("height_max_unspecified_unit", "float", True), "Feuchtigkeit": ("humidity", "float", False),
    "Temperatur": ("temperature_c_assumed", "float", False), "Wasser_Anteil": ("water_share", "float", False),
    "Baum_Dichte": ("tree_density", "float", False), "Höhlen_Wahrscheinlichkeit": ("cave_probability", "float", False),
    "Boden_Material": ("ground_material_name", "str", False), "Besonderheit": ("special", "str", False),
}, id_pattern=r"^B\d{3}$", description="Biome")

spec("11_Werkzeuge_Items", "items.json", "items", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Typ": ("type", "str", True),
    "Rohstoff_1": ("raw_material_1_name", "str", False), "Rohstoff_2": ("raw_material_2_name", "str", False),
    "Härte": ("hardness", "float", False), "Gewicht": ("weight_kg_assumed", "float", False), "Funktion": ("function", "list_str", False),
    "Herstellung": ("crafting", "str", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^I\d{3}$", description="Werkzeuge und Gegenstände")

spec("12_Verletzungen_Prothesen", "injuries.json", "injuries", "ID", {
    "ID": ("id", "str", True), "Verletzung": ("name", "str", True), "Betroffenes_Modul": ("affected_module", "str", True),
    "Schweregrad": ("severity", "int", False), "Effekt": ("effect", "str", False), "Heilung": ("healing", "str", False),
    "Prothese_möglich": ("prosthesis_possible", "bool", False), "Prothese_Typ": ("prosthesis_type_text", "str", False),
    "Bewegungseinschränkung": ("movement_restriction", "str", False),
}, id_pattern=r"^V\d{3}$", description="Verletzungen und Prothesen")

spec("13_Vererbung_Genetik", "genetics.json", "genetics", None, {
    "Merkmal": ("name", "str", True), "Vererbung_Rate": ("inheritance_rate", "float", True),
    "Mutation_Chance": ("mutation_chance", "float", True), "Min_Wert": ("min_value", "float", False),
    "Max_Wert": ("max_value", "float", False), "Beeinflusst": ("affects", "str", False), "Beschreibung": ("description", "str", False),
}, id_from="Merkmal", description="Vererbbare Merkmale")

spec("14_Nahrung_Konsum", "food.json", "food", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Typ": ("type", "str", True), "Nährwert": ("nutrition", "float", False),
    "Wassergehalt": ("water_content", "float", False), "Effekt": ("effect", "str", False), "Quelle": ("source_text", "str", False),
    "Beschreibung": ("description", "str", False),
}, id_pattern=r"^N\d{3}$", description="Nahrung")

spec("15_Verhalten_KI", "behaviors.json", "behaviors", "ID", {
    "ID": ("id", "str", True), "Verhalten": ("name", "str", True), "Priorität": ("priority", "int", False),
    "Bedingung": ("condition_text", "str", False), "Aktion": ("action_text", "str", False),
    "Energiekosten": ("energy_cost", "float", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^KI\d{3}$", description="Verhaltensregeln (für spätere Schritte)")

spec("16_Farben_Paletten", "palettes.json", "palettes", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Hex": ("color", "hex", True), "RGB": ("rgb_text", "str", False),
    "Verwendung": ("usage", "str", False), "Variation": ("variation", "pct_variation", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^F\d{3}$", description="Farben")

spec("17_Voxel_Typen", "voxel_types.json", "voxel_types", "ID", {
    "ID": ("id", "str", True), "Name": ("name", "str", True), "Solid": ("solid", "bool", True), "Transparent": ("transparent", "bool", False),
    "Kollision": ("collision", "bool", False), "Material_ID": ("material_ref", "ref:03_Materialien", False),
    "Härte": ("hardness", "float", False), "Besonderheit": ("special", "str", False),
}, id_pattern=r"^V\d{3}$", description="Voxeltypen (Designdaten; im Spiel gilt data/config/voxel_palette.json)")

spec("18_Interaktionen", "interactions.json", "interactions", "ID", {
    "ID": ("id", "str", True), "Aktion": ("name", "str", True), "Ziel": ("target_text", "str", False),
    "Voraussetzung": ("requirement_text", "str", False), "Effekt": ("effect", "str", False),
    "Animation": ("animation_ref", "ref:08_Animationen", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^INT\d{3}$", description="Interaktionen (für spätere Schritte)")

spec("19_Zucht_Fortpflanzung", "breeding.json", "breeding", "ID", {
    "ID": ("id", "str", True), "Bedingung": ("condition_text", "str", True), "Dauer_Tage": ("duration_days", "float", False),
    "Nachkommen": ("offspring", "int_nonneg", True), "Merkmale_Vererbung": ("inheritance_text", "str", False),
    "Mutation": ("mutation_text", "str", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^Z\d{3}$", description="Fortpflanzung (für spätere Schritte)")

spec("20_Umwelt_Effekte", "environment_effects.json", "environment_effects", "ID", {
    "ID": ("id", "str", True), "Effekt": ("name", "str", True), "Auslöser": ("trigger_text", "str", False),
    "Auswirkung": ("effect_text", "str", False), "Dauer": ("duration_text", "str", False),
    "Betroffene": ("affected_text", "str", False), "Beschreibung": ("description", "str", False),
}, id_pattern=r"^U\d{3}$", description="Umwelteffekte (für spätere Schritte)")

spec("21_Balancing_Statistik", "balancing.json", "balancing", None, {
    "Statistik": ("name", "str", True), "Min": ("min", "float", True), "Standard": ("default", "float", True),
    "Max": ("max", "float", True), "Beeinflusst_von": ("influenced_by", "str", False), "Einheit": ("unit", "str", False),
    "Beschreibung": ("description", "str", False),
}, id_from="Statistik", description="Balancing-Werte (für spätere Schritte)")

INFO_SHEETS = {"00_Übersicht"}

# Bekannte chemische Zusammensetzungen für Plausibilitätswarnungen (heuristisch).
KNOWN_ELEMENTS = {
    "Cellulose": {"C", "H", "O"}, "Lignin": {"C", "H", "O"}, "Holz": {"C", "H", "O"},
    "Wasser": {"H", "O"}, "Quarz": {"Si", "O"}, "Kupfer": {"Cu"},
}
# Bekannte Referenzwerte (data/materials) für Widerspruchsmeldungen
PHYSICS_REFERENCE = {"Kupfer_rein": {"density_kg_m3": 8960.0, "melting_point_c": 1084.62}}


class Issue:
    def __init__(self, severity, sheet, row, col, message):
        self.severity, self.sheet, self.row, self.col, self.message = severity, sheet, row, col, message

    def where(self):
        if self.row is None:
            return self.sheet
        cell = f"{self.col}{self.row}" if self.col else f"Zeile {self.row}"
        return f"{self.sheet}!{cell}"


def slugify(text: str) -> str:
    t = unicodedata.normalize("NFKD", str(text).replace("ß", "ss").replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
                              .replace("Ä", "Ae").replace("Ö", "Oe").replace("Ü", "Ue"))
    t = t.encode("ascii", "ignore").decode().lower()
    t = re.sub(r"[^a-z0-9]+", "_", t).strip("_")
    return t or "eintrag"


def raw_value(v):
    if v is None:
        return MISSING
    if isinstance(v, str):
        s = v.strip()
        if s == "":
            return MISSING
        if s in ("-", "–", "—"):
            return NA
        return s
    return v


def parse_cell(value, typ, warns):
    """Gibt (wert, fehlertext|None) zurück. value ist bereits raw_value()."""
    if typ == "str":
        return str(value), None
    if typ in ("int", "int_nonneg"):
        if isinstance(value, bool) or not isinstance(value, (int, float)) or float(value) != int(value):
            return None, f"Ganzzahl erwartet, gefunden '{value}'"
        if typ == "int_nonneg" and int(value) < 0:
            return None, f"Wert darf nicht negativ sein (gefunden {int(value)})"
        return int(value), None
    if typ == "float":
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None, f"Zahl erwartet, gefunden '{value}'"
        return float(value), None
    if typ == "bool":
        m = {"ja": True, "nein": False}
        if isinstance(value, str) and value.lower() in m:
            return m[value.lower()], None
        return None, f"'Ja' oder 'Nein' erwartet, gefunden '{value}'"
    if typ == "hex":
        if isinstance(value, str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
            return value.upper(), None
        return None, f"Hex-Farbe #RRGGBB erwartet, gefunden '{value}'"
    if typ == "list_str":
        return [p.strip() for p in str(value).split(",") if p.strip()], None
    if typ.startswith("enum:"):
        opts = typ[5:].split("|")
        if value in opts:
            return value, None
        return None, f"einer von {opts} erwartet, gefunden '{value}'"
    if typ.startswith("idlist:") or typ.startswith("ref:"):
        items = [p.strip() for p in re.split(r"[,+]", str(value)) if p.strip()]
        if typ.startswith("ref:"):
            if len(items) != 1:
                return None, f"genau ein Verweis erwartet, gefunden '{value}'"
            return items[0], None
        return items, None
    if typ == "comp_elem":
        pairs = re.findall(r"([A-Z][a-z]?)\s*:\s*(\d+(?:[.,]\d+)?)", str(value))
        rest = re.sub(r"([A-Z][a-z]?)\s*:\s*(\d+(?:[.,]\d+)?)", "", str(value)).strip()
        if not pairs or rest:
            return None, f"Format 'Symbol:Prozent …' erwartet, gefunden '{value}'"
        return _sum_pairs(pairs, warns), None
    if typ.startswith("comp_ref:"):
        pairs = re.findall(r"([A-Z]+\d+)\s*:\s*(\d+(?:[.,]\d+)?)", str(value))
        rest = re.sub(r"([A-Z]+\d+)\s*:\s*(\d+(?:[.,]\d+)?)", "", str(value)).strip()
        if not pairs or rest:
            return None, f"Format 'ID:Prozent …' erwartet, gefunden '{value}'"
        return _sum_pairs(pairs, warns), None
    if typ == "pct_variation":
        m = re.fullmatch(r"±?\s*(\d+(?:[.,]\d+)?)\s*%", str(value))
        if not m:
            return None, f"Format '±20%' erwartet, gefunden '{value}'"
        return float(m.group(1).replace(",", ".")) / 100.0, None
    return None, f"interner Fehler: unbekannter Typ {typ}"


def _sum_pairs(pairs, warns):
    out = {}
    for k, v in pairs:
        f = float(v.replace(",", "."))
        if k in out:
            warns.append(f"Bestandteil {k} kommt mehrfach vor; Anteile werden addiert ({out[k]:g} + {f:g}).")
        out[k] = out.get(k, 0.0) + f
    return out


def load_json(path: Path):
    if not path.exists():
        return None
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def dump_json(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=False) + "\n"


def run_import(excel_path: Path, out_dir: Path, report_path: Path, write: bool, quiet: bool = False):
    issues: list[Issue] = []
    if not excel_path.exists():
        issues.append(Issue("FATAL", str(excel_path), None, None, "Excel-Datei nicht gefunden."))
        return 2, issues, {}
    sha = hashlib.sha256(excel_path.read_bytes()).hexdigest()
    # Nur lesen: read_only=True; zwei Durchläufe (Formeln / gespeicherte Ergebnisse)
    wb_f = openpyxl.load_workbook(excel_path, read_only=True, data_only=False)
    wb_v = openpyxl.load_workbook(excel_path, read_only=True, data_only=True)
    status_cfg = load_json(CONFIG_DIR / "implementation_status.json") or {}
    mapping_cfg = load_json(CONFIG_DIR / "material_mapping.json") or {"rules": []}
    id_registry_path = out_dir / "_id_registry.json"
    id_registry = load_json(id_registry_path) or {"schema_version": 1, "sheets": {}}

    sheet_rows = {}
    formula_count = 0
    for name in wb_f.sheetnames:
        ws_f, ws_v = wb_f[name], wb_v[name]
        f_rows = list(ws_f.iter_rows(values_only=False))
        v_rows = list(ws_v.iter_rows(values_only=True))
        for r_idx, row in enumerate(f_rows, start=1):
            for c in row:
                if getattr(c, "data_type", None) == "f":
                    formula_count += 1
                    val = v_rows[r_idx - 1][c.column - 1] if c.column - 1 < len(v_rows[r_idx - 1]) else None
                    if val is None:
                        issues.append(Issue("ERROR", name, r_idx, get_column_letter(c.column),
                                            "Formel ohne gespeichertes Ergebnis. openpyxl berechnet keine Formeln – Datei in Excel öffnen, neu berechnen und speichern."))
        sheet_rows[name] = v_rows

    for name in sheet_rows:
        if name not in S and name not in INFO_SHEETS:
            issues.append(Issue("WARNING", name, None, None, "Tabellenblatt ist keinem Import zugeordnet und wird nicht übernommen."))
    for name in S:
        if name not in sheet_rows:
            issues.append(Issue("ERROR", name, None, None, "Erwartetes Tabellenblatt fehlt."))

    parsed = {}   # sheet -> list of (excel_row, entry, row_issues)
    headers_map = {}
    for name, sp in S.items():
        rows = sheet_rows.get(name)
        if not rows:
            continue
        header = [str(h).strip() if h is not None else None for h in rows[0]]
        col_index = {}
        for i, h in enumerate(header):
            if h is None:
                continue
            if h in col_index:
                issues.append(Issue("ERROR", name, 1, get_column_letter(i + 1), f"Spaltenüberschrift '{h}' doppelt."))
            col_index[h] = i
        headers_map[name] = col_index
        missing_cols = [c for c, (_, _, req) in sp["cols"].items() if c not in col_index and req]
        if missing_cols:
            issues.append(Issue("ERROR", name, 1, None, f"Pflichtspalten fehlen: {missing_cols}. Blatt wird nicht importiert."))
            continue
        for h, i in col_index.items():
            if h not in sp["cols"]:
                issues.append(Issue("WARNING", name, 1, get_column_letter(i + 1), f"Unbekannte Spalte '{h}' wird ignoriert."))
        for i, h in enumerate(header):
            if h is None and any(len(r) > i and r[i] not in (None, "") for r in rows[1:]):
                issues.append(Issue("WARNING", name, 1, get_column_letter(i + 1), "Spalte ohne Überschrift enthält Werte; ignoriert."))
        out_rows = []
        for r_idx, row in enumerate(rows[1:], start=2):
            if all(v is None or (isinstance(v, str) and v.strip() == "") for v in row):
                continue
            entry, row_issues = {}, []
            missing, na = [], []
            for col, (key, typ, req) in sp["cols"].items():
                if col not in col_index:
                    missing.append(key)
                    continue
                ci = col_index[col]
                v = raw_value(row[ci] if ci < len(row) else None)
                letter = get_column_letter(ci + 1)
                if v is MISSING:
                    if req:
                        row_issues.append(Issue("ERROR", name, r_idx, letter, f"Pflichtangabe '{col}' fehlt."))
                    missing.append(key)
                    entry[key] = None
                    continue
                if v is NA:
                    if req:
                        row_issues.append(Issue("ERROR", name, r_idx, letter, f"Pflichtangabe '{col}' ist '-' (nicht anwendbar)."))
                    na.append(key)
                    entry[key] = None
                    continue
                cell_warns = []
                val, err = parse_cell(v, typ, cell_warns)
                for w in cell_warns:
                    row_issues.append(Issue("WARNING", name, r_idx, letter, f"{col}: {w}"))
                if err:
                    row_issues.append(Issue("ERROR", name, r_idx, letter, f"{col}: {err}"))
                    entry[key] = None
                else:
                    entry[key] = val
            entry["_excel_row"] = r_idx
            if missing:
                entry["missing_fields"] = missing
            if na:
                entry["not_applicable_fields"] = na
            out_rows.append((r_idx, entry, row_issues))
        parsed[name] = out_rows

    # IDs ────────────────────────────────────────────
    for name, rows in parsed.items():
        sp = S[name]
        reg = id_registry["sheets"].setdefault(name, {})
        used = set(reg.values())
        seen = {}
        for r_idx, e, ri in rows:
            if sp["id_col"]:
                key_field = sp["cols"][sp["id_col"]][0]
                eid = e.get(key_field)
                if sp["id_col"] != "ID":
                    e["id"] = eid
                if eid is None:
                    continue
                if sp["id_pattern"] and not re.fullmatch(sp["id_pattern"], str(eid)):
                    ri.append(Issue("ERROR", name, r_idx, get_column_letter(headers_map[name][sp["id_col"]] + 1),
                                    f"ID '{eid}' entspricht nicht dem Muster {sp['id_pattern']}."))
            else:
                key_field = sp["cols"][sp["id_from"]][0]
                natural = e.get(key_field)
                if natural is None:
                    continue
                if natural in reg:
                    eid = reg[natural]
                else:
                    base = slugify(natural)
                    eid, n = base, 2
                    while eid in used:
                        eid, n = f"{base}_{n}", n + 1
                    reg[natural] = eid
                    used.add(eid)
                e["id"] = eid
                e["id_source"] = f"abgeleitet aus '{sp['id_from']}' (stabil über _id_registry.json)"
            if eid in seen:
                ri.append(Issue("ERROR", name, r_idx, None, f"Doppelte ID '{eid}' (bereits in Zeile {seen[eid]})."))
            else:
                seen[eid] = r_idx

    # IDs, die im Zielblatt existieren (Verweisprüfung). Ob ein Ziel selbst wegen eigener
    # Fehler abgewiesen wird, meldet ein zweiter Durchgang als Warnung – sonst würde ein
    # einzelner Datenfehler alle abhängigen Einträge (Komponente → Körperteil → Art) mitreißen.
    def valid_ids(sheet):
        return {e["id"] for _, e, ri in parsed.get(sheet, []) if e.get("id") is not None}

    names_by_sheet = {s: {e.get("name"): e.get("id") for _, e, _ in rows} for s, rows in parsed.items()}
    element_symbols = valid_ids("01_Elemente")

    # Verweise und Plausibilität ─────────────────────
    for name, rows in parsed.items():
        sp = S[name]
        col_index = headers_map[name]
        for r_idx, e, ri in rows:
            for col, (key, typ, req) in sp["cols"].items():
                val = e.get(key)
                if val is None or col not in col_index:
                    continue
                letter = get_column_letter(col_index[col] + 1)
                if typ.startswith("ref:") or typ.startswith("idlist:") or typ.startswith("comp_ref:"):
                    target = typ.split(":", 1)[1]
                    ids = valid_ids(target)
                    refs = [val] if isinstance(val, str) else (list(val.keys()) if isinstance(val, dict) else val)
                    bad = [x for x in refs if x not in ids]
                    if bad:
                        ri.append(Issue("ERROR", name, r_idx, letter, f"Ungültiger Verweis {bad} auf {target} (ID existiert dort nicht)."))
                    if typ.startswith("comp_ref:") and abs(sum(val.values()) - 100.0) > 0.5:
                        ri.append(Issue("ERROR", name, r_idx, letter, f"Anteile ergeben {sum(val.values()):g} % statt 100 %."))
                if typ == "comp_elem":
                    bad = [x for x in val if x not in element_symbols]
                    if bad:
                        ri.append(Issue("ERROR", name, r_idx, letter, f"Unbekannte Elemente {bad}."))
                    s = sum(val.values())
                    if abs(s - 100.0) > 0.5:
                        ri.append(Issue("WARNING", name, r_idx, letter, f"Element-Anteile ergeben {s:g} % statt 100 %."))
            # blattspezifische Prüfungen
            if name == "02_Rohstoffe" and e.get("main_elements") and e.get("composition_pct"):
                if set(e["main_elements"]) != set(e["composition_pct"]):
                    ri.append(Issue("WARNING", name, r_idx, None, f"Haupt_Elemente {e['main_elements']} passen nicht zur Zusammensetzung {list(e['composition_pct'])}."))
                exp = KNOWN_ELEMENTS.get(e.get("name"))
                if exp and set(e["composition_pct"]) != exp:
                    ri.append(Issue("WARNING", name, r_idx, None, f"Chemisch unplausibel: {e['name']} besteht real aus {sorted(exp)}, Excel nennt {sorted(e['composition_pct'])}."))
            if name == "03_Materialien":
                if e.get("composition") and e.get("base_raw_materials"):
                    missing_base = [b for b in e["base_raw_materials"] if b not in e["composition"]]
                    if missing_base:
                        ri.append(Issue("WARNING", name, r_idx, None, f"Rohstoff_Basis {missing_base} kommt in der Zusammensetzung {list(e['composition'])} nicht vor."))
                ref = PHYSICS_REFERENCE.get(e.get("name"))
                if ref:
                    for k, rv in ref.items():
                        if e.get(k) is not None and abs(e[k] - rv) / rv > 0.05:
                            ri.append(Issue("WARNING", name, r_idx, None, f"Widerspruch zu data/materials: {e['name']} {k}={e[k]:g}, Referenzwert {rv:g}. Im Spiel gilt der Referenzwert."))
                # Physikzuordnung (vorläufige Annahme aus Konfiguration)
                e["physics_material_id"] = None
                for rule in mapping_cfg.get("rules", []):
                    if any(t.lower() in str(e.get("name", "")).lower() for t in rule["match_name_contains"]):
                        e["physics_material_id"] = rule["physics_material_id"]
                        e["physics_mapping"] = "vorläufige Annahme (data/config/material_mapping.json)"
                        break
            if name == "04_Komponenten" and None not in (e.get("voxels_x"), e.get("voxels_y"), e.get("voxels_z"), e.get("voxel_count")):
                if e["voxels_x"] * e["voxels_y"] * e["voxels_z"] != e["voxel_count"]:
                    ri.append(Issue("WARNING", name, r_idx, None, "Anzahl_Voxel ≠ Breite×Höhe×Tiefe."))
            if name == "05_Körperteile" and e.get("component_refs") is not None and e.get("component_count") is not None:
                if len(e["component_refs"]) != e["component_count"]:
                    ri.append(Issue("ERROR", name, r_idx, None, f"Anzahl_Komponenten {e['component_count']} ≠ Anzahl der Verweise {len(e['component_refs'])}."))
            if name == "17_Voxel_Typen" and e.get("material_ref"):
                mat_name = names_lookup(parsed, "03_Materialien", e["material_ref"])
                if mat_name and slugify(e.get("name", "")).split("_")[0] not in slugify(mat_name):
                    ri.append(Issue("WARNING", name, r_idx, None, f"Voxeltyp '{e.get('name')}' verweist auf Material {e['material_ref']} = '{mat_name}' (Name passt nicht)."))
            if name == "11_Werkzeuge_Items":
                for k in ("raw_material_1_name", "raw_material_2_name"):
                    if e.get(k) and e[k] not in names_by_sheet.get("02_Rohstoffe", {}):
                        ri.append(Issue("WARNING", name, r_idx, None, f"Rohstoff '{e[k]}' ist ein Name, keine ID, und existiert nicht in 02_Rohstoffe."))
            if name == "12_Verletzungen_Prothesen" and e.get("prosthesis_type_text"):
                t = e["prosthesis_type_text"]
                if t not in names_by_sheet.get("11_Werkzeuge_Items", {}) and t not in valid_ids("11_Werkzeuge_Items"):
                    ri.append(Issue("WARNING", name, r_idx, None, f"Prothese_Typ '{t}' verweist auf keinen Eintrag in 11_Werkzeuge_Items (uneinheitlich: Code vs. Name)."))
            if name == "19_Zucht_Fortpflanzung" and e.get("inheritance_text") and re.search(r"\b12_Vererbung\b", e["inheritance_text"]):
                ri.append(Issue("WARNING", name, r_idx, None, "Text verweist auf '12_Vererbung'; das Blatt heißt '13_Vererbung_Genetik'."))
            if name == "13_Vererbung_Genetik" and e.get("min_value") is not None and e.get("max_value") is not None and e["min_value"] > e["max_value"]:
                ri.append(Issue("ERROR", name, r_idx, None, "Min_Wert > Max_Wert."))
            if name == "21_Balancing_Statistik" and None not in (e.get("min"), e.get("default"), e.get("max")):
                if not e["min"] <= e["default"] <= e["max"]:
                    ri.append(Issue("ERROR", name, r_idx, None, "Erwartet Min ≤ Standard ≤ Max."))
            if name == "16_Farben_Paletten" and e.get("color") and e.get("rgb_text"):
                try:
                    rgb = tuple(int(x) for x in e["rgb_text"].split(","))
                    hx = tuple(int(e["color"][i:i + 2], 16) for i in (1, 3, 5))
                    if rgb != hx:
                        ri.append(Issue("WARNING", name, r_idx, None, f"RGB {rgb} passt nicht zu {e['color']}."))
                except ValueError:
                    ri.append(Issue("WARNING", name, r_idx, None, "RGB-Text nicht lesbar."))
            if name == "06_Kreaturen" and e.get("id") == "KR001" and e.get("body_part_refs"):
                types = [types_lookup(parsed, x) for x in e["body_part_refs"]]
                if "Schwanz" in types:
                    ri.append(Issue("WARNING", name, r_idx, None, f"Mutterbaum verwendet Körperteiltypen {types} (u. a. 'Schwanz'); für einen Baum unklar. Der Lebensbaum wird unabhängig davon generiert."))
            if name == "06_Kreaturen" and e.get("id") == "KR002" and e.get("body_part_refs"):
                ri.append(Issue("INFO", name, r_idx, None, "Setzling listet nur Arm_Links (KT006) und Bein_Links (KT008); der Grundkörper wird spiegelsymmetrisch mit zwei Armen und zwei Beinen erzeugt (Annahme)."))

    # Zweiter Durchgang: Verweise auf Einträge, die selbst abgewiesen werden
    rejected_ids = {s: {e.get("id") for _, e, ri in rows if any(i.severity == "ERROR" for i in ri)} for s, rows in parsed.items()}
    for name, rows in parsed.items():
        for r_idx, e, ri in rows:
            for col, (key, typ, req) in S[name]["cols"].items():
                if not (typ.startswith("ref:") or typ.startswith("idlist:") or typ.startswith("comp_ref:")) or e.get(key) is None:
                    continue
                target = typ.split(":", 1)[1]
                val = e[key]
                refs = [val] if isinstance(val, str) else (list(val.keys()) if isinstance(val, dict) else val)
                hit = [x for x in refs if x in rejected_ids.get(target, set())]
                if hit:
                    ri.append(Issue("WARNING", name, r_idx, None, f"{col} verweist auf {hit} in {target}; diese Einträge wurden wegen eigener Fehler abgewiesen."))

    # Doppelte Namen (Warnung) und globale ID-Überschneidungen (Info)
    for name, rows in parsed.items():
        seen_names = {}
        for r_idx, e, ri in rows:
            n = e.get("name")
            if n and n in seen_names:
                ri.append(Issue("WARNING", name, r_idx, None, f"Name '{n}' kommt mehrfach vor (zuerst Zeile {seen_names[n]})."))
            elif n:
                seen_names[n] = r_idx
    owner = {}
    for name, rows in parsed.items():
        for _, e, _ in rows:
            if e.get("id") is not None and S[name]["id_col"] == "ID":
                owner.setdefault(e["id"], []).append(name)
    for i, sheets in owner.items():
        if len(sheets) > 1:
            issues.append(Issue("WARNING", ", ".join(sheets), None, None, f"ID '{i}' existiert in mehreren Blättern. Im Spiel sind IDs je Definitionsart getrennt; Verweise müssen das Zielblatt eindeutig festlegen."))

    # Ergebnis zusammensetzen ────────────────────────
    outputs = {}
    for name, rows in parsed.items():
        sp = S[name]
        status_map = status_cfg.get(sp["status_key"], {})
        entries, rejected = [], []
        for r_idx, e, ri in rows:
            issues.extend(ri)
            errs = [i for i in ri if i.severity == "ERROR"]
            if errs:
                rejected.append({"excel_row": r_idx, "id": e.get("id"), "errors": [f"{i.where()}: {i.message}" for i in errs]})
                continue
            st = status_map.get(e.get("id"), {"status": "data_only"})
            e["game_status"] = st.get("status", "data_only")
            if st.get("note"):
                e["game_status_note"] = st["note"]
            warns = [f"{i.where()}: {i.message}" for i in ri if i.severity == "WARNING"]
            if warns:
                e["import_warnings"] = warns
            ordered = {"id": e.pop("id")}
            ordered.update(e)
            entries.append(ordered)
        outputs[sp["out"]] = {
            "schema_version": SCHEMA_VERSION,
            "generated_by": "tools/import_definitions.py – NICHT VON HAND BEARBEITEN",
            "source_sheet": name,
            "kind": sp["kind"],
            "description": sp["description"],
            "status_note": "game_status stammt aus data/config/implementation_status.json; ein Excel-Eintrag aktiviert keine Spielfunktion.",
            "entries": entries,
            "rejected": rejected,
        }
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "source_file": excel_path.name,
        "source_sha256": sha,
        "imported_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "openpyxl_version": openpyxl.__version__,
        "formula_cells": formula_count,
        "files": sorted(outputs.keys()),
    }

    # Unterschiede zu vorhandenen Dateien ────────────
    diffs = {}
    for fname, data in outputs.items():
        old = load_json(out_dir / fname)
        diffs[fname] = diff_entries(old, data)
    fatal = any(i.severity == "FATAL" for i in issues)
    has_err = any(i.severity == "ERROR" for i in issues)

    if write and not fatal:
        out_dir.mkdir(parents=True, exist_ok=True)
        for fname, data in outputs.items():
            (out_dir / fname).write_text(dump_json(data), encoding="utf-8")
        (out_dir / "_manifest.json").write_text(dump_json(manifest), encoding="utf-8")
        id_registry_path.write_text(dump_json(id_registry), encoding="utf-8")

    write_report(report_path, excel_path, sha, formula_count, outputs, issues, diffs, write and not fatal)
    if not quiet:
        print(f"Excel: {excel_path}")
        for fname in sorted(outputs):
            d = diffs[fname]
            print(f"  {fname:28s} {len(outputs[fname]['entries']):4d} übernommen, {len(outputs[fname]['rejected']):3d} abgewiesen | "
                  f"neu {len(d['added'])}, entfernt {len(d['removed'])}, geändert {len(d['changed'])}")
        cnt = {s: sum(1 for i in issues if i.severity == s) for s in ("FATAL", "ERROR", "WARNING", "INFO")}
        print(f"Fehler: {cnt['ERROR']}, Warnungen: {cnt['WARNING']}, Hinweise: {cnt['INFO']}")
        print(("Geschrieben nach " + str(out_dir)) if (write and not fatal) else "Nur geprüft (zum Schreiben --write angeben).")
        print(f"Bericht: {report_path}")
    return (2 if fatal else (1 if has_err else 0)), issues, outputs


def names_lookup(parsed, sheet, eid):
    for _, e, _ in parsed.get(sheet, []):
        if e.get("id") == eid:
            return e.get("name")
    return None


def types_lookup(parsed, eid):
    for _, e, _ in parsed.get("05_Körperteile", []):
        if e.get("id") == eid:
            return e.get("type")
    return None


def diff_entries(old, new):
    res = {"added": [], "removed": [], "changed": [], "file_new": old is None}
    if old is None:
        res["added"] = [e["id"] for e in new["entries"]]
        return res
    o = {e["id"]: e for e in old.get("entries", [])}
    n = {e["id"]: e for e in new["entries"]}
    res["added"] = sorted(set(n) - set(o))
    res["removed"] = sorted(set(o) - set(n))
    for k in sorted(set(o) & set(n)):
        if o[k] != n[k]:
            fields = sorted(f for f in set(o[k]) | set(n[k]) if o[k].get(f) != n[k].get(f))
            res["changed"].append((k, fields))
    return res


def write_report(path: Path, excel_path, sha, formula_count, outputs, issues, diffs, written):
    path.parent.mkdir(parents=True, exist_ok=True)
    L = ["# Import-Bericht Excel → JSON", "",
         f"- Quelle: `{excel_path.name}` (SHA-256 `{sha[:16]}…`), nur lesend geöffnet",
         f"- Werkzeug: `tools/import_definitions.py`, openpyxl {openpyxl.__version__}",
         f"- Formelzellen: {formula_count} (openpyxl berechnet keine Formeln; gelesen werden gespeicherte Ergebnisse)",
         f"- Ergebnis: {'**geschrieben** nach `data/generated/excel/`' if written else 'nur geprüft, **nicht geschrieben**'}",
         f"- Erstellt: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}", "",
         "## Übersicht", "", "| Datei | Blatt | übernommen | abgewiesen | neu | entfernt | geändert |", "|---|---|---|---|---|---|---|"]
    for fname in sorted(outputs):
        d, o = diffs[fname], outputs[fname]
        L.append(f"| `{fname}` | {o['source_sheet']} | {len(o['entries'])} | {len(o['rejected'])} | {len(d['added'])}{' (Datei neu)' if d['file_new'] else ''} | {len(d['removed'])} | {len(d['changed'])} |")
    cnt = {s: sum(1 for i in issues if i.severity == s) for s in ("FATAL", "ERROR", "WARNING", "INFO")}
    L += ["", f"**Fehler: {cnt['ERROR'] + cnt['FATAL']} · Warnungen: {cnt['WARNING']} · Hinweise: {cnt['INFO']}**", "",
          "Fehler führen dazu, dass die betroffene Zeile **nicht** übernommen wird (sie steht unter `rejected` in der JSON-Datei). Warnungen werden am Eintrag unter `import_warnings` mitgeführt.", ""]
    changed = [(f, d) for f, d in diffs.items() if d["changed"] or d["removed"]]
    if changed:
        L += ["## Unterschiede zu vorhandenen Definitionen", ""]
        for f, d in changed:
            for k in d["removed"]:
                L.append(f"- `{f}`: **entfernt** `{k}`")
            for k, fields in d["changed"][:50]:
                L.append(f"- `{f}`: `{k}` geändert in {', '.join(fields)}")
        L.append("")
    for sev, title in (("FATAL", "Abbrüche"), ("ERROR", "Fehler (Zeile abgewiesen)"), ("WARNING", "Warnungen"), ("INFO", "Hinweise")):
        items = [i for i in issues if i.severity == sev]
        if not items:
            continue
        L += [f"## {title} ({len(items)})", ""]
        groups = {}
        for i in items:
            groups.setdefault(i.sheet, []).append(i)
        for sheet, its in groups.items():
            L.append(f"### {sheet} ({len(its)})")
            for i in its[:60]:
                L.append(f"- `{i.where()}` {i.message}")
            if len(its) > 60:
                L.append(f"- … {len(its) - 60} weitere gleichartige Meldungen (vollständig in den `rejected`/`import_warnings`-Feldern der JSON-Dateien)")
            L.append("")
    path.write_text("\n".join(L) + "\n", encoding="utf-8")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Excel-Datenbasis in JSON-Definitionen übersetzen (Entwicklungswerkzeug).")
    ap.add_argument("--excel", type=Path, default=DEFAULT_EXCEL)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    ap.add_argument("--write", action="store_true", help="Definitionen schreiben (ohne: nur prüfen und Unterschiede melden)")
    a = ap.parse_args(argv)
    code, _, _ = run_import(a.excel, a.out, a.report, a.write)
    return code


if __name__ == "__main__":
    sys.exit(main())
