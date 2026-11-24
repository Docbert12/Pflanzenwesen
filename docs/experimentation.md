# Experimente (Prompt 6)

Ein Versuch ist eine **Folge echter Handlungen** über den gemeinsamen `ActionExecutor`. Er erzeugt nichts selbst. Ergebnisse entstehen nur aus Materialien, Geometrie, eingesetzter Energie, Körperfähigkeiten und ausgeführten Schritten.

Module:
- `scripts/technology/experiment_system.gd`: Ablauf, Auswahl, Begrenzung.
- `experiment_record.gd`: Protokoll.
- `scripts/physics/material_process_system.gd`: Bearbeiten, Bruch, Gießen.
- `scripts/technology/test_heater.gd`: Testheizung.

## 1. Versuchsprotokoll (`ExperimentRecord`)
| Feld | Inhalt |
|---|---|
| `id`, `actor_id` | eindeutige ID, handelndes Wesen |
| `question`, `expected` | Fragestellung / erwartete Wirkung |
| `objects_used` | verwendete Gegenstände und Mengen (kg) |
| `sim_initial` / `perceived_initial` | Ausgangszustand: **vollständige Simulationsdaten** (exakte Masse, Maße, Temperatur, ε, Schaden) **getrennt** von dem, was das Wesen wahrnimmt (Aussehen, Form, Temperaturkategorie) |
| `proposed_steps` | vorgeschlagene Arbeitsschritte (Vorgänge, siehe 2) |
| `executed_steps` | tatsächlich ausgeführte Handlungen mit Status, Dauer, Messdaten |
| `effort` | Dauer, Schläge, mechanische Arbeit, Stoffwechselenergie, Heizzufuhr |
| `sim_results` / `perceived_results` | messbare Ergebnisse (Debug) / vom Wesen bemerkte Ergebnisse |
| `failures` | fehlgeschlagene Voraussetzungen und Schritte mit Code |
| `uncertainty`, `outcome`, `status` | Unsicherheit, Resultat, Status `laufend/abgeschlossen/fehlgeschlagen/abgebrochen/unterbrochen` |
| `source`, `hypothesis_id`, `procedure_key`, `learner_id` | Herkunft (eigene Idee, Modell, Verfahren, Testwerkstatt), Bezug zu Hypothese, Verfahren, Lernendem |

**Wahrnehmung ohne Messmittel**
- Temperatur nur als Kategorie: kühl, lauwarm, warm, heiß, sehr heiß, glühend, schmilzt, flüssig.
- Formänderung erst ab 5 % sichtbarer Dickenänderung.
- Verschleiß ab 25 %, Lockerung der Verbindung ab 50 %.
- Exakte Werte erscheinen nur in der **Spielerdiagnose**. Diese ist im Oberflächentext ausdrücklich als „Debug-Wissen, das Wesen kennt diese Werte nicht“ gekennzeichnet.

## 2. Vorgänge und Handlungen
| Vorgang | Handlung | Prüft |
|---|---|---|
| `inspect` | `inspect_object` | Reichweite; berührt kurz (heiß → Verbrennung, wird bemerkt) |
| `equip` / `release` | `equip_tool` / `drop` | freie Hand, Griffbreite, Masse, Temperatur, Flüssigkeit, Reservierung |
| `strike` / `deform` | `strike_target` / `deform_material` | gehaltenes Werkzeug oder Hand, schwingbare Masse, Ziel fest, Reichweite; je Schlag echte Arbeit |
| `connect` / `disconnect` | `connect_parts` / `disconnect_parts` | Methode, Stiel, Kopf, Fasermenge, Temperatur, Reservierung aller drei Teile |
| `heat` | `place_in_heater` | Testheizung frei, Behälter unterstützt, Griff kühl |
| `wait_molten` | `wait` (wiederholt) | Ende bei Flüssiganteil ≥ 95 % oder Zeitlimit |
| `pour` | `pour_into_mold` | Flüssiganteil, Form vorhanden, Formmaterial hält die Temperatur, Platz in der Form, Griff kühl (auch während des Gießens) |
| `demonstrate` / `practice` | `demonstrate_procedure` / `practice_procedure` | wie `connect`/`strike`, zusätzlich Wissensstand; Vorführung sichtbar für Zuschauer |
| `bring` (hintragen und ablegen) | `equip_tool` → `move_to` → `drop` | wie `equip`; wird **automatisch vor** `connect`/`demonstrate`/`practice` ergänzt, wenn Kopf oder Fasern weiter als 70 % der Reichweite vom Stiel liegen; im Protokoll als „automatisch ergänzt“ markiert. Modelle können `bring` nicht selbst vorschlagen |

