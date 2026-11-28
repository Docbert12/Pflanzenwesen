# Testergebnisse (Alpha 1.1; darunter 0.6.1-prototype – Prompt 6B und älter)

Alle Angaben stammen aus tatsächlich ausgeführten Läufen. Prompt 6B: 25.11.2026; Prompt 6: 22.11.2026; die Abschnitte zu Prompt 5 und Prompt 4 weiter unten sind vom 21.11. bzw. 19.11.2026. Protokolle liegen in `docs/test_reports/`.

> **Wichtig:** Alle Modellantworten in diesen Tests stammen vom **SIMULIERTEN Testdienst** (`MockOllama`) oder einer lokalen **HTTP-Attrappe** (`tools/ollama_attrappe.py`). **Mit einem echten Ollama-Modell wurde nichts getestet**, auch keine Versuchsvorschläge aus Prompt 6 und keine Arbeitsvorschläge (`work`) aus Prompt 6B.
>
> **Gezielt ausgelöst ≠ entdeckt:** Die Technik-Abnahmetests (1)–(15) und die Arbeitsketten (lagern, bauen, schmelzen) werden gezielt ausgelöst. Sie beweisen, dass die Regeln funktionieren, nicht, dass Wesen etwas von selbst entdecken. Eigenständiges Verhalten steht unter „Beobachtungsläufe“ und ist ein Messwert.

## Testumgebung
| | |
|---|---|
| System | Linux-Container, Intel Xeon 2,1 GHz, **2 Kerne**, 7,8 GB RAM |
| Grafik | **keine GPU**; Bildschirmfotos mit Xvfb + OpenGL über Mesa **llvmpipe** (Software-Rendering) |
| Godot | **4.7.2-stable** und **4.5-stable** (GDScript) |
| Python | 3.13 mit openpyxl (nur Importer) |

**Nicht geprüft:**
- Windows;
- echte Grafikkarte;
- Bedienung mit Maus und Tastatur von Hand. Die Szenentests rufen dieselben Funktionen auf, die auch die Knöpfe auslösen.
- **echtes Ollama** (nicht erreichbar, kein Modell, keine GPU).

## Gesamtergebnis (Alpha 1.1 – Fundament, 28.11.2026)
| Lauf | Godot 4.7.2 | Godot 4.5 |
|---|---|---|
| Ausgangsbasis v0.6.1 vor jeder Änderung (`--quick`) | **491/491** (373 s) | – |
| Projektimport | ohne Fehler | ohne Fehler |
| `tests/run_tests.gd` vollständig (inkl. 10-Minuten-Dauerlauf und beiden 10-Minuten-Beobachtungsläufen) | **564/564** (597 s) | **564/564** (584 s) |
| davon Alpha 1.1 (`tests/test_modules.gd`, neu) | **71/71** | **71/71** |
| davon neue Szenenprüfungen (Neues-Spiel-Dialog, Startmeldung mit Karte) | 2/2 | 2/2 |
| Start aller 6 Szenen + Testwerkstatt + Testszene Werkzeugkette, je 240 Bilder (`tools/scene_smoke.gd`) | 8/8 | 8/8 |
| Python-Tests (`tools/tests`) | **39/39** | – |
| Leitlinie prüfen (`tools/build_leitlinie.py --pruefen`) | bestanden (Alpha 1.1: +0 Erfindungen, nichts zu ändern) | – |
| Versionsvergleich gegen v0.6.1 + Roadmap (`tools/compare_versions.py`) | 36 Dateien neu, 0 entfernt, 21 geändert; 3 private Hilfsfunktionen und 1 Testtext als entfernt gelistet und begründet (`reports/versionsvergleiche/README.md`) | – |
| Windows-Export (`--export-release "Windows Desktop"`) | Build erzeugt (`Pflanzenwesen.exe` + `.pck`); das Spielpaket startet mit der Linux-Engine (neues Spiel, 10 s, Speichern, Prüfung ohne Befund) | – |

Nach dem vollständigen Lauf wurde nur noch ein Messwert-Text in `tests/test_modules.gd` gekürzt (irreführende Angabe „bewegte Wesen“); danach liefen die 71 Modul-Prüfungen erneut auf beiden Versionen (71/71).

**Nachweis „Umbau ohne Verhaltensänderung“** (`tools/state_hash.gd`, je 120 s, Startwert 12345): Zustandsprüfsummen vor der ersten Codeänderung und nach dem Umbau **identisch** – Spiel `8a47aa1594d43d4b77048e00`, Testwerkstatt `590346b6a35bfeae34110cce`, Testszene Werkzeugkette `dfcaaad48d16ffd95d1ff9b5`. Taktzeit 50 Wesen: 2,89 ms vorher, 2,95 ms nachher (Dauerlauf 600 s im Testlauf: 3,24 ms).

**Neue Prüfungen (`[Module]`, gezielte Regeltests – keine Aussage über eigenständiges Verhalten):**
1. Reihenfolge der 16 Module = Taktreihenfolge v0.6.1; Akteur-Gruppe; zusätzliche Module werden eingeordnet und laufen im selben Pfad; Pause.
2. Registerfehler: Zyklus, unbekannte Abhängigkeit, doppelte ID, stabile Sortierung.
3. Zufallsströme je Modul: reproduzierbar, unabhängig, gespeichert; ein neuer Strom verändert den Ablauf der 50 Wesen nicht.
4. `WorldAccess`: 400 Stichproben gegen die Weltdaten, Oberflächenhöhe, Schreibweg mit Navigation und Protokoll, Ablehnungen, Strahl.
5. Kartenvorlagen: Lichtung = Welt von v0.6.x (Gelände bitgleich), unbekannte und ungültige Vorlagen.
6. Nicht-quadratische Karte 48 × 32 × 80: neues Spiel, 60 s mit 50 Wesen (289 Wegsuchen, 0 fehlgeschlagen), Speichern und Laden.
7. Format 6 im Rundlauf: jeder Abschnitt nach dem Laden identisch, Region mit Chunk-Deltas, Zufallszustände; Abweisung ohne Teil-Laden (4 Fälle); Menü-Kurzinfo.
8. Chunk-Deltas: 299 Zufallsänderungen, Kartenkante, Umrechnung der Format-5-Liste, beschädigte Daten.
9. **Migration 5 → 6 mit drei echten v0.6.1-Spielständen** (normales Spiel, Testwerkstatt, Werkzeugkette mitten in einer Kette): Inhalt, Zeit, IDs, Zufall, Gelände, Wasser; die laufende Kette wird zu Ende geführt; danach Format 6 ohne Migration; veränderte Definitionen und unvollständige Stände abgewiesen.
10. Determinismus: zwei Läufe à 30 s – Zustand und Messwerte je Modul gleich.
11. Abschnittsversionen: Anheben durch das Modul, optionaler Abschnitt fehlt → Startzustand, ungültige Version abgewiesen.
12. Kein Skript außerhalb `scripts/world` greift direkt auf die Zelldaten zu.
13. Zeitmessung je Modul (Anteile = 100 %, abschaltbar), Messwerte je Modul.
14. Definitionen und Version: Karten im Fingerabdruck, „Alpha 1.N“, ausgelieferte Fingerabdrücke v0.6.1 und alpha-1.1 eingetragen, unbekannte abgewiesen.

