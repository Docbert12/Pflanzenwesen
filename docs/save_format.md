# Speicherformat (Formatversion 6, seit Alpha 1.1)

Dateien: `scripts/persistence/save_manager.gd`, `save_schema.gd`, `save_migrations.gd`.

## Format 6 auf einen Blick (Alpha 1.1)
Die Datei besteht weiter aus Kopfzeile + Nutzdaten (siehe „Dateiaufbau“). Neu ist der **Aufbau der Nutzdaten**:

```
{
  "format_version": 6,
  "meta":    { game_version, definitions (Fingerabdruck), saved_at_real, map_id, seed, module_order, migrations },
  "modules": { "<modul-id>": { "v": <Abschnittsversion>, … }, … },
  "regions": { "main": { "v": 1, map_id, seed, generator, generator_version, cell_size_m, size, chunk_size,
                         base_hash, current_hash, changed_cells, chunks: { "cx,cy,cz": {n, bytes, data} },
                         water_b64, water_total_m3, world_objects } }
}
```

| Abschnitt (Modul) | Inhalt (Schlüssel wie bis Format 5) |
|---|---|
| `core` | `time_s`, `tick_count`, `registry_next_id`, `sim_rng`, `dev_mode`, `population_initial`, **`rng_streams`** (Zufallsströme je Modul, neu) |
| `actors` | `creatures` (jedes Wesen als Ganzes: Körper, Stoffwechsel, Geist, Pläne, praktisches Wissen), `observation_stats` |
| `actions` | `actions` (laufende Handlungen, Zähler, letzte 50 Ergebnisse) |
| `ecology.food` | `foods`, `items`, `ledger`, `food_rng`, `next_refill_t`, `refill_enabled` |
| `technology` | `material_pieces`, `assemblies`, `heaters`, `experiments`, `thermal` |
| `settlement` | `storages`, `structures` |
| `work` | `work`, `workshop` |
| `social` | `social` |
| `god` | `interventions` |
| `communication` | `communication`, `ai_note` |

Module ohne Zustand (`time.sky`, `technology.tools`, `life`, `mind.perception`, `technology.perception`, `mind.decision`) schreiben keinen Abschnitt.

**Regeln:**
- **Abschnittsversion je Modul** (`"v"`). Beim Laden hebt jedes Modul seinen Abschnitt selbst an (`SimModule.migrate_section`). Die Formatversion 6 bleibt, solange der Kopf sich nicht ändert.
- **Neues Modul, alter Spielstand:** Fehlt der Abschnitt eines Moduls, das seinen Abschnitt als optional kennzeichnet (`section_optional`), lädt der Spielstand mit dem Startzustand dieses Moduls. Es wird nichts erfunden.
- **Kein Teil-Laden:** Abschnitt eines unbekannten Moduls (`unknown_module`), neuere Abschnittsversion (`newer_format`), fehlender Pflichtabschnitt (`invalid`) → der Spielstand wird abgewiesen, bevor irgendetwas geladen ist. Abschnitte werden zuerst alle geprüft und angehoben, dann geladen.
- **Chunk-Deltas:** In der Region stehen nur die gegenüber dem Generator geänderten Zellen, je Chunk als Paare (lokaler Index, Typ), 32-Bit, mit Deflate gepackt und als Base64 abgelegt. Das Grundgelände entsteht beim Laden aus Kartenvorlage + Startwert + Generatorversion; `base_hash` muss stimmen (sonst `world_mismatch`), nach dem Anwenden auch `current_hash`.
- **Ladereihenfolge** (`SimModule.load_order`): Region → `core` → `ecology.food` → `actors` → `technology` → `settlement` → `work` → `social` → `communication` → `god` → `actions`; danach Nacharbeit (`after_load`): nächste freie ID, Pläne der KI, Wärmekontakte und laufende Versuche, Arbeitsketten, Gehaltenes und Positionen; zuletzt die Konsistenzprüfung.
- **Flache Sicht:** `SaveManager.snapshot(life)` bzw. `SaveManager.flat(document)` liefert alle Abschnitte nebeneinander unter den alten Schlüsseln (`creatures`, `foods`, `simulation`, `world` …) – für Vergleiche, Tests und das Menü.
- **Definitionen:** Der Fingerabdruck umfasst jetzt auch `data/maps/`. Ein Spielstand wird geladen, wenn sein Fingerabdruck dem aktuellen entspricht **oder** dem einer ausgelieferten Vorversion (`SaveSchema.SHIPPED_DEFINITIONS`: v0.6.1, alpha-1.1 …). Unbekannte Fingerabdrücke bedeuten veränderte Definitionen → abgewiesen (`definitions_changed`) wie bisher.
- **Eine Datei:** Kopf, Abschnitte und Region liegen noch in einer Datei. Der in der Roadmap (8.8) skizzierte Ordner mit einer Datei je Region und Chunk kommt mit den gestreamten Chunks (Alpha 1.2).

