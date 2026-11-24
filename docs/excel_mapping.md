# Excel-Zuordnung: `design/Pflanzenwesen_Voxel_Datenbasis.xlsx`

Diese Datei beschreibt, was in deiner Excel steht, wohin es im Spiel geht und wo Daten fehlen oder sich widersprechen.
Die Original-Excel wird **nur gelesen** (Prüfsumme im Importbericht). Erzeugte Dateien: `data/generated/excel/`. Vollständige Meldungen mit Blatt, Zeile und Zelle: `reports/import_report.md`.

## Import ausführen

```
python -m pip install -r tools/requirements.txt     # einmalig (nur openpyxl)
python tools/import_definitions.py                  # prüfen + Unterschiede melden, schreibt nichts
python tools/import_definitions.py --write          # prüfen + schreiben
```
Unter Windows kann statt `python` auch `py` stehen. Das Spiel selbst braucht weder Python noch Excel.

## Allgemeine Befunde

| Befund | Ergebnis |
|---|---|
| Tabellenblätter | 22 (00 Übersicht + 21 Datenblätter) |
| Formeln | **keine** (alle Werte sind feste Werte) |
| Leere Zellen in Datenspalten | nur 4 (Blatt 09, Spalte Einheit) |
| „-“ als Wert | 01 (58×), 12 (3×), 13 (4×), 17 (1×) → als „nicht anwendbar“ übernommen |
| Spalten ohne Überschrift | in 00, 02, 03, 04; alle leer → ignoriert |
| Ergebnis des Imports | **4 Fehler** (Zeilen abgewiesen), **321 Warnungen**, 1 Hinweis |

## Blätter, Spalten und Zuordnung

Spaltennamen werden über die Kopfzeile gefunden, nicht über die Position. Einheiten aus der Kopfzeile wandern in die JSON-Feldnamen (z. B. `Dichte_kg_m3` → `density_kg_m3`). Spalten ohne Einheitsangabe tragen im Feldnamen `_unspecified_unit`.

| Blatt | Zeilen | Zieldatei | ID | Verwendung im Spiel (Stand 0.2) |
|---|---|---|---|---|
| 01_Elemente | 55 | `elements.json` | Symbol | nur Daten (für spätere Chemie) |
| 02_Rohstoffe | 300 | `raw_materials.json` | R### | nur Daten |
| 03_Materialien | 300 | `material_catalog.json` | MAT### | nur Daten; vorläufige Zuordnung zu Physikmaterialien (s. u.) |
| 04_Komponenten | 300 | `components.json` | KMP### | nur Daten |
| 05_Körperteile | 80 | `body_parts.json` | KT### | Typen KT001/003/006/008/012/014 → Körperplan-Teile (teilweise) |
| 06_Kreaturen | 108 | `species.json` | KR### | **KR001** Lebensbaum (Höhe 800 cm), **KR002** Pflanzenwesen (85 cm) |
| 07_Pflanzen_Bäume | 20 | `plants.json` | P### | P007, P009, P010, P011, P013 → prozedurale Modelle (Höhe aus Basis_Höhe_Voxel) |
| 08_Animationen | 5 | `animations.json` | A### | A001/A002 Vorschau, A003/A004 als „Greifen“/„Zum Mund“ (teilweise), A005 nein |
| 09_Generator_Parameter | 8 | `generator_parameters.json` | aus Name | Gelände_Seed, Wasser_Höhe, Blatt_Variation, Kreatur_Max_Größe verwendet |
| 10_Biome_Gelände | 5 | `biomes.json` | B### | Orientierung für Weltaufbau (teilweise) |
| 11_Werkzeuge_Items | 5 | `items.json` | I### | I002 Kupferprothese (als Körperteil, Masse berechnet) |
| 12_Verletzungen_Prothesen | 5 | `injuries.json` | V### | V001/V003 als Vorschau-Eingriffe |
| 13_Vererbung_Genetik | 6 | `genetics.json` | aus Merkmal | Größenbereich, Blattzahl 0–8, Hautfarbe, Blattform |
| 14_Nahrung_Konsum | 5 | `food.json` | N### | spätere Schritte |
| 15_Verhalten_KI | 5 | `behaviors.json` | KI### | spätere Schritte |
| 16_Farben_Paletten | 6 | `palettes.json` | F### | Körper-, Blatt-, Pilz- und Rindenfarben |
| 17_Voxel_Typen | 7 | `voxel_types.json` | V### | nur Designdaten; im Spiel gilt `data/config/voxel_palette.json` |
| 18_Interaktionen | 5 | `interactions.json` | INT### | spätere Schritte |
| 19_Zucht_Fortpflanzung | 3 | `breeding.json` | Z### | spätere Schritte |
| 20_Umwelt_Effekte | 5 | `environment_effects.json` | U### | spätere Schritte |
| 21_Balancing_Statistik | 7 | `balancing.json` | aus Statistik | spätere Schritte |