**Messwerte Alpha 1.1** (headless, 2 Kerne; vollständig in `docs/world_expansion.md`): Simulationstakt Ø 2,95 ms (99 % unter 6,4 ms); größte Anteile Handlungen 41 %, Wahrnehmung 26 %, Leben 22 %; Netz + Kollision 9,6 ms je Chunk; Wegsuche quer über die Karte Ø 8,5 ms; Wasserschritt 2,5 ms; Arbeitsspeicher 111 MB; Spielstand 1,1 MB.

**Nicht verifiziert (Alpha 1.1):**
- **Bildzeiten und Darstellung auf einer Grafikkarte** (keine in der Arbeitsumgebung);
- **Start des Windows-Builds unter Windows**;
- **Neues-Spiel-Dialog von Hand** mit Maus und Tastatur (der Szenentest ruft dieselben Funktionen auf);
- weiterhin: echtes Ollama, Animationen als bewegte Bilder.

## Gesamtergebnis (Prompt 6B)
| Lauf | Godot 4.7.2 | Godot 4.5 |
|---|---|---|
| Ausgangsbasis v0.6.0 vor jeder Änderung (24.11.2026) | **432/432** | **432/432** |
| Projektimport | ohne Fehler | ohne Fehler |
| `tests/run_tests.gd` vollständig (inkl. 10-Minuten-Dauerlauf, 10-Minuten-Werkstattbeobachtung, 10-Minuten-Arbeitsbeobachtung) | **491/491** (566 s) | **491/491** (582 s, frischer Ordner) |
| davon Arbeitsketten und Arbeitsposen (`tests/test_work_chain.gd`, neu) | **54/54** | **54/54** |
| davon Szenentest Testszene Werkzeugkette (neu) | **4/4** | **4/4** |
| davon Technik (`tests/test_technology.gd`, Prompt 6, unverändert) | **71/71** | **71/71** |
| Start aller 6 Szenen + Testwerkstatt + Testszene Werkzeugkette headless, je 240 Bilder (`tools/scene_smoke.gd`) | 8/8, 0 Fehler, 0 Warnungen | 8/8, 0 Fehler, 0 Warnungen (frischer Ordner, Import ohne Fehler) |
| Python-Tests (Importer, Importkonfiguration, beide Erfindungskataloge, Versionsvergleich) | **23/23** | – |
| Versionsvergleich gegen v0.6.0 (`tools/compare_versions.py`) | 0 Dateien, Klassen, Funktionen oder Schlüssel entfernt; 2 Testprüfungs-Texte geändert (begründet); 51 neue Dateien, 63 geänderte (`reports/versionsvergleiche/versionsvergleich_v0.6.0_zu_v0.6.1.md`) | – |
| Bildschirmfotos Testszene Werkzeugkette (`tools/capture_work_chain.gd`, Software-Rendering) | 15 Bilder (lagern, bauen, schmelzen), ohne Fehler (nur fehlende Audioausgabe der Umgebung gemeldet); 10 davon in `docs/screenshots/` | – |

**Neue und geänderte Prüfungen:**
- `tests/test_work_chain.gd` (neu, 54 Prüfungen): Arbeitsposen-Geometrie, Körpergrenzen, die drei Ketten, sieben Fehlerfälle, Unterbrechung, Speichern/Laden, Schlagkontakt, normales Spiel, Modellvorschlag und Modellanfrage (SIMULIERT), Beobachtungslauf, Excel-Abgleich, aktivierte Erfindungen, Erfindungskatalog, Migration 4→5 mit beiden echten v0.6.0-Spielständen.
- Szenentest Testszene Werkzeugkette (neu, 4 Prüfungen); eine neue Prüfung „ausgelieferte Definitionen v0.6.1“.
- 3 bestehende Prüfungen angepasst und im CHANGELOG begründet: Werkstatt-Griffpunkt (strenger), Migrationsstufen (1→2→3→4→5), Fingerabdruck v0.6.0 (jetzt am echten v0.6.0-Spielstand geprüft).
- Ein erster vollständiger Lauf auf 4.7.2 ergab 488/490: genau diese zwei veralteten Migrationsprüfungen schlugen fehl (Stufen 1→2→3→4 bzw. Fingerabdruck v0.6.0 gegen die neuen Definitionen). Sie wurden angepasst. Nach den Bildschirmfotos wurden noch die Knopfbeschriftungen und die Größe der schwebenden Beschriftungen geändert; die Läufe oben sind die vollständigen Läufe auf dem **ausgelieferten** Stand.

## Roadmap und Alpha-Plan der Leitlinie (25.11.2026, keine neue Spielversion)
| Lauf | Ergebnis |
|---|---|
| Python-Tests (`python3 -m unittest discover -s tools/tests`), davon 16 in `tools/tests/test_leitlinie.py` | **39/39** |
| Nachrechnen der Leitlinien-Excel mit LibreOffice (inkl. Blätter „Alpha-Plan“, „Alpha-Zeitalter“) | 7.779 Formeln, **0 Fehler** |
| Formelwerte gegen die Python-Zählung (zusätzlich: Alpha-Spalte, Alpha-Rang, Alpha-Plan je Version, Matrix Zeitalter × Version) | 0 Abweichungen |
| Sichtprüfung der neuen Blätter als PDF | lesbar, Farbskala der Matrix korrekt |

Godot-Tests wurden nicht erneut ausgeführt: Am Spiel hat sich nichts geändert.