**Ablauf** (`advance`)
- Vor jedem Schritt prüft `ActionExecutor.dry_run` die Voraussetzungen ohne Seiteneffekte.
- Ist ein Gegenstand außer Reichweite, geht das Wesen hin, höchstens dreimal je Schritt. Liegen die Teile weiter auseinander, als man von einem Standpunkt aus reicht, schlägt der Schritt ehrlich fehl.
- Ist die Hand voll, legt das Wesen zuerst ab.
- Ein Versuch, der an einer Voraussetzung scheitert, wird gemerkt (`tech.failed_plans`). Für 300 s zählt seine Neuheit dann nur 20 %. So wiederholt ein neugieriges Wesen nicht endlos dasselbe Unmögliche.

**Abbruch** durch andere Entscheidung, Tod, Spieler oder Testabbruch:
- Status wird „abgebrochen“. **Der Zwischenstand bleibt**: verformtes Kupfer, verbrauchte Energie, beschädigte Teile, gegossenes Material.
- Ein Verbinden, das vor Abschluss abgebrochen wird, verbraucht keine Fasern und gibt die Reservierungen frei (Test 10).

## 3. Mechanisches Bearbeiten (`MaterialProcessSystem.work_piece`)
Ein Schlag liefert die **begrenzte** wirksame Arbeit W aus dem Schlagmodell (`docs/tools_and_construction.md`).

**Plastisch (Kupfer)**
- Verformung: Δε = W / (σ(ε) · V), höchstens 0,2 je Schlag. σ(ε) = (σ₀ + k · ε) · Warmentfestigung.
- Kennwerte: σ₀ = 70 MPa, k = 400 MPa (Verfestigung). Die Warmentfestigung sinkt linear bis 0,12 am Schmelzpunkt.
- Volumen bleibt gleich: Höhe · e^(−Δε), Breite und Tiefe · e^(Δε/2).
- Gleiche Arbeit bewirkt später weniger Verformung (Kaltverfestigung).
- Jenseits von ε = 1,6 (kalt) entstehen **Risse**: der Schaden steigt.
- **Kupfer muss nicht geschmolzen werden**, um es zu bearbeiten.

**Spröde (Stein, Keramik)**
- Schaden += W / (m · Zähigkeit). Bei Schaden 1 zerbricht das Stück.
- Bruchstücke übernehmen Masse und Wärme exakt, mit derselben Aufteilungsregel wie `DamageSystem`.

**Nicht modelliert:** Wasser und Erde (`not_modelled`).

Alle Kennwerte stehen im Abschnitt `working` der Materialdateien. Es sind **empirische Spielparameter in plausibler Größenordnung**, keine Werkstoffdaten.

## 4. Heizen und Gießen
**Testheizung** (`TestHeater`)
- Wird **ausdrücklich als Testausrüstung** in der Testwerkstatt platziert und **extern versorgt**. Sie ist keine Erfindung der Wesen.
- Leistung: 3500 W.
- Die zugeführte Energie zählt in der Wärmebilanz als Heizzufuhr: `ThermalSystem.heaters[…].supplied_j`.
- Sie heizt den eingesetzten **Behälter** (Keramiktiegel). Die Probe erwärmt sich über den Leitwert Tiegel ↔ Probe (3 W/K).
- Es gibt keine frei erfundene Energiequelle.