Die folgenden Abschnitte beschreiben Schreiben, Laden und Ladeverhalten; sie gelten unverändert. Wo dort von Feldern der Datei die Rede ist (`creatures`, `world` …), stehen diese seit Format 6 in den oben genannten Abschnitten.

## Ablage
- Spielstand: `user://saves/spielstand.json`. Unter Windows liegt `user://` bei `%APPDATA%\Godot\app_userdata\Pflanzenwesen\`.
- Vorherige gültige Speicherung: `user://saves/spielstand.json.bak`.
- Während des Schreibens entsteht kurz `spielstand.json.tmp`.

## Dateiaufbau
```
Zeile 1:  {"magic":"pflanzenwesen_save","format_version":1,"sha256":"<Prüfsumme Zeile 2>","bytes":…}
Zeile 2:  Nutzdaten als JSON (Schlüssel sortiert, volle Gleitkommagenauigkeit)
```
Die Prüfsumme deckt abgeschnittene und veränderte Dateien auf.

## Schreiben
1. Die Momentaufnahme entsteht **zwischen zwei Takten**. Während eines Takts wird Speichern abgewiesen (`LifeSimulation.stepping`).
2. Die Daten werden in die `.tmp`-Datei geschrieben, die danach **erneut gelesen und vollständig geprüft** wird (Kopfzeile, Prüfsumme, Pflichtfelder).
3. Die bisherige `spielstand.json` wird zu `.bak`. Eine ältere `.bak` wird vorher entfernt.
4. Die `.tmp`-Datei wird in `spielstand.json` umbenannt.

Scheitert Schritt 2, bleibt die alte Datei unberührt. Scheitert Schritt 4, liegt die vorherige Speicherung als `.bak` vor.

