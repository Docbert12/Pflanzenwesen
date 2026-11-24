# Physikmodell (Stand 0.3.0-prototype)

## Einheiten
Intern: **m, s, kg, K, J, W**. Die Oberfläche zeigt Temperaturen zusätzlich in °C (T[°C] = T[K] − 273,15).

## Gespeicherte und abgeleitete Größen
Gespeichert je Objekt: Masse *m* [kg] und thermische Energie *E* [J].
Abgeleitet: spezifische Enthalpie *h = E/m*, Temperatur *T(h)*, Flüssiganteil *φ(h)*, Volumen *V = m/ρ*.
Beim Erzeugen gilt exakt *m = ρ · V* (getestet). Wärmeausdehnung und Dichteänderung beim Schmelzen werden **vernachlässigt**: Das Modellvolumen bleibt *m/ρ_fest*.

## Enthalpiemodell (Energiebezug)
Bezug: **Festkörper bei 0 K mit konstanter Wärmekapazität je Phase**. Der absolute Wert hat keine physikalische Bedeutung; nur Differenzen zählen, und auf diesen beruhen alle Bilanzen.

```
fest:        h = c_s · T                              (T < T_m)
Schmelzen:   c_s·T_m ≤ h ≤ c_s·T_m + L    →  T = T_m,  φ = (h − c_s·T_m) / L
flüssig:     h = c_s·T_m + L + c_l·(T − T_m)          (T > T_m)
```
Daraus folgt ohne Sonderregeln: Erwärmen bis T_m, Aufnahme der latenten Wärme L bei konstanter Temperatur, erst danach weiterer Temperaturanstieg. Beim Abkühlen läuft es umgekehrt. Masse wird dabei nicht verändert.
Materialien mit `phase_model = solid_only` (Stein, Holz, Pflanzengewebe) haben nur den festen Ast.

## Wärmeaustausch

**Heizung** (Leistung *P*): pro Schritt *Q = P · Δt*, vollständig dem Ziel zugeführt und bilanziert. Die Heizung stoppt an der oberen Modellgrenze des Materials (z. B. Siedepunkt von Wasser, Zersetzungsannahme bei Holz), weil Verdampfen oder Zersetzen nicht modelliert sind.

**Kühlung / Wärmesenke** (Leistung *P*, Senkentemperatur *T_s*): entzieht *min(P·Δt, E − m·h(T_s))*, also nie unter *T_s*.

**Expliziter Kontakt** zwischen zwei Proben: Leitwert
```
G = A / (L_a/k_a + L_b/k_b)        L = halbe Würfelkante (Zentrum → Kontaktfläche)
```
Wärmemenge pro Schritt mit der **exakten Lösung** für zwei konstante Wärmekapazitäten C₁, C₂:
```
Q = ΔT · (1 − exp(−G·Δt·(1/C₁ + 1/C₂))) / (1/C₁ + 1/C₂)
```
Während des Schmelzens bleibt T konstant; die Kapazität dieses Objekts wird dann als unendlich behandelt (1/C = 0 → Q = G·ΔT·Δt).
**Überschwingschutz:** Q wird zusätzlich so begrenzt (Bisektion), dass das wärmere Objekt nach dem Schritt nicht kälter als das kältere ist. Das gilt auch über Phasenwechsel hinweg.
Jeder Kontakt wird pro Schritt genau einmal berechnet (Schlüssel „kleinere ID:größere ID“; doppeltes Anlegen ist ausgeschlossen).

**Umgebung** als Reservoir mit fester Temperatur *T_amb* (293,15 K): Konvektion mit *G = h · A*, *h* = 10 W/(m²·K) (**Annahme**, ungeprüft), *A* = Würfeloberfläche 6·(V^(1/3))². Gleiche Exponentiallösung mit unendlicher Reservoirkapazität, begrenzt auf *T_amb*. Die aufgenommene Energie wird separat bilanziert.

**Energiebilanz** (in der Oberfläche angezeigt):
```
Σ E_Objekte + E_Umgebung + E_Kühlung − E_Heizung = konstant
```

## Mechanik
Godot übernimmt starre Körper, Schwerkraft (g = 9,81 m/s², aus `simulation.json`) und Kollisionen. Lineare Dämpfung ist 0 (kein künstlicher Luftwiderstand). Fallzeit ohne Luftwiderstand: *t = √(2h/g)*, unabhängig von der Masse.
Die Messung der Aufschlagzeit hat eine Auflösung von einem Physiktick (1/60 s) plus Kontaktverzögerung: gemessen 0,800 s statt 0,7755 s (1,5 Ticks). Alle vier Massen landen im selben Tick.