## Leitlinien-Excel „Steinzeit → Zukunft“ (25.11.2026, keine neue Spielversion)
| Lauf | Ergebnis |
|---|---|
| Python-Tests (`python3 -m unittest discover -s tools/tests`), davon 15 neu in `tools/tests/test_leitlinie.py` | **38/38** |
| Quellenprüfung `python3 tools/build_leitlinie.py --pruefen` | 2.680 Erfindungen, 24 Zeitalter (54–192 je Zeitalter), 0 Fehler |
| Nachrechnen der Excel mit LibreOffice (`recalc.py` des xlsx-Werkzeugs) | 7.157 Formeln, **0 Fehler** |
| Formelwerte gegen die Python-Zählung (alle Zählspalten, Kennzahlen, Zwischenschritte, Lücken, Prompt-Abgleich, Katalog) | 0 Abweichungen |
| Auswahl geändert (Werkzeugformen dazu, Erz ab, Großbuchstabe „X“) und neu gerechnet | Ergebnis gleich der Python-Zählung |
| Sichtprüfung als PDF (Vorschau mit verkleinerter Erfindungsliste) | Kopfzeilen, Spaltenbreiten, Farben, Diagramme lesbar |

Godot-Tests wurden nicht erneut ausgeführt: Am Spiel (Code, Daten, Szenen) hat sich nichts geändert.

## Prompt 6B – Werkzeug- und Materialkette (gezielt in der Testszene ausgelöst)
Alle drei Ketten laufen über dieselben Handlungen wie im normalen Spiel (`WorkSystem` → `DecisionSystem`-Option bzw. `WorkSystem.tick` → `ActionExecutor`). Messwerte aus `tests/test_work_chain.gd` (Startwert fest) und `tools/probe_work_chain.gd`.

| Kette | Ergebnis | Messwerte |
|---|---|---|
| **lagern** | abgeschlossen | Hammer #159 aus Stiel, Steinkopf und Fasern gebunden (eigene ID); ausgerüstet ohne Kopie; großer Stein 2,7 kg nach **16 Schlägen mit genau 16 Kontakten** zerbrochen; 2 Bruchstücke, Masse 2,700000 kg von 2,700000 kg, Wärmeenergie erhalten; beide Stücke eingelagert, das schwerere (1,80 kg) **zweihändig** getragen; Gesamtmasse der Welt 23,135787 → 23,135787 kg; Wissen verbucht (Binden, Schlagen, Lagern); Audit leer. Probe: abgeschlossen nach **59,5 s** Spielzeit. |
| **bauen** | abgeschlossen | Steinreihe 3/3 aus realen Steinen (Bruchstücke + vorhandener Stein), zusammenhängend; Funktion aus den Teilen gemessen („markiert eine Linie am Boden, Höhe 0,11 m; kein Hindernis für die Wegsuche“); verbaute Teile nicht mehr greifbar; Masse erhalten. Probe: **66,9 s** Spielzeit; Reihe 0,44 m lang, 0,108 m hoch, 3,839 kg. |
| **schmelzen** | abgeschlossen | Kupfer mit dem Hammer **kalt verformt** (Dehnung 0,042, kein Bruch); Stücke in den Tiegel, im Testofen geschmolzen, vor dem Gießen vereinigt; **Guss 0,1671 kg von 0,1671 kg**; Kupfermasse gesamt erhalten. Testofen = Testausrüstung. Probe: **185,0 s** Spielzeit. |

**Sichtbarkeit (Geometrie gemessen, Aussehen nur als Standbild):**
- Arbeitsposen: Die Gelenkkette der Animation trifft die `WorkPose`-Kontaktpunkte in 42 Posen (beide Seiten, Schlag/Einsetzen/Gießen) mit größter Abweichung 0,0000 m. Ziele von Bodenhöhe bis 0,2 m sind erreichbar.
- Schlag in der Simulation: 6 Kontakte gemessen, sichtbarer Hammerkopf höchstens **0,022 m** vom Ziel (Grenze 8 cm); Phasen Anlauf → Ausholen → Kontakt → Rückkehr; **0,0000 m** Fußgleiten während der Arbeit.
- Szene: Hammer-Modell sitzt am Griffpunkt der animierten Hand (Abweichung 0,0000 m), Kopf beim Kontakt 0,022 m vom Ziel.

## Prompt 6B – Fehlerfälle (gezielt ausgelöst)
| Fall | Verhalten (gemessen) |
|---|---|
| Fehlendes Material | Fasern entfernt → „Nicht planbar: Bauteile für einen Hammer fehlen: Fasern nicht bekannt“ |
| Blockierter Weg | Lager ummauert → Kette „fehlgeschlagen“, Grund „Weg blockiert: Wegsuche … abgebrochen“; Getragenes danach abgelegt |
| Fehlender Arm | rechter Unterarm entfernt → Hammer **einarmig** gebunden (Variante, länger, weniger straff); zu breites Stück (0,11 m) mit Begründung „eine zweite greiffähige Hand fehlt“ liegen gelassen; Schlag weicht auf die linke Hand aus; entfernte Teile werden nie bewegt |
| Zu schwer | Block 17,5 kg → „Auch mit beiden Händen zu schwer (17,50 kg > 4,60 kg)“, kein Tragen, keine Teleportation |
| Unterbrechung | Schlagfolge abgebrochen, ausgeführte Schläge bleiben wirksam (Schaden 0,132 bleibt), Kette pausiert, nach 2 s fortgesetzt und abgeschlossen – ein Hammer, Stücke genau einmal eingelagert |
| Ungeeignetes Schmelzgut | Holz nicht in den Tiegel („brennbar; Verbrennung ist noch nicht simuliert – Schmelzen abgewiesen“), Kupfer wird geschmolzen |
| Fehlende Wärmequelle | Testofen entfernt → „Nicht planbar: keine Wärmequelle: Ofen #157 fehlt“ |
| Speichern/Laden mitten in der Kette | Kette, Werkzeug und Gehaltenes erhalten (Format 5); Zustand identisch bis auf den Fortsetzungsvermerk; danach abgeschlossen ohne Verdopplung, Masse erhalten |
| Graben/Verdichten | als Pose vorbereitet, Handlung abgewiesen („es gibt noch keine Grabhandlung (Weltarchitektur-Zusatz)“) |

**Normales Spiel:** Arbeitssystem aktiv, aber ohne Testausrüstung, Lager, Baustelle oder Kette beim Start. Mit Göttermenü-Material läuft dieselbe Kette (WorkSystem → Handlungen) und wird abgeschlossen; Audit leer.