## Inhalt
| Feld | Inhalt |
|---|---|
| `format_version` | Speicherformat (5) |
| `game_version` | Programmversion (`application/config/version`) |
| `definitions` | Fingerabdruck aller Definitionsdateien: Gesamt-SHA-256 + SHA-256 je Datei |
| `saved_at_real` | reale Uhrzeit – **nur zur Anzeige** |
| `simulation` | Simulationszeit, Taktzahl, nächste freie Entitäts-ID, Zufallszustände (Simulation, Nahrung; als Text wegen 64 Bit), nächster Nachfüllzeitpunkt, Testoption, Entwicklermodus |
| `world` | Startwert, Größe, Prüfsumme des Grundgeländes, **Terrainänderungen** als Liste `[Zellindex, Typ]` gegenüber dem Grundgelände, Prüfsumme des aktuellen Geländes, **Wasser** (m³ je Spalte, Base64 von float64), Anzahl nicht gespeicherter Bruchstücke |
| `world_objects` | IDs der Weltmassen (Baum, Pflanzen) und **Lebensbaumzustand** (Startwert, Höhe, Position, Wurzelbeet, belegte Spalten; statisch) |
| `foods` | Nahrungsquellen: ID, Art, Excel-Nahrung, Position, **Restmenge**, Startmenge, Energie/Nährstoffe je kg, Pflanzen-Startwert, nachgefüllte Menge |
| `items` | Portionen: ID, Masse, Eigenschaften, Träger-ID oder Bodenposition, Herkunft |
| `creatures` | je Wesen (lebend **und tot**): ID, Name, **Körperplan** (alle Teile mit Status, **Prothesen**), Grundgene, Startwert, **Verletzungen** (Schaden je Teil, Mangelschaden), **Stoffwechsel** (Speicher, Kapazität, Bilanzsummen), Position, Blickrichtung, Tod (Zeit, Ursache, Ort), **getragener Gegenstand**, Wahrnehmungsspeicher, verworfene Ziele, Verhaltenszustand + Grund, **Ziel**, letztes Ergebnis, Zufallszustand, nächste Wahrnehmung/Entscheidung, Erkundungszähler, Verhalten an/aus, Statistik |
| `actions` | laufende Handlungen (ohne Weg), nächste Aktions-/Reservierungs-ID, Zähler, letzte 50 Ergebnisse. **Reservierungen werden nicht gespeichert.** |
| `ledger` | Nahrungsbilanz (Start, Nachfüllung, **göttliche Gaben `god_kg`**, entnommen, gegessen, assimiliert, Abfall) |
| `creatures[].mind` | **(neu in 2)** Persönlichkeit, Erinnerungen, Überzeugungen (α, β, Belege), gerichtete Beziehungen, offene Lern-Erwartungen, Zielbindung, letzte Entscheidung mit Beiträgen, soziale Wartezeiten und Bitten-Eingang, wahrgenommene Eingriffe, Zielvorschläge, `mind_since_t` |
| `social` | **(neu)** offene/abgeschlossene Bitten (Weltseite), Zähler |
| `interventions` | **(neu)** Eingriffsprotokoll mit IDs, Spielerabsicht (nur Diagnose), Beobachterliste, Summen, sichtbare Leuchtzeichen |
| `material_pieces` | Materialstücke (seit 2 aus Eingriffen). **Erweitert in 4:** Form, Maße, Hohlraum, **Wärmeenergie** (Temperatur und Phase folgen daraus), Masse, Position, Träger, Verbund, Rolle, Behälter, **Verformung ε, Schaden, Verschleiß**, Testausrüstung, Herkunft, Verlauf |
| `assemblies` | **(neu in 4)** zusammengesetzte Gegenstände: Bauteil-IDs, Abstände, **Verbindungen** (Methode, Teile, Bindemittel, Belastbarkeit, Verschleiß, Schläge, Passung, Geschick), Griff-/Kopfteil, Träger, Bezeichnung |
| `heaters` | **(neu in 4)** Testheizungen (Leistung, Position, eingesetzter Behälter) |
| `thermal` | **(neu in 4)** Wärmebilanz: Umgebungs- und Körperenergie, **Wärmekontakte** (Leitwerte, z. B. Tiegel↔Probe, Guss↔Form, Griff), Heizungen mit zugeführter Energie |
| `experiments` | **(neu in 4)** Versuchsprotokolle (Ausgangslage Simulation und Wahrnehmung, Schritte geplant/ausgeführt, Aufwand, Ergebnisse, Fehlschläge, Herkunft), nächste ID, Statistik |
| `workshop` | **(neu in 4)** nur in der Testwerkstatt: Rollen → IDs der Testausrüstung; im normalen Spiel leer |
| `creatures[].held_object_id`, `creatures[].mind.tech` | **(neu in 4)** gehaltener Gegenstand; **Verfahrenswissen** (Stufe, Herkunft, Voraussetzungen, Schritte, Materialbereich, eigene/beobachtete/gehörte Fälle mit Quellen, Sicherheit, Versionen), Hypothesen, bekannte Gegenstände (wahrgenommene Eigenschaften), Versuchsbudget, **Unterrichtsfortschritt** (angeboten, erklärt, gelehrt, zusehend) |
| `storages` | **(neu in 5)** Lagerplätze: Position, Größe, Kapazität (kg, m³), Inhalt (Stück-IDs), Herkunft, Verlauf |
| `structures` | **(neu in 5)** Baustellen/Einzelbauwerke: Bauplan, Position, Richtung, Plätze mit Bauteil-ID, Initiator, Status, Verlauf |
| `work` | **(neu in 5)** Arbeitsketten (Ziel, Herkunft, autonom, Schritte mit Status, Werkzeug, Zielobjekt, Bestimmung, erzeugte/abgelieferte Stücke, Masse, Abweisungen, Abbruch-/Pausegrund, Verlauf), offene Kette je Wesen, Abklingzeiten, Statistik, geprüfte Modellvorschläge, ausstehendes Ablegen |
| `material_pieces[].storage_id/structure_id`, `creatures[].hold_mode/hold_side` | **(neu in 5)** eingelagert in / verbaut in; Halten mit einer oder beiden Händen und Seite |
| `observation_stats` | Zähler der Ereignisverteilung (nur Leistung/Diagnose) |
| `creatures[].mind.ai` | **(neu in 3)** angenommener Plan (Schritte mit Status/Ergebnis, Quelle Ollama/SIMULIERT, Unsicherheit, Modellbegründung), letzte 5 Pläne mit Ergebnis, gesperrte gescheiterte Plansignaturen, Modelldeutungen (≤ 8), **Hörensagen** mit Sprecher, Ursprung, Kette, Vertrauen beim Hören, Status, Widersprüchen; leer gesehene Quellen, Gesprächs-Wartezeiten, Mindestabstand bis zur nächsten Anfrage, Fehlschlagserie, letzte Anfrage (nur Diagnose) |
| `communication` | **(neu in 3)** Gesprächsprotokoll (≤ 200 Äußerungen), nächste Äußerungs-ID, Zähler |
| `ai_note` | **(neu in 3)** Klartext: was gespeichert ist und was nicht |

