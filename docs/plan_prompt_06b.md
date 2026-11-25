# Prompt 6B – Arbeitsplan, Entscheidungen und Abschluss

> **Abgeschlossen am 2026-11-25 – ausgeliefert als v0.6.1.** Dieses Dokument bleibt als Begründung der Entscheidungen erhalten (Abschnitte 1–3, 6–9). Die Abschnitte 0, 4 und 5 beschreiben den Zwischenstand der Pause am 2026-11-24 und sind **erledigt**; was tatsächlich umgesetzt wurde, steht in `CHANGELOG.md` (0.6.1), `docs/work_chains.md`, `docs/animations.md` und `docs/test_results.md`.
>
> Abweichungen vom Plan bei der Umsetzung:
> - Tragen mit zwei Händen gilt jetzt auch für zu **breite** Stücke (`carry_two_max_width_m` 0,4 m), nicht nur für zu schwere.
> - Vor dem Gießen vereinigen sich gleichartige, vollständig flüssige Stücke im Tiegel (`MaterialProcessSystem.merge_melts`), sonst blieb ein Teil der Schmelze zurück.
> - Gehaltene Gegenstände sitzen am **Griffpunkt** der animierten Hand (Griffrahmen aus `WorkPose.tool_frame`), nicht am Handgelenk-Pivot.
> - Modellvorschläge (`work`) werden zur Option `work:model`, die das `DecisionSystem` wie jede andere abwägt.
> - Unterbrochene, gezielt ausgelöste Ketten setzen nach `resume_after_s` (2 s) selbst fort.

## 0. So ging es weiter (Zwischenstand 2026-11-24 – erledigt)

1. Nutzer schreibt: „Pflanzenwesen, Repository Docbert12/Pflanzenwesen, weiter mit Prompt 6B (Zweig wip/prompt-06b)“.
2. Repository anbinden und klonen; danach den Arbeitszweig holen:
   `git fetch --depth=1 origin wip/prompt-06b && git checkout -b wip/prompt-06b FETCH_HEAD`
3. Godot 4.7.2 und 4.5 laden (GitHub `godotengine/godot-builds`, Release `4.7.2-stable` bzw. `4.5-stable`, Datei `Godot_v<ver>_linux.x86_64.zip`) nach `/home/claude/tools/godot/`, dann `godot --headless --path . --import`.
4. **Prüflinge NICHT neu erzeugen** – sie liegen schon im Repository und stammen vom unveränderten v0.6.0-Code (siehe Abschnitt 1). Der Code auf dem Arbeitszweig ist bereits verändert.
5. Mit Abschnitt 5 („Noch offen“) in der dort genannten Reihenfolge weitermachen.

Der Zweig `main` ist unverändert v0.6.0 (plus Dokumente, Prompt-Texte, Prüflinge, Werkzeug `tools/make_workshop_fixture.gd`) und bleibt lauffähig. Der Arbeitszweig `wip/prompt-06b` **kompiliert noch nicht vollständig** (fehlende Klasse `WorkSystem`, siehe Abschnitt 4).

## 1. Ausgangsbasis (geprüft am 2026-11-24)

| Prüfung | Ergebnis |
|---|---|
| Vollständige Tests v0.6.0, Godot 4.7.2 | **432/432 bestanden** (450 s) |
| Vollständige Tests v0.6.0, Godot 4.5 (frischer Ordner) | **432/432 bestanden** (446 s) |
| Prüfling normales Spiel | `tests/fixtures/save_v4_prompt06.json` – Format 4, 90 s, 50 Wesen, 3 Materialstücke über das Göttermenü, Definitionen `6303a08d…` (= `V4_SHIPPED_DEFINITIONS`), Version 0.6.0-prototype |
| Prüfling Testwerkstatt | `tests/fixtures/save_v4_prompt06_werkstatt.json` – Format 4, 21 s: Hammer gebaut (Versuch 2 abgeschlossen), Versuch 5 läuft (Kupfer im Tiegel in der Testheizung), Verfahrenswissen vorhanden. Erzeugt mit `tools/make_workshop_fixture.gd` |

## 2. Auftrag

