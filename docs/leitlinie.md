# Leitlinie „Steinzeit → Zukunft“

Stand 25.11.2026, Spielversion 0.6.1. Ein Designdokument, keine neue Spielversion: Am Spiel selbst ändert sich nichts.

## Worum es geht
Der Nutzer will, dass die Pflanzenwesen sich **selbst** von der Steinzeit bis in die Zukunft entwickeln, vom Steinhammer über Schmelzen und Legieren bis zu Abbauwerkzeugen. Seine Erfindungs-Excel ist dafür nur eine Leitlinie.
Diese Leitlinie hat 24 Zeitalter mit je 50–500 Erfindungen. Für jede Erfindung beschreibt sie die **physikalische Kette**:

> Materialien → Verfahren/Arbeitsschritte → Energie/Temperatur → was die Erfindung physikalisch leistet

Dazu kommen die Vorläufer (was vorher da sein muss), der **Spielstand** (ab wann das Spiel die nötige Physik und die Handlungen bietet) und eine Angabe, **was fehlt**.

- **Kein Technologiebaum:** Nichts wird freigeschaltet. Es gibt keine Boni und keine Prozentwerte. Das Zeitalter dient nur der Einordnung. Die Wesen können eine Erfindung erst machen, wenn das Spiel Physik und Handlungen bietet, und auch dann nur, wenn sie selbst darauf kommen.
- Die Excel wird **nicht** ins Spiel importiert. Die Original-Excel-Dateien des Nutzers bleiben unverändert.

## Dateien
| Datei | Inhalt |
|---|---|
| `design/Leitlinie_Steinzeit_bis_Zukunft.xlsx` | erzeugte Excel, 9 Blätter (siehe unten) |
| `design/leitlinie/zeitalter_01.txt` … `zeitalter_24.txt` | **Quelle**: eine Erfindung je Zeile; Format in `design/leitlinie/README.md` |
| `tools/leitlinie/vokabular.py` | Zeitalter, Kategorien, Verfahren und Materialien mit Physik, Spielstand, Lücke; Lückengruppen (= mögliche Zwischenschritte) |
| `tools/leitlinie/quellen.py` | Einlesen, Prüfen, Ableiten (Spielstand, Lücken, Testbereich, Energie/Temperatur) |
| `tools/leitlinie/katalog_abgleich.py` | Zuordnung der echten Namen aus der alten Erfindungs-Excel |
| `tools/build_leitlinie.py` | erzeugt die Excel |
| `tools/tests/test_leitlinie.py` | 15 Python-Tests (Quellen und Excel) |

## Befehle
```
python3 tools/build_leitlinie.py              # Quellen prüfen und Excel schreiben
python3 tools/build_leitlinie.py --pruefen    # nur prüfen
python3 tools/build_leitlinie.py --out X.xlsx # anderer Zielpfad
python3 -m unittest tools.tests.test_leitlinie
```
Geprüft werden:
- 50–500 Einträge je Zeitalter;
- eindeutige Namen;
- bekannte Codes;
- Vorläufer, die es gibt und die nicht später liegen als die Erfindung selbst;
- keine Prozent-Boni.

Bei einem Fehler schreibt das Werkzeug keine Excel und gibt 1 zurück. **Änderungen gehören in die Textquellen.** Was direkt in der Excel geändert wird, ist beim nächsten Erzeugen weg. Die einzige Ausnahme ist die Auswahlspalte zum Ausprobieren.

openpyxl speichert nur Formeln, keine Ergebnisse. Excel und LibreOffice rechnen deshalb beim Öffnen neu. Die abgelegte Datei enthält zusätzlich die von LibreOffice berechneten Werte, damit auch Vorschauen Zahlen zeigen.

## Blätter der Excel
| Blatt | Inhalt |
|---|---|
| Anleitung | Zweck, Regeln, Legenden, Kennzahlen (Formeln) |
| Zeitalter | 24 Zeitalter mit Zeitraum, Kennzeichen, Energiequellen und höchster nutzbarer Temperatur. Zählungen nach Spielstand und mit Auswahl, dazu ein Diagramm. |
| Erfindungen | eine Erfindung je Zeile mit Filter. Spielstand farbig, „Im normalen Spiel möglich ab“ per Formel. Graue Hilfsspalten T–W. |
| Zwischenschritte | Lücken, gebündelt zu möglichen Zwischenschritten: wie viele Erfindungen betroffen sind und wie viele **nur** an diesem Schritt hängen. Mit Diagramm und **Auswahl zum Ausprobieren** (Spalte B, gelb). |
| Lücken | jedes fehlende Verfahren und Material mit Zahl der betroffenen Erfindungen, frühestem Zeitalter und Beispielen |
| Prompt-Abgleich | was jede Stufe physikalisch bringt; Anzahl und Anteil der Erfindungen, auch kumuliert |
| Verfahren / Materialien | das kontrollierte Vokabular mit Physik, Spielstand und Häufigkeit |
| Katalogabgleich | die echten Namen der alten Erfindungs-Excel und wo sie in der Leitlinie stehen |