## Schaden (SPIELMODELL, keine reale Bruchmechanik)
```
Δd = Last [J] / (m · Zähigkeit_Spiel [J/kg]),   d ≤ 1
```
Bei d = 1 brechen spröde (Stein), faserige (Holz) und weiche (Pflanzengewebe) Materialien in 2…max_fragments Teile (zufällige Anteile, Startwert-abhängig). Duktiles Kupfer wird nur als „verformt“ markiert (volumentreue Stauchung in der Darstellung). Auf Wasser und auf teilweise flüssige Proben wirkt keine Last (nicht modelliert).
Fragmente: Massen summieren sich **exakt** zur Ausgangsmasse (der letzte Teil schließt die Bilanz); die Energie wird massenanteilig verteilt, die Temperatur bleibt also gleich. Belastungen kommen nur aus dem Labor (ausdrücklich als Laboreingriff protokolliert); Schäden durch Aufprall sind **nicht** implementiert.

## Teilen und Zusammenführen (Laboroperationen)
Teilen: Anteil 0,05–0,95, nur vollständig feste Proben. Zusammenführen: gleiches Material, beide fest. Neue Energie = Summe der Energien, daraus ergibt sich die Mischtemperatur (Test: 300 K + 400 K → 350 K). Der Schaden wird massengewichtet übernommen. **Zusammenführen ist keine spielbare Herstellungs- oder Schweißfunktion.**

## Modellgrenzen (bewusst nicht modelliert)
- Wärmestrahlung. Eigene Abschätzung ε·σ·A·T⁴ für die 3-cm-Kupferprobe bei 1358 K: etwa 50 W (blank, ε≈0,05) bis 800 W (oxidiert, ε≈0,8). Deshalb bräuchte das reale Schmelzen deutlich mehr Heizleistung als im Labor.
- Temperaturabhängige Stoffwerte (c, k konstant); c_flüssig von Kupfer = c_fest angenommen
- Dichteänderung beim Schmelzen, Wärmeausdehnung, Volumenänderung von Eis
- Verdampfen, Sieden, Zersetzung, Verbrennung, Oxidation
- Strömung von Flüssigkeiten. Flüssige Proben liegen nur als ruhende Schicht im Behälter; der feste Rest wird *auf* der Schmelze gezeigt (Auftrieb/Absinken nicht modelliert)
- Wärmekapazität von Tiegel, Heizplatte und Becherglas
- Automatische Kontaktflächen (Wärmeleitung nur über explizit angelegte Kontakte)
- Temperaturgradienten innerhalb einer Probe (eine Temperatur pro Objekt)

## Materialwerte und Herkunft
Jeder Zahlenwert in `data/materials/*.json` trägt eine `kind`-Kennzeichnung:

| kind | Bedeutung |
|---|---|
| `reference` | Referenzwert eines realen Stoffs, mit Quelle |
| `derived` | aus Quellenwerten berechnet (Rechenweg in `note`), mit Quelle |
| `assumed` | Annahme für eine unspezifische Stoffklasse; `unverified: true`, wenn nicht gegen eine Quelle geprüft |
| `game` | bewusst vereinfachter Spielparameter |
| `not_applicable` | nicht anwendbar, Wert `null` (z. B. Schmelzpunkt von Holz) |

| Material | Modell | ρ kg/m³ | c J/(kg·K) | k W/(m·K) | T_m K | L J/kg | Gültig bis K |
|---|---|---|---|---|---|---|---|
| Kupfer | rein Cu | 8960 (ref) | 385 fest (ref), 385 flüssig (Annahme) | 401 (ref) | 1357,77 (ref) | 208 670 (abgel.) | 2835 Siedep. |
| Stein | Granit | 2700 (Annahme) | 790 (ref) | 2,7 (ref) | – | – | 623,15 |
| Holz | trockenes Hartholz | 700 (Annahme) | 1236 (abgel.) | 0,17 (Annahme) | – | – | 500 (Annahme) |
| Wasser | H₂O, 1 atm | 998,2 (ref) | 2108 Eis / 4182 (ref) | 0,598 (ref) | 273,15 (ref) | 333 400 (ref) | 373,15 Siedep. |
| Pflanzengewebe | 80 % Wasser (Annahme) | 950 (Spiel) | 3702 (abgel.) | 0,51 (abgel., ungeprüft) | – | – | 333,15 (Spiel) |
| Erde (neu in 0.2) | trockener Mineralboden | 1400 (abgel., ungeprüft) | 870 (ref) | 0,3 (Annahme) | – | – | 1000 (Spiel) |

