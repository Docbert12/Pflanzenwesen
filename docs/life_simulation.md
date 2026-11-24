# Lebenssimulation (Stand 0.3.0-prototype – Prompt 3; Ergänzungen 0.4.0 am Ende)

**Spielbiologie.** Alle Zahlen dieser Datei sind vereinfachte, frei gewählte Spielwerte in
`data/config/life.json`, sofern nicht ausdrücklich „Excel“ dasteht. Es ist **keine** realistische
Pflanzenphysiologie und kein ausgeglichenes Ökosystem.

## Überblick

```
LivingWorld (Szene, nur Darstellung + Bedienung)
  └─ LifeSimulation (Kern, auch in den Tests verwendet)
       ├─ LifeContext: gemeinsamer Zugriff (Simulation, Welt, Navigation, Tag/Nacht, Executor, Bilanz, Entitäten)
       ├─ ActionExecutor + ActionValidator + Handlungen (move_to, pick_up, eat, drop, wait)
       ├─ Creature (Körper, Gesundheit, Stoffwechsel, Wahrnehmungsspeicher, Verhalten)
       ├─ FoodSource / FoodItem / ResourceLedger
       ├─ NavigationService (Spaltenraster-A*) + Locomotion
       ├─ Perception, BasicBehavior
       └─ DayNightSystem, Photosynthesis, Metabolism, Health, BodyCapabilities
```

Alle Wesen, Nahrungsquellen und Portionen haben eine ID aus dem gemeinsamen `EntityRegistry`
(`Simulation.add_entity`). Es gibt keine zweite ID-Vergabe.

### Ablauf eines Takts (fester Physiktakt, 60 Hz)
1. `Simulation.step` – Uhr, Wärme/Phasen der Weltmassen. Bei Pause liefert sie 0 → Abbruch.
2. Nachbarraster neu (1-m-Zellen), Wegsuchbudget zurücksetzen.
3. `ActionExecutor.step` – laufende Handlungen (Bewegung, Aufnehmen, Essen …), Ablauf von Reservierungen.
4. Je lebendem Wesen: Licht → Photosynthese, Stoffwechsel, Mangelschaden, ggf. Tod.
5. Je Wesen **versetzt**: Wahrnehmung alle 1 s, Entscheidung alle 0,5 s (nicht alle im selben Takt).
6. Nur bei eingeschalteter **Testoption**: Nachfüllen der Nahrung.

Prüfungen (`LifeSimulation.audit`) laufen in Tests und auf Anforderung, nicht in jedem Takt.

## Handlungssystem (`scripts/actions/`)

| Datei | Aufgabe |
|---|---|
| `action_definition.gd` | Typen, Zustände, benötigte Fähigkeiten, Ziel-Art, unterbrechbar, Ladeverhalten |
| `game_action.gd` | Handlungsinstanz: ID, Wesen, Typ, Ziel-ID/-Position, Fähigkeiten, Ressourcenbedarf, Status, Fortschritt, Zeitlimit, Reservierung, Ergebnis |
| `action_validator.gd` | allgemeine Prüfungen beim Start und in jedem Schritt |
| `action_executor.gd` | Ausführung, Reservierungen, Ergebnisprotokoll |
| `implementations/*.gd` | handlungsspezifische Prüfung, Start, Schritt, Aufräumen, Leistung |

**Zustände:** `planned → running → succeeded | failed | cancelled`.
Je Wesen läuft höchstens eine Handlung. Eine neue wird mit `busy` abgewiesen, außer mit `preempt` bei unterbrechbaren Handlungen.

**Prüfungen beim Start und während der Ausführung:** Wesen existiert und lebt; benötigte Körperfähigkeit > 0 (Gehen zusätzlich `can_walk`); Ziel existiert; Reichweite 1,1 m; freie Menge vorhanden; Gegenstand nicht getragen und nicht reserviert.

**Reservierung und atomare Mengenänderung:**
- Freie Menge = Menge − Σ Reservierungen.
- `pick_up` und direktes `eat` reservieren beim Start genau einen Bissen (0,1 kg) bzw. den ganzen Gegenstand.
- Die Entnahme erfolgt in einem einzigen Aufruf `FoodSource.take_reserved` (nur gegen die eigene Reservierung, nie mehr als reserviert, nie mehr als vorhanden).
- Jedes Ende gibt die Reservierung frei: Erfolg, Fehlschlag, Abbruch, Tod, Zeitlimit, Zielverlust. Dazu kommt eine Lebensdauer von 60 s je Reservierung als Sicherung.

