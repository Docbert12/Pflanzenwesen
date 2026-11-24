# Geist und Lernen (Stand 0.4.0-prototype – Prompt 4)

> Ergänzt in 0.5.0 (Prompt 5): Hörensagen, Gespräche und Modellvorschläge – siehe `docs/communication.md` und `docs/ai_integration.md`. Gehörtes wird nie als Beleg in die hier beschriebenen Überzeugungen übernommen.

Alle Zahlen sind **Spielparameter** in `data/config/mind.json`. Die Excel enthält keine Persönlichkeitswerte; aus ihr stammen nur die Verhaltensvorlagen KI004 „Erkunden“ und KI005 „Sozial“ als Orientierung. Es gibt keine neuronalen Netze und kein Sprachmodell. Alles beruht auf lokalen Regeln und strukturierten Daten.

## Fünf getrennte Ebenen

| Ebene | Wo | Inhalt | Wer liest sie |
|---|---|---|---|
| 1. Weltzustand | `LifeContext` (Wesen, Nahrung, Gegenstände), `EventLog` | was tatsächlich ist und geschah | Simulation, Spieler, Diagnose |
| 2. Beobachtung | `Observation` (kurzlebig) | was **ein** Wesen davon wahrgenommen hat | `LearningSystem` dieses Wesens |
| 3. Erinnerung | `MemoryStore` | eigene, begrenzte Kopie bedeutsamer Beobachtungen | Entscheidung, Anzeige |
| 4. Vermutung | `BeliefStore`, `RelationshipStore` | Häufigkeiten und Vertrauen aus eigenen Erfahrungen | Entscheidung, Anzeige |
| 5. Entscheidung | `DecisionSystem` → `ActionExecutor` | gewählte Option mit Bewertungsbeiträgen | Handlungssystem |

- **Kein Allwissen:** Das globale Ereignisprotokoll liest **kein** Wesen. Der Test leert das Protokoll; der Geist bleibt danach unverändert und enthält keine ungültigen Verweise.
- **Weltfakten verteilen:** Ein Weltfakt erreicht einen Geist nur über `LifeContext.publish` → `Perception.broadcast`.

**Bekannte Vereinfachung:** Eine Nahrungsquelle, die nicht mehr existiert, verschwindet aus der Merkliste, ohne dass das Wesen das gesehen haben muss. Das verhindert ungültige Verweise. Bei einem einzelnen verschwundenen Bissen ist das ein kleiner Informationsvorsprung.

## Persönlichkeit (`scripts/mind/personality.gd`)
Es gibt fünf Werte zwischen 0,05 und 0,95:

| Wert | wirkt auf |
|---|---|
| Neugier | Erkunden, gelegentliches Ausprobieren von „Arme heben“, Wert eines Materialfunds |
| Geselligkeit | Annäherung an andere, Bereitschaft zu bitten |
| Hilfsbereitschaft | Geben auf Bitte, Anbieten, Sammeln für andere |
| Vorsicht | Abschlag für unsichere Optionen, ein Geschenk wirkt bei Sättigung eher wie ein Schreck |
| Beharrlichkeit | Mindestbindung an ein gewähltes Ziel |

- **Erzeugung:** Die Werte entstehen reproduzierbar aus dem Körper-Startwert (`plan_seed`) plus einem Salz. Sie sind annähernd glockenförmig um 0,5 verteilt, mit einer Streuung von etwa 0,18 (Test: Mittel 0,499 über 1000 Werte).
- **Keine Kopplung:** Sie hängen nicht an Farbe, Art, Körperform oder Mutation. Es gibt kein „gut/böse“ und keine Berufsklasse.
- **Stabilität:** Die Werte ändern sich in dieser Version nie. Kurzfristige Zustände wie Hunger stehen im Stoffwechsel, nicht hier.
- **Grenze:** Die Werte sind grobe Regler, keine psychologische Theorie. Die Wirkung ist klein und nur in Kombination mit Bedarf und Erfahrung sichtbar.

## Wahrnehmung von Ereignissen (`perception.gd: broadcast`)
Ein beobachtbares Ereignis enthält Typ, Handelnden, Ziel, Ort, sichtbare Folgen und eine Sichtweite (Gesten 10 m, Eingriffe 14 m).