### Quellen (in den JSON-Dateien je Wert verlinkt)
- PPPL ARIES, *Pure Copper*: https://aries.pppl.gov/LIB/PROPS/PANOS/cu.html
- Wikiwand/Wikipedia, *Copper*: https://wikiwand.com/en/articles/copper
- KnowledgeDoor, *Copper – Elements Handbook*: https://www.knowledgedoor.com/2/elements_handbook/copper.html
- MakeItFrom, *Engineering Porcelain vs. Granite*: https://www.makeitfrom.com/compare/Engineering-Porcelain/Granite
- Engineering ToolBox, *Sensible Heat Storage* (Granit): https://www.engineeringtoolbox.com/sensible-heat-storage-d_1217.html
- Glass & Zelinka (2010), Wood Handbook Kap. 4, FPL-GTR-190: https://research.fs.usda.gov/treesearch/37428
- chemics.wood (Umsetzung Gl. 4-16a): https://chemics.readthedocs.io/en/latest/_modules/chemics/wood.html
- Wood Combustion Lesson 02 (FPL-Daten): https://is.muni.cz/el/1423/podzim2013/MEB423/um/Wood_Combustion_Lesson_02.pdf
- nTop/matweb, *Water*: https://docs.ntop.com/Product-Documentation/ntop/block-documentation/blocks/fluids-beta/material-information/water.md
- Engineering ToolBox, *Water – Thermophysical Properties*: https://www.engineeringtoolbox.com/water-thermal-properties-d_162.html
- The Engineering Mindset, Wasser-Tabelle: https://theengineeringmindset.com/?p=434
- FH Erfurt, *Formula Basics Water*: https://www.fh-erfurt.de/fileadmin/Dokumente/Module/BKR/Orbit/Formula/General/e/B_3_6_13-Formula-Basics-Water-ENG.pdf
- METER Group, *Thermal properties of soil materials* (nach Campbell & Norman 1998), für Erde: https://publications.metergroup.com/Sales%20and%20Support/METER%20Environment/Website%20Articles/understanding-rho-changes-changing-density-temperature-composition-water-content-backfill.pdf
- Benincá et al., *Thermophysical properties of mate leaves*: https://searchworks.jioinstitute.edu.in/articles/edsair__edsair.doi...........83820d0bfc947205715c93f7ed765b89

Die Quellen wurden über eine Websuche gefunden; die Werte stammen aus den dort angezeigten Tabellen und Auszügen. Die Primärliteratur (z. B. Tabelle 4-7 des Wood Handbook) wurde **nicht** vollständig eingesehen. Solche Werte sind als `unverified` markiert.

## Numerische Genauigkeit (gemessen, Godot 4.7.2)
| Prüfung | Ergebnis |
|---|---|
| Geschlossener Austausch Cu/Stein/Wasser, 600 s, dt = 1/60 s | max. relative Energieabweichung 3,5·10⁻¹⁵ |
| Kontakt Cu–Stein, 600 s, dt = 1/120 … 10 s | Abweichung zur analytischen Lösung ≤ 6,8·10⁻¹¹ K für alle Schritte |
| Heizen 1000 W mit Umgebungsverlust, T nach 60 s | dt 1/60: −1,5·10⁻³ K, dt 1/30: −4,6·10⁻³ K gegenüber dt 1/120 |
| Flüssiganteil nach 150 s (im Schmelzen) | dt 1/30: −1,4·10⁻⁵ gegenüber dt 1/120 |
| Schmelzen 0,2419 kg Cu: Beginn / vollständig | 99 175 J / 149 650 J (erwartet 99 158 / 149 639 J; Abweichung < P·Δt = 25 J, weil nur pro Schritt geprüft wird) |


---

# Ergänzungen aus Prompt 2

## Erde (`soil`)
Die Dichte 1400 kg/m³ ist abgeleitet: Feststoffdichte der Bodenminerale 2650 kg/m³ (Quelle METER/Campbell & Norman) × (1 − 0,47 angenommene Porosität). Die spezifische Wärme 870 J/(kg·K) ist der Quellenwert für Bodenminerale. Die Wärmeleitfähigkeit 0,3 W/(m·K) für trockenen, lockeren Boden ist eine ungeprüfte Annahme. Gras-, Erd- und Wurzelbeetzellen haben alle dieses Material; nur das Aussehen unterscheidet sich.

## Terrainmasse
Masse je Zelle = Zellvolumen (0,5 m)³ = 0,125 m³ × Dichte des Physikmaterials der Zelle. Eine Erdzelle wiegt 175 kg, eine Steinzelle 337,5 kg. Die Terrainmasse der Testkarte beträgt bei Startwert 12345 etwa 16 136 t.