**Unterbrechung:** Bei `eat` wird in jedem Schritt die tatsächlich gegessene Masse gebucht. Bei Abbruch bleibt das Gegessene bilanziert, der Rest bleibt im Gegenstand bzw. in der Quelle (getestet).

**Ergebnisereignisse:** Jedes Ende erzeugt einen strukturierten Eintrag `{action_id, actor, type, target, status, code, message, duration_s, consumed, t}`:
- im begrenzten `ActionExecutor.history` (500 Einträge),
- Fehlschläge und Abbrüche zusätzlich im gemeinsamen Ereignisprotokoll.

Start und Erfolg einer Handlung sowie Reservierungen gelten als Routine. Sie stehen nicht im Ereignisprotokoll, sonst würden 50 Wesen alle übrigen Einträge in Sekunden verdrängen.

**Später für Ollama:** Ein Sprachmodell soll später nur über `ActionExecutor.request` handeln, also dieselben geprüften Typen, Prüfungen und Ergebnisse nutzen.

## Körper, Fähigkeiten, Gesundheit

- **Grundkonfiguration** `Creature.base_genes` + `plan_seed`: aus `CreatureGenerator`, reproduzierbar.
- **Aktueller Körper** `Creature.plan` (`BodyPlan`): Teile mit Status `present/removed/replaced`, Prothesen als eigene Teile.
- **Verletzungszustand** `Creature.health`: Schaden je Teil 0…1 und Mangelschaden.
- **Fähigkeiten** `BodyCapabilities.compute` – aus der **Funktion** der Teile, nicht aus Namen:

| Funktion (Körperplan) | Beitrag (life.json) |
|---|---|
| `bein` (Oberschenkel) | Fortbewegung 0,20 |
| `unterschenkel` | Fortbewegung 0,15 |
| `stehen` (Fuß) | Fortbewegung 0,15 |
| `greifen` (Hand) | Greifen 1,0 · zum Mund führen 1,0 |
| `haken` (Kupferprothese) | Greifen 0,6 · zum Mund führen 0,5 |
| `stuetze` (Holzprothese) | – |
| `kopf_sinne` (Kopf) | Mund 1,0 · Wahrnehmung 1,0 |
| `photosynthese_dekor` (Blatt) | Blattfläche = Länge · Breite · 0,6 |

Wirksamer Beitrag = Tabellenwert · Π(1 − Schaden) über das Teil und alle Vorfahren. Ein verletzter Oberschenkel schwächt also auch Unterschenkel und Fuß.

- **Gehen:** Jede Körperseite braucht mindestens 0,3. Die Geschwindigkeit ist 1,0 m/s (Excel 21_Balancing) × Summe beider Seiten, bei Energie < 15 % zusätzlich × 0,6.
- **Bein verletzen** (Entwicklermodus): Der Unterschenkel bekommt 60 % Schaden, das Wesen geht danach mit 0,82 m/s. Ein zweites Mal ergibt 100 %: Unterschenkel und Fuß gehen verloren, Gehen ist nicht mehr möglich. Die Begründung steht im Beobachtungsfenster, und `move_to` wird mit `cannot_walk` abgewiesen.
- **Nicht implementiert:** Hinken, Kriechen und andere Körperformen. Für einen Körper, dessen Bewegung nicht implementiert ist, wird die Bewegung erklärt gestoppt; es gibt keine automatische Anpassung.
- **Unterarm entfernen:**
  - Greifen und Essen laufen über die andere Hand.
  - Ohne beide Hände frisst das Wesen direkt an der Quelle mit dem Mund, mit 25 % der Rate.
  - Eine getragene Portion wird abgelegt, wenn keine Greiffähigkeit mehr bleibt.
- **Prothesen** (nur Entwicklermodus; die Wesen stellen sie noch nicht selbst her):
  - Holz ist eine Stütze ohne Greiffunktion.
  - Der Kupferhaken greift und führt eingeschränkt zum Mund.
  - Die Masse kommt aus Material × Volumen und erhöht Grundumsatz, Bewegungskosten und Speicher.