**Ausprobieren:** Im Blatt „Zwischenschritte“, Spalte B, wird ein Schritt mit `x` markiert. Die Blätter „Zeitalter“ (Spalten O/P), „Zwischenschritte“ und „Anleitung“ zeigen dann, wie viele Erfindungen damit zusätzlich möglich wären. Vorausgewählt sind die beiden Vorschläge aus `docs/plan_prompt_06b.md` Abschnitt 8.

## Wie der Spielstand abgeleitet wird
- Jedes Verfahren und jedes Material hat einen Spielstand:
  - **A**: in v0.6.1 vorhanden;
  - **WA**: Zusatz Weltarchitektur;
  - **P7 … P12**: aus den Prompt-Texten in `design/prompts/`;
  - **L**: Lücke, in keinem vorliegenden Prompt vorgesehen.
- Eine Erfindung ist ab dem **spätesten** Stand ihrer Verfahren und Materialien möglich. Reihenfolge: A < WA < P7 < … < P12 < L. Die Einordnung von WA direkt nach v0.6.1 ist eine Annahme, entschieden ist sie noch nicht.
- **Vorläufer gehen nicht in den Spielstand ein.** Sie zeigen die Entwicklungslinie und was vorher da sein sollte. Nicht jeder Vorläufer ist streng nötig: Ein Bronzepickel braucht keine Geweihpicke. „Was fehlt“ nennt nur die eigenen Lücken der Erfindung.
- **Testbereich „ja“** gilt, wenn alles Nötige vorhanden ist oder als Testausrüstung vorliegt:
  - Der Testofen ersetzt Feuer, Holzkohle und Luftzufuhr.
  - Die Testkeramik ist nur Tiegel und Gussform und zählt deshalb nur beim Schmelzen und Gießen.
  - Heute trifft das auf 7 Kupfererfindungen zu, z. B. Kupfer schmelzen, Kupferguss und Kupfer-Flachbeil.
- **Weltmodell:** Manche Grundlagen sind keine Stoffe, sondern etwas, das die Welt bieten muss. Sie stehen als „Material“ der Art „Weltmodell“ in der Liste:
  - Jahreszeiten, Mond, Sterne, Gezeiten: v0.6.1 kennt nur Tag und Nacht;
  - Gesteinsschichten, Fossilien, Erdbeben.
- **Energie/Temperatur:** gerundete Lehrbuchwerte. Beim Schmelzen und Gießen steht der Schmelzpunkt der beteiligten Metalle da (z. B. Kupfer 1.085 °C, Bronze 950 °C).
- **Projektregel:** Bei Sprengstoffen und Pulverwaffen stehen nur Name und Funktion, keine Stoffe. Massenvernichtungswaffen sind nicht aufgenommen.

## Zahlen (Stand 25.11.2026)
2.680 Erfindungen in 24 Zeitaltern. Das kleinste Zeitalter ist die Frühe Steinzeit mit 54, das größte das Viktorianische Zeitalter mit 192. Davon sind 120 spekulativ (das ganze Zeitalter 24) und 69 „in Entwicklung“.

| Spielstand | Erfindungen |
|---|---|
| A – heute im Spiel (v0.6.1) | 95 |
| WA – Zusatz Weltarchitektur | 23 |
| P7 | 0 (Prompt 7 bringt Leben und Vererbung, aber keine neue Technik) |
| P8 | 82 |
| P9 | 91 |
| P10 | 94 |
| P11 | 28 |
| P12 | 60 |
| **bis Prompt 12 zusammen** | **473 (17,6 %)** |
| L – Lücke | 2.207 (82,4 %) |
| heute im Testbereich vorführbar | 7 |

Von den 2.207 Lücken-Erfindungen hängen 1.064 an **genau einem** Zwischenschritt, 1.143 an mehreren.