**Nicht gespeichert (Format 3):** offene Modellanfragen, Netzwerkverbindungen, Warteschlange, Modellname, Dienstadresse, Zugangsschlüssel. Modell und Adresse sind Anwendungseinstellungen (`user://ai_settings.json`); ein Spielstand lädt ohne Modell und ohne Ollama.

Es werden keine Node-Referenzen gespeichert, nur Daten. Darstellung, Netze, Kollision und Wege werden beim Laden neu erzeugt.

## Laden
1. Kopfzeile, Prüfsumme, JSON → sonst **„beschädigt“** (Code `corrupt`) mit verständlicher Meldung. Im Menü erscheint dann „Sicherung laden“, falls eine gültige `.bak` existiert.
2. Formatversion über `SaveMigrations.migrate`:
   - größer als 4 → **abgewiesen** (`newer_format`), nicht ungeprüft geladen;
   - 1, 2 oder 3 → Migration (siehe unten); kleiner als 1 → ungültig;
   - fehlende Migrationsstufe → abgewiesen (`no_migration`).
3. Pflichtfelder und Typen prüfen (`invalid`).
4. **Definitionsfingerabdruck** vergleichen (siehe unten) → bei Abweichung abgewiesen (`definitions_changed`), mit Liste der geänderten Dateien.
5. Laden geht nur in eine **frische** Welt: leeres Register, kein laufendes Spiel. Sonst wird abgewiesen (`not_fresh`); so entsteht keine doppelte Registrierung. In der Szene erzeugt „Laden“ deshalb immer eine neue Szeneninstanz.
6. Welt aus dem Startwert neu erzeugen. Prüfsumme des Grundgeländes und IDs der Weltobjekte müssen übereinstimmen, sonst `world_mismatch` (Weltgenerator geändert).
7. Terrainänderungen anwenden; anschließend aktuelle Gelände-Prüfsumme kontrollieren, Netze neu bauen, Navigation neu berechnen, Wasser übernehmen.
8. Uhr und Zufallszustände setzen. Nahrung, Portionen und Wesen werden **mit ihren gespeicherten IDs** registriert. Der `PopulationSpawner` wird **nie** aufgerufen; das ist mit einem Zähler getestet.
9. Handlungen nach dem Ladeverhalten (siehe unten).
9a. **(neu in 3)** Modellanbindung: neue Sitzungsnummer, Warteschlange leer, offene Anfragen der alten Welt abgebrochen bzw. ihre Antworten verworfen; eine beim Speichern offene Anfrage erscheint beim Wesen als „beim Laden verworfen“. **Angenommene Pläne werden neu geprüft** (Nahrungsziele noch bekannt, Zielwesen leben); ungültige scheitern mit Grund. Pläne halten keine Reservierungen – diese hängen nur an Handlungen (siehe unten).
9b. **(neu in 4)** Gegenstände: Materialstücke werden als physikalische Objekte mit ihrer Wärmeenergie registriert, danach Verbünde, Testheizungen, Wärmekontakte und Bilanzposten. **Laufende Versuche** werden als „unterbrochen“ abgeschlossen. Das geschieht ohne rückwirkende Auswertung und ohne Fortsetzung mit veralteten Annahmen. Laufende Technik-Handlungen werden kontrolliert abgebrochen (siehe unten). Gehaltene Gegenstände werden mit dem Halter abgeglichen.
10. Konsistenzprüfung (`audit`, einschließlich `ConstructionSystem.audit`). Geprüft wird: kein Teil doppelt, kein Teil gleichzeitig einzeln und im Verbund, Verbindungen verweisen auf vorhandene Teile, höchstens ein Träger, Inhalte in genau einem Behälter, Masse nicht negativ. Bei Befund wird das Spiel nicht gestartet (`inconsistent`).