Jeder übernommene Eintrag trägt `game_status`. Der Wert stammt **nur** aus der handgeschriebenen `data/config/implementation_status.json`:
`preview_only`, `world_object_preview`, `partial`, `implemented`, `not_implemented`, sonst `data_only`. Ein Excel-Eintrag allein schaltet nichts frei.

### Stabile IDs
- Blätter mit ID-Spalte: Excel-ID unverändert.
- Blätter ohne ID-Spalte (09, 13, 21): ID aus dem Namen, z. B. „Kopfblätter_Anzahl“ → `kopfblaetter_anzahl`. Einmal vergebene IDs stehen in `data/generated/excel/_id_registry.json` und bleiben auch nach Umsortieren gleich (getestet).
- IDs gelten je Definitionsart. `V001` gibt es in 12 und 17. Im Spiel ist das eindeutig, weil die Art immer mitgeführt wird.

## Fehler (Zeilen abgewiesen)

| Zelle | Problem |
|---|---|
| 17_Voxel_Typen!F3 | Erde → `MAT_Erde` existiert nicht in 03_Materialien |
| 17_Voxel_Typen!F4 | Gras → `MAT_Gras` existiert nicht |
| 17_Voxel_Typen!F6 | Holz → `MAT_Holz` existiert nicht |
| 19_Zucht_Fortpflanzung!D3 | Nachkommen = −1 (negativ) |

Das Spiel nutzt für Erde, Gras und Holz die eigene Voxelpalette mit Physikmaterialien. Die abgewiesenen Excel-Zeilen blockieren deshalb nichts.

## Warnungen (übernommen, aber markiert)

| Art | Anzahl | Beispiel |
|---|---|---|
| Element-Anteile ergeben nicht 100 % | 259 | 02 Rohstoffe, meist 97–99 %, einzelne 72 % oder 116 % |
| Haupt_Elemente ≠ Elemente der Zusammensetzung | 30 | 02 Metalle/Erze (z. B. Haupt_Elemente nur „Cu“, Zusammensetzung mit weiteren Elementen) |
| Doppelter Bestandteil in Zusammensetzung | 8 | 02 (6×, z. B. Fe doppelt); 03!E11 `R001:70 R001:30` (MAT010) und 03!E41 (MAT040) |
| Chemisch unplausibel | 5 | Cellulose mit P, Lignin ohne C, Holz aus N:61 C:38, außerdem Quarz und Wasser |
| Widerspruch zu Physikdaten | 2 | 03 Kupfer_rein: Dichte 3093 kg/m³ (real 8960), Schmelzpunkt 1501 °C (real 1084,62) |
| Voxeltyp verweist auf Material mit anderem Namen | 2 | 17 Wasser → MAT004 „Holz_gehärtet“, Kupfer → MAT002 „Cellulose_rein“ |
| Rohstoff als Name statt ID | 5 | 11 Werkzeuge: „Stein“, „Ton“, „Kork“ usw. existieren nicht in 02 |
| Prothese_Typ uneinheitlich | 2 | 12: `M_PROTHESE_KUPFER` (Code) vs. „Holzprothese“ (Name), beide ohne Gegenstück in 11 |
| Falscher Blattname im Text | 1 | 19!E2 „Aus 12_Vererbung“ → gemeint ist 13_Vererbung_Genetik |
| Doppelter Name | 1 | 08: „Stehen“ (A001 Zweibeiner, A005 Vierbeiner) |
| ID in mehreren Blättern | 5 | V001–V005 in 12 und 17 |

Summe: 316 Warnungen an Einträgen und 5 blattübergreifende Warnungen, zusammen 321.
| Mutterbaum mit Körperteil „Schwanz“ | 1 | 06 KR001 → KT001 + KT016 (Schwanz_16) |