**Wer es empfängt:**
- nur lebende Wesen in Reichweite (Sichtweite und Wahrnehmungsradius × Kopffunktion);
- mit freier Sichtlinie (Voxel-Strahl von Augenhöhe);
- mit einer Qualität ≥ 0,15. Die Qualität beträgt 1 − 0,6 · Entfernung/Reichweite.

Wer selbst Handelnder oder Ziel ist, nimmt seine Beteiligung immer wahr (Qualität 1).

**Effizienz:** Kandidaten kommen aus dem räumlichen Raster, und je Kandidat gibt es höchstens einen Strahl. Es gibt keine Paarprüfung aller Wesen. Gemessen in 10 Minuten: 495 Ereignisse, 8467 Strahlen, 5901 Beobachtungen.

**Die Beobachtung enthält nicht:**
- Absichten anderer;
- verdeckte Ursachen. Eine Verletzung wird als `injury_visible` mit `ursache_sichtbar: false` wahrgenommen;
- die Ereigniszuordnung aus dem Göttermenü.

**Quellenart:** `{"kind": "eigene_beobachtung"}`. Die Struktur ist für spätere Mitteilungen vorbereitet (`via`, `chain`), aber es gibt noch kein Gesprächssystem.

## Erinnerungen (`memory_store.gd`)
- **Inhalt:** ID, Typ, Handelnder, Ziel, Beteiligte, Ort, wahrgenommene Folgen, Bedeutung, Sicherheit (= Beobachtungsqualität), erster und letzter Zeitpunkt, Anzahl, Quelle. Die Erinnerung ist eine **eigene Kopie**, kein Verweis auf das Protokoll.
- **Bedeutung:** Sie kommt aus einer Tabelle je Ereignistyp. Eigene Beteiligung zählt mehr: Hilfe erhalten 0,5, Eingriff 0,55, Tod gesehen 0,6 …
- **Speichern:** nur ab einer Bedeutung von 0,08.
- **Zugänglichkeit:** exp(−Δt · ln2 / (300 s · (1 + 4 · Bedeutung))). Wichtiges verblasst langsamer.
- **Verdichtung:**
  - Wann: gleicher Typ, gleicher Handelnder, gleiches Ziel, gleiche 4-m-Zelle, innerhalb von 120 s.
  - Wirkung: Die Anzahl steigt, der letzte Zeitpunkt wird aktualisiert, die Bedeutung ist das Maximum.
  - Sicherheit: das **Minimum**. Unsicheres wird nie gewisser, und es entsteht kein neues Ereignis.
- **Kapazität:** 64 Einträge. Bei Überlauf wird das Kleinste aus Bedeutung × Zugänglichkeit vergessen und gezählt.
- **Abruf:** nach Beteiligtem, Typ, Typenliste, Ort mit Radius und Zeitpunkt; sortiert nach Bedeutung × Zugänglichkeit.

## Überzeugungen (`belief_store.gd`) – das Lernmodell
Jede Hypothese hat Schlüssel, Art, Gegenstand, Gültigkeitsbereich (`self` bzw. `others`), α, β, Zähler und die letzten 6 Belege dafür und dagegen. Dazu kommen ein erlebter Wert und die Aktualisierungszeit.

```
Vergessen vor jeder Aktualisierung:  α ← α₀ + (α − α₀)·0,97   β ← β₀ + (β − β₀)·0,97      (α₀ = β₀ = 1)
Erfolg mit Gewicht w ≤ 1:            α += w        Gegenbeispiel:  β += w
geschätzte Häufigkeit                p = α / (α + β)
wirksame Erfahrungsmenge             n = α + β − 2   (gedeckelt auf 30)
Konfidenz                            n / (n + 4)     → nach einer Erfahrung höchstens 0,2
erlebter Wert                        gleitender Mittelwert, Schrittweite ≥ 1/10 (getrennt von p und Konfidenz)
```

**Arten:**

| Art | Aussage (Anzeige) | Aktualisierung |
|---|---|---|
| `food_place` | „Bei Ort (x,z) finde ich Nahrung“ | eigenes Aufnehmen/Essen ✓, leere Quelle ✗ |
| `helper` | „#n gibt mir Nahrung, wenn ich bitte“ | erhaltene Gabe ✓, Ablehnung ✗ |
| `gift_after_action` | „Nach eigenem X folgte ein auffälliges Ereignis“ | siehe Belohnungszuordnung |
| `gift_after_other` | „Nach X eines anderen Wesens folgte …“ | bei Eingriffen an anderen |
| `gift_base` | Grundhäufigkeit auffälliger Ereignisse bei mir | alle 12 s: Treffer ja/nein |