**Schmelzen**
- Über das vorhandene Phasenmodell mit latenter Wärme.
- Bei 40 W in 120 s schmilzt Kupfer nicht (Test 7).
- Bei 3500 W wird die Probe (0,14 kg) erst flüssig, nachdem ≈ 4,6·10⁵ J zugeführt wurden. Der Bedarf der Probe allein liegt bei 8,7·10⁴ J; der größte Teil erwärmt den Tiegel.

**Gießen** (`MaterialProcessSystem.pour`)
- Bedingungen:
  - Flüssiganteil ≥ 95 %;
  - Form vorhanden (`mold` mit Hohlraum);
  - Formmaterial hält die Temperatur (`valid_max_k`);
  - genug freies Volumen in der Form;
  - Tiegelgriff kühl.
- Die **ganze Masse und Wärmeenergie** wechselt in ein Gussstück (`ingot`) in der Form.
- Der Kontakt Tiegel ↔ Probe wird durch einen Kontakt Guss ↔ Form (2 W/K) ersetzt.
- Masse und Energie vor und nach dem Gießen sind exakt gleich (Test 8).
- Abkühlung und Erstarrung laufen weiter über Umgebung und Phasenmodell. Die Gesamtbilanz Objekte + Umgebung + Körper − Heizung bleibt geschlossen (Test 8).

**Flüssigkeitsdarstellung:** vereinfacht (glühender Block im Tiegel bzw. in der Form). **Keine Schmelzströmung.**

**Heiße Schmelze tragen:** Flüssiges lässt sich nicht greifen. Der Tiegel lässt sich nur am kühlen Holzgriff bewegen. Der Griff ist mit 0,002 W/K angebunden; zur Begründung siehe `technology.json`.

## 5. Eigenständige Versuche (ohne festen Technologiebaum)
Es gibt **keine Freischaltung** und **keine verpflichtende Entdeckung**. `ExperimentSystem.candidates` bildet Versuche **nur aus dem eigenen Wissen** des Wesens: wahrgenommene Gegenstände (`tech.objects`), bekannte Verfahren, ungeprüfte Hypothesen.

**Mögliche Arten**
- unbekannten Gegenstand untersuchen;
- mit einem Gegenstand auf einen anderen schlagen (auch: bekanntes Verfahren mit anderem Werkzeug abwandeln);
- unbewaffnet schlagen;
- Stiel und Kopf verbinden, wenn Fasern bekannt sind;
- gießen, wenn Tiegel, Heizung und Form bekannt sind;
- eine Hypothese prüfen.

**Begrenzung** (`blocked_reason`, `options`):

| Grenze | Wert |
|---|---|
| Bedarf | Kein Versuch bei Hunger ≥ 0,45; kritische Lagen (Hunger, Gefahr) haben Vorrang |
| Neugier | Nutzen = 0,6 · Neugier · Neuheit · freie Zeit + Bedarf − 0,5 · Vorsicht · Risiko − 0,004 · Weg (m) |
| Neuheit | unbekannt 1; gehört/zugesehen 0,5; versucht 0,35; erfolgreich 0,15 · (1 − Sicherheit) |
| Ressourcen / Fähigkeiten | nur wahrgenommene, freie Gegenstände bis 20 m; Greifhand nötig |
| Risiko | heiße Gegenstände, Bruch |
| Zeitbudget | höchstens 25 % von 600 s; 45 s Abklingzeit nach jedem Versuch |

Ein laufender Versuch konkurriert über `tech:continue` mit allen anderen Optionen im **einzigen** Entscheider (`DecisionSystem`). Wählt das Wesen etwas anderes (z. B. Essen), wird der Versuch abgebrochen. Der Zwischenstand bleibt erhalten.

Es gibt **keine Garantie**, dass eine Technik entdeckt wird. Beobachtungsläufe zeigen: Das neugierige Wesen untersucht und probiert. Das wenig neugierige ruht oft lieber.

