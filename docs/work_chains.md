# Arbeitsketten: Werkzeug → Bearbeiten → Tragen → Lagern / Verbauen / Schmelzen (Prompt 6B)

Stand v0.6.1. Grundlage: `design/prompts/prompt_06b_excel_animationen_herstellung.txt` und der verbindliche Zusatz
`design/prompts/prompt_06b_zusatz_werkzeug_materialkette.txt`.

## Kurzfassung

Ein Wesen kann einen Hammer aus vorhandenen Teilen binden, genau diesen Hammer aufnehmen, damit einen Stein zerschlagen
oder Kupfer verformen, die tatsächlich entstandenen Stücke aufnehmen, tragen und dann

1. in einen **realen Lagerplatz** einlagern,
2. an einer **Baustelle** („Steinreihe“, einfaches Einzelbauwerk) verbauen oder
3. in einen **Tiegel** legen, im **Testofen** schmelzen und in eine Form gießen.

Alle Schritte sind normale Handlungen über den `ActionExecutor` (Reichweite, Masse, Hände, Temperatur, Kapazität,
Bauplan, Schmelzeignung). Es gibt keinen zweiten Entscheider: Ketten werden über Optionen des `DecisionSystem`
gestartet und fortgesetzt; gezielt ausgelöste Ketten (Testszene) treibt `WorkSystem.tick()` nur bei Wesen mit
abgeschaltetem eigenem Verhalten.

| Was | Status |
|---|---|
| Gegenstandsherstellung (Hammer aus Stiel, Steinkopf, Fasern) | **funktioniert** (gezielt und aus eigenem Bedarf) |
| Einfaches Einzelbauwerk (Steinreihe, 3 Plätze) | **funktioniert** (ein Wesen, eigener oder vorgegebener Bauplatz) |
| Schmelzen und Gießen | funktioniert **nur mit Testausrüstung** (Testofen, Tiegel, Form); Wesen bauen noch keine Öfen |
| Gemeinsames Siedlungsbauen, Projekte, Aufgabenverteilung | **nicht umgesetzt** (Prompt 9) |
| Graben / Erde verdichten | Posen vorbereitet, **abgewiesen** (keine Abbau-Mengenbilanz; Zusatz Weltarchitektur) |

## Bausteine

| Datei | Aufgabe |
|---|---|
| `scripts/technology/work_chain.gd` | Datenklasse einer Kette: Ziel, Herkunft (gezielt / eigener Bedarf / Modellvorschlag), Schritte, Werkzeug-ID, Zielobjekt, Bestimmung, erzeugte/abgelieferte Stücke, transportierte Masse, Abweisungen, Abbruch-/Pausegrund, Verlauf |
| `scripts/technology/work_system.gd` | Planung (`plan`), Bedarf (`needs`), Optionen für den Entscheider (`options`, `execute_option`), Ausführung (`advance`, `_step`), Rückmeldungen (`on_action_finished`), Anzeige (`status_view`), Modellvorschläge (`validate_model_plan`, `add_proposal`), Speichern |
| `scripts/settlement/storage_place.gd`, `storage_system.gd` | Lagerplatz: Bodenbereich mit Kapazität (Masse, Volumen), Platzraster 0,2 m, Temperaturgrenze; Stücke bleiben eigene Weltobjekte |
| `scripts/settlement/structure.gd`, `structure_system.gd` | Baustelle und Bauplan „Steinreihe“; Platzprüfung, Untergrund, messbare Funktion (`evaluate`) |
| `scripts/actions/implementations/deposit_in_storage_action.gd`, `place_building_part_action.gd`, `put_into_container_action.gd` | Einlagern, Verbauen, in den Tiegel legen – je mit Anlauf, Pose und Übergabe genau einmal |
| `scripts/lab/work_chain_scene.gd` | Testszene „Werkzeugkette“ (Aufbau, gezielte Auslöser, Fehlerfälle) |

## Ablauf einer Kette