**Kapazität:** 32 Hypothesen. Die Grundhäufigkeit wird nie verdrängt.

## Beziehungen (`relationship_store.gd`)
Beziehungen sind gerichtet: A→B ist unabhängig von B→A (Test B).

**Getrennte Größen:**
- Vertrautheit 0…1: wächst mit Beobachtung und Begegnung, sinkt langsam;
- Vertrauen als Beta-Schätzung aus eigener Erfahrung;
- erhaltene und gegebene Hilfe;
- Ablehnungen und negative Erlebnisse;
- beobachtete Hilfe an Dritte;
- Ähnlichkeit und Herkunft. Die Herkunft ist bei der Startpopulation „unbekannt“.

**Ähnlichkeit:** Sie kommt nur aus **sichtbaren** Merkmalen: Hautfarbe, Größe, Blattform, Blattzahl, fehlende Teile (`visible_traits`). Verborgene Gene werden nicht gelesen.

**Einfluss der Ähnlichkeit:**
- Anfangsvertrautheit bis 0,12;
- Anfangsvertrauen über α₀ = 1 + 0,6 · Ähnlichkeit, bei voller Ähnlichkeit also höchstens 0,62.

Eigene Erfahrung überwiegt schnell. In Test F stieg das Vertrauen zum unähnlichen Helfer nach 3 Hilfen von 0,55 auf 0,81, während es zum ähnlichen Wesen bei 0,61 blieb.

**Gewichte der Vertrauensänderung:**

| Erfahrung | Gewicht |
|---|---|
| erhaltene Hilfe | +1,0 |
| beobachtete Hilfe an Dritte | +0,25 · Qualität |
| Ablehnung, wenn der Ablehnende sichtbar Nahrung trug | −0,3 |
| Ablehnung ohne sichtbare Nahrung | 0 |

Die Ablehnung ist bewusst **kein schwerer Vertrauensbruch**: Gemessen sank das Vertrauen von 0,59 auf 0,53.

**Ehrlichkeit:** Das Feld `honesty` ist vorbereitet, aber immer `null` und wird nicht angezeigt. Ohne Sprache gibt es keine Grundlage dafür.

## Belohnungszuordnung (`scripts/god/reward_association.gd`)
**Auslöser:** Ein Wesen hat einen Eingriff gesehen (`food_appeared`, `material_appeared`, `healed`).

**Liegt der Eingriff bei mir** (Ziel ich oder ≤ 2 m):
- **Kandidaten:** eigene Handlungen, die höchstens 12 s vorher endeten, sowie die gerade laufende Handlung mit Δt = 0.
- **Gewicht:** wᵢ = exp(−Δtᵢ / 4 s), normiert auf Summe 1. Nur Gewichte ≥ 0,15 zählen, jede Handlung höchstens einmal. So verstärkt ein Eingriff nicht alle kürzlichen Handlungen gleich: Im Test erhielt „Arme heben“ (0,5 s vorher) 0,92, „Warten“ (8 s vorher) nichts.
- **Wirkung:** `gift_after_action:X` erhält einen Erfolg mit Gewicht wᵢ · Qualität und dem **Wert für das Wesen**. Der Treffer zählt außerdem für die Grundhäufigkeit.

**Liegt der Eingriff bei einem anderen:**
- Er wird dessen von mir wahrgenommenen Gesten im Fenster zugeordnet (`gift_after_other`). Der Beobachter bildet also eine **andere Erklärung** (Test D).
- Ohne wahrgenommene Geste steht dort „keine Erklärung“.

**Wert für das Wesen** (tatsächliche Folgen, nicht „Belohnung an sich“):

| Eingriff | Wert |
|---|---|
| Nahrung | Hunger + 0,1 − 0,2 · Vorsicht. Gemessen: hungrig 0,92, satt und vorsichtig −0,04. |
| Heilung | 0,6 + geheilter Schaden, wenn ich geheilt wurde |
| Material | 0,1 + 0,2 · Neugier − 0,2 · Vorsicht |