**Keine Offline-Zeit:** Die Simulationszeit ist exakt die gespeicherte; `saved_at_real` wird nie verrechnet (getestet).

## Ladeverhalten laufender Handlungen
| Handlung | Beim Laden | Grund |
|---|---|---|
| `move_to` | **fortgesetzt, Weg neu geplant** (Neuplanungszähler 0) | Wege werden nicht gespeichert; das Terrain könnte anders sein |
| `wait` | **fortgesetzt** mit gespeicherter Restdauer | keine Ressourcen beteiligt |
| `eat` getragener Portion | **fortgesetzt** | Portion gehört dem Wesen, keine Reservierung |
| `eat` direkt an der Quelle | **kontrolliert abgebrochen** | hing an einer Reservierung |
| `pick_up` | **kontrolliert abgebrochen** | hing an einer Reservierung |
| `drop` | **kontrolliert abgebrochen** | kurz, nicht unterbrechbar; das Wesen entscheidet neu |
| `raise_arms` | **fortgesetzt** | keine Ressourcen beteiligt |
| `request_food`, `decline_request` | **kontrolliert abgebrochen** | Geste kurz; die offene Bitte selbst ist gespeichert und verfällt regulär |
| `offer_food`, `give_food` | **kontrolliert abgebrochen** | hingen an einer Reservierung der getragenen Portion; die Portion bleibt beim Geber |
| `talk` | **kontrolliert abgebrochen** | die Äußerung war noch nicht zugestellt; sie erscheint als „abgebrochen“ |
| `inspect_object`, `equip_tool`, `strike_target`, `deform_material`, `connect_parts`, `disconnect_parts`, `place_in_heater`, `pour_into_mold`, `demonstrate_procedure`, `practice_procedure` | **kontrolliert abgebrochen** | hingen an Reservierungen; **der Zwischenstand bleibt**: ausgeführte Schläge, verbrauchte Energie, eine bereits stehende Verbindung, ein Tiegel in der Heizung (heizt weiter). Ein nicht abgeschlossenes Verbinden hat noch keine Fasern verbraucht |

- Prüft eine fortgesetzte Handlung beim Laden nicht mehr gültig (z. B. fehlende Fähigkeit), wird sie ebenfalls abgebrochen.
- Abbrüche erscheinen im Ereignisprotokoll (`action_cancelled_on_load`) und im letzten Ergebnis des Wesens (`cancelled_on_load`). Das Wesen entscheidet sofort neu.
- **Reservierungen:** Alle werden beim Laden **freigegeben**, keine wird wiederhergestellt. Die freie Menge jeder Quelle ist danach gleich ihrer Restmenge (getestet).

## Geänderte Excel-Definitionen (Strategie)
**Streng:** Jede Änderung einer Definitionsdatei führt zur Abweisung. Das betrifft:
- `data/generated/excel/*.json` (außer `_manifest.json` mit Zeitstempel),
- `data/materials/*.json`,
- `data/config/life.json`, `mind.json`, `world.json`, `voxel_palette.json`, `creature_defaults.json`, `material_mapping.json`, `technology.json` (seit 4),
- `data/settings/simulation.json`.

Die Meldung nennt die geänderten Dateien.

**Gründe:**
- Werte wie Nährwert, Materialdichte oder Körperproportionen stecken bereits in gespeicherten Zuständen (Energie, Masse).
- Eine stille Übernahme würde Bilanzen und Körper inkonsistent machen.

**Nicht enthalten:** `implementation_status.json` (nur beschreibend) sowie `data/settings/ai.json` und `data/ai/*` (Anwendungseinstellungen bzw. Schnittstelle zum Modell; ändern keine gespeicherten Zustände).