- Haupttext: `design/prompts/prompt_06b_excel_animationen_herstellung.txt` (Excel-Abgleich, sichtbare Arbeitsanimationen, eigenständige einfache Herstellung, Testszene, Fehlerfälle).
- Verbindlicher Zusatz und **Abschlusskriterium**: `design/prompts/prompt_06b_zusatz_werkzeug_materialkette.txt` (Hammer bauen → aufnehmen/ausrüsten → sichtbar am Griffpunkt halten → schlagen mit Kontakt genau einmal → Bruchstücke mit Masse/Temperatur → aufnehmen → tragen → lagern **oder** verbauen **oder** im Testofen schmelzen; Anzeige Ziel/Handlung/Werkzeug-ID/Zielobjekt/Menge/Fortschritt/Abbruchgrund; autonomer Durchlauf getrennt dokumentiert).
- Wunsch des Nutzers (2026-11-24): Die Excel ist eine **Leitlinie**. Die Wesen sollen sich **selbst** von der Steinzeit bis in die Zukunft entwickeln: vom Steinhammer über Schmelzen und Legieren bis zu Abbauwerkzeugen (siehe Abschnitt 8).
- Alle weiteren Prompt-Texte liegen jetzt in `design/prompts/` (7, 8, 9, 10, 11, 12, 13 und `prompt_zusatz_weltarchitektur_abbau_bauen.txt`).

## 3. Bestandsprüfung (Ergebnis, aus Code gelesen)

**Vorhanden (v0.6.0):** Handlungen `equip_tool`, `strike_target`, `deform_material`, `connect_parts` (Umwickeln), `place_in_heater`, `pour_into_mold`, `drop` (auch für Gegenstände); Bruch mit exakter Massen-/Energieaufteilung (`MaterialProcessSystem.fracture_piece`); Kupfer plastisch verformbar; Testheizung, Tiegel mit Griff, Gussform (nur Testwerkstatt); Versuchssystem mit Vorgang „bring“; `DecisionSystem` als einziger Entscheider; Verfahrenswissen je Wesen.

**Fehlte vor 6B (Befund):**
- Keine Animation für Technikhandlungen: `LivingWorld._sync_views` kennt nur move_to/pick_up/eat/raise_arms/give – Schlagen, Verbinden, Gießen zeigen die **Ruhehaltung**.
- Gehaltene Gegenstände sitzen an einem festen Punkt vor dem Körper (`ToolUseSystem.hand_position`), nicht am Handgelenk.
- Schlagkontakt nicht synchronisiert: Schaden am Ende jeder Schwungdauer, keine sichtbare Kontaktphase; Reichweite 1,1 m → sichtbar „Hämmern neben dem Ziel“.
- Nur eine Hand-Belegung (`held_object_id`); schwere Stücke können nicht mit zwei Händen getragen werden.
- Kein Lager, keine Baustelle, keine Arbeitskette aus Bedarf, keine Arbeitsanzeige.
- Bruchstücke verlieren Testausrüstungs-Kennzeichen und Behälter; Stein/Holz würden in der Heizung erhitzt (keine Schmelz-Eignungsprüfung).
- Animator: Gelenke `legs` hängen am Rumpf (`parent: torso`) → bei Rumpfneigung Beine gegensteuern.

**Excel `Pflanzenwesen_Voxel_Datenbasis.xlsx`** (die vom Nutzer geschickte Datei ist bytegleich mit `design/`): Der vorhandene Importer meldet bereits alle im Prompt genannten Probleme (`reports/import_report.md`): MAT_Erde/MAT_Gras/MAT_Holz fehlen (3 Fehler, Zeilen abgewiesen), Kupfer→MAT002 = Cellulose_rein (Warnung), Fortpflanzung −1 Nachkommen (Fehler) und Verweis auf „12_Vererbung“ statt „13_Vererbung_Genetik“, Setzling-Körperteile. Noch zu tun: dokumentierte **Importkonfiguration** mit Korrekturen (Abschnitt 5, Schritt 7).

**Excel `Erfindungen_Echt_nach_Kategorien.xlsx`** (neu, Original des Nutzers unverändert in `design/` abgelegt, MD5 914666d6…; vom Importer noch nicht verarbeitet): 12 Kategorien, 5.862 Zeilen, nur 2.774 verschiedene Namen; dieselben Erfindungen bis zu 18-mal über die Zeitalter; ab der Mitte erzeugte Fantasienamen („Quanten- Kupferaxt 6“, „KI-gestützt Hochofen 22“); falsche Zeitalter (Dampfmaschine/Hochofen in der Bronzezeit, Buchdruck in der Kupferzeit, Rad/Kalender in der frühen Steinzeit, Bronzelegierung in der Mittelsteinzeit); Effekte sind Zufallsboni (55 verschiedene, z. B. „+70 % alle Ressourcen“); alle Beschreibungen derselbe Mustersatz; es fehlen Hammer, Töpferei/Keramik, Blasebalg, Seil/Schnur, Guss, Lager, Korb. → Als **Katalog** importieren (Name, Kategorie, Quellenzeile, Beschreibung, Stufe als Metadatum), Effekte nie anwenden, nur gleichwertige Einträge zusammenfassen (gleicher Name **und** gleiche Kategorie), erzeugte Namen kennzeichnen.

