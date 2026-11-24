# Import-Bericht Excel → JSON

- Quelle: `Pflanzenwesen_Voxel_Datenbasis.xlsx` (SHA-256 `a5557d3a1f206105…`), nur lesend geöffnet
- Werkzeug: `tools/import_definitions.py`, openpyxl 3.1.5
- Formelzellen: 0 (openpyxl berechnet keine Formeln; gelesen werden gespeicherte Ergebnisse)
- Ergebnis: **geschrieben** nach `data/generated/excel/`
- Erstellt: 2026-11-19 14:55 UTC

## Übersicht

| Datei | Blatt | übernommen | abgewiesen | neu | entfernt | geändert |
|---|---|---|---|---|---|---|
| `animations.json` | 08_Animationen | 5 | 0 | 0 | 0 | 0 |
| `balancing.json` | 21_Balancing_Statistik | 7 | 0 | 0 | 0 | 0 |
| `behaviors.json` | 15_Verhalten_KI | 5 | 0 | 0 | 0 | 2 |
| `biomes.json` | 10_Biome_Gelände | 5 | 0 | 0 | 0 | 0 |
| `body_parts.json` | 05_Körperteile | 80 | 0 | 0 | 0 | 0 |
| `breeding.json` | 19_Zucht_Fortpflanzung | 2 | 1 | 0 | 0 | 0 |
| `components.json` | 04_Komponenten | 300 | 0 | 0 | 0 | 0 |
| `elements.json` | 01_Elemente | 55 | 0 | 0 | 0 | 0 |
| `environment_effects.json` | 20_Umwelt_Effekte | 5 | 0 | 0 | 0 | 0 |
| `food.json` | 14_Nahrung_Konsum | 5 | 0 | 0 | 0 | 0 |
| `generator_parameters.json` | 09_Generator_Parameter | 8 | 0 | 0 | 0 | 0 |
| `genetics.json` | 13_Vererbung_Genetik | 6 | 0 | 0 | 0 | 0 |
| `injuries.json` | 12_Verletzungen_Prothesen | 5 | 0 | 0 | 0 | 0 |
| `interactions.json` | 18_Interaktionen | 5 | 0 | 0 | 0 | 0 |
| `items.json` | 11_Werkzeuge_Items | 5 | 0 | 0 | 0 | 0 |
| `material_catalog.json` | 03_Materialien | 300 | 0 | 0 | 0 | 0 |
| `palettes.json` | 16_Farben_Paletten | 6 | 0 | 0 | 0 | 0 |
| `plants.json` | 07_Pflanzen_Bäume | 20 | 0 | 0 | 0 | 0 |
| `raw_materials.json` | 02_Rohstoffe | 300 | 0 | 0 | 0 | 0 |
| `species.json` | 06_Kreaturen | 108 | 0 | 0 | 0 | 1 |
| `voxel_types.json` | 17_Voxel_Typen | 4 | 3 | 0 | 0 | 0 |

**Fehler: 4 · Warnungen: 321 · Hinweise: 1**

Fehler führen dazu, dass die betroffene Zeile **nicht** übernommen wird (sie steht unter `rejected` in der JSON-Datei). Warnungen werden am Eintrag unter `import_warnings` mitgeführt.

## Unterschiede zu vorhandenen Definitionen

- `species.json`: `KR002` geändert in game_status_note
- `behaviors.json`: `KI004` geändert in game_status_note
- `behaviors.json`: `KI005` geändert in game_status, game_status_note

## Fehler (Zeile abgewiesen) (4)

### 17_Voxel_Typen (3)
- `17_Voxel_Typen!F3` Ungültiger Verweis ['MAT_Erde'] auf 03_Materialien (ID existiert dort nicht).
- `17_Voxel_Typen!F4` Ungültiger Verweis ['MAT_Gras'] auf 03_Materialien (ID existiert dort nicht).
- `17_Voxel_Typen!F6` Ungültiger Verweis ['MAT_Holz'] auf 03_Materialien (ID existiert dort nicht).

### 19_Zucht_Fortpflanzung (1)
- `19_Zucht_Fortpflanzung!D3` Nachkommen: Wert darf nicht negativ sein (gefunden -1)

## Warnungen (321)

### 12_Verletzungen_Prothesen, 17_Voxel_Typen (5)
- `12_Verletzungen_Prothesen, 17_Voxel_Typen` ID 'V001' existiert in mehreren Blättern. Im Spiel sind IDs je Definitionsart getrennt; Verweise müssen das Zielblatt eindeutig festlegen.
- `12_Verletzungen_Prothesen, 17_Voxel_Typen` ID 'V002' existiert in mehreren Blättern. Im Spiel sind IDs je Definitionsart getrennt; Verweise müssen das Zielblatt eindeutig festlegen.
- `12_Verletzungen_Prothesen, 17_Voxel_Typen` ID 'V003' existiert in mehreren Blättern. Im Spiel sind IDs je Definitionsart getrennt; Verweise müssen das Zielblatt eindeutig festlegen.
- `12_Verletzungen_Prothesen, 17_Voxel_Typen` ID 'V004' existiert in mehreren Blättern. Im Spiel sind IDs je Definitionsart getrennt; Verweise müssen das Zielblatt eindeutig festlegen.
- `12_Verletzungen_Prothesen, 17_Voxel_Typen` ID 'V005' existiert in mehreren Blättern. Im Spiel sind IDs je Definitionsart getrennt; Verweise müssen das Zielblatt eindeutig festlegen.

