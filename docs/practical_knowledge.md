# Praktisches Wissen und Unterricht (Prompt 6)

Module:
- `scripts/technology/procedural_knowledge.gd`: Verfahrenswissen je Wesen.
- `scripts/social/teaching_system.gd`: Erklären, Vorführen, Zusehen, Üben.
- `scripts/social/communication_system.gd`: Absichten `explain_procedure`, `offer_demo`.

Gespeichert wird alles in `Creature.tech`. **Es gibt kein globales Wissen.**

## 1. Verfahren
Ein Verfahren hat einen strukturierten Schlüssel:
- `schlagen:<Kontaktmaterial>:<Form>><Ziel>`, z. B. `schlagen:stone:Stück>copper`. Formen: Hand, Stück, Stiel+Kopf, Stab.
- `verbinden:lashing:<Stielmaterial>+<Kopfmaterial>`, z. B. `verbinden:lashing:wood+stone`.
- `giessen:<Material>:Tiegel>Form`.

Ein Eintrag enthält:

| Feld | Inhalt |
|---|---|
| `origin` | Herkunft des Eintrags: eigener Versuch, Beobachtung, Unterricht, Mitteilung |
| `prerequisites` | Voraussetzungen, z. B. Stiel ≥ 0,2 m, Faserbedarf 8 % der Kopfmasse, freie Hand, Griff kühl |
| `steps` | Arbeitsschritte (Vorgänge, wie in `docs/experimentation.md`) |
| `materials` | unterstützter Materialbereich: nur Materialien, mit denen das Wesen es **selbst** ausgeführt hat |
| `own` | eigene Versuche, Erfolge, letztes Ergebnis |
| `observed` | gesehene fremde Versuche/Vorführungen, Erfolge, bei wem |
| `heard` | Mitteilungen mit Sprecher, Ursprung, Wissensstand des Sprechers; **unabhängige Ursprünge** |
| `confidence` | Sicherheit 0..1 |
| `versions` | nachvollziehbare Versionsgeschichte: angelegt, Stufe erhöht, Materialbereich erweitert, je mit Zeit und Wesen |
| `experiments` | IDs der eigenen Versuchsprotokolle |

## 2. Erfahrungsstufen
**gehört < zugesehen < versucht < erfolgreich**

| Stufe | Entsteht nur durch |
|---|---|
| gehört | strukturierte Mitteilung im Gespräch (`explain_procedure`). Freier Text schaltet nichts frei |
| zugesehen | **tatsächlich wahrgenommene** Vorführung oder beobachteter fremder Versuch (Ereignis über die Wahrnehmung, Sichtweite 6 m bei Vorführungen) |
| versucht | **eigener** ausgeführter Versuch ohne Erfolg |
| erfolgreich | **eigener** ausgeführter Versuch mit Erfolg (z. B. Verbund entstanden, sichtbare Stauchung) |

Stufen werden nur erhöht, nie durch schwächere Quellen gesenkt.

**Sicherheit**
- Gewichtung: eigene Versuche zählen voll, beobachtete halb, Hörensagen 0,15, und dies **je unabhängigem Ursprung**. Hört ein Wesen dieselbe Quelle zweimal, zählt sie einmal (Test 13).
- Formel: Sicherheit = (s + 0,5) / (n + 1) · min(1, n / 2), mit s = gewichtete Erfolge und n = gewichtete Fälle.

**Geschick**
- Die Stufe beeinflusst die Ausführung: Die Passung beim Umwickeln steigt von 45 % (unbekannt) bis 100 % (erfolgreich).
- Ein Wesen, das nur zugesehen hat, bindet also schwächer als ein erfahrenes.

## 3. Unterricht
1. **Erklären** (`explain_procedure`, lokales Gespräch über `CommunicationSystem`)
   - Der Lernende erhält nur Schlüssel und Schritte als strukturierten Inhalt: Stufe „gehört“ mit Quelle.
   - **Keine** Lehrerdaten (Versuchsprotokolle, Erfolgszahlen, exakte Werte).