## 4. Umgesetzt bis zur Pause am 2026-11-24 (Zweig `wip/prompt-06b`)

| Datei | Inhalt |
|---|---|
| `scripts/agents/creature.gd` | `hold_mode` ("" / "one" / "two"), `hold_side`; gespeichert; beim Tod Arbeitskette abbrechen (`ctx.work.abort`) |
| `scripts/ecology/material_piece.gd` | `storage_id`, `structure_id` (gespeichert); `is_free()` berücksichtigt Verbautes |
| `scripts/world/life_context.gd` | `storages`, `structures`, `work: WorkSystem`; `position_of` kennt Lager und Bauwerke |
| `scripts/technology/tool_use_system.gd` | `grasp_hands`, `carry_limit_two_kg`, `check_carry` (zu schwer für eine Hand → beide Hände, sonst nachvollziehbar ablehnen), `hold(…, mode)`, `release_at(pos)`, `hand_position` je Seite/zweihändig, verbautes Stück nicht greifbar, Lager-Entnahme beim Greifen; Heizung weist ungeeigneten Inhalt ab |
| `scripts/physics/material_process_system.gd` | `melt_support(material, behälter)` – Schmelzen keine universelle Recyclingaktion (Stein „nur fest“, Holz/Fasern brennbar → abgewiesen, Behältergrenze); Bruch überträgt Testausrüstung, Behälter, Verlauf, Lager/Bauwerk-Austrag |
| `scripts/technology/construction_system.gd` | `connect_lashing(…, quality)` für die einarmige Variante |
| `scripts/settlement/storage_place.gd`, `storage_system.gd` | reales Lager: Kapazität Masse/Volumen/Platzraster 0,2 m, Temperaturgrenze, Einlagern/Entnehmen nur durch Tragen, Audit, Wahrnehmung |
| `scripts/settlement/structure.gd`, `structure_system.gd` | Baustelle + Einzelbauwerk „Steinreihe“ (3 Plätze, Stein 0,12–2,2 kg), Platzprüfung, Untergrund, messbare Funktion (`evaluate`), Audit, Wahrnehmung |
| `scripts/animation/work_pose.gd` | Geometrie der Arbeitsbewegung aus Körperplan + Werkzeug (Schulter, Arm, Beine, Kopfabstand), Kontaktpose (Rumpfneigung, Hocke, Arm-/Handwinkel), Standpunkt, Körper↔Welt |
| `scripts/actions/work_motion.gd` | Phasen approach→prepare→work(contact)→recover, Anlauf mit Voxelprüfung, Animationsangabe `a.state.anim`, Händeprüfung (zweihändig/einarmig/ablehnen) |
| `scripts/actions/implementations/tech_action_util.gd` | `strike_series` neu: Anlauf zum Standpunkt (Kopf trifft das Ziel), Ausholen über die Schwungdauer, **genau ein Kontakt je Schlag** (`a.state.contacts`), Rückkehrphase |
| `equip_tool_action.gd` | Anlauf → greifen → aufnehmen (genau einmal) → aufrichten; `params.carry` = Tragen (ggf. zweihändig) |
| `drop_action.gd` | sichtbares Ablegen am Kontaktpunkt vor dem Wesen (`put_down_point`) |
| `connect_parts_action.gd` | Anlauf, Animation „assemble“, einarmige Variante (×1,8 Zeit, Passung ×0,8) |
| `place_in_heater_action.gd`, `pour_into_mold_action.gd` | Animationsangaben; Heizung prüft Schmelzeignung des Inhalts |
| **neu** `deposit_in_storage_action.gd`, `place_building_part_action.gd`, `put_into_container_action.gd` | Einlagern, Verbauen, in den Tiegel legen – je mit Anlauf, Pose, Übergabe genau einmal, Prüfungen |
| `action_definition.gd`, `action_executor.gd` | drei neue Handlungstypen registriert (TECH_TYPES, Labels, on_load cancel) |
| `data/config/technology.json` | neue Abschnitte `motion`, `storage`, `structures`, `containers`, `work` (alle Spielparameter dokumentiert) |