| Zwischenschritt | hängen nur daran | betroffen | ab Zeitalter |
|---|---|---|---|
| Licht, Messen, Zeit und Zeichen | 229 | 556 | 1 |
| Erz und Legierungen | 170 | 648 | 6 |
| Elektronik, Rechnen und Netze | 102 | 358 | 17 |
| Feuer, Ton und eigener Ofen | 98 | 241 | 3 |
| Chemie und Baustoffe | 80 | 398 | 3 |
| Werkzeugformen und spanende Bearbeitung | 72 | 159 | 2 |
| Pflanzenstoffe, Haltbarmachen und Gärung | 54 | 150 | 1 |
| Heilen, Hygiene und Medizin | 47 | 158 | 1 |
| Fasern, Seil und Textil | 46 | 165 | 3 |
| Biotechnik | 45 | 98 | 18 |
| Wasser- und Windkraft, Schwimmen | 25 | 147 | 1 |
| Tierische Werkstoffe (nach Prompt 8) | 23 | 84 | 3 |
| Jahreszeiten, Himmel und Erdgeschichte im Weltmodell | 23 | 37 | 3 |
| Hochtechnologie und Raumfahrt | 14 | 130 | 17 |
| Elektrotechnik über Prompt 12 hinaus | 11 | 211 | 9 |
| Sprengen (nicht vorgesehen) | 11 | 19 | 11 |
| Wärmekraft, Motoren und Brennstoffe | 9 | 155 | 9 |
| Werfen und elastische Energie | 5 | 34 | 1 |

Was zusätzliche Zwischenschritte bringen würden (jeweils zusammen mit den geplanten Prompts bis 12):

| Auswahl | zusätzlich | dann möglich |
|---|---|---|
| keine | – | 473 (17,6 %) |
| Feuer, Ton und eigener Ofen | 98 | 571 (21,3 %) |
| Erz und Legierungen | 170 | 643 (24,0 %) |
| **beide Vorschläge** | **315** | **788 (29,4 %)** |
| + Werkzeugformen und spanende Bearbeitung | 417 | 890 (33,2 %) |
| + Fasern, Seil und Textil | 487 | 960 (35,8 %) |
| + Chemie und Baustoffe | 628 | 1.101 (41,1 %) |
| + Pflanzenstoffe, Haltbarmachen und Gärung | 728 | 1.201 (44,8 %) |

Je Zeitalter:

| Nr | Zeitalter | Erfindungen | heute (v0.6.1) | bis Prompt 12 | + Feuer/Ton/Ofen + Erz/Legierungen | + zusätzlich Werkzeugformen |
|---|---|---|---|---|---|---|
| 1 | Tierwelt | 60 | 42 (70 %) | 52 (87 %) | 52 (87 %) | 52 (87 %) |
| 2 | Frühe Steinzeit | 54 | 36 (67 %) | 43 (80 %) | 43 (80 %) | 52 (96 %) |
| 3 | Altsteinzeit | 89 | 5 (6 %) | 32 (36 %) | 32 (36 %) | 47 (53 %) |
| 4 | Mittelsteinzeit | 69 | 2 (3 %) | 20 (29 %) | 20 (29 %) | 36 (52 %) |
| 5 | Jungsteinzeit / Steinzeit | 115 | 3 (3 %) | 44 (38 %) | 71 (62 %) | 85 (74 %) |
| 6 | Kupferzeit | 79 | 5 (6 %) | 23 (29 %) | 57 (72 %) | 67 (85 %) |
| 7 | Bronzezeit | 131 | 1 (1 %) | 28 (21 %) | 71 (54 %) | 86 (66 %) |
| 8 | Eisenzeit | 96 | 1 (1 %) | 19 (20 %) | 54 (56 %) | 60 (62 %) |
| 9 | Klassische Antike | 146 | 0 (0 %) | 34 (23 %) | 58 (40 %) | 59 (40 %) |
| 10 | Spätantike | 63 | 0 (0 %) | 12 (19 %) | 20 (32 %) | 21 (33 %) |
| 11 | Frühmittelalter | 73 | 0 (0 %) | 14 (19 %) | 25 (34 %) | 25 (34 %) |
| 12 | Hochmittelalter | 101 | 0 (0 %) | 18 (18 %) | 32 (32 %) | 34 (34 %) |
| 13 | Spätmittelalter | 97 | 0 (0 %) | 19 (20 %) | 31 (32 %) | 32 (33 %) |
| 14 | Renaissance | 101 | 0 (0 %) | 14 (14 %) | 31 (31 %) | 32 (32 %) |
| 15 | Zeitalter der Entdeckungen | 107 | 0 (0 %) | 21 (20 %) | 30 (28 %) | 31 (29 %) |
| 16 | Aufklärung | 132 | 0 (0 %) | 17 (13 %) | 33 (25 %) | 35 (27 %) |
| 17 | Industrielle Revolution | 157 | 0 (0 %) | 10 (6 %) | 33 (21 %) | 37 (24 %) |
| 18 | Viktorianisches Zeitalter | 192 | 0 (0 %) | 11 (6 %) | 33 (17 %) | 37 (19 %) |
| 19 | Moderne / Erster Weltkrieg | 157 | 0 (0 %) | 9 (6 %) | 20 (13 %) | 20 (13 %) |
| 20 | Atomzeitalter | 148 | 0 (0 %) | 3 (2 %) | 9 (6 %) | 9 (6 %) |
| 21 | Informationszeitalter | 140 | 0 (0 %) | 5 (4 %) | 6 (4 %) | 6 (4 %) |
| 22 | Digitalzeitalter | 132 | 0 (0 %) | 6 (5 %) | 7 (5 %) | 7 (5 %) |
| 23 | Biotechnologie-Ära | 121 | 0 (0 %) | 10 (8 %) | 11 (9 %) | 11 (9 %) |
| 24 | Zukunft / Singularität | 120 | 0 (0 %) | 9 (8 %) | 9 (8 %) | 9 (8 %) |