**Modell (SIMULIERT):** Eine gescheiterte eigene Kette löst eine Anfrage `work` aus. Der Vorschlag wird geprüft und nur als Option abgelegt (noch keine Handlung). Gewählt wird er wie jede andere Option; ausgeführt nur über Spielhandlungen (2 Stücke real eingelagert, Herkunft „Modellvorschlag (SIMULIERT, geprüft)“). Abgewiesen: erfundener Schritt (Stufe 5), unbekannte ID (Stufe 3), erfundenes Feld (Stufe 2), `teleport`, unbekannter Gegenstand #999999.

## Prompt 6B – Beobachtungslauf (eigenständiges Verhalten, Messwert)
**Arbeits-Beobachtungslauf 600 s** in `run_tests.gd` (Testszene, ein Wesen, Verhalten AN **nach** einer gezielt ausgelösten ersten Steinreihe und neu hingelegten Steinen): autonom gestartete Ketten **1**, abgeschlossen **1** (#2 „bauen“, 3 Stücke verbaut); Wesen lebt, Hunger am Ende 23 %.
- Das Wesen hat **von selbst** eine Kette „bauen“ gewählt (Anlass: eigene Erfahrung mit Steinreihen, Kompetenzerleben) und abgeschlossen.
- **Nicht beobachtet:** eigenständiges Lagern, eigenständiges Schmelzen, ein ganz ohne Vorgeschichte begonnenes Bauwerk. Das ist ein Messwert, kein Fehler – es gibt keine Pflicht zur Entdeckung.
- Gezielt ausgelöste Ketten (Tabelle oben) und dieser Lauf sind getrennt ausgewiesen; die Herkunft steht an jeder Kette („gezielt ausgelöst“ / „eigener Bedarf“ / „Modellvorschlag“).

## Prompt 6B – Excel-Abgleich
- Importkonfiguration `design/import_config/datenbasis_korrekturen.json`: 5 Korrekturen (Kupfer-Voxeltyp → MAT111, Wasser-Voxeltyp → MAT206, MAT_Erde/Gras/Holz → soil/plant_tissue/wood) und Projektentscheidungen (Voxelgröße überstimmt, Fortpflanzungszeilen nicht übernommen, Setzling-Ernährung dokumentiert). Neuimport: **1 Fehler** (vorher 4 abgewiesene Zeilen), 319 Warnungen (`reports/import_report.md`). Die Original-Excel wurde nicht verändert.
- Erfindungskatalog „echte Namen“: 5.862 Quellenzeilen → 2.785 Einträge (nur gleicher Name + gleiche Kategorie zusammengefasst), alles „catalog“, **0 Startverfahren** (`reports/inventions_real_import_report.md`).
- Aktivierte Erfindungen: 8 Definitionen, alle Handlungen, Materialien, aktiven Animationen, Spielparameter und Katalogverweise existieren (Konsistenztest).

## Gesamtergebnis (Prompt 6)
| Lauf | Godot 4.7.2 | Godot 4.5 |
|---|---|---|
| Ausgangsbasis v0.5.1 vor jeder Änderung | **354/354** | **354/354** |
| Projektimport | ohne Fehler | ohne Fehler |
| `tests/run_tests.gd` vollständig (inkl. 10-Minuten-Dauerlauf und 10-Minuten-Werkstattbeobachtung) | **432/432** | **432/432** |
| davon Technik (`tests/test_technology.gd`) | **71/71** | **71/71** |
| davon Szenentest Testwerkstatt | **7/7** | **7/7** |
| Start aller 6 Szenen + Testwerkstatt headless, je 240 Bilder (`tools/scene_smoke.gd`) | 7/7, 0 Fehler, 0 Warnungen | 7/7, 0 Fehler, 0 Warnungen |
| Python-Tests (Importer, Erfindungskatalog, Versionsvergleich) | **17/17** | – |
| Versionsvergleich gegen v0.5.1 (`tools/compare_versions.py`) | 0 Dateien/Klassen/Funktionen/Schlüssel entfernt; 2 Testprüfungen umbenannt (begründet) | – |
| Bildschirmfotos Testwerkstatt (`tools/capture_workshop.gd`, Software-Rendering) | 6 Bilder, ohne Fehler (nur fehlende Audioausgabe der Umgebung gemeldet) | – |

**Neue und geänderte Prüfungen:**
- `tests/test_technology.gd` mit den Abnahmetests (1)–(15), (3b) Zusammentragen und dem Beobachtungslauf;
- Szenentest Testwerkstatt;
- 5 bestehende Prüfungen angepasst und im CHANGELOG begründet: Materialliste, Materialanzahl, Migrationsstufen, Fingerabdruck v0.6.0, Portsuche im Spielstand.

## Prompt 6 – Abnahmetests (gezielt in der Testwerkstatt ausgelöst)
| Nr. | Prüfung | Messwert |
|---|---|---|
| 1 | „Hammer“ mit weichem Kopf: Name ändert nichts; Bewertung sagt Zerfall voraus, er tritt ein; erster Schlag exakt wie vorhergesagt | Steinkopf ε 0,0391 nach 4 Schlägen; „Hammer“ 0,0032 (1. Schlag), danach trifft der Holzstiel |
| 2 | Stein in der Hand vs. bloße Hand | 16 Schläge: Stein ε = 0,0371 (Höhe 20 → 19,27 mm); Hand ε = 0,0083 plus Handschaden |
| 3 | Verbinden: Masse exakt, Fasern Teil des Verbunds, falsches Bindemittel und falsche Methode abgewiesen | 16 g Fasern → Belastbarkeit 3,24 J/Schlag (Geschick 45 % beim 1. Versuch) |
| 3b | Verstreute Teile (2 m) werden zusammengetragen, dann verbunden; gescheiterte Versuche gemerkt | 2 × „hintragen und ablegen“ + verbinden, Masse exakt |
| 4/5 | Überlast bricht die Verbindung, alle Teile genau einmal erhalten, Fasern zerrissen, Stiel bleibt in der Hand; Steinbruch erhält Masse und Wärme | Kopf 0,58 kg mit 5 g Fasern: 0,109 J < Rückprall 1,42 J → Bruch beim 1. Schlag |
| 6 | Δε = W/(σ(ε)·V) exakt; Verfestigung; Risse jenseits ε 1,6; Stein: Schaden = W/(m·Zähigkeit) | – |
| 7 | Kupfer schmilzt nicht bei 40 W/120 s; schmilzt erst nach ausreichender Zufuhr | Probe 0,140 kg braucht 86 597 J; zugeführt bis flüssig 464 042 J (Tiegel und Verluste eingeschlossen) |
| 8 | Gießen erhält Masse und Energie exakt; Gesamtbilanz (Objekte + Umgebung + Körper − Heizung) geschlossen; Guss erstarrt | Versuch 5 dauert 138 s |
| 9 | Heißer Stein (420 K) nicht greifbar, Verbrennung bilanziert; Schmelze ohne Behälter nicht greifbar; heißer Griff verhindert das Gießen; Reflex lässt heiß Gewordenes los | – |
| 10 | Abbruch beim Verformen/Verbinden/Versuch: Zwischenstand bleibt, Energie nicht erstattet, keine Fasern verbraucht vor Abschluss | – |
| 11 | Modellvorschlag (SIMULIERT) → nur ungeprüfte Hypothese; „Generator“, unbekannte ID, erfundenes Material abgewiesen; Evidenz erst durch Versuch | – |
| 12 | Wissen individuell; Wesen außer Sicht bekommt nichts; Tod überträgt nichts | – |
| 13 | Erklären → „gehört“; Vorführung → „zugesehen“ (0 eigene Versuche); Üben → „versucht“/„erfolgreich“; dieselbe Quelle zählt einmal | – |
| 14 | Speichern/Laden mit Werkzeug, Versuchen, Wissen, mitten im Erhitzen; Versuch „unterbrochen“; Erhitzen läuft weiter; Migration echter v0.5.1-Spielstand | – |
| 15 | Normales Spiel ohne Testausrüstung; Göttermenü-Fasern/Stab; Leben läuft weiter | – |

## Prompt 6 – Beobachtungsläufe (eigenständiges Verhalten, keine Auslöser)
**10 min in `run_tests.gd`:** 4 eigene Versuche, alle „untersuchen“, alle abgeschlossen; Versuchszeit A 0 %, B 8 % (Budget 25 %); gegessen 0,60 kg; kein Verfahren entstanden; Audit ohne Befund. Bei 10 min reicht die Zeit für Untersuchungen, aber noch nicht für eigenes Verbinden.

**30 min mit `tools/observe_workshop.gd -- 1800`** (Startwert 12345, 4.7.2). Protokoll: `docs/test_reports/werkstatt_beobachtung_1800s.txt`.
- 14 eigene Versuche, alle abgeschlossen: 12 × untersuchen, dazu 1 × Verbinden durch B.
- **B (Neugier 0,59) hat von selbst** Kopf und Fasern zum Stiel getragen und einen **Kupferkopf** an einen Holzstiel gebunden. Gewählt hat es Kupfer, nicht Stein. Das ist nicht falsch: Kupfer ist ein kompakter, harter Block.
- **A (Neugier 0,33)** kannte das Verfahren danach durch B (Beobachtung oder Mitteilung; das Protokoll unterscheidet das nicht), hat es selbst geübt (Herkunft „Übung“) und ist jetzt ebenfalls auf „erfolgreich“.
- Gegessen: A 0,90 kg, B 1,00 kg. Audit ohne Befund.
- **Vor** den Korrekturen „Zusammentragen“ und „Gedächtnis für Fehlschläge“ scheiterten im selben Lauf alle Verbindungsversuche an der Reichweite. Derselbe Versuch wurde bis zu siebenmal wiederholt.
- Nicht beobachtet wurden: spontanes Schlagen von Kupfer, spontanes Heizen und Gießen, spontanes Erklären oder Vorführen. Das ist ein Messwert, kein Fehler. Es gibt keine Pflicht zur Entdeckung.

## Gesamtergebnis (Prompt 5)
| Lauf | Godot 4.7.2 | Godot 4.5 |
|---|---|---|
| Projektimport | ohne Fehler | ohne Fehler |
| `tests/run_tests.gd` vollständig (inkl. 10-Minuten-Dauerlauf) | **354/354** (334 s) | **354/354** (328 s) |
| davon KI/Gespräche/Hörensagen/Format 3 (`tests/test_ai.gd`, SIMULIERT + Attrappe) | **60/60** | **60/60** |
| Start aller 6 Szenen headless, je 240 Bilder (`tools/scene_smoke.gd`) | 0 Fehler, 0 Warnungen | 0 Fehler, 0 Warnungen |
| Python-Importertests | **15/15** | – |
| Bildschirmfotos mit Grafik (`tools/capture_living.gd`, KI-Panel im SIMULIERT-Modus) | 13 Bilder, ohne Fehler | – |
| Live-Werkzeug `tools/ollama_live_test.gd` | nur gegen die **Attrappe** gelaufen (Werkzeugprüfung, `docs/test_reports/ollama_live_test_gegen_ATTRAPPE.txt`) | – |
| **Live-Tests 1–5 mit echtem Ollama** | **nicht ausgeführt** | **nicht ausgeführt** |

**Aufteilung der 354 Prüfungen:** Physik 69 · Welt 36 · Wesen/Vorschau 30 · Lebenssimulation 68 · Geist/Soziales/Göttermenü/Migration 39 · **KI/Gespräche 60 (neu)** · Szenentests 52 (neu: KI-Panel und Gesprächsansicht öffnen sich ohne Dienst).

## Prompt 5 – Tests mit kontrolliertem (SIMULIERTEM) Testdienst
Geforderte Fälle aus Prompt 5, Abschnitt 17 – alle bestanden auf 4.7.2 und 4.5:
| Fall | Prüfung |
|---|---|
| Gültiger Plan über das Handlungssystem | Gehen → Aufnehmen → Essen tatsächlich ausgeführt, Plan „abgeschlossen“, Entscheidungsquelle „modellplan“, Bilanz geschlossen |
| Unbekannte IDs | abgelehnt in Stufe 3, kein Plan |
| Verbotene Handlungen | `create_food`, `build_generator` abgelehnt in Stufe 5; keine Nahrung, keine Objekte |
| Erfundenes Material | Zusatzfeld `material` abgelehnt in Stufe 2; Freitext über Gold/Fahrzeug bewirkt nichts |
| Veraltete Antwort nach Laden/Zurücksetzen | offene Anfrage beim Beenden der Welt abgebrochen; späte Antwort mit alter Sitzungsnummer verworfen und gezählt |
| Tod des Akteurs | laufende Anfrage abgebrochen, aktiver Plan „abgebrochen“ |
| Pause | keine Sendungen; eingetroffene Antwort bleibt im Eingang; nach dem Fortsetzen geprüft und angewendet |
| Zeitüberschreitung | Simulation läuft 12 s weiter, Wesen entscheidet lokal, genau 1 Wiederholung, danach „fehlgeschlagen“, kein Plan |
| Keine fremden Erinnerungen | Kontext enthält nur eigene Erinnerungen; keine Persönlichkeitswerte anderer, keine Spielerabsicht, kein Technologiekatalog; Größe begrenzt |
| Hörensagen gekennzeichnet | nicht im Nahrungsgedächtnis, keine Überzeugungsänderung, Wesenfenster zeigt HÖRENSAGEN |
| Weitererzählen ≠ unabhängig | A→B→C und A→C: unabhängig 1, weitererzählt 1; eine echte zweite Beobachtung ergibt unabhängig 2 |
| Keine doppelten Ressourcen | Bilanz und Prüfung nach Plänen und Gesprächen ohne Befund |

Zusätzlich: Einstellungen (nur lokal, Schlüssel nie gespeichert), Client nur Abfragen, Warteschlange (Länge, Duplikate, Verdrängung, Priorität, Fairness, Ablauf, Wiederholung), Unterbrecher nach 3 Fehlern und Wiederherstellung, Modell fehlt, kein Modell gewählt, ungültiges JSON, leere Antwort, fremde Anfrage-ID, unmögliche Schrittfolge, kritischer Hunger, gegessenes Planziel (kein Ersatzobjekt, Signatur gesperrt), Prüfstatus bestätigt/veraltet/widersprochen/Fehler, Vertrauensänderung, Prüfung eines Hinweises durch hungriges Wesen, Sicherheit auf eigene begrenzt, Täuschung nicht möglich, Format-3-Rundlauf, Migration 2→3 mit echtem v0.4.0-Spielstand, Welt ohne Ollama, echter HTTP-Weg zu geschlossenem Port und zur Python-Attrappe.

**50 Wesen, SIMULIERT, 180 s, 1,5 s Antwortzeit, 8 Anfragen/min:** gesendet 24 (= Ratengrenze), angenommen 23, abgelehnt 1 (Prüfung), Anlässe: 23 Gesprächsgelegenheiten, 8 knappe Wahlen; Abstand je Wesen eingehalten, Warteschlange ≤ 16, Prüfung ohne Befund. Das sagt nichts über ein echtes Modell aus.

**Fehler, die die Tests gefunden haben (behoben):**
- HTTP-Antworten kamen leer an: `PackedByteArray` ist ein Werttyp – angehängte Daten gingen verloren.
- Server, die nach der Antwort schließen, galten als Verbindungsfehler: jetzt wird vor dem nächsten `poll()` gelesen.
- Ein bereits erfüllter Planschritt („hingehen“, schon dort) ließ das Wesen bis zur nächsten Entscheidung ruhen: erfüllte Schritte werden jetzt sofort abgehakt.
- Die KI-Fähigkeit eines Wesens wurde nie gesetzt (keine automatischen Anfragen): jetzt fest aus dem Körper-Startwert.

## Dauerlauf 10 Minuten mit 50 Wesen (Prompt 5, KI aus, lokale Gespräche an)
| Prüfpunkt | 4.7.2 | 4.5 |
|---|---|---|
| Laufzeit-, Bilanz-, Reservierungs- und Geistesprüfung jede Minute | ohne Befund | ohne Befund |
| Feststeckende Handlungen / Fehlschlagschleifen | 0 / höchstens 3 je Wesen | gleich |
| Anfragen / erfolgreich / fehlgeschlagen / abgewiesen | 6803 / 6711 / 28 / 15 | gleich |
| Lebend nach 10 min / gegessen / Rest | 50 / 19,3 kg / 16,5 kg | gleich |
| Speicher | +53 Objekte, +14,8 MB | +14,9 MB |
| Simulationstakt Ø / max | 3,43 ms / 24 ms | 3,20 ms / 59 ms |

**Vergleich auf derselben Maschine am selben Tag** (`smoke_life.gd -- 600`, 4.7.2): v0.4.0 **2,97 ms**/Takt, v0.5.0 **3,03 ms**/Takt (+2 %). Die höheren Werte gegenüber dem Bericht vom 19.11. (2,18 ms) liegen an der langsameren Umgebung, nicht am Code. Lokale Gespräche in 10 min: 53 (alle zugestellt); Hörensagen danach: 23 „selbst beobachtet“, 2 „bestätigt“, 3 „nicht prüfbar“.

# Ergebnisse aus Prompt 4 (19.11.2026)

## Gesamtergebnis
| Lauf | Godot 4.7.2 | Godot 4.5 |
|---|---|---|
| Projektimport | ohne Fehler | ohne Fehler |
| `tests/run_tests.gd` vollständig (inkl. 10-Minuten-Dauerlauf) | **293/293** (188 s) | **293/293** (188 s) |
| Start aller 6 Szenen headless, je 240 Bilder (`tools/scene_smoke.gd`) | 0 Fehler, 0 Warnungen | 0 Fehler, 0 Warnungen |
| Python-Importertests (Excel + Erfindungskatalog) | **15/15** | – |
| Bildschirmfotos mit Grafik (`tools/capture_living.gd`) | 10 Bilder, ohne Fehler | – |
| 30-Minuten-Lauf ohne Grafik (`tools/smoke_life.gd -- 1800`) | ohne Befund, Speicher begrenzt | – |

**Aufteilung der 293 Prüfungen:**
- Physik 69
- Welt 36
- Wesen/Vorschau 30
- Lebenssimulation 68
- **Geist/Soziales/Göttermenü/Migration 39 (neu)**
- Szenentests 51 (davon neu: Göttermenü, Vergleich, getrennte Ebenen, Eingriffe nach Speichern/Laden, Geistlabor im Menü)

Die einzige ERROR-Zeile im Protokoll („EntityRegistry: doppelte ID 5 abgewiesen“) ist beabsichtigt: Ein Physiktest prüft genau diese Abweisung.

## Prompt 4 – kontrollierte Szenarien (je 3 Startwerte: 101, 202, 303)
Die Szenarien liegen in `scripts/lab/mind_scenarios.gd` und sind im Spiel unter „Geistlabor (Testbereich)“ sichtbar ausführbar.

**Geskriptet:** Verhalten aus, Handlungen und Eingriffe direkt per Code. Das ist **Funktionsprüfung**, nicht spontanes Verhalten (dazu unten).

| Szenario | Teilprüfungen | Kernergebnis (Startwert 101) |
|---|---|---|
| A Individuelle Erfahrung | 18/18 | a erhält Hilfe von c, b wird von c abgelehnt. Vertrauen a→c 0,71, b→c 0,56. Die Bedeutung der eigenen Hilfe (0,68) liegt über der nur beobachteten (0,23). Die Ablehnung senkt das Vertrauen nur leicht (0,59 → 0,53). |
| B Hilfe | 15/15 | 0,1 kg Portion tatsächlich übertragen, beim Geber abgezogen, während der Übergabe nicht essbar; Bilanz geschlossen. Empfänger→Geber Vertrauen ↑ und „Hilfe erhalten 1“; Geber→Empfänger unverändert (gerichtet). |
| C Verdecktes Ereignis | 15/15 | Ein Wesen 22 m entfernt: keine Erinnerung, keine Beziehungsänderung, keine Deutung. Empfänger und nahes Wesen haben es wahrgenommen. Heilen ohne Verletzung wird abgewiesen. |
| D Belohnungsassoziation | 18/18 | „Arme heben“, 1 s später Gabe, 6×: Häufigkeit 0,67 → 0,87, Konfidenz 0,20 → 0,58 (nach einer Gabe ≤ 0,2), Vorteil zur Grundhäufigkeit +0,41. Die Kontrolle mit Gabe 20 s später ergibt keine Erwartung. Der Beobachter bildet „nach Geste eines anderen“. Zuordnung: Arme heben 0,92, Warten (8 s früher) 0. |
| E Widerspruch | 12/12 | 8× ohne Gabe: Häufigkeit 0,87 → 0,40, größter Schritt 0,106 (begrenzt), 8 Gegenbeispiele, Vorteil 0,41 → 0,17 |
| F Ähnlichkeit und Erfahrung | 9/9 | Ähnlichkeit 0,93 vs 0,41 → Anfangsvertrauen 0,61 vs 0,55. Nach 3 Hilfen des Unähnlichen 0,81 vs 0,61. |
| G Speichern/Laden | 15/15 | Geist, Eingriffsprotokoll, Materialstücke, Bitten und Bilanz gleich; gelernte Bewertung nach dem Laden gleich. Unter 4.5 gleich innerhalb von 10⁻¹² relativ. |

**Weitere Prüfungen (Auswahl):**
- **Persönlichkeit:** reproduzierbar, begrenzt, Mittel 0,499 über 1000 Werte; unverändert nach Ereignissen.
- **Hilfsbereitschaft:** hilfsbereit → geben, wenig hilfsbereit → ablehnen; sehr hungrig gibt nicht ab.
- **Gelernte Vorliebe:** Sie wird versorgt gewählt (`repeat:raise_arms`), bei kritischem Hunger gewinnt `seek_food`.
- **Erklärbarkeit:** Entscheidungen protokollieren ihre Beiträge; Zielbindung, Vorschlags-Schnittstelle (begrenzt, unbekannte Ziele abgewiesen) und Wartezeit gegen sofortige erneute Bitte sind geprüft.
- **Wert eines Geschenks:** hungrig 0,92, satt und vorsichtig −0,04.
- **Göttermenü:**
  - keine Platzierung im Baum, im Körper oder außerhalb; Mengen und Materialien begrenzt;
  - die Vorschau zeigt alle vier Angaben;
  - Nahrung wird extern bilanziert, Material hat die Masse Dichte × Volumen (Kupfer 15,5 kg);
  - Heilen 0,60 → 0,20 Schaden, der Unterarm bleibt fehlend; Heilen von Toten wird abgewiesen;
  - IDs 1, 2, 3.
- **Privatsphäre:** Das zugeordnete Ereignis gelangt nicht in den Geist. Nach Leeren des Ereignisprotokolls bleibt der Geist unverändert.
- **Pause** stoppt das Lernen.
- **Erinnerungen:** Kapazität 64 (238 vergessen); bei der Verdichtung bleibt die Sicherheit beim Minimum.
- **Migration** mit einem echten v0.3.0-Spielstand (50 Wesen, Prothese, Verletzung, ein toter):
  - Original gesichert, Körper und Zustände gleich, Persönlichkeit reproduzierbar;
  - Geist leer, kein Spawner-Aufruf, die Simulation läuft weiter;
  - ein Format-1-Stand mit veränderten Definitionen wird abgewiesen.

## Spontanes Verhalten (nicht geskriptet)
**10 Minuten, 50 Wesen, Startwert 12345, normales Spiel:**
- **Soziales:** 16 Bitten, 2 Gaben auf Bitte, 9 Ablehnungen, 4 verfallen; 13 unaufgeforderte Angebote, davon 6 angenommen.
- **Ereignisse:** 495 verteilte Ereignisse, 8467 Sichtstrahlen, 5901 Beobachtungen.
- **Geist am Ende:** 2000 Erinnerungen und 177 Überzeugungen in 50 Wesen.

Teilen entsteht vor allem, wenn versorgte, hilfsbereite Wesen eine Portion tragen und ein hungriges, geselliges Wesen in der Nähe ist. Bei reichlich Nahrung in der Nähe gehen die meisten lieber selbst zur Quelle (Wegkosten).

**Gefundene und behobene Fehler:**
- Die Konsistenzprüfung im 10-Minuten-Lauf fand zwei Portionen, deren Träger sie „nicht hielt“: Ein laufendes Aufnehmen überschrieb eine gerade erhaltene Gabe. Behoben: `hands_full`; zusätzlich nimmt ein Empfänger, der gerade mit Nahrung beschäftigt ist, nichts an.
- Im 30-Minuten-Lauf hörten hungrige Wesen nach erschöpfter Nahrung nach 3 Erkundungen ganz auf zu suchen. Das war eine Regression gegenüber Prompt 3 und ist behoben (8 s warten, dann erneut suchen).

## Dauerlauf 10 Minuten mit 50 Wesen (in `run_tests.gd`)
| Prüfpunkt | 4.7.2 | 4.5 |
|---|---|---|
| Laufzeit-, Bilanz-, Reservierungs- und Geistesprüfung jede Minute | ohne Befund | ohne Befund |
| Feststeckende Handlungen / Fehlschlagschleifen | 0 / höchstens 2 je Wesen | 0 / höchstens 2 |
| Anfragen / erfolgreich / fehlgeschlagen / abgewiesen | 6804 / 6716 / 17 / 21 | gleich |
| Lebend nach 10 min / gegessen / Rest | 50 / 18,3 kg / 17,3 kg | gleich |
| Speicher | +56 Objekte, +13,7 MB statisch | +13,8 MB |

### Speicher über 30 Minuten (`smoke_life.gd -- 1800`, 4.7.2)
| Zeit | statischer Speicher | Erinnerungen gesamt | Überzeugungen gesamt | Objekte |
|---|---|---|---|---|
| 0 s | 82,4 MB | 0 | 0 | 2737 |
| 300 s | 90,2 MB | 823 | 103 | 2792 |
| 600 s | 96,0 MB | 2034 | 181 | 2793 |
| 900 s | 99,2 MB | 2697 | 248 | 2792 |
| 1200 s | 101,3 MB | 2983 | 309 | 2787 |
| 1770 s | 101,4 MB | 3030 | 311 | 2762 |

Der Zuwachs kommt von den Geistesspeichern und **flacht ab**, wenn sie ihre Kapazität erreichen (64 Erinnerungen je Wesen, höchstens 3200). Es gibt kein unbegrenztes Wachstum.

**Ökologie:** Nach etwa 20 Minuten ist die Nahrung aufgebraucht, danach verhungern Wesen (bis 29,5 Minuten 24 von 50). Das war schon in Prompt 3 so und ist kein ausgeglichenes Ökosystem.

## Leistung (gemessen)
| Größe | Wert | Bedingung |
|---|---|---|
| Simulationstakt, 50 Wesen, Mittel über 10 min | **2,18 ms** (4.7.2) / 2,20 ms (4.5) | headless; Prompt 3: 1,87 ms |
| Simulationstakt, schlechtester | 13–18 ms im 10-min-Lauf, einmal 53 ms im 30-min-Lauf | einzelne Spitzen (Wegsuchen + Entscheidungen + Speicherverwaltung) |
| Anteil am 60-Hz-Budget | ≈ 13 % im Mittel | |
| Bildzeit mit Grafik, 50 Wesen | ≈ 300 ms (≈ 3–4 FPS) | **Software-Rendering, keine GPU** – sagt nichts über deine Grafikkarte |

**Bewertung:**
- Wahrnehmung und Entscheidungen bleiben auch mit Geist effizient: Kandidaten kommen aus dem räumlichen Raster, die Takte sind versetzt, Erinnerungen werden nicht in jedem Bild ausgewertet und alle Listen sind begrenzt.
- Eine Unterstützung für 1000 Wesen wird nicht behauptet.

## Bildschirmfotos
`docs/screenshots/screenshot_life_*.png` (neu in Prompt 5: 10 KI-Panel im SIMULIERT-Modus, 11 Wesenfenster mit Modellplan-Option, 12 Gesprächsansicht – mit dem SIMULIERTEN Testdienst aufgenommen):
- 0 Startbildschirm (mit Geistlabor);
- 1 Übersicht;
- 2 Wesen untersuchen (getrennte Ebenen);
- 3 Entwicklermodus;
- 4 Pause;
- 5 Nacht;
- 6 Göttermenü mit Vorschau und zugeordnetem Ereignis;
- 7 Gabe ausgeführt (Leuchtzeichen, „Arme heben“-Symbol);
- 8 Vergleichsansicht;
- 9 Geistlabor mit Szenario D.

Gesehen wurden Standbilder; die Animation „Arme heben“ in Bewegung ist **ungeprüft**.

**Neu in Prompt 6:** `docs/screenshots/screenshot_werkstatt_*.png` (`tools/capture_workshop.gd`, Versuche gezielt ausgelöst, ohne Ollama):
- 1 Testausrüstung;
- 2 Werkzeug (Stiel + Steinkopf) in der Hand;
- 3 verformte Kupferprobe mit Versuchs-/Gegenstandsansicht (Spielerdiagnose und Wahrnehmung getrennt);
- 4 Wissensansicht;
- 5 Schmelze im Tiegel in der Testheizung;
- 6 glühendes Gussstück in der Form.

Die Bilder zeigten drei Darstellungsfehler, die behoben sind (CHANGELOG). Schlagbewegung, Gießen und Abkühlen in Bewegung sind **ungeprüft** (nur Standbilder).

**Neu in Prompt 6B:** `docs/screenshots/screenshot_werkzeugkette_*.png` (`tools/capture_work_chain.gd`, Ketten gezielt ausgelöst, ohne Ollama; die Simulation wird für jedes Bild angehalten, damit Bild und Zustand übereinstimmen). Ausgewählt (alle 15 Bilder entstehen beim Lauf im Benutzerordner):
- 1 Ausgangslage der Testszene mit Bedienfeld;
- 3 Hammer binden (Haltung „Zusammenfügen“);
- 4 Ausholen mit dem Hammer in der Hand;
- 5 Kontakt: Hammerkopf am großen Stein;
- 7 Bruchstück zweihändig tragen (Hammer liegt sichtbar abgelegt);
- 10 Stein in die Steinreihe setzen;
- 11 fertige Steinreihe (3/3);
- 13 Tiegel in den Testofen setzen;
- 14 Gießen;
- 15 Guss in der Form.

Die Bilder zeigten zwei Darstellungsmängel, die behoben sind: abgeschnittene, kaum unterscheidbare Knopftexte im Bedienfeld (jetzt kurze Beschriftungen) und schwebende Beschriftungen, die in Nahansichten das Bild verdeckten (jetzt feste Bildschirmgröße). Bild 7 wirkt aus der Kameraperspektive einhändig; nachgemessen sitzt das Stück mittig zwischen beiden Griffpunkten (seitlich 0,000 m, Griffe bei ±0,126 m, 0,21 m vor dem Körper). Bewegungsabläufe sind **ungeprüft** (nur Standbilder).

## Was nicht geprüft werden konnte
- Windows, echte GPU, Bildrate auf deiner Hardware.
- Bedienung mit Maus und Tastatur von Hand (Klick auf Position im Göttermenü nur über denselben Strahlaufruf getestet).
- Ob die Entscheidungen „natürlich“ wirken – das ist eine Spielgefühl-Frage. Gemessen sind nur Häufigkeiten und Regeln.