**Stand der Pause (erledigt):** `LifeContext` und `Creature` verwiesen auf die damals noch fehlende Klasse `WorkSystem`; sie ist inzwischen geschrieben (`scripts/technology/work_system.gd`).

## 5. Reihenfolge nach der Pause (alle Schritte erledigt, v0.6.1)

1. **`scripts/technology/work_chain.gd` + `work_system.gd`** (Arbeitsketten; Entwurf in Abschnitt 6.4). Danach sofort `tools/check_scripts.gd` und die Prompt-6-Tests (`tools/run_tech_tests.gd -- --quick`) – die neuen Anlauf-/Rückkehrphasen verändern Zeiten.
2. **Einbindung:** `LifeSimulation.setup` (`ctx.work = WorkSystem.new()`), `step` (`ctx.work.tick`), Wahrnehmung (`StorageSystem.perceive`, `StructureSystem.perceive` im Wahrnehmungstakt), `audit` (beide Audits + Lager/Bauwerk-Teile in `ConstructionSystem.audit`), `dispose`; `DecisionSystem.evaluate` (`ctx.work.options`) und `_execute` (`work:`-Optionen; andere Option gewählt → Kette **pausieren**, nicht abbrechen); `Creature.on_action_finished` → `ctx.work.on_action_finished`; `after_body_change` (Greifhand weg → Kette prüfen).
3. **Animation:** `CreatureAnimator` um antriebsgesteuerte Posen erweitern (`drive(d)` aus `a.state.anim`): `grasp`, `carry`, `carry_two`, `put_down(_two)`, `strike` (Ausholen→Kontakt→Rückkehr aus WorkPose), `assemble`, `assemble_one`, `place(_two)`, `operate_heater`, `pour`, `walk_short`; `dig`/`compact` **vorbereitet, aber abgewiesen** („Abbau und Mengenbilanz fehlen“). Beine bei Rumpfneigung gegensteuern, Hocke über Knie. Abbruch: Pose weich zurückblenden. `LivingWorld`: Animation aus `a.state.anim`, gehaltene Objekte am **Handgelenk-Pivot** (Werkzeug-+x → Hand-+z), zweihändig zwischen beiden Händen, Lager (Bodenrahmen) und Baustelle (Platzmarken) zeichnen.
4. **Testszene** `scripts/lab/work_chain_scene.gd` (`WorkChainScene.setup`, Modus `werkzeugkette` in `LivingWorld`, Eintrag im Startbildschirm): 1 Wesen (für Lernen/Autonomie optional ein zweites), Holzstiele, faustgroße Steine, Fasern, **Steinblock ≈ 2,6 kg** (für eine Hand zu schwer, muss zerkleinert werden), Kupferstücke, Lagerplatz, Baustelle „Steinreihe“, Testofen (Testheizung + Tiegel + Form). Knöpfe: Kette Lager / Kette Baustelle / Kette Schmelzen / Stein schmelzen (wird abgewiesen) / Autonom beobachten; Fehlerfälle: fehlendes Material, blockierter Weg (Voxelwand), fehlender Arm, zu schwer, Unterbrechung, Speichern/Laden während der Herstellung. Anzeige (Wesenfenster-Abschnitt „ARBEIT“ + Arbeitsfeld): Ziel, laufende Handlung + Phase, Werkzeug-ID, Zielobjekt, getragene/transportierte Menge, Fortschritt, Abbruch-/Pausengrund, Herkunft (eigener Bedarf / gezielt ausgelöst / Modell).
5. **Speicherformat 5** + Migration 4→5 (`storages`, `structures`, `work`, Stückfelder, Wesenfelder), Tests mit **beiden** Prüflingen; `V5_SHIPPED_DEFINITIONS` setzen; Stufe 3→4 vergleicht dann nicht mehr mit den aktuellen Definitionen (Muster wie 2→3). Laufende Ketten werden nach dem Laden **fortgesetzt** (jeder Schritt neu geprüft; laufende Handlung wird wie bisher abgebrochen).
6. **Tests** `tests/test_work_chain.gd` (+ `tools/run_work_tests.gd`, Aufnahme in `tests/run_tests.gd`, Szenentest): Hammer-ID eindeutig; Ausrüsten ohne Kopie (ein Objekt, ein Träger); Griffpunkt; Kontaktpunkt am Ziel (WorkPose, < 8 cm); **mehrfache Animationsbilder in der Kontaktphase → genau ein Schaden**; Schaden abhängig von Werkzeug/Material/Verbindung; Verschleiß; Bruchstücke: Material, Gesamtmasse exakt, Temperatur übertragen; nicht jeder Schlag bricht; Kupfer verformt statt bricht; Aufnehmen/Tragen (Zeit, Tragfähigkeit, zweihändig, einarmig abgelehnt); Lager (Kapazität, kein Doppelbestand); Baustelle (Bauplan, Masse im Bauwerk); Schmelzen im Testofen; Stein/Holz abgewiesen; Abbruchgründe (fehlendes Werkzeug, ungeeignetes Material, blockierter Weg, fehlende Wärmequelle); Speichern/Laden während der Kette; normaler Modus nutzt denselben Code; autonomer Durchlauf als **Messwert** (getrennt von gezielt ausgelöst).
7. **Excel:** `design/Erfindungen_Echt_nach_Kategorien.xlsx` (liegt bereits vor, Original unverändert); dokumentierte Importkonfiguration (z. B. `design/import_config/datenbasis_korrekturen.json`, vom Importer gelesen): Kupfer-Voxeltyp → Kupfer-Material per Namensabgleich, MAT_Erde/MAT_Gras/MAT_Holz → Physikmaterial soil/plant_tissue/wood (als Korrektur gekennzeichnet), Voxel_Größe 0,1 m durch Projektentscheidung überstimmt (Gelände 0,5 m, Körper 0,02 m, Gegenstände 0,005 m), Fortpflanzung (Zwei-Wesen-Regel, −1, falscher Tabellenverweis) **nicht** als Regel übernommen (Nachwuchs über den Lebensbaum), Setzling-Ernährung dokumentiert, nicht aktiviert. Importbericht-Abschnitt „Prompt 6B“. Erfindungsimporter für die neue Datei (Spalten ohne Forschungskosten), alter Katalog bleibt als eigene Datei erhalten. Strukturierte Definitionen für **aktivierte** Erfindungen in `data/config/inventions_activated.json` (Materialien/Mengen, Körperfähigkeiten, Werkzeuge, Vorgänge, Schritte, Zeit/Energie, Ergebnisgeometrie, messbare Funktion, Animationen, Status, Testname) + Konsistenztest.
8. **Ollama:** Anfrageart `work` (Schema `data/ai/work_schema.json`, Systemanweisung, Prüfung jedes Schritts über `dry_run`, SIMULIERTER Testdienst) – Ergebnis nur Vorschlag; echte Verbindung „nicht verifiziert“.
9. **Abschluss v0.6.1 – Prompt 6B:** Doku (README, CHANGELOG mit „Entfernt/Geändert“, architecture, implementation_status, test_results, tools_and_construction, neue `docs/work_chains.md`, `docs/animations.md` mit Liste vorhandener/fehlender Animationen, Importbericht), HANDOVER, Versionsvergleich gegen `version/v0.6.0`, Tests 4.7.2 + 4.5, Bildschirmfotos der Testszene ansehen, ZIP in frischem Ordner prüfen, Push `main` + `version/v0.6.1`.