**Ausbleiben:** Endet eine eigene Handlung, ohne dass innerhalb von 12 s ein Ereignis folgt, zählt das als **Gegenbeispiel**, aber nur für bereits bestehende Hypothesen.

**Wiederholen:** Der erwartete Nutzen einer Wiederholung ist (p(Ereignis | X) − p(Grundhäufigkeit)) × erlebter Wert × Konfidenz. Die Konfidenz wird getrennt angezeigt.

### Was das vereinfachte System NICHT kann
- **Ursache:** Es erkennt **keine Ursache**. Gespeichert wird nur, wie oft etwas zeitlich nach etwas anderem kam. „Arme heben → Geschenk“ kann reiner Zufall oder Spielerlaune sein, und das Wesen kann das nicht unterscheiden.
- **Störgrößen:** Es gibt keine Kontrolle für Störgrößen: Ort, Tageszeit, Anwesenheit anderer. Der einzige Vergleich ist die Grundhäufigkeit in gleich langen Zeitfenstern.
- **Rückfragen:** Es gibt kein Gegenfaktisches („was wäre ohne die Geste geschehen“) und kein gezieltes Experimentieren.
- **Verzögerung:** Liegt die Folge mehr als 12 s zurück, wird sie nicht zugeordnet.
- **Mehrere Ursachen:** Mehrere gleichzeitige Ursachen werden nur über die Zeitgewichtung aufgeteilt, nicht über ihre Wirkung.
- **Nach Laden:** Nach dem Laden eines alten Spielstands ist die Vergangenheit unbekannt; es werden keine Erinnerungen erfunden.

## Entscheidungen (`decision_system.gd`, `goal_manager.gd`)
`DecisionSystem.decide` ist der **einzige** Entscheider. `BasicBehavior` enthält nur noch Ausführungshilfen: Nahrung aufsuchen, erkunden, warten.

**Ablauf:**
- **Takt:** alle 0,5 s, je Wesen versetzt, nur ohne laufende Handlung.
- **Bewertung:** Alle gültigen Optionen bekommen einen Nutzwert aus benannten Beiträgen. Die besten vier werden der Reihe nach versucht.
- **Protokoll:** Bewertung und Gründe stehen in `Creature.decision` und erscheinen im Beobachtungsfenster.

| Option | wichtigste Beiträge |
|---|---|
| getragene Nahrung essen / Nahrung aufsuchen / suchen | Bedarf 1,2 · glatt(0,3…0,9, Hunger); Überleben +2,5 ab 80 % Hunger; Wegkosten 0,015/m (≤ 0,3) |
| um Nahrung bitten (Träger sichtbar) | 0,85 · Bedarf; Vertrauen; Geselligkeit 0,3 · g; Wegvergleich Träger ↔ nächste Quelle; Unsicherheit · Vorsicht |
| auf Bitte geben / ablehnen | Bereitschaft = 0,6·Hilfsb. + 0,3·Vertrauen + 0,2·Vertrautheit − 0,9·Hunger − 0,15 |
| anbieten, für andere sammeln | Hilfsbereitschaft, Vertrauen, beobachtete Bitten |
| annähern, erkunden | Geselligkeit bzw. Neugier × freier Spielraum (1 − Bedarf) |
| gelernte Handlung wiederholen | erwarteter Nutzen (siehe oben) × freier Spielraum, Abschlag Unsicherheit |
| ruhen | 0,15 + 0,05 · (1 − Neugier) |

**Schutz gegen Zielwechsel und Schleifen:**
- **Bindung:** Ein Ziel hält mindestens 6 s · (0,5 + Beharrlichkeit). Während dieser Zeit bekommt es +0,15, außer bei kritischem Hunger.
- **Wartezeiten beim Bitten:** 15 s allgemein, 60 s je Ziel nach unbeantworteter Bitte, 90 s nach Ablehnung.
- **Neuplanung:** Wegsuche wie in Prompt 3.
- **Erfolglose Suche:** Nach 3 erfolglosen Erkundungen wartet ein hungriges Wesen 8 s und sucht danach erneut (wie in Prompt 3).