## Unklarheiten und vorläufige Annahmen

Keine dieser Unklarheiten hat die Umsetzung blockiert. Ich habe deshalb nicht nachgefragt, sondern die Annahmen gekennzeichnet:

1. **Voxelgröße.** 09 nennt 0,1 m für die „Gesamte Welt“. Eine 64×32×64-Karte wäre damit nur 6,4 m breit, und ein 85-cm-Wesen hätte keine erkennbaren Gesichtszüge. **Annahme:** Terrain 0,5 m, Lebensbaum 0,2 m, Pflanzen 0,05 m, Wesen 0,02 m (`data/config/world.json`). Die Pflanzenhöhe rechnet weiter mit 0,1 m × Basis_Höhe_Voxel.
2. **Voxelmaße der Körperteile (05).** Sie passen nicht zur Wesengröße: KT001 3×20×4 Voxel ergäben bei 0,1 m einen 2 m hohen Rumpf für ein 85-cm-Wesen. **Annahme:** Proportionen aus `data/config/creature_defaults.json` (dokumentierte Standardwerte).
3. **Gewicht_kg (04, 05, 11).** Das Spiel berechnet Masse immer aus Physikmaterial und Modellvolumen. Die Excel-Gewichte sind nur Vergleichswerte. Beispiel: Kupferprothese berechnet 2,8 kg, Excel nennt 3,5 kg.
4. **KR002 listet nur linken Arm/linkes Bein.** **Annahme:** spiegelsymmetrischer Zweibeiner.
5. **Einheiten ohne Angabe.** 02 „Dichte“ (0,001–18,22, vermutlich g/cm³), 02/03 „Wärmeleitfähigkeit“ (0,05–396, vermutlich W/(m·K)), 10 „Höhe_Min/Max“ (0–80, Einheit unklar; Berg 30–80 überschreitet die Testkarte von 32 Zellen), 10 „Temperatur“ (vermutlich °C).
6. **Physikalische Werte der Excel-Materialien.** Sie widersprechen teils realen Werten (Kupfer, s. o.), und es fehlt die spezifische Wärmekapazität. Deshalb bleibt `data/materials/` (mit Quellen) die einzige Quelle für Physik. `material_mapping.json` ordnet Excel-Materialien nur vorläufig über Namensbestandteile zu (z. B. „Kupfer“ → `copper`).
7. **Pilzgewebe.** Kein eigenes Physikmaterial. **Annahme:** wie Pflanzengewebe.
8. **„Gras“ und „Wurzelbeet“.** Darstellungsvarianten von Erde (gleiches Material).
9. **Wasser (17 V004).** Im Spiel kein Voxel, sondern ein mengenbasiertes Höhenmodell.

## Für spätere Schritte relevant (importiert, nicht verwendet)
Elemente, Rohstoffe, Materialkatalog, Komponenten, die übrigen 106 Arten (Tiere, Pilzwesen), Nahrung, Verhalten/KI, Interaktionen, Zucht, Umwelteffekte, Balancing, Werkzeuge außer I002, Verletzungen außer V001/V003, Arm_Anzahl ≠ 2, Animation A005 (Vierbeiner), 15 Pflanzenarten (u. a. Bäume P001–P006, Schilf, Algen, Leuchtmoos).

## Empfohlene Korrekturen in der Excel (deine Entscheidung)
- 17: Material_ID für Erde/Gras/Holz auf existierende MAT-IDs setzen; Wasser/Kupfer auf passende Materialien (z. B. MAT111 Kupfer_rein).
- 19!D3: Nachkommen −1 klären (z. B. „unbegrenzt“ als eigenen Text).
- 03 MAT010/MAT040: doppelten Bestandteil `R001` korrigieren.
- 03 Kupfer_rein: Dichte 8960 kg/m³, Schmelzpunkt 1084,6 °C.
- 02: Zusammensetzungen auf 100 % bringen; Cellulose/Lignin/Holz chemisch korrigieren.
- 12: V-IDs umbenennen (z. B. `VL001`), Prothese_Typ als ID aus 11 angeben.
- 11: Rohstoffe als R-IDs angeben.
- Einheiten in die Spaltenköpfe schreiben (02 Dichte, 02/03 Wärmeleitfähigkeit, 10 Höhe).