**Später möglich:** Eine echte Migration (`MIGRATIONS[1] = …`) oder eine Einteilung in verträgliche und unverträgliche Änderungen. Beides ist bewusst noch **nicht** gebaut.

**Folge für dich:** Nach einem erneuten Excel-Import mit inhaltlichen Änderungen sind alte Spielstände nicht mehr ladbar. Das ist so gewollt.

## Migrationen
`SaveMigrations.MIGRATIONS = {1: "_migrate_1_to_2", 2: "_migrate_2_to_3", 3: "_migrate_3_to_4", 4: "_migrate_4_to_5"}`. Stufen werden nacheinander angewendet (1 → 2 → 3 → 4 → 5); nur die **letzte** Stufe vergleicht mit den aktuellen Definitionen, die Zwischenstufen setzen den Fingerabdruck der jeweils ausgelieferten Version; fehlt eine, wird abgewiesen. Vor jeder Migration entsteht eine unveränderte Kopie `spielstand.json.vN.vor_migration` (N = Ausgangsformat).

### Format 1 (v0.3.0) → Format 2 (v0.4.0)
**Vor dem Laden** legt `SaveManager.load_into` eine unveränderte Kopie `spielstand.json.v1.vor_migration` an. Gelingt das nicht, wird nichts geladen.

**Voraussetzungen:**
- Der Spielstand wurde mit den **unveränderten Definitionen von v0.3.0** gespeichert (Fingerabdruck in `V1_KNOWN_DEFINITIONS`).
- Die aktuellen Definitionen sind die **mit v0.4.0 ausgelieferten** (`V2_SHIPPED_DEFINITIONS`; ein Test prüft, dass dieser Wert stimmt).

Andernfalls wird nicht migriert (`definitions_changed`): Der Spielstand bleibt unangetastet, eine stille Übernahme gibt es nicht. Hintergrund: In v0.4.0 kamen `mind.json` und eine Armfunktion („Arme heben“) in `life.json` hinzu, und die Statusangaben wurden neu importiert. Genau diese bekannten Änderungen deckt die Migration ab.

**Ablauf:**
- **Persönlichkeit:** Jedes Wesen erhält Persönlichkeitswerte aus seinem Körper-Startwert, mit derselben Funktion wie bei „Neues Spiel“, also reproduzierbar.
- **Erinnerungen, Überzeugungen, Beziehungen:** Sie bleiben **leer**. Es werden **keine historischen Erinnerungen erfunden**. `mind_since_t` = gespeicherte Simulationszeit; die Vergangenheit davor bleibt unbekannt (im Beobachtungsfenster: „bekannt seit t = …“).
- **Unverändert übernommen:** Körper, Verletzungen, Prothesen, Stoffwechsel, Positionen, Nahrung, Bilanz, Gelände, Wasser, Handlungen und Zufallszustände.
- **Neue, leere Bereiche:** soziale Bitten, Eingriffsprotokoll, Materialstücke, `god_kg = 0`.
- **Vermerk:** `migration` mit Herkunftsversion und altem Fingerabdruck.

**Getestet** mit einem echten Spielstand aus v0.3.0 (`tests/fixtures/save_v1_prompt03.json`: 50 Wesen, Prothese, Verletzung, ein totes Wesen):
- Laden gelingt, das Original ist gesichert;
- Körper und Zustände sind gleich, die Persönlichkeit ist reproduzierbar, der Geist ist leer;
- die Bilanz ist geschlossen, der Spawner wurde nicht aufgerufen;
- die Simulation läuft weiter.

Ein Format-1-Stand mit verändertem Fingerabdruck wird abgewiesen.

Seit 0.5.0 setzt die Stufe 1→2 den Fingerabdruck auf den von v0.4.0 (`V2_SHIPPED_DEFINITIONS`); die Stufe 2→3 übernimmt danach. Ein v0.3.0-Stand läuft so durch beide Stufen.

### Format 2 (v0.4.0) → Format 3 (v0.5.0)
**Voraussetzungen:** Spielstand mit den ausgelieferten v0.4.0-Definitionen (`V2_KNOWN_DEFINITIONS`) und aktuelle Definitionen = ausgelieferte v0.5.0-Definitionen (`V3_SHIPPED_DEFINITIONS`, per Test geprüft). Geändert hat sich `mind.json` (neue Abschnitte `plans`, `ai_triggers`, `communication`, `hearsay`).

