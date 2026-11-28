# Weltausbau – Vermessung und Weg zur großen Welt

**Stand:** Alpha 1.1 (28.11.2026). Auftrag: Zusatz Weltarchitektur §2 („Welt zuerst vermessen“), Roadmap Abschnitt 6 (Alpha 1.1, Muss 1) und Abschnitt 8.
Dieses Dokument hält fest, **was heute gemessen ist**, wo die Engpässe liegen und was daraus für Alpha 1.2 (große, gestreamte Welt) folgt. Zahlen ohne Grafikkarte stammen aus der Arbeitsumgebung der KI (2 Prozessorkerne, kein Grafikprozessor). **Bildzeiten auf einer Grafikkarte sind nicht verifiziert** – sie misst der Nutzer ab Alpha 1.2 mit der Messszene.

## 1. So wird gemessen
```
godot --headless --path . -s res://tools/benchmark_world.gd -- [--map=lichtung] [--secs=120] [--seed=N]
```
Der Bericht steht danach in `user://benchmark_report.txt` (Windows: `%APPDATA%\Godot\app_userdata\Pflanzenwesen\`). Ohne `--headless` läuft dieselbe Messung mit Grafikkarte. Im Spiel zeigt die Leistungsanzeige (F3) zusätzlich die Simulationszeit je Modul.

## 2. Ist-Zustand der Welt (Karte „Lichtung“, wie v0.6.x)
| Größe | Wert |
|---|---|
| Karte | 64 × 32 × 64 Zellen à 0,50 m = 32 × 16 × 32 m, Fläche 1.024 m² |
| Zellen | 131.072, ein Byte je Zelle (dichtes Feld, 0,13 MB) |
| Chunks | 16 Stück à 16 × 32 × 16 Zellen (Netz und Kollision je Chunk) |
| Wasser | Spaltenmodell, 4.096 Spalten, Schritt alle 0,1 s |
| Navigation | Spaltenraster 64 × 64, A* mit höchstens 2.500 Knoten je Suche, höchstens 4 Suchen je Takt |
| Weltobjekte | Lebensbaum (ein Modell), 66 Pflanzen und Pilze (46 + 20 zusätzliche Nahrungsstandorte) |

## 3. Messwerte (Godot 4.7.2, headless, 2 Kerne, Startwert 12345)
| Vorgang | Messwert |
|---|---|
| Neues Spiel gesamt (Gelände, Netze, Kollision, Baum, Pflanzen, Navigation, 50 Wesen) | 764 ms |
| Geländeerzeugung, nur Daten | 15,9 ms |
| Netz + Kollision aller 16 Chunks | 154 ms, also 9,6 ms je Chunk (8.192 Zellen) |
| 20 Geländeänderungen (Daten, Wasser, Abstützung, Navigation) | 0,62 ms; danach 2 Chunks neu: 14,6 ms |
| Navigation aufbauen (4.096 Spalten) | 11,0 ms |
| Wegsuche quer über die Karte (100 zufällige Strecken) | Ø 8,5 ms, längste 44 ms, Ø 318 Knoten |
| Wasser, ein Schritt über alle Spalten | 2,48 ms |
| Simulationstakt mit 50 Wesen (1/60 s) | Ø 2,95 ms, Median 2,52 ms, 99 % unter 6,41 ms, längster 13,3 ms |
| Arbeitsspeicher (statisch) | 111 MB mit Welt und 50 Wesen (69 MB vor der Welt) |
| Objekte / Knoten / Entitäten | 2.923 / 297 / 194 |
| Spielstand Format 6 | 1.132 kB; Speichern 135 ms (mit Kontrolllesen), Lesen und Prüfen 33 ms |

**Simulationszeit je Modul** (Ø je Takt, 120 s Spielzeit, 50 Wesen):

| Modul | Ø je Takt | Anteil |
|---|---|---|
| actions (Handlungen, Bewegung, Wegsuche) | 0,96 ms | 41 % |
| mind.perception (Wahrnehmung, Lernen) | 0,61 ms | 26 % |
| life (Stoffwechsel, Photosynthese) | 0,51 ms | 22 % |
| mind.decision | 0,10 ms | 4 % |
| alle übrigen Module zusammen | 0,17 ms | 7 % |
| außerhalb der Module (Uhr, Wärme und Phasen der Weltmassen) | 0,60 ms | – |

Vergleich vor und nach dem Umbau zu Modulen (gleicher Startwert, 300 s bzw. 120 s): 2,89 ms je Takt vorher, 2,95 ms nachher. Der Zustand nach 120 s ist **bitgleich** (Abschnitt 6).

## 4. Was das für die 20-fache Fläche bedeutet (Hochrechnung, keine Messung)
Die Standardkarte von Alpha 1.2 soll etwa 143 × 143 m groß werden (20-fache Fläche, Roadmap Alpha 1.2). Hochgerechnet aus den Messwerten oben, **wenn nichts geändert würde**:

| Größe | heute | 20-fache Fläche, 48 m hoch, 0,5 m | dasselbe mit 0,25-m-Zellen |
|---|---|---|---|
| Zellen | 0,13 Mio. | etwa 7,9 Mio. | etwa 63 Mio. |
| dichtes Zellfeld | 0,13 MB | 7,9 MB | 63 MB |
| Netz + Kollision aller Chunks | 0,15 s | etwa 9 s | etwa 74 s |
| Wasserschritt über alle Spalten | 2,5 ms | etwa 50 ms | etwa 200 ms |
| Wegsuche quer über die Karte | Ø 8,5 ms | Knotenlimit 2.500 reicht nicht mehr; ohne Limit etwa 20-fach | – |
| Navigation aufbauen | 11 ms | etwa 220 ms | etwa 880 ms |

**Folgerungen für Alpha 1.2 (verbindlich als Ausgangspunkt, dort neu zu messen):**
1. **Netze und Kollision nicht für die ganze Karte auf einmal.** Chunks nach Bedarf (Kamera, aktive Akteure) laden; Netze im Hintergrund (`WorkerThreadPool`), Übergabe im Hauptthread mit Budget je Bild. Ungeladene Bereiche stellt ein Höhenfeld dar und sie gelten **nicht** als Luft.
2. **Wasser nur dort rechnen, wo es sich bewegt** (aktive Spalten statt aller Spalten). Ein Schritt über alle Spalten wäre bei der großen Karte allein teurer als das Ziel von 8 ms je Simulationsbild.
3. **Wegsuche hierarchisch** (Chunk-Portale für die Strecke, lokales A* im Chunk). Das feste Knotenlimit von 2.500 passt nur zur kleinen Karte.
4. **Zellgröße 0,25 m** ist mit einem dichten Feld und GDScript-Netzen voraussichtlich nicht tragfähig (8-fache Zellzahl). Der Vergleich 0,50 m gegen 0,25 m wird in 1.2 gemessen; ist das feine Profil nicht tragfähig, bleibt es experimentell (Zusatz Weltarchitektur §4).
5. **Wesen-Simulation skaliert mit der Zahl der Wesen, nicht mit der Kartengröße** (Handlungen, Wahrnehmung, Stoffwechsel = 89 % der Modulzeit). Mit 50 Wesen bleibt sie auf der großen Karte bei rund 3 ms, solange die Wegsuche begrenzt ist.
6. **Kompakter Chunk-Speicher** (homogen, Palette plus Bits oder Lauflängen) lohnt sich für Arbeitsspeicher und Spielstand; im Spielstand stehen schon seit Alpha 1.1 nur die Änderungen je Chunk.

## 5. Was Alpha 1.1 dafür vorbereitet hat
| Baustein | Stand |
|---|---|
| **Kartenvorlagen** `data/maps/<id>.json` | Größe, Zellgröße, Startwert, Generator und Generatorversion, geografische Breite, Meer, Biome, Startgebiet, Geologieprofil. „Lichtung (klein, wie v0.6)“ ist die bisherige Welt. Auswahl im Neues-Spiel-Dialog. |
| **`WorldAccess`** (`ctx.terrain`) | einziger Geländezugriff außerhalb der Welt-Schicht: `size_cells`, `cell_size`, `is_loaded`, `type_at`, `material_at`, `is_solid`, `surface_height`, `water_depth_m`, `raycast`, `set_material` (einziger Schreibweg). Ein Test durchsucht alle Skripte außerhalb von `scripts/world` nach direkten Zugriffen auf die Zelldaten. |
| **Keine feste Kartengröße** | Prüfkarte 48 × 32 × 80 Zellen (nicht quadratisch): neues Spiel, 60 s mit 50 Wesen, Speichern und Laden – getestet. |
| **Chunk-Deltas im Spielstand** | je Region nur die gegenüber dem Generator geänderten Zellen, je Chunk (`RegionStore`). Das Grundgelände entsteht beim Laden aus Vorlage + Startwert + Generatorversion und wird per Prüfsumme kontrolliert. |
| **Module mit Zeitmessung** | jedes Teilsystem ist ein `SimModule`; das Register misst die Zeit je Modul. Neue Module (Klima, Ökologie …) hängen sich über Abhängigkeiten ein. |
| **Zufallsströme je Modul** | `ctx.rng_streams.stream("<modul-id>")` aus Weltstartwert + ID; ein neues Modul verschiebt bestehende Abläufe nicht (getestet). |
| **Zonen A/B/C** | im Modulvertrag vorgesehen (`tick(dt, zone)`), heute läuft alles in Zone A. Die Zonen selbst kommen mit 1.2. |

## 6. Nachweis „Umbau ohne Verhaltensänderung“
`tools/state_hash.gd` startet ein Spiel mit festem Startwert, lässt es N Sekunden laufen und bildet Prüfsummen über den Zustand je Bereich (Wesen mit Geist und Wissen, Nahrung, Gegenstände, Bilanz, Soziales, Arbeit, Versuche, Gespräche, Eingriffe). Gemessen wurde **vor** jeder Codeänderung von Alpha 1.1 (Stand v0.6.1) und **nach** dem Umbau, je 120 s:

| Lauf | Gesamtprüfsumme vorher | nachher |
|---|---|---|
| normales Spiel, 50 Wesen | `8a47aa1594d43d4b77048e00` | identisch |
| Testwerkstatt (Verhalten an) | `590346b6a35bfeae34110cce` | identisch |
| Testszene Werkzeugkette (Verhalten an) | `dfcaaad48d16ffd95d1ff9b5` | identisch |

Gelände (`b54f34964bfa264b…`) und Wassermenge (90,5 m³) sind ebenfalls gleich. Der Umbau zu Modulen hat das Verhalten also nicht verändert, auch nicht in der Reihenfolge der Zufallszahlen.

## 7. Offen (wandert in die Aufgabenliste von Alpha 1.2)
- Bildzeit, Netz- und Kollisionsdauer **auf einer Grafikkarte** (GTX 1660 Ti, RTX 3080): nicht verifiziert – Test beim Nutzer mit der Messszene aus 1.2.
- Speicherlayout als Ordner mit einer Datei je Region und Chunk (Roadmap 8.8): Alpha 1.1 legt Kopf, Modulabschnitte und Region noch in **eine** Datei. Der Aufbau ist derselbe; getrennte Dateien lohnen erst mit gestreamten Chunks (1.2).
- Blockgrößenvergleich 0,50 m gegen 0,25 m: Alpha 1.2.