- **Tod:** Vitalität = (1 − Mangelschaden) · (1 − Schaden Rumpf) · (1 − Schaden Kopf). Bei Vitalität ≤ 0 passiert Folgendes:
  - laufende Handlung abbrechen, Reservierungen freigeben;
  - Getragenes am Körper ablegen (es kann wieder aufgenommen werden);
  - Ursache, Zeit und Ort festhalten;
  - Stoffwechsel und Verhalten enden;
  - der Körper bleibt als Weltzustand liegen.

  Der Lebensbaum recycelt nichts. Regeneration gibt es nicht.

## Stoffwechsel und Ressourcenbilanz (`metabolism.gd`, `resource_ledger.gd`)

| Größe | Spielwert |
|---|---|
| Energiespeicher | 1500 J je kg Körpermasse |
| Nährstoffspeicher | 2 g je kg Körpermasse |
| Startfüllung | zufällig 40–75 % |
| Grundumsatz | 1 W je kg (Wesen wiegen etwa 11–19 kg, also 11–19 W) |
| Blattunterhalt | 0,25 W je Blatt |
| Bewegung | 2 J je kg und m |
| Handlungen | Aufnehmen 4 W, Essen 2 W, Ablegen 2 W |
| Nährstoffverbrauch | 0,0006 g je s und kg |
| Verdauung | 80 % assimiliert, 20 % Abfall |
| Mangelschaden | Energie leer 0,4 %/s, Nährstoffe leer 0,2 %/s (bis 100 % = Tod) |

**Nahrung (Excel 14_Nahrung_Konsum):**
- Energie je kg = Nährwert × 3000 J/kg: Beeren N001 ergeben 45 kJ/kg, Pilz N002 60 kJ/kg.
- Nährstoffe je kg = (1 − Wassergehalt) × 100 g: Beeren 60 g/kg, Pilz 40 g/kg.
- Quellen sind Beerensträucher (P007) sowie rote und braune Pilze (P009/P010) mit 0,5–1,0 kg essbarer Menge.
- Dazu kommen 20 zusätzliche, deterministisch platzierte Quellen im Ring 5–13 m um den Baum. Bei Startwert 12345 sind es insgesamt 45 Quellen mit 36,1 kg.
- Die Quellen wachsen nicht nach.

**Bilanzen (in jedem Prüfungslauf geschlossen):**
```
Nahrung:  Startmenge + Testnachfüllung = Σ Quellen + Σ Portionen + gegessen
          gegessen = assimiliert + Abfall
Energie (je Wesen):  E = E_start + Nahrung + Licht − Grundumsatz − Blätter − Bewegung − Handlungen − Überlauf + Defizit
```
- **Überlauf:** Bei vollem Speicher wird der Rest verworfen und als Überlauf gebucht.
- **Defizit:** Was bei leerem Speicher fehlt, wird als Defizit gebucht. Es wirkt dann als Mangelschaden.
- **Nicht modelliert:** Körperwachstum und Wasser bzw. Durst.

**Hunger** (0–100 %) ist 1 − min(Energie-, Nährstofffüllung). Das Wesen sucht Nahrung ab 60 % (Excel KI001 „Hunger > 60“) und hört unter 15 % auf (Hysterese).

## Photosynthese und Tag/Nacht

```
P [W] = 230 W/m² · wirksame Blattfläche [m²] · Licht · Verschattung
Licht = max(0, sin(2π·(Tageszeit − 0,25)))   (Tag = 600 s, Start 07:12)
Verschattung = 0,35 unter der Baumkrone, sonst 1
```
- **Licht:** Es wird nur aus der Simulationszeit berechnet. Bildschirmhelligkeit und Kamera spielen keine Rolle.
- **Blattfläche:** Beschädigte Blätter zählen anteilig, entfernte gar nicht.
- **Größenordnung:** Ein Blatt bringt mittags etwa 1–7 W. Das ist ein Bruchteil des Grundumsatzes. Licht hilft, ersetzt aber weder Nahrung noch Nährstoffe; Licht liefert **keine** Nährstoffe.
- **Kosten der Blätter:** Mehr Blätter bedeuten mehr Fläche, aber auch mehr Masse (Grundumsatz) und mehr Blattunterhalt.
- **Kein Schlafzwang:** Nachts handeln die Wesen weiter (getestet).

## Wahrnehmung und Verhalten