**Ablauf:** Jedes Wesen erhält leere Plan-/Gesprächsdaten (kein Plan, kein Hörensagen, keine Modellnotizen, keine Wartezeiten); neues leeres Gesprächsprotokoll; Vermerk `migration_2_3`. **Nichts wird erfunden.** Alles andere – Körper, Geist (Persönlichkeit, Erinnerungen, Vermutungen, Beziehungen), Welt, Handlungen – bleibt unverändert.

**Getestet** mit einem echten Spielstand aus v0.4.0 (`tests/fixtures/save_v2_prompt04.json`, vor jeder Codeänderung mit `tools/make_save_fixture.gd` erzeugt: 50 Wesen, 90 s gespielt): lädt, Original gesichert, Spawner nicht aufgerufen, Erinnerungen und Persönlichkeit identisch, keine erfundenen Pläne/Gespräche, Prüfung ohne Befund, Simulation läuft weiter. Ein Format-2-Stand mit verändertem Fingerabdruck wird abgewiesen.

### Format 3 (v0.5.x) → Format 4 (v0.6.0)
**Voraussetzungen:** Spielstand mit den ausgelieferten v0.5.x-Definitionen (`V3_KNOWN_DEFINITIONS`), aktuelle Definitionen = ausgelieferte v0.6.0-Definitionen (`V4_SHIPPED_DEFINITIONS`, per Test geprüft). Geändert haben sich:
- Materialdateien: neuer Abschnitt `working`, neue Materialien `plant_fiber` und `ceramic`;
- neue Datei `technology.json`;
- `mind.json`: Auslöserpriorität `experiment`, Göttermenü-Material `plant_fiber`.

**Ablauf:**
- Materialstücke erhalten die Wärmeenergie bei Umgebungstemperatur (293,15 K), ihre Würfelmaße und leere Werte für Träger, Verbund, ε, Schaden und Verschleiß. Die **Masse bleibt exakt**.
- Jedes Wesen erhält `held_object_id = 0` und **leeres** Verfahrenswissen: keine Verfahren, keine Hypothesen, keine bekannten Gegenstände.
- Neu und leer: Verbünde, Heizungen, Versuche (Statistik mit Nullen), Wärmebereich.
- Vermerk `migration_3_4`.

**Keine rückwirkend geschenkten Entdeckungen.**

**Getestet** mit einem echten Spielstand aus v0.5.1 (`tests/fixtures/save_v3_prompt05.json`). Er wurde vor jeder Codeänderung mit `tools/make_save_fixture.gd --mit-material` erzeugt: 50 Wesen, 90 s gespielt, Materialstücke aus dem Göttermenü. Ergebnisse:
- lädt, das Original ist gesichert (`.v3.vor_migration`), der Spawner wurde nicht aufgerufen;
- Materialstücke sind massengleich bei 293,15 K;
- es gibt kein Wissen, keine Werkzeuge und keine Versuche;
- die Simulation läuft weiter, auch mit eigenen Versuchen an den migrierten Stücken, und die Prüfung ist ohne Befund.

v1- und v2-Prüflinge laufen durch die ganze Kette 1→2→3→4.

Seit 0.6.1 prüft die Stufe 3→4 die aktuellen Definitionen nicht mehr (sie setzt den Fingerabdruck auf `V4_SHIPPED_DEFINITIONS`); die Stufe 4→5 übernimmt danach.

### Format 4 (v0.6.0) → Format 5 (v0.6.1)
**Voraussetzungen:** Spielstand mit den ausgelieferten v0.6.0-Definitionen (`V4_KNOWN_DEFINITIONS`), aktuelle Definitionen = ausgelieferte v0.6.1-Definitionen (`V5_SHIPPED_DEFINITIONS`, per Test geprüft). Geändert haben sich `technology.json` (Abschnitte `motion`, `storage`, `structures`, `containers`, `work`, `hands.carry_two_max_width_m`), `mind.json` (Auslöserpriorität `work`), die neu importierten Excel-Definitionen (Importkonfiguration: Voxeltyp-Verweise, Projektentscheidungen, Statusnotizen) und `implementation_status.json`.