## 6. Entscheidungen (verbindlich für die Fortsetzung)

### 6.1 Hände
Ein Halteplatz (`held_object_id`) plus `hold_mode`: Werkzeug/Stück in einer Hand, schweres Stück mit beiden Händen (Tragegrenze = Summe der Greifwerte · 0,15 · Körpermasse). Zum Tragen von Bruchstücken legt das Wesen den Hammer **sichtbar ab** (Werkzeug bleibt dasselbe Objekt, keine Kopie). Einarmige Wesen: einhändig tragen/schlagen möglich, zweihändiges Tragen abgelehnt, Umwickeln als einarmige Variante.

### 6.2 Kontakt und Animation
Simulationswirkung nur in der Handlung an einem eindeutigen Zeitpunkt; die Animation liest `a.state.anim` = {pose, phase, u, target, contacts, tool_h …} und verändert nichts. Kontakt = Ende des Ausholens; `contacts` zählt. Standpunkt so, dass der Werkzeugkopf (WorkPose) am Ziel liegt.

### 6.3 Lager, Baustelle, Schmelzen
Namen wie in Prompt 9 (`deposit_in_storage`, `place_building_part`, `scripts/settlement/…`), damit Prompt 9 erweitert statt ersetzt. Lager/Baustelle im normalen Spiel nur durch Wesen (Anlass „eigenes Einzelbauwerk beginnen“) oder Testaufbau – kein versteckter Startbestand. Schmelzen nur über `melt_support`.