## 6. Modellvorschläge (Ollama)
- Auslöser: ein Versuch scheitert oder ein Problem tritt auf, Art `experiment`.
- Kontext (`ContextBuilder`, Art `experiment`):
  - das konkrete Problem;
  - **individuell bekannte** Gegenstände mit wahrgenommenen Eigenschaften;
  - die angebotene Heizung;
  - verfügbare Fähigkeiten;
  - eigene Versuchserfahrungen;
  - die zugelassenen Vorgänge.
- Schema: `data/ai/experiment_schema.json`. Prompt: `data/ai/prompts/experiment_system.txt`.
- Prüfung in `ResponseValidator.validate_experiment`:
  - Stufe 2: Schema, Typen, unbekannte Felder (z. B. „material“);
  - Stufe 3: nur angebotene, bekannte IDs;
  - Stufe 5: nur erlaubte Vorgänge (z. B. kein „build_generator“);
  - Stufe 6: **jeder Schritt über `ActionExecutor.dry_run`** gegen die echte Handlungsschnittstelle (zustandsabhängige Codes wie „Hand voll“ werden geduldet);
  - Stufe 7: Zustandsalter.
- Ergebnis: eine **ungeprüfte Hypothese**, Quelle „Modell (Ollama)“ bzw. „Modell (SIMULIERT)“. Sie erzeugt weder Gegenstand noch Verfahrenswissen (Test 11).
- Erst ein ausgeführter Versuch liefert Evidenz. Die Hypothese wird dann „bestätigt“ oder „nicht bestätigt (Versuch #n)“.
- Die Oberfläche zeigt nie „Technologie erfunden“.
- **Echte Ollama-Verbindung: ungeprüft.** Alle Tests nutzen den SIMULIERTEN Testdienst `MockOllama`.

## 7. Testwerkstatt (`scripts/lab/test_workshop.gd`)
**Start:** Startbildschirm → „Testwerkstatt (Testbereich)“ (eigener Speicherplatz `werkstatt`).

**Ausstattung** (alles markiert als TESTAUSRÜSTUNG)
- 2 Testwesen;
- 3 Steine (2 faustgroß, 1 schwer), 2 Holzstiele, 2 Faserbündel;
- 3 Kupferwürfel (20 mm);
- Keramiktiegel mit fest montiertem Holzgriff, darin 0,14 kg Kupfer;
- Gussform (Keramik);
- Testheizung.

Im normalen Spiel gibt es **nichts davon** (Test 15). Materialien kommen dort nur über das Göttermenü, jetzt auch Pflanzenfasern und Holzstäbe.

**Gezielt auslösbare Versuche** (Werkstattfeld rechts unten; Herkunft „Testwerkstatt (gezielt ausgelöst)“):
1. Stein als Werkzeug: untersuchen, aufnehmen, Kupferprobe schlagen.
2. Stiel und Steinkopf mit Fasern verbinden.
3. Verbundwerkzeug praktisch testen (Kupferprobe).
4. Kupferprobe kalt verformen (16 Schläge).
5. Kupfer im Tiegel erhitzen, warten bis flüssig, in die Form gießen.
6. Wesen A führt das Verbinden vor, B sieht zu. Danach „B übt das Verbinden“.

Mit „Beobachtungslauf“ wird das eigenständige Verhalten der Testwesen ein- bzw. ausgeschaltet. Ohne Grafik misst `tools/observe_workshop.gd -- 1800` dasselbe über 30 min Simulationszeit und listet Versuche, Fehlschlaggründe und Verfahren je Wesen.

**Wichtig:** Ein **gezielt ausgelöster** Versuch beweist, dass der Vorgang funktioniert, **nicht**, dass die Wesen ihn von selbst entdecken würden. Ob und was Wesen selbst ausprobieren, zeigt nur der **Beobachtungslauf**. Seine Ergebnisse werden als Messwert protokolliert, ohne Erfolgspflicht (`docs/test_results.md`).