**Ablauf:** Materialstücke erhalten `storage_id = 0`, `structure_id = 0`; Wesen erhalten `hold_mode = "one"`, wenn sie etwas halten (sonst leer), und `hold_side`; neu und leer: Lager, Bauwerke, Arbeitsketten. Vermerk `migration_4_5`. **Nichts wird erfunden** (keine Lager, keine Baustellen, keine Ketten).

**Getestet** mit zwei echten v0.6.0-Spielständen, die vor jeder 6B-Codeänderung erzeugt wurden: `tests/fixtures/save_v4_prompt06.json` (normales Spiel, 50 Wesen, Göttermenü-Material) und `tests/fixtures/save_v4_prompt06_werkstatt.json` (Testwerkstatt mit Verbünden, Heizung, Versuchen; `tools/make_workshop_fixture.gd`). Beide laden, das Original ist gesichert (`.v4.vor_migration`), Stücke, Masse, Verbünde und Wesen sind unverändert, danach wird im Format 5 gespeichert und unverändert wieder geladen; Prüfung ohne Befund. v1-, v2- und v3-Prüflinge laufen durch die ganze Kette.

**Für spätere Versionen:** `V5_SHIPPED_DEFINITIONS` bei Definitionsänderungen neu eintragen (`tools/print_definitions_fingerprint.gd`) und eine Stufe 5→6 ergänzen.

### Format 5 (v0.6.1) → Format 6 (Alpha 1.1)
- **Voraussetzung:** Spielstand mit den ausgelieferten Definitionen von v0.6.1. Die aktuellen Definitionen dürfen neuer sein (ab Format 6 heben die Module ihre Abschnitte selbst an).
- **Reine Umordnung:** Die flache Datei wird in Kopf, Modulabschnitte (alle Version 1) und die Hauptregion zerlegt. Kein Inhalt wird erfunden oder verworfen; frühere Migrationsvermerke wandern nach `meta.migrations`.
- **Welt:** Karte „lichtung“ (Generator `lichtung_v0`, Version 1). Die Liste der Terrainänderungen wird in Chunk-Deltas (Chunks 16 × 32 × 16) umgerechnet.
- **Zufallsströme je Modul:** leer (gab es nicht).
- **Getestet mit drei echten Spielständen aus v0.6.1**, erzeugt vor jeder Codeänderung von Alpha 1.1: normales Spiel (50 Wesen, mit Göttermaterial), Testwerkstatt (laufender Heizversuch), Testszene Werkzeugkette **mitten in einer Kette** (`tests/fixtures/save_v5_v061*.json`). Geprüft: Inhalt unverändert, Zeit, IDs, Zufallszustände, Gelände und Wasser erhalten, Original gesichert (`….v5.vor_migration`), die laufende Kette wird nach dem Laden zu Ende geführt, danach Speichern im Format 6 und erneutes Laden ohne Migration.
- Das Ladeverhalten ist unverändert: laufende Handlungen werden fortgesetzt, neu geplant oder kontrolliert abgebrochen; laufende Versuche werden als „unterbrochen“ beendet.

## Bekannte Grenzen
- **Bruchstücke** (abgelöste Terrainteile als Godot-Körper) werden nicht gespeichert. Ihre Anzahl steht in `fragments_not_saved`. In der Lebenssimulation gibt es keine Terrainbearbeitung durch den Spieler, daher entstehen dort keine.
- **Ereignisprotokoll:** Es wird nicht gespeichert, nach dem Laden beginnt es neu mit `game_loaded`. Die letzten 50 Handlungsergebnisse bleiben erhalten.
- **Spielstand:** Es gibt genau einen Spielstand (keine Spielstandauswahl). Die Testwerkstatt speichert getrennt unter `user://saves/werkstatt.json`.
- **Laufende Versuche** werden beim Laden nicht fortgesetzt, sondern als „unterbrochen“ abgeschlossen. Der physikalische Zustand (z. B. Tiegel in der Heizung) läuft weiter.
- **Laufende Arbeitsketten** werden nach dem Laden **fortgesetzt**: Die vor dem Speichern laufende Handlung wird wie jede Handlung abgebrochen, der aktuelle Schritt wird aus dem Weltzustand neu geprüft (nichts wird doppelt ausgeführt). Die Testszene Werkzeugkette speichert getrennt unter `user://saves/werkzeugkette.json`.