2. **Vorführung anbieten** (`offer_demo`): Ein Wesen auf Stufe „erfolgreich“ bietet die Vorführung einem bekannten, nahen Wesen an.
3. **Vorführen** (`demonstrate_procedure`)
   - Der Lehrer führt das Verfahren **wirklich** aus: echter Verbund, echter Faserverbrauch, echte Schläge.
   - Er veröffentlicht `demonstration_started`/`procedure_demonstrated` als wahrnehmbare Ereignisse.
4. **Zusehen** (`tech:watch`)
   - Der Lernende hält sich in Sichtweite.
   - Nur wenn er das Ereignis **tatsächlich wahrnimmt** (Sichtweite, Sichtlinie), steigt er auf „zugesehen“.
   - Ein Wesen außer Sicht erhält nichts (Test 12).
5. **Üben** (`practice_procedure`)
   - Der Lernende führt das Verfahren selbst aus. Das ist sein **eigener** Versuch mit eigenem Protokoll: „versucht“ oder „erfolgreich“.

**Unterricht überträgt Information, aber keine Praxiserfahrung:**
- Nach Erklärung und Vorführung hat der Lernende **0 eigene Versuche** und keine Lehrerprotokolle, seine Stufe ist „zugesehen“.
- Erst Üben hebt ihn darüber (Test 13).

## 4. Wissen bleibt individuell
Ein Wesen kennt ein Verfahren nur durch:
- eigenen Versuch;
- tatsächliche Beobachtung;
- Mitteilung;
- praktischen Unterricht.

Herkunft und Sicherheit sind gespeichert. Stirbt das einzige sachkundige Wesen, geht sein **ungeteiltes Wissen verloren**. Es geht auf niemanden über (Test 12); die Wissensansicht zeigt das am toten Wesen an.

**Ungeprüfte Hypothesen** (eigene Ideen oder Modellvorschläge):
- Liegen getrennt in `tech.hypotheses`.
- Werden erst durch einen ausgeführten Versuch „bestätigt“ oder „nicht bestätigt“.
- **Vortrainiertes Modellwissen ersetzt keine persönliche Entdeckung.** Eine Hypothese erzeugt nie einen Eintrag in `procedures`.

## 5. Wie man Unterricht beobachtet
1. Startbildschirm → **Testwerkstatt (Testbereich)**.
2. Im Werkstattfeld **„6 Wesen A führt das Verbinden vor …“** drücken. A muss das Verbinden schon können; sonst zuerst Versuch 2 ausführen.
3. Wesen B anklicken, **„Wissen (W)“** öffnen. Während der Vorführung steht dort „Sieht gerade #A zu …“, danach `verbinden:lashing:wood+stone` (angezeigt als „Stiel (Holz) und Kopf (Stein) mit Fasern umwickeln“) mit Stufe **„dabei zugesehen“**, Herkunft „Vorführung (Unterricht)“ (wurde es vorher erklärt: „Mitteilung (Hörensagen)“), 0 eigene Versuche.
4. **„B übt das Verbinden“** drücken. Danach zeigt die Wissensansicht von B „selbst versucht“ oder „selbst erfolgreich ausgeführt“, einen eigenen Versuch und eine neue Version im Verlauf.
5. **„Versuche (E)“** zeigt beide Protokolle: das Vorführprotokoll von A mit Lernendem B und das Übungsprotokoll von B.

## 6. Speichern
- Verfahren, Hypothesen, bekannte Gegenstände (wahrgenommene Eigenschaften) und Zeitbudget werden gespeichert, ebenso Unterrichtsfortschritt (angeboten, erklärt, gelehrt, zusehend) und Quellenbezüge. Sie liegen in `mind.tech` des Wesens.
- Eine Migration aus Format 3 legt **leeres** Wissen an: keine rückwirkend geschenkten Entdeckungen.