**Wahrnehmung** (`perception.gd`):
- Radius 10 m (Excel 21_Balancing) × Kopffunktion.
- Sichtprüfung über einen Voxel-Strahl von Augenhöhe (0,75 m); feste Zellen dazwischen verdecken.
- Merkliste je Ziel: Position, gesehene freie Menge, Zeitpunkt. Einträge verfallen nach 120 s.
- Bei Ankunft am Ziel wird sofort neu wahrgenommen (erneute Prüfung).
- Ein Wesen kennt nie automatisch alle Quellen.

**Verhalten** (`basic_behavior.gd`) ist ein verständliches Zustandsverhalten:
1. Wer hungrig ist und Nahrung trägt, isst.
2. Wer hungrig ist, wählt die nächste gemerkte, nicht verworfene Quelle. In Reichweite folgt `pick_up` (mit Hand) bzw. direktes `eat` (ohne Hand), sonst `move_to` bis 0,88 m an die Quelle heran.
3. Wer hungrig ist und nichts kennt, erkundet bis zu 3-mal zufällige begehbare Punkte im Umkreis von 8 m und wartet danach 8 s.
4. Wer versorgt ist, wartet 3–6 s oder geht mit 25 % Wahrscheinlichkeit kurz umher.

**Vorkehrungen:**
- Entscheidungen fallen nur alle 0,5 s und nie, solange eine Handlung läuft. Es gibt also keinen Zielwechsel pro Bild.
- Fehlgeschlagene oder unerreichbare Ziele werden für 60 s verworfen; endlose Wiederholung ist damit ausgeschlossen.
- Die Wegsuche ist begrenzt (siehe Navigation).
- Aufnehmen und Essen setzen Reichweite voraus.
- Gehen setzt `can_walk` voraus.

**Erklärungen:** Der Zustandstext wird aus Werten gebildet, etwa „Hunger 64 % ≥ 60 % → Nahrung #131, 4,2 m entfernt, gesehen vor 3 s“. Innere Gedanken werden nicht erfunden.

Im Entwicklermodus lässt sich das Verhalten eines Wesens anhalten; laufende Handlungen werden dann trotzdem fertig ausgeführt.

## Navigation (Entscheidung)

**Gewählt:** eigenes Raster-A* über die 64 × 64 Terrainspalten (`navigation_service.gd`).

**Gründe:**
- Godots NavigationMesh müsste nach jeder Voxeländerung neu gebacken werden und kennt die Voxeldaten nicht direkt.
- Die Welt hat je Spalte eine Bodenhöhe. Das Spaltenraster bildet sie 1:1 ab und ist deterministisch, was für Speichern/Laden und Tests wichtig ist.
- Eine Terrainänderung aktualisiert über das Signal `terrain_changed` nur die betroffene Spalte (getestet: 32 Zellen ergaben 32 Spaltenaktualisierungen).

**Begehbar:** im Feld, nicht von Baumstamm oder tiefen Ästen belegt (0,6–2 m über Boden), Kopffreiheit, Wassertiefe ≤ 0,25 m. Pflanzen blockieren nicht.

**Schritt:** höchstens 1 Zelle (0,5 m) hinauf und 2 Zellen hinab. 8er-Nachbarschaft, Diagonalen nur ohne Eckenabkürzung.

**Grenzen:**
- höchstens 2500 Knoten je Suche, danach `search_limit`;
- höchstens 4 Suchen je Takt, weitere warten auf den nächsten Takt;
- keine Wegplanung pro Bild.

**Bewegung** (`locomotion.gd`):
- Sie ist kinematisch und läuft im festen Takt entlang des Wegs.
- Vor jeder neuen Spalte werden Begehbarkeit und Stufe erneut gegen die Voxeldaten geprüft. So läuft kein Wesen durch Wände oder in den Boden.
- Die Höhe folgt dem Boden.
- Animationen verändern die Position nie.

**Blockierter Weg:** Das Ereignis `path_blocked` wird geschrieben und neu geplant, höchstens 2-mal. Danach endet die Handlung mit einem erklärten Fehlschlag `path_blocked`, und das Ziel wird für 60 s verworfen.

**Ausweichen:** Wesen im Umkreis von 0,45 m stoßen sich ab, aber nur in begehbare Spalten.