**Lesart:**
- Ab der Altsteinzeit bremst vor allem das fehlende **gezielte Abschlagen und Formen** (Faustkeil, Klinge, Spitze). Die Wesen können Steine heute nur zerschlagen.
- Ab der Jungsteinzeit kommen **Feuer, Ton und Ofen** dazu. Feuer gibt es erst in Prompt 12.
- Ab der Kupferzeit fehlen **Erz und Legierungen**.
- Ab der Antike überwiegen Optik, Messen, Papier und Druck, Chemie, Elektrotechnik und später Elektronik.

## Entwicklungslinie Steinhammer → Abbauwerkzeug
Über Vorläufer verbunden und in einem Test geprüft:

> **Bronzepickel** (Zeitalter 7) ← Bronzeguss ← Zinnbronze (Legieren) sowie ← zweischalige Gussform ← offene Gussform ← Kupfer schmelzen
> **Bronzepickel** ← Geweihpicke ← Geweihaxt ← … ← Hammerstein ← Stein als Hammer

Danach folgt die Spitzhacke aus Eisen (Zeitalter 8) mit Kupferverhüttung, Hammerstein und Geweihpicke unter ihren Vorläufern. Der Rillenschlägel (Zeitalter 6, Stein + Holz, binden + schlagen) ist schon heute möglich.

## Abgleich mit der alten Erfindungs-Excel
Aus `Erfindungen_Echt_nach_Kategorien.xlsx` sind 85 echte Namen und 92 Varianten „(verbessert)“ zugeordnet, zusammen 177:
- 139 stehen in der Leitlinie **später**, 16 früher, 13 im gleichen Zeitalter.
- 9 haben keine Entsprechung:
  - Atomwaffe und Laserwaffen sind bewusst nicht aufgenommen.
  - Den Warp-Antrieb gibt es physikalisch nicht.
  - Die übrigen 6 stecken in anderen Einträgen.
- Beispiele:
  - „Hygiene“: alt Mittelsteinzeit, neu Viktorianisches Zeitalter;
  - „Telegraf“: alt Bronzezeit, neu Industrielle Revolution;
  - „Sichel“: alt Bronzezeit, neu Mittelsteinzeit.
- Die 2.608 erzeugten Fantasienamen sind nicht übernommen.

## Grenzen
- Die Einträge folgen allgemeinem historischem und technischem Wissen. Einzelquellen sind nicht geprüft.
- Eingeordnet wird nach dem ersten verbreiteten Auftreten. Regionale Unterschiede stehen nur im Hinweis.
- Die Codes sind grob: Ein Verfahren steht für viele Varianten. Ein paar zu optimistische Einordnungen wurden beim Bau korrigiert. Dazu gehören Kalender (Jahreszeiten fehlen), geologische Theorien (Weltmodell), Klimaabkommen (Messen) und Institutionen wie der Kindergarten (Nachwuchs erst ab Prompt 7, Gemeinschaften ab Prompt 10).
- Die Stufen P7–P12 sind aus den Prompt-Texten abgeleitet. Was diese Prompts am Ende umsetzen, kann davon abweichen; nach jedem Prompt sollte der Spielstand im Vokabular nachgezogen werden.

## Offene Entscheidungen (beim Nutzer)
1. **Zwischenschritte:** Kommen „Feuer, Ton und eigener Ofen“ und „Erz und Legierungen“ dazu, und wann? Weitere Kandidaten mit großer Wirkung auf die Frühzeit sind „Werkzeugformen und spanende Bearbeitung“ und „Fasern, Seil und Textil“.
2. Einordnung des **Zusatzes Weltarchitektur**.
3. Sollen **Jahreszeiten** ins Weltmodell? Sie sind die Grundlage für Kalender, Wanderungen und Fruchtwechsel.
4. Soll die Leitlinie später **ins Spiel** einfließen, etwa als Ideenkatalog für Modellvorschläge? Das wäre nur Information, keine Freischaltung. Bisher ist sie nur ein Designdokument.