Jeder Schritt ist **zustandsbasiert**: Zuerst wird aus dem Weltzustand geprüft, ob er schon erledigt ist (gehalten,
eingelagert, verbaut, im Tiegel, zerbrochen …); nur sonst wird eine Teilhandlung angefordert. Dadurch verdoppelt
weder eine Unterbrechung noch Speichern/Laden einen Schritt.

| Schritt (`op`) | Bedeutung |
|---|---|
| `bring` | Bauteil zum Stiel tragen (Aufnehmen → Gehen → Ablegen) |
| `connect` | Hammer binden (`connect_parts`; einarmige Variante möglich) |
| `check_tool` | Werkzeug funktional bewerten (`ObjectEvaluator`), ungeeignet → Abbruch |
| `equip` | Werkzeug aufnehmen – **das Original**, keine Kopie |
| `break` | Stein zerschlagen (`deform_material`, Schlagfolgen bis zum Bruch, höchstens 8 Folgen) |
| `work_copper` | Kupfer kalt verformen (Verformung statt Bruch) |
| `release` | Werkzeug ablegen |
| `collect` | Stücke auswählen (eigene Bruchstücke + angegebene), Ungeeignetes mit Grund abweisen, je Stück einen `carry`-Schritt einfügen; bei Bedarf umplanen (weiteren Stein zerschlagen) |
| `carry` | Stück aufnehmen (eine Hand oder beide Hände), zum Ziel gehen, abliefern (`deposit_in_storage`, `place_building_part`, `put_into_container`) |
| `heat`, `wait_molten`, `pour` | Tiegel in den Testofen, warten bis vollständig flüssig, gießen (gleichartige Schmelzen vereinigen sich, Masse und Energie bleiben erhalten) |
| `check` | Ergebnis messen und Verfahrenswissen verbuchen (`lagern:stone`, `bauen:steinreihe:stone`, Gießverfahren) |

Hingehen: `_move_near` läuft das Ziel aus wechselnder Richtung an (Umplanen bei blockiertem Weg), begrenzt durch
`move_retries`; der Ankunftsradius ist kleiner als der Wunschabstand.

## Werkzeug, Schlag, Bruchstücke

- Der gebundene Hammer ist ein `Assembly` mit **eigener eindeutiger ID**; Stiel, Kopf und Fasern bleiben seine Teile.
- Ausrüsten setzt Träger und Hand; das Modell sitzt am Griffpunkt der animierten Hand (`LivingWorld._place_held`). Es gibt kein zweites Objekt am Boden.
- Schlag: Standpunkt aus Arm- und Werkzeuglänge (`WorkPose`), Ausholen über die Schwungdauer, **genau ein Kontakt je Schlag** (`a.state.contacts`); Schaden berechnet `ToolUseSystem.strike` am Kontaktzeitpunkt. Die Animation liest nur.
- Verbindung und Kopf verschleißen; Überlast bricht die Verbindung (Teile bleiben erhalten).
- Spröder Stein: Schaden = Arbeit / (Masse · Zähigkeit); bei 100 % Bruch in 2 … `max_fragments` Stücke mit exakt aufgeteilter Masse und Wärmeenergie, gleichem Material, Herkunft `bruch:#ID`, Testausrüstungs-Kennzeichen und Behälter werden übertragen.
- Kupfer: plastische Verformung statt Bruch.

## Tragen und Hände

- Eine Hand bis `carry_kg_per_body_kg · Körpermasse · Greifwert` und Griffbreite ≤ `grasp_max_width_m`.
- Zu schwer **oder** zu breit für eine Hand → mit **beiden** Händen bis `carry_limit_two_kg` und `carry_two_max_width_m` (Animation `carry_two`, Gegenstand mittig zwischen den Händen).
- Fehlt die zweite Hand → nachvollziehbar abgelehnt („… eine zweite greiffähige Hand fehlt“). Verliert ein Wesen die haltende Hand, wird abgelegt.
- Nach Ende/Abbruch einer Kette wird getragenes Material (kein Werkzeug) mit einer normalen Ablegehandlung abgelegt.