**Grenzen der Navigation:**
- nur eine Oberfläche je Spalte; Höhlen, Brücken und Überhänge sind nicht begehbar;
- kein Springen, Klettern oder Schwimmen;
- Ausweichen ist lokal, ohne Vorausplanung;
- Wesen können sich kurz berühren, weil Godot-Physik für Wesen nicht genutzt wird;
- bei einem Weg quer über die Karte kann die Grenze von 2500 Knoten greifen.

## Animation

Die Animation richtet sich nach der laufenden Handlung:

| Handlung | Animation |
|---|---|
| `move_to` mit tatsächlicher Geschwindigkeit > 0,05 m/s | Gehen. Der Takt ist proportional zur tatsächlichen Geschwindigkeit, ein verletztes Wesen geht also langsamer. |
| `pick_up` | Greifen auf der Seite, die tatsächlich greift (Hand oder Haken) |
| `eat` (getragen) | Zum Mund führen |
| sonst | Ruhe |

- Direktes Essen ohne Hände hat keine eigene Animation (Ruhehaltung).
- Ist eine Animation für den Körper nicht möglich, lehnt der Animator sie ab und zeigt die Ruhehaltung.
- Entfernte Teile werden nicht animiert.
- Tote Wesen liegen.
- Die Darstellung eines Wesens wird nur bei einer Körperänderung neu aufgebaut, nicht in jedem Bild.

## Bedienung (Szene `scenes/living_world.tscn`)

| Eingabe | Wirkung |
|---|---|
| Startbildschirm → **Neues Spiel** | neue Welt, genau 50 Wesen |
| Startbildschirm → **Fortsetzen / Laden** | letzten Spielstand laden; bei beschädigter Datei ggf. „Sicherung laden“ |
| Linksklick auf ein Wesen / Eintrag links | Wesen untersuchen (rechts) |
| **F** | Kamera auf ausgewähltes Wesen |
| **Leertaste** / „Pause“ | Simulation anhalten; Kamera und Oberfläche bleiben bedienbar |
| **F5** / „Speichern“ | Spielstand `user://saves/spielstand.json` (alte Datei → `.bak`) |
| **F9** / „Laden“ | Spielstand neu laden (frische Szene) |
| „Entwicklermodus“ | rotes Feld: Unterarm entfernen, Holz-/Kupferprothese, Bein verletzen, Blatt entfernen, Wesen töten, Verhalten anhalten, **TESTOPTION** Nachfüllen |
| „◀ Menü“ | zurück zum Startbildschirm |
| Kamera | rechte Maustaste drehen, mittlere verschieben, Rad zoomen, W A S D / Q E |

**Anzeigen:**
- links: Population (lebend, gestorben, Nahrung, Zeit, Tagesphase, Zustände) und Wesenliste;
- rechts: Beobachtungsfenster;
- unten: Ereignisse (optional nur für das ausgewählte Wesen);
- unten rechts: Leistung.

## Testoption Nachfüllen

Die Testoption ist im normalen Spiel ausgeschaltet. Einschalten lässt sie sich nur sichtbar im Entwicklermodus.

**Wirkung:** Alle 60 s erhält jede Quelle bis zu 0,5 kg, höchstens bis zu ihrer Startmenge.

**Kennzeichnung:**
- Die Menge wird als `refill_kg` in der Bilanz gebucht.
- Im Ereignisprotokoll steht ein Warnereignis.
- Die Populationsanzeige zeigt „TESTOPTION Nachfüllen AKTIV“.

## Leistung

Siehe `docs/test_results.md`. Eine Unterstützung für 1000 Wesen wird nicht behauptet.

## Änderungen in 0.4.0 (Prompt 4)
- **Entscheider:** Das Verhalten entscheidet jetzt `DecisionSystem` (`docs/mind_and_learning.md`). `BasicBehavior` führt nur noch aus. Die Abläufe Nahrung aufsuchen → aufnehmen → essen, das Erkunden und die Hysterese bleiben erhalten; dazu kommen Persönlichkeit, Erfahrung, soziale Optionen und Wegkosten.
- **Neue Handlungen:** `request_food`, `offer_food`, `give_food`, `decline_request` und `raise_arms`.
- **Takt:** Je Wesen kommt `LearningSystem.tick` im 1-s-Takt hinzu, je Takt `social.tick` und `interventions.tick`.
- **Leistung:** Ein Takt dauert mit 50 Wesen etwa 2,2–2,5 ms statt 1,9 ms (siehe `docs/test_results.md`).
