# Werkzeuge, Bauteile und Verbindungen (Prompt 6)

Alle Zahlen sind **dokumentierte Spielparameter** in `data/config/technology.json` (Abschnitte `hands`, `strike`, `connection`, `temperature`) und im Abschnitt `working` der Materialdateien. Es ist ein **vereinfachtes Modell**, keine vollständige Werkstoff- oder Biomechaniksimulation.

## 1. Gegenstände in der Welt
- **Materialstück** (`scripts/ecology/material_piece.gd`, erbt `PhysicalObject`): Material, Form (`block`, `rod`, `lump`, `bundle`, `cup`, `mold`, `ingot`), Maße `dims_m`, Masse (Quelle der Wahrheit), Wärmeenergie (Quelle der Wahrheit; Temperatur und Flüssiganteil folgen aus dem Phasenmodell), Hohlraum (Gefäß/Form), Behälter, Träger, Verbund, Verformung ε, Schaden, Verschleiß, Verlauf.
- **Verbund** (`scripts/technology/assembly.gd`): Bauteil-IDs, Abstände der Teile entlang des Griffs, Verbindungen, Griffteil, Arbeitskopf, Träger. Masse und Wärme gehören **nur** den Teilen; der Verbund speichert keine eigene Masse. Damit gibt es keine doppelte Masse.
- **Eindeutigkeit** (`ConstructionSystem.audit`, Teil von `LifeSimulation.audit`): Jedes Teil gehört zu höchstens einem Verbund. Ein Teil im Verbund hat keinen eigenen Träger. Jeder Gegenstand hat höchstens einen Träger, und dieser hält ihn auch. Inhalte stehen in genau einem Behälter, Masse ist nie negativ.

## 2. Greifen und Halten (`ToolUseSystem.check_grasp`)
Ein Wesen kann einen Gegenstand nur halten, wenn alle Bedingungen erfüllt sind:
- eine **freie Greifhand** ist vorhanden; Nahrung und Gegenstand belegen je eine Hand;
- die **Griffbreite** ist höchstens `grasp_max_width_m` (0,10 m);
- die **Masse** ist höchstens `carry_kg_per_body_kg · Körpermasse · Greiffähigkeit`;
- der Gegenstand ist **nicht flüssig** und liegt nicht in einem Behälter;
- der **Griff ist nicht zu heiß** (≤ `handle_safe_k` = 318,15 K).

Ist der Griff zu heiß, wird das Greifen abgewiesen. Die kurze Berührung (`touch_s`) verbrennt dabei die Hand:
- Schaden = (T − 318,15 K) · t · 0,0008, höchstens 0,6.
- Die Wärme fließt bilanziert in den Körper: `ThermalSystem.transfer_to_body`, Leitwert 0,25 W/K, Körper 310 K.

Wird ein gehaltener Gegenstand heiß, lässt das Wesen ihn sofort los (lokaler Reflex in `ToolUseSystem.tick`, keine Modellanfrage).

## 3. Schlagmodell (`ToolUseSystem.swing`, `predict_work`, `strike`)
Der Schwung erfolgt um die Schulter mit Armlänge r aus dem Körperplan.

**Trägheitsmoment**
- I = Handmasse · r² + Σ Teile mᵢ · (r + Abstandᵢ)².
- Stäbe zusätzlich + m·L²/12.
- Ein einzelner Stab wird am Ende gehalten und trifft mit dem anderen Ende.

**Schlagenergie**
- E = min(Körperarbeit, Geschwindigkeitsgrenze).
- Körperarbeit = `body_work_j_per_kg_body` (0,5 J/kg) · Körpermasse · Greiffähigkeit.
- Geschwindigkeitsgrenze = ½ · I · ω_max², mit ω_max = 14 rad/s.
- Leichte Werkzeuge stoßen also an die Geschwindigkeitsgrenze, schwere an die Körperarbeit.

**Wirksame Arbeit am Ziel**

W = E · Kopplung · Härtefaktor · Massenfaktor · Verschleißfaktor

| Faktor | Formel / Wert |
|---|---|
| Kopplung | plastisch 0,8; spröde 0,5; sonst 0,3 |
| Härtefaktor | √(clamp(H_Kopf / H_Ziel, 0, 1)) – weicher Kopf auf hartem Ziel wirkt schwach |
| Massenfaktor | m_eff / (m_eff + 0,05 kg), m_eff = I / d_Kopf² |
| Verschleißfaktor | 1 − 0,5 · Verschleiß |