### 6.4 Arbeitsketten (Entwurf `WorkSystem`)
- **Kette** (`WorkChain`): id, Wesen, Ziel (`lagern` | `bauen` | `schmelzen`), Zieltext, Herkunft, Status (läuft/pausiert/abgeschlossen/fehlgeschlagen/abgebrochen), Schritte, Schrittindex, Werkzeug-ID, Zielobjekt, Bestimmungsort, transportierte kg, erzeugte Bruchstücke, Umplanungen, Abbruch-/Pausengrund, Protokoll, Ergebnis.
- **Schritte (op):** `bring` (Teil zum Stiel tragen), `connect`, `check_tool` (ObjectEvaluator), `equip`, `release`, `break` (deform_material bis zum Bruch, wiederholt; Kupfer: `work_copper` = verformen), `collect` (erweitert sich nach dem Bruch zu `carry`-Schritten je Bruchstück), `carry` (Unterphasen: ablegen falls Hand belegt → aufnehmen [carry] → hingehen → deposit/place/put_in), `heat`, `wait_molten`, `pour`, `check` (Ergebnis bewerten, Verfahrenswissen verbuchen), `mark_site` (eigene Baustelle markieren).
- **Bedarf (eigener Anlass, nur eigenes Wissen):** eigene Baustelle mit freien Plätzen (`need_site`); selbst erzeugte lose Stücke + bekanntes Lager mit Platz (`need_store`); bekanntes Gießverfahren + Kupfer + Tiegel + freie Heizung + leere Form (`need_cast`); eigenes Einzelbauwerk beginnen (nur beharrliche Wesen, selten, `need_start_site`). Nutzwert = Gewicht · Bedarf · (0,5 + 0,5 · Beharrlichkeit) · Spielraum − Weg; Hunger > `max_hunger` blockiert.
- **Wissen:** Werkzeugbau nur mit bekanntem Umwickelverfahren (≥ `tool_min_level`), sonst Handstein als Werkzeug oder Abbruch „kein bekanntes Werkzeugverfahren“. Ergebnisse über `ProceduralKnowledge.record_own`.
- **Umplanen/Abbruch:** außer Reichweite → `move_to`; Weg blockiert → andere Seite (`move_retries`), sonst Abbruch „Weg blockiert“; Werkzeug zerbrochen → neues bauen, sonst Abbruch; ungeeignetes Material → Stück überspringen mit Grund, nichts Geeignetes → Abbruch; keine freie Wärmequelle → Abbruch „keine Wärmequelle“; Hunger/Gefahr → andere Option gewinnt → **pausieren** (zweihändig Getragenes ablegen), nach `pause_max_s` Abbruch.
- **Ohne Verhalten** (gezielt ausgelöst): `WorkSystem.tick` treibt die Kette (wie `ExperimentSystem.tick`).

### 6.5 Version
6B wird als **v0.6.1 – Prompt 6B** ausgeliefert (Prompt N bleibt v0.N.0; der Zusatz Weltarchitektur würde v0.6.2).

## 7. Risiken / Prüfpunkte

- Neue Phasen (Anlauf, Ausgangspose, Rückkehr) verlängern Technikhandlungen um ≈ 0,5–3 s → Prompt-6-Tests und die kalibrierte Versuchsbeobachtung (Gewicht 0,6) früh prüfen.
- Vorzeichen der Gelenkwinkel (negativ = nach vorn heben; Rumpf positiv = vorneigen) per Test absichern (Kontaktpunkt am Ziel).
- GDScript-Stolperfallen aus HANDOVER Abschnitt 9 (kein `:=` bei Variant, Warnungen = Fehler).
- Testläufe 4.7.2 und 4.5 **nacheinander** (gemeinsamer `user://`-Ordner) – am 2026-11-24 ist ein 4.5-Lauf daran gescheitert, dass während des Laufs Code geändert wurde; Ausgangsbasis danach in einem frischen Ordner bestätigt.

## 8. Leitlinie „Steinzeit → Zukunft“ – Abgleich mit allen Prompts