## Vereinfachte Abstützung (keine Baustatik)
- Eine feste Zelle gilt als gestützt, wenn sie über Flächennachbarn (6er-Nachbarschaft) mit einer verankerten Zelle verbunden ist (Grundgestein in der untersten Lage, nicht editierbar).
- Nach jedem Entfernen werden die Verbände der 6 Nachbarzellen per Breitensuche geprüft.
- Findet die Suche keine Verankerung und umfasst der Verband ≤ 256 Zellen, wird er abgetrennt. Die Zellen werden aus dem Terrain gelöscht und als **ein** RigidBody erzeugt, dazu je Material ein `PhysicalObject` mit Volumen = Zellanzahl · 0,125 m³ (Masse = Dichte · Volumen). Materie existiert so nie doppelt (getestet: Terrainmasse + Bruchstückmasse bleibt gleich).
- **Oberhalb der Grenzen:**
  - Hat die Suche nach 257 Zellen noch keine Verankerung gefunden, gilt der Verband als gestützt und bleibt stehen. Das trifft fast immer zusammenhängendes Terrain. Echte große Überhänge halten sich dadurch im Modell ebenfalls.
  - Sind bereits 6 Bruchstücke beweglich, bleibt ein weiterer abgetrennter Verband als Terrain stehen (Ereignis `fragment_limit_reached`).
- Material, Festigkeit, Last und Hebel spielen **keine** Rolle. Bruchstücke werden nicht wieder ins Terrain eingefügt. Als Kollision dient ihre konvexe Hülle (Näherung). Fällt ein Bruchstück unter y = −20 m, wird es eingefroren; seine Masse bleibt registriert.

## Wasser: mengenbasiertes Höhenmodell (keine Flüssigkeitsphysik)
- Je Spalte (x, z) wird eine Wassermenge V [m³] geführt. Sie liegt auf der höchsten festen Zelle der Spalte (Bodenhöhe g).
- Spiegel h = g · 0,5 m + V / A mit Spaltenfläche A = 0,25 m².
- Alle 0,1 s fließt zwischen 4-Nachbarn i, j: q = min(k · Δt · (hᵢ − hⱼ) · A, Vᵢ / 4), mit k · Δt ≤ 0,25 (Spielparameter flow_rate_per_s = 2,0).
  - Jede Spalte gibt je Nachbar höchstens ¼ ihres Wassers ab. Mengen werden deshalb nie negativ.
  - Die Begrenzung auf ¼ der Spiegeldifferenz verhindert Überschwingen.
- Jede Übertragung wird paarweise gebucht (−q/+q): Die Gesamtmenge ist bis auf Rundungsfehler erhalten (gemessen ≤ 3·10⁻¹⁶ relativ).
- **Barrieren:** Liegt der Boden eines Nachbarn über dem eigenen Spiegel, ist dessen Spiegel höher und es fließt nichts hinüber (getestet).
- **Untergrundänderungen** aktualisieren die Bodenhöhe der Spalte. Die Wassermenge bleibt gleich: Eine Zelle unter Wasser hebt den Spiegel. Eine Zelle über dem Spiegel setzt das Wasser der Spalte auf die neue Oberfläche (Modellgrenze).
- **Grenzen:**
  - Nur eine Wasserschicht je Spalte.
  - Höhlen und Überhänge (Luft unter festen Zellen) werden nicht gefüllt.
  - Mehrere Wasserebenen übereinander sind nicht möglich.
  - Kein Druck, keine Strömungsgeschwindigkeit, keine Verdunstung, kein Auftrieb für Bruchstücke, keine Wärme im Wasser.
  - Am Kartenrand fließt kein Wasser ab.

## Masse von Weltobjekten (Lebensbaum, Pflanzen, Pilze)
Modellvolumen je Material = Zellanzahl · Voxelvolumen · Füllanteil. Masse = Modellvolumen · Dichte.

| Typ | Voxel | Füllanteil (Spielannahme) |
|---|---|---|
| Stamm, Äste, Wurzeln (Holz) | 0,2 m | 1,0 |
| Baumlaub | 0,2 m | 0,02 |
| Buschlaub | 0,05 m | 0,08 |
| Grashalme, Farnfiedern | 0,05 m | 0,1 |
| Farnstiele | 0,05 m | 0,3 |
| Beeren, Pilze | 0,05 m | 1,0 |

Ohne Füllanteil hätte die Laubkrone (lauter 0,2-m-Würfel) etwa 37 t gewogen. Mit Füllanteil wiegt sie etwa 1 t, das Holz etwa 5,2 t (Startwert 12345). Das sind Spielannahmen, keine gemessenen Werte. Pilzgewebe wird vorläufig wie Pflanzengewebe behandelt.