## Lager, Baustelle, Schmelzen

- **Lager:** nur einzelne, feste, nicht heiße Stücke (≤ `max_temperature_k`); Kapazität nach Masse und Volumen; freier Platz im 0,2-m-Raster. Entnehmen nur durch Aufnehmen.
- **Baustelle Steinreihe:** 3 Plätze im Abstand 0,22 m, je ein Stein 0,12–2,2 kg (lump/block). Verbaute Teile sind fest (nicht greifbar). `evaluate` misst Länge, Höhe, Zusammenhang und ob die Reihe ein Hindernis für die Wegsuche ist – nie aus dem Namen.
- **Schmelzen** ist keine Recyclingaktion: `MaterialProcessSystem.melt_support` weist nicht schmelzbare (Stein „nur fest“), brennbare (Holz, Fasern – Verbrennung nicht simuliert) und behälterunverträgliche Inhalte ab. Der Testofen ist **Testausrüstung**.

## Autonomie (eigener Bedarf) und Modellvorschläge

`WorkSystem.needs` kennt nur Anlässe aus dem **eigenen** Wissen des Wesens:

| Anlass | Bedarf |
|---|---|
| eigene Baustelle mit freien Plätzen | `need_site` · Anteil freier Plätze |
| selbst erzeugte lose Stücke + bekanntes Lager mit Platz | `need_store` |
| bekanntes Gießverfahren + Kupfer + Tiegel + freier Ofen + Form | `need_cast` |
| eigene Steinreihe beginnen | `need_start_site_known`, wenn das Wesen schon **selbst erfolgreich gebaut** hat (Kompetenzerleben); sonst `need_start_site` und nur bei Beharrlichkeit ≥ 0,55 |

Der Nutzwert konkurriert mit allen anderen Optionen (Hunger, Ruhe, Erkunden …). Werkzeugbau aus eigenem Antrieb nur mit
bekanntem Umwickelverfahren (`tool_min_level`). Andere Ziele **pausieren** eine Kette (zweihändig Getragenes wird abgelegt);
`work:continue` setzt fort; nach `pause_max_s` wird abgebrochen.

**Ollama (Anfrageart `work`):** Nach einer gescheiterten eigenen Kette kann das Wesen einen Vorschlag erbitten
(`data/ai/work_schema.json`, `data/ai/prompts/work_system.txt`). `ResponseValidator.validate_work` prüft Schema, IDs (nur
angebotene, dem Wesen bekannte Gegenstände/Lager/Baustellen/Heizungen), erlaubte Schritte, Wissen
(`validate_model_plan`) und aktuelle Voraussetzungen. Ein gültiger Vorschlag wird nur als Option `work:model` abgelegt;
ausgeführt wird er erst, wenn der Entscheider ihn wählt – und dann ausschließlich über geprüfte Handlungen.
Getestet mit dem **SIMULIERTEN** Testdienst; eine echte Ollama-Verbindung ist **nicht verifiziert**.

## Beobachtet: gezielt vs. eigenständig (getrennt dokumentiert)

- **Kontrolliert (gezielt ausgelöst):** alle drei Wege und sieben Fehlerfälle in `tests/test_work_chain.gd` (siehe `docs/test_results.md`).
- **Eigenständig beobachtet** (Beobachtungslauf `_t12_autonomous_run`, Verhalten AN): Nach einer gezielt ausgelösten Steinreihe
  (Vorgeschichte, bei der das Wesen das Binden, Schlagen und Bauen selbst erlernt) und neu hingelegtem Material (wie
  Göttermenü) startete das Testwesen **aus eigenem Bedarf** eine Kette: eigene Baustelle markiert, den eigenen Hammer wieder
  aufgenommen, den neuen großen Stein zerschlagen, drei Steine verbaut. Ohne diese Vorgeschichte (kein Verfahrenswissen)
  wird kein Werkzeug aus eigenem Antrieb gebaut. Ob und wann die Kette gewählt wird, hängt von Hunger und Persönlichkeit ab;
  der Lauf protokolliert das als Messwert, nicht als Pflichtergebnis.