**Kritischer Hunger:** Ab 80 % Hunger erhält Nahrung +2,5, und Nicht-Überlebensziele schrumpfen mit (1 − Bedarf). Ergebnis im Test: Eine stark gelernte Vorliebe („Arme heben“, Konfidenz hoch) wird versorgt gewählt, bei kritischem Hunger aber nicht.

**Zielvorschläge (für Ollama vorbereitet):** `GoalManager.suggest(wesen, ziel, quelle, gewicht)`.
- Ein Vorschlag ist nur ein **begrenzter Zuschlag** (≤ 0,2) für eine bereits gültige Option desselben Entscheiders.
- Er gilt 30 s, höchstens 3 Vorschläge gleichzeitig. Unbekannte Ziele werden abgewiesen.
- Es gibt keine Netzwerkverbindung und keinen zweiten Entscheider.

## Soziale Handlungen
| Handlung | Reichweite | Dauer/Zeitlimit | Wirkung | Abbruch |
|---|---|---|---|---|
| `request_food` | ≤ 3 m, Sichtweite der Geste 10 m | 1,5 s | offene Bitte (verfällt nach 10 s), Ereignis `food_requested` | Ziel weg/tot, außer Reichweite, Wartezeit |
| `give_food` | ≤ 1,4 m | 1 s | Portion **reserviert**, dann atomar übergeben (Träger wechselt, beim Geber abgezogen) | Empfänger nimmt nicht an (Hände voll, beschäftigt, kein Bedarf), Portion weg |
| `offer_food` | Start ≤ 3 m, Übergabe ≤ 1,4 m | bis 10 s | Portion reserviert; Übergabe, wenn der Empfänger nach **eigener** Bewertung annimmt | Zeitlimit → `not_accepted` |
| `decline_request` | – | 1 s | Ereignis `request_declined` (sichtbar: ob Nahrung getragen wurde) | – |
| `raise_arms` | Sichtweite 10 m | 3 s, 3 W | neutrale Geste, Ereignis `raise_arms` | – |

Eine angebotene oder zur Übergabe reservierte Portion kann weder gegessen noch anders vergeben werden (getestet). Eine Bitte ist kein Zwang; der Empfänger entscheidet in seiner eigenen Entscheidungsrunde.

**Gemessen (10 Minuten, 50 Wesen, spontan, Startwert 12345):** 16 Bitten, 2 Gaben auf Bitte, 9 Ablehnungen, 4 verfallen, 13 unaufgeforderte Angebote, davon 6 angenommen. Das Teilen entsteht vor allem bei Wesen, die versorgt und hilfsbereit sind und eine Portion für andere tragen.

## „Arme heben“
Das ist eine neutrale Ausdruckshandlung mit der Bezeichnung „Arme heben“ und keine religiöse Deutung.
- **Voraussetzung:** mindestens ein Oberarm (Fähigkeit `gesture`).
- **Auftreten:** beim Erkunden mit 2 % · (0,5 + Neugier) Wahrscheinlichkeit als Ausprobieren. Nicht jedes Wesen tut es; einen festen Nutzen gibt es nicht.
- **Wiederholung:** Sie wird nur dann öfter gewählt, wenn eigene Erfahrungen danach einen Vorteil gegenüber der Grundhäufigkeit zeigen (Test D und E).
- **Später:** Eine religiöse Deutung gehört in ein Kultursystem.

## Woran man erkennt, dass ein Wesen etwas gelernt hat
- **Überzeugungen:** Im Beobachtungsfenster unter **VERMUTUNG** steht die Hypothese, z. B. „Nach eigenem „Arme heben“ folgte ein auffälliges Ereignis“, mit Häufigkeit, Konfidenz, Zahl der Belege dafür und dagegen und dem erlebten Wert.
- **Entscheidungen:** Unter **ENTSCHEIDUNG** erscheint die Option `repeat:raise_arms` mit dem Beitrag „erwartung“. Ist sie gewählt, steht im Zustand „Wiederholt …: erlebte Häufigkeit danach 87 % gegenüber allgemein 46 %, Konfidenz 0,58 …“.
- **Deutungen:** „Wahrgenommene Eingriffe“ zeigt die eigene Deutung jedes gesehenen Eingriffs, z. B. „Zeitlich nach eigener Handlung: „Arme heben“ (Δt 0,5 s, Gewicht 0,92). Zeitliche Folge, keine bewiesene Ursache.“