Ziel des Nutzers: Die Wesen entwickeln sich **selbst** (kein Technologiebaum). Jede Stufe braucht vorher die passende **Physik und Handlung** im Spiel; die Leitlinien-Excel (nach 6B zu bauen) beschreibt je Erfindung die physikalische Kette Material → Werkzeug → Arbeitsschritt → Energie/Temperatur → Ergebnis und „im Spiel möglich ab Prompt X / fehlt“.

| Entwicklungsschritt | Physikalisch nötig | Kommt in | Lücke |
|---|---|---|---|
| Schlagstein, geschäfteter Steinhammer | Schlagmodell, Umwickeln mit Fasern | 6 / 6B | – |
| Stein zerkleinern, Bruchstücke nutzen | Bruch, Tragen, Lager, Einzelbau | 6B | – |
| Graben, Erde/Stein abbauen, Wälle | Gelände abbauen mit Mengenbilanz | Zusatz Weltarchitektur | Einordnung in die Reihenfolge noch offen |
| Gemeinsames Bauen, Lager, Handel | Projekte, Aufgaben | 9 | – |
| **Feuer machen** (Holz anzünden) | Verbrennung, Zündung | **12** | sehr spät – bis dahin keine eigene Wärmequelle der Wesen |
| Holzkohle, Luftzufuhr (Blasrohr/Blasebalg) | Verbrennung mit Luftzufuhr, höhere Temperatur | – | **fehlt in allen Prompts** |
| Ton formen und brennen (Tiegel, Form, Ofen selbst herstellen) | Ton als Material, Brennen → Keramik | – (Prompt 11 erwähnt nur „Tonplatte“) | **fehlt** |
| Kupfer schmelzen und gießen im **eigenen** Ofen | eigener Ofen + Feuer | 6 nur Testofen | hängt an Feuer + Ton |
| Erz finden und verhütten | Erz im Boden, Reduktion | 12 (Reaktionen, allgemein) | **Erz im Gelände fehlt** (Weltarchitektur kennt Erde/Sand/Stein) |
| Legierung (Bronze = Kupfer + Zinn) | Zinn, Mischung zweier Schmelzen | – | **fehlt** (kein Zinn, kein Mischmodell) |
| Abbauwerkzeuge (Hacke, Pickel) | andere Kopfformen, Abbau-Handlung | Weltarchitektur + Konstruktion | Kopfformen-Varianten fehlen |
| Hebel, Rad und Achse | Mechanik | 12 | – |
| Elektrizität | Gleichstrom | 12 | – |
| Schrift, Bücher | Zeichen, Träger | 11 | – |
| Ackerbau, Tiere | Ökosystem | 8 | – |

**Vorschlag (Entscheidung beim Nutzer):** einen Zwischenschritt „Feuer, Ton und eigener Ofen“ (Zündung, Holzkohle, Luftzufuhr, Ton brennen, eigener Schmelzofen) **vor** Prompt 7 oder 9 einschieben und einen Schritt „Erz und Legierungen“ (Erz im Gelände, Verhüttung, Zinn, Bronze) ergänzen; sonst bleibt der Weg vom Steinhammer zur Bronze bis Prompt 12 blockiert. Der Zusatz Weltarchitektur (Abbau) passt sinnvoll direkt nach 6B, weil 6B Graben/Verdichten nur vorbereitet.

**Umgesetzt (25.11.2026):** Leitlinien-Excel `design/Leitlinie_Steinzeit_bis_Zukunft.xlsx` mit 2.680 Erfindungen, Spielstand je Erfindung und den Zwischenschritten als Auswahl zum Ausprobieren – `docs/leitlinie.md`. Zusätzlich gefundene Lücken: gezieltes Abschlagen/Formen (ab der Frühen Steinzeit), Jahreszeiten/Mond/Sterne und Erdgeschichte im Weltmodell.

## 9. Zusatz Weltarchitektur (`prompt_zusatz_weltarchitektur_abbau_bauen.txt`)

Noch nicht eingeordnet. Inhalt: 20-fache Grundfläche (Seiten × √20), Blockgröße 0,25 m (Vergleich mit 0,5 m), Abbau/Bau mit Massenbilanz, Einsturz, Wasser in Gruben/Tunneln, Navigation nach Körpergröße, Speicherformat für Chunk-Änderungen. Der Nutzer entscheidet, wann er kommt.