## Anzeige (Spielerdiagnose)

Wesenfenster, Abschnitt **ARBEIT**: Ziel, Status, Herkunft (autonom / gezielt / Modellvorschlag), laufende Handlung mit
Phase, Schritt, Pose, Kontakte, **Werkzeug-ID**, **Zielobjekt**, Bestimmung, **getragene Masse**, transportierte Masse
gesamt, **Fortschritt**, **Abbruchgrund**, Pausegrund und die letzten Verlaufseinträge. Zusätzlich eine kurze
Arbeitsanzeige über dem Wesen. Lagerplätze (Bodenrahmen, Belegung) und Baustellen (Platzmarken leer/belegt) sind sichtbar.
Die schwebenden Beschriftungen (Arbeitsanzeige, Lager, Baustelle) haben eine feste Bildschirmgröße: nah verdecken sie
das Bild nicht, fern bleiben sie lesbar.

## Testszene „Werkzeugkette“

Startbildschirm → **Testszene Werkzeugkette (Testbereich)**. Ein Testwesen, Holzstiel, Steinkopf, Fasern, großer Stein
(2,7 kg, für eine Hand zu schwer und zu groß für einen Bauplatz), mittlerer Stein, Kupferstücke, Holzstück (nicht
schmelzbar), sehr schwerer Block (17,5 kg), Lagerplatz, Baustelle Steinreihe, Testofen mit Tiegel und Form.

Bedienfeld links (zwei Spalten): drei Ketten (lagern, bauen, schmelzen), Speichern (F5) / Laden (F9) mitten in der
Kette, Beobachtungslauf (eigenes Verhalten an/aus) und die Fehlerfälle. Die Knöpfe tragen kurze Beschriftungen
(„▶ lagern: Stein zerschlagen → Lager“, „Fehler: Fasern fehlen“ …); der ausführliche Text erscheint als Hinweis, wenn
die Maus darauf ruht. Am besten jeden Fehlerfall in einer frisch gestarteten Testszene auslösen.

| Fall | Erwartetes Verhalten |
|---|---|
| Fehlendes Material | Fasern entfernt → „Bauteile für einen Hammer fehlen: Fasern nicht bekannt“ (Kette startet nicht) |
| Blockierter Weg | Lager ummauert → Kette stoppt mit „Weg blockiert“, Getragenes wird abgelegt |
| Fehlender Arm | rechter Unterarm entfernt → Hammer einarmig gebunden; zu breites Stück „eine zweite greiffähige Hand fehlt“ |
| Zu schwer | 17,5-kg-Block → „Auch mit beiden Händen zu schwer“, nichts wird teleportiert |
| Unterbrechung | Schlagfolge abgebrochen, Kette pausiert, ausgeführte Schläge bleiben wirksam, Fortsetzung ohne Verdopplung |
| Ungeeignetes Schmelzgut | Holz abgewiesen (brennbar), Kupfer wird geschmolzen und gegossen |
| Fehlende Wärmequelle | Ofen entfernt → „keine Wärmequelle: Ofen #… fehlt“ |

Der normale Spielmodus verwendet denselben Code (Test „Normales Spiel: dieselbe Kette …“ mit Göttermenü-Material).

## Spielparameter

`data/config/technology.json`: `motion` (Anlauf, Toleranzen, Phasen, einarmig), `hands` (`carry_two_max_width_m`),
`storage`, `structures`, `containers`, `work` (Bedarf, Gewichte, Abklingzeiten, `need_model`, `proposal_ttl_s`,
`resume_after_s`). Alle Werte sind **Spielparameter**, keine Messdaten.