**Rückprall und Verbindungslast**
- Rückprall = E · (1 − Kopplung · Härtefaktor) · Anteil des Kopfes am Trägheitsmoment.
- Der Rückprall belastet jede Verbindung des Werkzeugs (Abschnitt 4).

**Verschleiß des Kopfes** (`head_wear_per_strike`)
- Verschleiß je Schlag = 0,001 · E · (H_Ziel / H_Kopf)² / (5 · m_Kopf).
- Ein spröder Kopf mit Verschleiß 1 zerbricht in Bruchstücke.
- Ein Kopf aus Pflanzengewebe (Härte 0,3) zerfällt auf Kupfer (Härte 3) schon beim ersten Schlag. Danach trifft der Stiel.

**Unbewaffnet**
- Gilt das Ziel als härter als die Hand, erleidet die Hand Schaden: 0,004 · E · (H_Ziel − H_Hand) / H_Ziel.

**Dauer und Leistung**
- Dauer = 0,7 s + 1,2 · √I.
- Leistung = E / 0,25 / Dauer; über `metabolic_cost` wird sie dem Stoffwechsel abgezogen (Wirkungsgrad 25 %).

## 4. Verbindungen (`ConnectionDefinition`, `ConstructionSystem.connect_lashing`)
Für Wesen gibt es genau **eine** Methode: **Umwickeln mit Pflanzenfasern** (`lashing`). `test_fixture` (fest montiert) ist nur für ausdrücklich platzierte Testausrüstung (Tiegel mit Griff) vorgesehen und für Wesen gesperrt. Andere Methoden (z. B. „kleben“) werden mit `unsupported_connection` abgewiesen.

**Voraussetzungen**
- Stiel: stabförmig, mindestens 0,2 m lang, höchstens 0,05 m dick, formstabiles Material.
- Kopf: kompakt (`block`/`lump`/`ingot`), höchstens 1 kg.
- Bindemittel: tatsächlich `plant_fiber`, sonst `no_binding_material`.
- Alle drei: frei, fest und kühler als die Fasergrenze.

**Fasermenge und Belastbarkeit**
- Bedarf = max(0,004 kg; 0,08 · Kopfmasse).
- Verwendet = min(vorhanden; Bedarf; 0,04 kg). Diese Menge wird **abgetrennt und Bauteil des Verbunds**; der Rest bleibt liegen. Die Masse bleibt exakt erhalten.
- Belastbarkeit je Schlag = verwendete Fasern · Bindeenergie (450 J/kg) · Passung · Geschick.
  - Passung = verwendet / Bedarf.
  - Geschick nach Wissensstufe: keine 0,45 · gehört 0,55 · zugesehen 0,75 · versucht 0,85 · erfolgreich 1,0.

**Belastung im Gebrauch**
- Bei jedem Schlag: Rückprall > Belastbarkeit → **sofortiger Bruch**.
- Sonst steigt der Verschleiß um 0,03 · (Rückprall / Belastbarkeit)². Bei Verschleiß 1 bricht die Verbindung.

**Beim Bruch** (`ConstructionSystem.dissolve`)
- Alle Teile werden wieder einzelne Weltobjekte, die Fasern sind zerrissen (Schaden 1).
- Der Stiel bleibt in der Hand, die übrigen Teile fallen herab.
- Masse und Wärme werden nicht verändert.
- Lösen (`disconnect_parts`) erfolgt geordnet: Die Fasern bleiben ein (gebrauchtes) Faserbündel.

**Zusammengesetzt ist nicht automatisch besser.** Ein schwerer Kopf (0,58 kg), mit nur 5 g Fasern angebunden, hält 0,11 J aus. Der Rückprall auf Kupfer beträgt aber 1,4 J. Die Verbindung bricht beim ersten Schlag (Test 4). Zu schwere Werkzeuge kann das Wesen nicht schwingen (`too_heavy_to_swing`).

## 5. Funktionale Bewertung (`ObjectEvaluator.evaluate`)
Der **Name spielt keine Rolle**. Ein „Hammer“ mit weichem Kopf bekommt dieselbe Bewertung wie derselbe Gegenstand unter anderem Namen (Test 1). Geprüft wird:

| Prüfung | Grundlage |
|---|---|
| Griff erreichbar | Griffbreite ≤ Handbreite |
| Masse tragbar / schwingbar | Körpergrenzen |
| Verbindung belastbar | Belastbarkeit > 0, Verschleiß < 1 |
| Arbeitskopf vorhanden, Form der Kontaktfläche | Kopf `block`/`lump`/`ingot` (flache Fläche, gerundet …) |
| Griff nicht zu heiß | Temperatur des Griffs |
| Kopf härter als Kupfer | Härtefaktor |
| Kopf hält Kupfer stand | Verschleiß je Schlag, Anzahl Schläge bis zum Zerfall (gleiche Formel wie beim echten Schlag) |

**Vorhersage**
- Grundlage ist ein **Referenzstück**, das nicht in der Welt existiert: ein Kupferwürfel mit 2 cm Kante und ein Stein von 0,2 kg.
- Vorhergesagt werden Stauchung je Schlag (Kupfer) und Schaden je Schlag (Stein) mit **denselben Funktionen** wie beim echten Schlag. Test 1 prüft: Der erste Schlag stimmt exakt mit der Vorhersage überein.

**Eignung**
- Alle Prüfungen bestanden („Kopf härter als Kupfer“ ausgenommen) und Stauchung ≥ 0,004 je Schlag.

**Gemessene Vergleichswerte** (Testwerkstatt, Wesen A, Kupferwürfel 20 mm; Messwerte in `docs/test_results.md`):
- Bloße Hand, 16 Schläge: ε ≈ 0,008, dazu Handschaden.
- Faustgroßer Stein in der Hand, 16 Schläge: ε ≈ 0,037.
- Stiel mit Steinkopf: ε ≈ 0,011 je Schlag, Belastbarkeit 3,2 J beim ersten Versuch ohne Geschick.

## 6. Sichtbare Modelle (`scripts/generation/object_generator.gd`)
- Voxelmodelle mit 5 mm Raster aus den **tatsächlichen** Maßen und Materialfarben.
- Glühfarbe je nach Temperatur; Risse und Verschleiß werden dunkler.
- Verbünde bestehen aus den echten Teilen an ihren Abständen, die Umwicklung sitzt sichtbar am Kopf.
- Das gehaltene Objekt sitzt an der Hand (`ToolUseSystem.hand_position`).
- Gussstücke liegen in der Form.
- Ein Modell wird **nur** neu aufgebaut, wenn sich seine Signatur ändert (Maße, ε, Schaden, Phase, Teile). Die Darstellung folgt also den Daten. Ein Modellname ändert nichts am Modell.

## 7. Prompt 6B: Tragen mit zwei Händen, Griffpunkt, Schlag mit Kontaktphase
- **Zwei Hände** (`ToolUseSystem.check_carry`): Ein Stück, das für eine Hand zu schwer (> `carry_kg_per_body_kg · Körpermasse · Greifwert`) oder zu breit (> `grasp_max_width_m`) ist, wird mit beiden freien Händen getragen – bis `carry_limit_two_kg` (Summe beider Greifwerte) und `carry_two_max_width_m`. Fehlt die zweite Hand: „… eine zweite greiffähige Hand fehlt“. Zweihändiges Halten (`hold_mode = "two"`) ist nur zum Tragen, nicht zum Werkzeuggebrauch.
- **Griffpunkt:** Gehaltenes sitzt am Griffrahmen der animierten Hand (`CreatureAnimator.grip_frame`, `WorkPose.tool_frame`): Verbund mit Ursprung am Griffpunkt, Stab am Ende gegriffen, Stück mittig; zweihändig mittig zwischen beiden Händen. Es gibt kein zweites Modell am Boden.
- **Schlag:** Standpunkt so, dass der Werkzeugkopf beim Kontakt auf der Oberkante des Ziels liegt (`WorkPose.contact`, `stand_point`); Ausholen über die Schwungdauer, am Ende genau **ein** Kontakt (`a.state.contacts`), danach Rückkehr. Schaden, Verschleiß und Verbindungsbelastung berechnet `ToolUseSystem.strike` nur am Kontakt.
- **Lösen nach Kettenende:** Getragenes Material wird abgelegt; Werkzeuge dürfen in der Hand bleiben.
- **Schmelzeignung** (`MaterialProcessSystem.melt_support`): Stein „nur fest“, Holz/Fasern brennbar (Verbrennung nicht simuliert), Behältergrenzen → abgewiesen. Gleichartige, vollständig flüssige Stücke in einem Tiegel vereinigen sich vor dem Gießen (`merge_melts`, Masse und Wärmeenergie exakt).
Mehr: `docs/work_chains.md`, `docs/animations.md`.