## Körpermassen der Wesen
- **Angezeigte Größe:** Hüllquader des Teils (`size`).
- **Modellvolumen** (Grundlage der Masse) = Hüllquader × Formfaktor:

| Form | Formfaktor |
|---|---|
| Quader | 1 |
| Ellipsoid | π/6 |
| Zylinder | π/4 |
| Fuß | 0,85 (Näherung) |
| Blatt | 0,6 (Näherung) |
| Haken | 0,35 (Näherung) |

- **Geometrisches Volumen** = Anzahl der Darstellungsvoxel (2 cm) · (0,02 m)³. Es wird nur zum Vergleich angezeigt und weicht durch die Rasterung um einige Prozent ab (z. B. Rumpf 4968 cm³ Modell gegenüber 4800 cm³ Voxel).
- **Masse** = Modellvolumen · Dichte (Pflanzengewebe 950, Holz 700, Kupfer 8960 kg/m³). Ein Wesen mit 88 cm wiegt etwa 16,7 kg. Die Excel-Spalten „Gewicht_kg“ werden nicht verwendet.
- Blätter sind 2 cm dick modelliert. Reale Blätter sind dünner, die Blattmasse ist daher zu hoch (Spielvereinfachung).


# Ergänzungen aus Prompt 3 – Lebenssimulation

Vollständige Beschreibung: `docs/life_simulation.md`. Hier steht nur, was die physikalischen Größen betrifft.

## Körpermasse lebender Wesen
- **Masse:** Σ Dichte × Modellvolumen der *vorhandenen* Teile (`BodyPlan.total_mass`), wie in Prompt 2. Bei Startwert 12345 wiegen die 50 Wesen etwa 11–19 kg.
- **Prothesen:** Sie zählen mit ihrem Material (gemessen: Holzstütze ≈ 0,13 kg, Kupferhaken ≈ 1,7 kg).
- **Wirkung der Masse:** Sie bestimmt Grundumsatz, Bewegungskosten und Speicherkapazität. Nach jeder Körperänderung wird sie neu berechnet.

## Bewegung (kinematisch, keine Godot-Körperphysik)
- **Bewegung:** Wesen bewegen sich mit fester Geschwindigkeit entlang eines Spaltenwegs, ohne Beschleunigung, Trägheit oder Reibung.
- **Höhe:** Die Höhe folgt der Bodenoberfläche der aktuellen Spalte (geglättet, mindestens 2,5 m/s Anpassung).
- **Kollision:** Statt Körpern werden die Voxeldaten vor jeder neuen Spalte geprüft (Begehbarkeit, Stufe ≤ 0,5 m hinauf, ≤ 1 m hinab).
- **Gründe:** Determinismus für Speichern/Laden und Tests; keine 50 Rigid-Bodies mit Gelenkketten.
- **Grenzen:** kein Fallen, kein Schieben, kein Stoß. Wesen untereinander weichen nur weich aus (Abstoßung im Umkreis von 0,45 m).

## Energiebilanz der Wesen (Spielbiologie, keine Physik)
Die Energieeinheit ist Joule, gezählt wird aber in **Spielwerten**:
- Grundumsatz 1 W/kg;
- Bewegung 2 J/(kg·m);
- Licht 230 W je m² Blattfläche bei vollem Licht.

Die Werte sind so gewählt, dass ein Wesen mit vollem Speicher ohne Nahrung etwa 25 Minuten Simulationszeit durchhält (Startfüllung 40–75 % → 10–19 Minuten). Der Vergleich mit realen Stoffwechselraten ist nicht sinnvoll.

Bilanzgleichung und Prüfung: `docs/life_simulation.md` (Abweichung in allen Tests < 10⁻⁶ J).

## Nahrungsmasse
- **Erhaltung:** Nahrung ist eine Masse in kg und bleibt exakt erhalten: Quellen + Portionen + gegessen = Startmenge (+ Testnachfüllung).
- **Aufteilung:** Gegessene Masse teilt sich in assimiliert (80 %) und Abfall (20 %).
- **Verbleib:** Der Abfall wird nur bilanziert, er erscheint nicht als Weltobjekt.
- **Weltmassen:** Nahrungsquellen sind keine `PhysicalObject`. Die physikalische Masse der Pflanzenmodelle (Prompt 2) bleibt unverändert, sie schrumpft nicht beim Essen, nur die Darstellung. Diese Trennung ist bewusst und wurde noch nicht vereinheitlicht.