### 02_Rohstoffe (300)
- `02_Rohstoffe!E2` Element-Anteile ergeben 97 % statt 100 %.
- `02_Rohstoffe!E3` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!Zeile 3` Chemisch unplausibel: Cellulose besteht real aus ['C', 'H', 'O'], Excel nennt ['C', 'H', 'O', 'P'].
- `02_Rohstoffe!E4` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!Zeile 4` Chemisch unplausibel: Lignin besteht real aus ['C', 'H', 'O'], Excel nennt ['H', 'O'].
- `02_Rohstoffe!E5` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!Zeile 5` Chemisch unplausibel: Holz besteht real aus ['C', 'H', 'O'], Excel nennt ['C', 'N'].
- `02_Rohstoffe!E6` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E7` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E8` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E9` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E10` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E11` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E12` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E13` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E14` Element-Anteile ergeben 97 % statt 100 %.
- `02_Rohstoffe!E15` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E17` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E18` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E19` Element-Anteile ergeben 97 % statt 100 %.
- `02_Rohstoffe!E20` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E21` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E22` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E23` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E24` Element-Anteile ergeben 97 % statt 100 %.
- `02_Rohstoffe!E25` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E26` Element-Anteile ergeben 97 % statt 100 %.
- `02_Rohstoffe!E27` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E28` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E29` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E30` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E31` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E32` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E33` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E34` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E35` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E36` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E37` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E38` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E40` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E41` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E42` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E43` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E44` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E45` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E46` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E47` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E48` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E49` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E50` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E51` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E52` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E53` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E54` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E55` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E56` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E57` Element-Anteile ergeben 98 % statt 100 %.
- `02_Rohstoffe!E58` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E59` Element-Anteile ergeben 99 % statt 100 %.
- `02_Rohstoffe!E60` Element-Anteile ergeben 98 % statt 100 %.
- … 240 weitere gleichartige Meldungen (vollständig in den `rejected`/`import_warnings`-Feldern der JSON-Dateien)

### 03_Materialien (4)
- `03_Materialien!E11` Zusammensetzung: Bestandteil R001 kommt mehrfach vor; Anteile werden addiert (70 + 30).
- `03_Materialien!E41` Zusammensetzung: Bestandteil R001 kommt mehrfach vor; Anteile werden addiert (70 + 30).
- `03_Materialien!Zeile 112` Widerspruch zu data/materials: Kupfer_rein density_kg_m3=3093, Referenzwert 8960. Im Spiel gilt der Referenzwert.
- `03_Materialien!Zeile 112` Widerspruch zu data/materials: Kupfer_rein melting_point_c=1501, Referenzwert 1084.62. Im Spiel gilt der Referenzwert.

### 06_Kreaturen (1)
- `06_Kreaturen!Zeile 2` Mutterbaum verwendet Körperteiltypen ['Körper', 'Schwanz'] (u. a. 'Schwanz'); für einen Baum unklar. Der Lebensbaum wird unabhängig davon generiert.

### 08_Animationen (1)
- `08_Animationen!Zeile 6` Name 'Stehen' kommt mehrfach vor (zuerst Zeile 2).

### 11_Werkzeuge_Items (5)
- `11_Werkzeuge_Items!Zeile 2` Rohstoff 'Stein' ist ein Name, keine ID, und existiert nicht in 02_Rohstoffe.
- `11_Werkzeuge_Items!Zeile 3` Rohstoff 'Kupfer' ist ein Name, keine ID, und existiert nicht in 02_Rohstoffe.
- `11_Werkzeuge_Items!Zeile 4` Rohstoff 'Stein' ist ein Name, keine ID, und existiert nicht in 02_Rohstoffe.
- `11_Werkzeuge_Items!Zeile 5` Rohstoff 'Blätter' ist ein Name, keine ID, und existiert nicht in 02_Rohstoffe.
- `11_Werkzeuge_Items!Zeile 6` Rohstoff 'Kork' ist ein Name, keine ID, und existiert nicht in 02_Rohstoffe.

### 12_Verletzungen_Prothesen (2)
- `12_Verletzungen_Prothesen!Zeile 2` Prothese_Typ 'M_PROTHESE_KUPFER' verweist auf keinen Eintrag in 11_Werkzeuge_Items (uneinheitlich: Code vs. Name).
- `12_Verletzungen_Prothesen!Zeile 3` Prothese_Typ 'Holzprothese' verweist auf keinen Eintrag in 11_Werkzeuge_Items (uneinheitlich: Code vs. Name).

### 17_Voxel_Typen (2)
- `17_Voxel_Typen!Zeile 5` Voxeltyp 'Wasser' verweist auf Material MAT004 = 'Holz_gehärtet' (Name passt nicht).
- `17_Voxel_Typen!Zeile 8` Voxeltyp 'Kupfer' verweist auf Material MAT002 = 'Cellulose_rein' (Name passt nicht).

### 19_Zucht_Fortpflanzung (1)
- `19_Zucht_Fortpflanzung!Zeile 2` Text verweist auf '12_Vererbung'; das Blatt heißt '13_Vererbung_Genetik'.

## Hinweise (1)

### 06_Kreaturen (1)
- `06_Kreaturen!Zeile 3` Setzling listet nur Arm_Links (KT006) und Bein_Links (KT008); der Grundkörper wird spiegelsymmetrisch mit zwei Armen und zwei Beinen erzeugt (Annahme).

