# Roadmap Alpha 1.x – Pflanzenwesen

**Stand:** 25.11.2026 · Ausgangsversion **v0.6.1** (Prompt 6B) · nächste Version **Alpha 1.1**
**Status:** verbindlicher Plan; Reihenfolge und Zuschnitt dürfen sich nur mit Begründung ändern (Änderungsprotokoll am Ende).

Dieses Dokument ist zusammen mit `docs/HANDOVER.md` das Gedächtnis des Projekts für alle weiteren Versionen. Wer an Pflanzenwesen weiterarbeitet, liest **zuerst HANDOVER, dann dieses Dokument**, dann den Abschnitt der anstehenden Version und die dort genannten Prompt-Texte. Kein Wissen darf nur im Chat stehen. Was hier fehlt, gilt als nicht beschlossen.

---

## Inhalt
0. [Kurzfassung](#0-kurzfassung)
1. [Entscheidungen des Nutzers vom 25.11.2026](#1-entscheidungen-des-nutzers-vom-25112026)
2. [Verbindliche Leitprinzipien](#2-verbindliche-leitprinzipien)
3. [Ausgangslage v0.6.1](#3-ausgangslage-v061)
4. [Versionsschema und Lieferablauf Alpha](#4-versionsschema-und-lieferablauf-alpha)
5. [Gesamtübersicht Alpha 1.1 – 1.21](#5-gesamtübersicht-alpha-11--121)
6. [Detailplan je Version (1.1 – 1.16)](#6-detailplan-je-version-11--116)
7. [Ausblick 1.17 – 1.21 und danach](#7-ausblick-117--121-und-danach)
8. [Zielarchitektur: Modularisierung und große Welten](#8-zielarchitektur-modularisierung-und-große-welten)
9. [Lebendige Welt: wie sich die Wesen selbst entwickeln](#9-lebendige-welt-wie-sich-die-wesen-selbst-entwickeln)
10. [Leitlinie und Alpha-Plan](#10-leitlinie-und-alpha-plan)
11. [Querschnitt: Tests, Leistung, Spielstände, Ollama, Doku](#11-querschnitt-tests-leistung-spielstände-ollama-doku)
12. [Risiken und Gegenmaßnahmen](#12-risiken-und-gegenmaßnahmen)
13. [Annahmen, die der Nutzer jederzeit ändern kann](#13-annahmen-die-der-nutzer-jederzeit-ändern-kann)
14. [Pflege dieses Dokuments und Änderungsprotokoll](#14-pflege-dieses-dokuments-und-änderungsprotokoll)

---

## 0. Kurzfassung
- Ab jetzt heißen die Versionen **Alpha 1.1, 1.2, …**. Geplant sind 1.1–1.16 im Detail und 1.17–1.21 als Ausblick; danach geht es nach der Leitlinie weiter.
- **Reihenfolge:**
  - Zuerst kommt das **Fundament**: modulare Architektur, große gestreamte Welt, Zeit/Himmel/Klima, veränderbares Gelände mit Geologie.
  - Dann folgt die **lebendige Welt**: Pflanzen, Fortpflanzung, Vererbung, Tiere.
  - Danach die **eigene Entwicklung der Wesen** in organischer Reihenfolge: Steinwerkzeuge und Fasern, Feuer, Landwirtschaft, Siedlungen, Keramik und eigener Ofen, Gemeinschaften, Erz und Bronze, Schrift.
- Die **Prompt-Texte 7–13** und der **Zusatz Weltarchitektur** bleiben verbindliche Auftragstexte für ihre Inhalte. Dieses Dokument legt nur Reihenfolge, Zuschnitt und die zusätzlichen Zwischenschritte fest.
- Die **Leitlinien-Excel** sortiert, was wann physikalisch möglich wird:
  - Blatt „Alpha-Plan“ und Spalte „geplant möglich ab“;
  - heute 95 der 2.680 Erfindungen, nach Alpha 1.16 989 (36,9 %), nach 1.21 1.248 (46,6 %).
  - Das sind Möglichkeiten, keine Ziele: Was die Wesen tatsächlich entdecken, entscheidet die Simulation.

## 1. Entscheidungen des Nutzers vom 25.11.2026
Wortlaut (Chat, 25.11.2026, 13:57) und Auslegung:

| Nr | Wortlaut (gekürzt) | Auslegung für die Planung |
|---|---|---|
| D1 | „wir müssen das Ökosystem und die Entwicklung aus den Prompts umsetzen, die Idee ist eine lebendige Welt. ich lass dich entscheiden wie organisch es ist; die Excel dient als Leitsatz, um zu sortieren, wie die das entwickeln könnten. wenn sie zusätzliche Erfindungen machen gerne, sie sollen halt lernen und ihre Probleme so lösen.“ | Prompts 7–12 werden umgesetzt. Ökosystem und Entwicklung haben Vorrang. Claude legt die organische Reihenfolge fest (Abschnitt 5) und baut die Zwischenschritte der Leitlinie ein. Die Excel sortiert nur. Die Wesen lösen Probleme selbst (Abschnitt 9), und eigene, nicht gelistete Erfindungen sind ausdrücklich erwünscht. |
| D2 | Jahreszeiten, Mond und Sterne ins Weltmodell: „ja“ | eigene Version **Alpha 1.3** (Kalender, Jahreszeiten, Mond, Sterne, Gezeiten, Temperatur, Wetter) |
| D3 | „wir müssen das Spiel modularisieren, so dass das geht; ich will größere Karten, vielleicht Weltkarten, damit die verschiedene Maps haben. das muss richtig geplant sein.“ | **Alpha 1.1** bringt die modulare Architektur, **1.2** die große gestreamte Welt mit wählbaren Kartenvorlagen, **1.17** die Weltkarte mit mehreren Regionen. Die Architektur ist von Anfang an darauf ausgelegt (Abschnitt 8). |
| D4 | Leitlinie im Spiel als Ideenquelle: „was du sagst“ | ab **Alpha 1.8**: Erfindungs-Chronik und Ideenkatalog. Nur Information, keine Freischaltung (Abschnitt 9.4). |
| D5 | „wir gehen jetzt in Alpha 1.1 … 1.16 … und so weiter“ | neues Versionsschema (Abschnitt 4) |
| D6 | „hinterlege eine detaillierte ausführliche Datei auf GitHub, damit keine Infos verloren gehen“ | dieses Dokument; Verweise in `CLAUDE.md` und `docs/HANDOVER.md` |

## 2. Verbindliche Leitprinzipien
Diese Regeln gelten für jede Alpha-Version. Sie stammen aus den Prompts 1–13, dem HANDOVER und den Entscheidungen des Nutzers.

1. **Kein Technologiebaum.** Technik entsteht nur aus Material, Geometrie, Energie, Körper und ausgeführten Handlungen. Kein Name, kein Excel-Eintrag und kein Modellvorschlag schaltet etwas frei.
2. **Physik zuerst, Entdeckung durch die Wesen.** Eine Version stellt Physik und Handlungen bereit. Ob und wann ein Wesen etwas entdeckt, entscheidet die Simulation (Bedarf, Neugier, Beobachtung, Nachahmung, Unterricht, Versuch). **Gezielt ausgelöst ≠ entdeckt:** Testknöpfe beweisen nur die Regeln. Eigenständiges Verhalten wird gemessen und als Messwert berichtet.
3. **Bilanzen:** Masse, Energie, Wasser und Biomasse bleiben erhalten oder fließen nachweisbar ab. Es gibt keine versteckte Erzeugung, keine Doppelernte und keine Teleportation.
4. **Eine Quelle der Wahrheit.** Vorhandene Module werden erweitert, nicht dupliziert. Es gibt einen Entscheider je Akteur und eine Handlungsausführung.
5. **Nichts unbemerkt entfernen.** Tests werden nur ergänzt. Jede Entfernung oder Umbenennung wird begründet (CHANGELOG, Versionsvergleich).
6. **Tests auf Godot 4.7.2 und 4.5**, nacheinander (gemeinsamer `user://`-Ordner). Nie Code ändern, während ein Testlauf läuft.
7. **Spielstände:** Jede Formatänderung bekommt eine Migration. Sie wird mit einem **echten** Spielstand der Vorversion getestet, der vor jeder Codeänderung erzeugt wird. Das Original wird vor der Migration gesichert.
8. **Ehrlichkeit:** keine erfundenen Testergebnisse. Ungeprüftes wird als „nicht verifiziert“ gekennzeichnet, simulierte Dienste als SIMULIERT.
9. **Ollama nur als Vorschlag:** Die Antworten sind ungeprüfte Daten. Wirkung entsteht nur über Prüfung und vorhandene Handlungen. Ollama selbst wird nur abgefragt, nie verwaltet.
10. **Original-Excel-Dateien des Nutzers nie ändern.** Erzeugte Daten und handgeschriebene Daten bleiben getrennt.
11. **Projektregeln:**
    - keine realen Explosivstoff-Rezepte, nirgends;
    - keine Massenvernichtungswaffen;
    - Gefangenschaft und Zwang nur als fiktive Spielzustände nach Prompt 10 §13–14.
12. **Sprache:** Oberfläche, Doku und Antworten auf Deutsch.
13. **Leistung wird gemessen, nicht behauptet.** Zielhardware: GTX 1660 Ti, zweites Profil RTX 3080. Die Arbeitsumgebung der KI hat keine Grafikkarte; Messungen auf Grafikkarten macht der Nutzer.

## 3. Ausgangslage v0.6.1
**Spielbar:**
- Voxelwelt mit 64 × 32 × 64 Zellen à 0,5 m (32 × 16 × 32 m, 16 Chunks à 16 × 32 × 16), Lebensbaum, 50 Pflanzenwesen;
- Stoffwechsel, Photosynthese, Wahrnehmung, Gedächtnis, Persönlichkeit, Beziehungen, Gespräche, Hörensagen, Göttermenü, optional Ollama (mit echtem Ollama **nicht verifiziert**);
- Prompt 6: Experimente, Werkzeuge (Schlagen, Kupfer kalt verformen, Hammer binden), praktisches Wissen, Testwerkstatt;
- Prompt 6B: Arbeitsketten lagern, bauen (Steinreihe), schmelzen (nur Testofen), Arbeitsanimationen, Testszene Werkzeugkette.

**Technik:**
- Speicherformat 5 mit Migrationen 1→2→3→4→5;
- 491 Godot-Tests (4.7.2 und 4.5), 8 Szenenstarts, Python-Tests für Importer, Kataloge, Versionsvergleich und Leitlinie.

**Grenzen:**
- Gelände: kleine Karte, Graben und Verdichten nur vorbereitet;
- Biologie und Natur: kein Ökosystem mit Tieren, kein Nachwuchs;
- Zeit und Wetter: keine Jahreszeiten, kein Mond, kein Wetter;
- Technik: Feuer fehlt (laut Prompts erst in Prompt 12), es gibt keinen eigenen Ofen.

Leitlinie (`design/Leitlinie_Steinzeit_bis_Zukunft.xlsx`, `docs/leitlinie.md`): 2.680 Erfindungen, davon heute 95 physikalisch möglich.

## 4. Versionsschema und Lieferablauf Alpha
| Was | Regel |
|---|---|
| Name | **Alpha 1.N** (N = 1, 2, …); Nachbesserungen innerhalb einer Version: Alpha 1.N.1 |
| `project.godot` | `config/version="alpha-1.N"`; Startbildschirm zeigt „Alpha 1.N“; Spielstand-Feld `game_version` = derselbe Text |
| Git | Commit „Alpha 1.N – Titel“ auf `main`; Versionszweig **`version/alpha-1.N`** (wird danach nicht mehr verändert); lokal Tag `alpha-1.N` |
| ZIP für den Nutzer | `Pflanzenwesen_alpha-1.N.zip` (ohne `.git`, `.godot`, `__pycache__`); in frischem Ordner geprüft |
| Versionsvergleich | `python3 tools/compare_versions.py git:origin/version/<vorher> . --md reports/versionsvergleiche/versionsvergleich_<vorher>_zu_alpha-1.N.md`. Bei Alpha 1.1 ist `<vorher>` = `v0.6.1`. |
| CHANGELOG | Abschnitt `## Alpha 1.N – Titel` mit Neu / Geändert / Entfernt (begründet) |
| Detailplanung | zu Beginn jeder Version `docs/plan_alpha_1_N.md`: Bestandsprüfung aus Code und Tests, Zuschnitt, Entscheidungen, Fortschritt. Vorbild: `docs/plan_prompt_06b.md` |
| Arbeitszweig | bei mehrtägiger Arbeit `wip/alpha-1.N` mit Zwischenständen; abgeschlossen wird auf `main` |
| Neuer Chat | Der Nutzer schreibt „Pflanzenwesen, Repository Docbert12/Pflanzenwesen, weiter mit Alpha 1.N“. Dann: Repository anbinden, klonen, HANDOVER und dieses Dokument lesen, die Prompt-Abschnitte der Version lesen. |
| Windows-Build | ab Alpha 1.1 versucht (Exportprofil); falls Exportvorlagen in der Arbeitsumgebung nicht ladbar sind: Blocker dokumentieren, der Nutzer exportiert im Editor |

**Ablauf je Version (Checkliste):**
1. **Beginn**
   - HANDOVER, dieses Dokument und die Prompt-Abschnitte lesen.
   - `docs/plan_alpha_1_N.md` anlegen (Bestandsprüfung).
   - Prüfling der Vorversion erzeugen, falls sich das Speicherformat ändert.
   - Ausgangstests auf beiden Godot-Versionen laufen lassen.
2. **Umsetzen** in überprüfbaren Abschnitten. Jeder Abschnitt funktioniert und ist getestet, bevor der nächste beginnt.
3. **Ende**
   - Vollständige Tests auf 4.7.2 und 4.5, Szenenstarts, Python-Tests, Versionsvergleich, Leistungsmessung.
   - Doku: README, CHANGELOG, HANDOVER, dieses Dokument (Status), `docs/test_results.md`, Fachdoku.
   - **Leitlinie nachziehen** (HANDOVER Schritt 4a): tatsächlich spielbare Codes in `tools/leitlinie/vokabular.py` auf `A` setzen, `python3 tools/build_leitlinie.py`.
   - Version erhöhen, Commit, Versionszweig, ZIP, Schlussnachricht auf Deutsch.

## 5. Gesamtübersicht Alpha 1.1 – 1.21
„+Leitlinie“ zählt die Erfindungen, die nach dem Alpha-Plan ab dieser Version physikalisch möglich werden; „kumuliert“ gilt für das normale Spiel.

| Version | Titel | Hauptquelle | Speicherformat | +Leitlinie | kumuliert |
|---|---|---|---|---|---|
| (heute) | v0.6.1 | Prompts 1–6B | 5 | 95 | 95 (3,5 %) |
| **1.1** | Fundament: modulare Architektur, Speicherformat 6, Kartenvorlagen | D3, Weltarchitektur §2/§5/§13/§15 (Vorbereitung) | **6** | 0 | 95 |
| **1.2** | Große Welt I: Chunk-Streaming, große Karte, Biome, Kartenvorlagen | Weltarchitektur §3–5, §12–13, §15–17 | 6 (Chunk-Deltas) | 0 | 95 |
| **1.3** | Zeit, Himmel und Klima | D2, Prompt 8 §5 | 6 (+ Kalender, Wetter) | 5 | 100 |
| **1.4** | Gelände und Geologie: Abbau, Bau, Einsturz, Schichten, Ton, Erz | Weltarchitektur §6–12, §14, Leitlinie | 6 | 42 | 142 |
| **1.5** | Ökosystem I: Pflanzen und Pilze | Prompt 8 §5–6, §15, §17 | 6 | 13 | 155 |
| **1.6** | Lebensbaum und Nachwuchs | Prompt 7 §6–8, §12–17 | 6 | 0 | 155 |
| **1.7** | Vererbung und Mutationen | Prompt 7 §3, §5, §9–11, §13 | 6 | 0 | 155 |
| **1.8** | Steinwerkzeuge, Schneiden, Fasern, Werfen; Erfindungs-Chronik; Ideenkatalog | Leitlinie, Prompt 6, D1, D4 | 6 | 92 | 247 |
| **1.9** | Ökosystem II: Tiere, Jagd, tierische Werkstoffe | Prompt 8 §3, §7–10, §15–17 | 6 | 47 | 294 |
| **1.10** | Feuer: Verbrennung, Kochen, Licht, Wärme, Holzkohle | Prompt 12 §6–8 (vorgezogen), Leitlinie | 6 | 34 | 328 |
| **1.11** | Zähmung, Zucht, Landwirtschaft, Haltbarmachen | Prompt 8 §10–14, §16 | 6 | 108 | 436 |
| **1.12** | Siedlungen und gemeinsames Bauen; Hebel; Spinnen und Weben | Prompt 9, Prompt 12 §11 (Hebel) | 6 | 151 | 587 |
| **1.13** | Ton, Keramik, eigener Ofen: Kupfer selbst schmelzen | Leitlinie, Prompt 6/6B | 6 | 91 | 678 |
| **1.14** | Gemeinschaften, Regeln, Religion, Konflikte | Prompt 10 | 6 | 139 | 817 |
| **1.15** | Erz, Verhüttung, Bronze, Metallwerkzeuge, Bergbau | Leitlinie, Prompt 12 §5–6 (vorgezogen) | 6 | 63 | 880 |
| **1.16** | Zeichen, Zählen, Maße, Schrift und Bücher | Prompt 11 | 6 | 109 | **989 (36,9 %)** |
| 1.17 | Große Welt II: Weltkarte, Regionen, Reisen, Wasserwege | D3, Weltarchitektur §13 | 6 (Regionen) | 18 | 1.007 |
| 1.18 | Mechanik II: Rad und Achse, Wagen, Winde, Getriebe | Prompt 12 §11 | 6 | 41 | 1.048 |
| 1.19 | Eisen und Stahl | Leitlinie | 6 | 171 | 1.219 |
| 1.20 | Strahlung und Elektrik | Prompt 12 §9–10, §12–14 | 6 | 29 | 1.248 |
| 1.21 | Gesamtaudit, Balance, Leistung, Windows-Export | Prompt 13 | 6 | 0 | **1.248 (46,6 %)** |

„Speicherformat 6“ heißt: Die Formatversion bleibt 6, neue Inhalte bekommen eigene **Abschnittsversionen** je Modul (Abschnitt 8.8). Muss die Struktur des Kopfes sich ändern, steigt die Formatversion. Immer mit Migration.

**Warum diese Reihenfolge:**
- **1.1–1.4 schaffen die Bühne:** Module, Weltgröße, Jahreslauf, Gelände und Rohstoffe. Ohne sie haben Ökosystem und Siedlungen keinen Platz, keine Jahreszeiten und keinen Ton oder kein Erz.
- **1.5 Pflanzen vor dem Nachwuchs:** Das Bodenmodell aus 1.5 versorgt den Lebensbaum (Prompt 7 §6 verlangt einen „definierten Bestand“ im Boden).
- **1.6/1.7 Nachwuchs vor den Tieren:** Raubtiere ohne Fortpflanzung der Wesen würden die Bevölkerung nur verkleinern.
- **1.8 Steinwerkzeuge vor den Tieren:** Jagd, Zerlegen und Fellbearbeitung brauchen Schneiden und Werfen. Der Schritt ist in der Leitlinie auch der früheste große Engpass, ab der Frühen Steinzeit.
- **1.10 Feuer vorgezogen:** Prompt 12 bringt Verbrennung sehr spät. Organisch gehört Feuer in die Altsteinzeit. Ein natürlicher Anlass entsteht durch die Blitze aus 1.3.
- **1.11–1.14 Sesshaftigkeit:** Landwirtschaft → Siedlung → Keramik und Ofen → Gemeinschaften, wie in der Jungsteinzeit.
- **1.15/1.16 Metall und Schrift**, wie in der Bronzezeit.
- **1.17 Weltkarte** erst, wenn Bevölkerung, Siedlungen und Wasserwege sie brauchen. Die Architektur steht ab 1.1/1.2. Der Nutzer kann 1.17 jederzeit vorziehen, frühestens nach 1.9.

**Was je Zeitalter physikalisch möglich wird** (Anteil der Leitlinien-Erfindungen, kumuliert; vollständige Matrix im Excel-Blatt „Alpha-Zeitalter“):

| Nr | Zeitalter | heute | 1.4 | 1.8 | 1.10 | 1.11 | 1.13 | 1.15 | 1.16 | 1.19 | 1.21 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Tierwelt | 70 % | 77 % | 82 % | 83 % | 83 % | 85 % | 98 % | 98 % | 100 % | 100 % |
| 2 | Frühe Steinzeit | 67 % | 67 % | 87 % | 87 % | 87 % | 94 % | 100 % | 100 % | 100 % | 100 % |
| 3 | Altsteinzeit | 6 % | 12 % | 42 % | 74 % | 79 % | 84 % | 94 % | 98 % | 99 % | 99 % |
| 4 | Mittelsteinzeit | 3 % | 9 % | 48 % | 68 % | 71 % | 81 % | 93 % | 94 % | 97 % | 97 % |
| 5 | Jungsteinzeit / Steinzeit | 3 % | 10 % | 25 % | 32 % | 50 % | 83 % | 89 % | 92 % | 92 % | 92 % |
| 6 | Kupferzeit | 6 % | 13 % | 20 % | 33 % | 43 % | 73 % | 86 % | 91 % | 95 % | 95 % |
| 7 | Bronzezeit | 1 % | 3 % | 8 % | 12 % | 18 % | 40 % | 66 % | 84 % | 87 % | 87 % |
| 8 | Eisenzeit | 1 % | 4 % | 5 % | 9 % | 14 % | 27 % | 45 % | 51 % | 84 % | 84 % |
| 9 | Klassische Antike | 0 % | 1 % | 1 % | 3 % | 6 % | 20 % | 32 % | 42 % | 62 % | 62 % |
| 12 | Hochmittelalter | 0 % | 1 % | 2 % | 3 % | 8 % | 26 % | 38 % | 42 % | 58 % | 58 % |
| 17 | Industrielle Revolution | 0 % | 1 % | 2 % | 2 % | 2 % | 5 % | 9 % | 12 % | 32 % | 34 % |
| 20 | Atomzeitalter | 0 % | 0 % | 0 % | 0 % | 1 % | 1 % | 2 % | 4 % | 9 % | 11 % |
| 24 | Zukunft / Singularität | 0 % | 0 % | 0 % | 0 % | 3 % | 4 % | 8 % | 8 % | 8 % | 8 % |

---

## 6. Detailplan je Version (1.1 – 1.16)
Jede Version hat denselben Aufbau. **Muss** ist der Lieferumfang. **Nicht** grenzt ab. **Abnahme** sind die Pflichttests. Ist ein Prompt genannt, ist sein Text für diese Inhalte **verbindlich**: Das hier ist der Zuschnitt, nicht ein Ersatz.

### Alpha 1.1 – Fundament: modulare Architektur
**Ziel:** Das Projekt so umbauen, dass große und mehrere Karten, viele neue Simulationsmodule und ein modularer Spielstand möglich werden, **ohne Funktionsverlust** und ohne sichtbare Verhaltensänderung.
**Quellen:** D3, D5; Zusatz Weltarchitektur §2 (Welt zuerst vermessen), §5, §13, §15 (vorbereitend); Prompt 13 §4 (Fehlerprioritäten).

**Muss:**
1. **Vermessung des Ist-Zustands** (Weltarchitektur §2) in `docs/world_expansion.md`:
   - Karten- und Chunkgröße, Zellgröße;
   - Bild- und Simulationszeiten je System, Speicherbedarf;
   - Mesh- und Kollisionsdauer, Navigationskosten.
2. **Modulvertrag `SimModule` + `ModuleRegistry`** (Abschnitt 8.3):
   - Die vorhandenen Systeme werden als Module angemeldet: Leben, Geist, Soziales, Kommunikation/KI, Technik, Arbeit, Lager und Bauwerke, Wasser, Tag/Nacht, Nahrung, Göttermenü.
   - Ihre Reihenfolge ergibt sich aus Abhängigkeiten. Jedes Modul hat Takt, Messwerte und einen Speicherabschnitt.
   - Das Verhalten bleibt gleich. `DecisionSystem` bleibt einziger Entscheider, `ActionExecutor` einzige Ausführung.
3. **Weltzugriff nur über eine Schnittstelle** (`WorldAccess`/`TerrainQuery`, Abschnitt 8.4). Alle Stellen mit fester Kartengröße und alle direkten Zugriffe auf `VoxelData` von außerhalb der Welt-Schicht werden umgestellt. Testfall ist eine nicht-quadratische Karte (z. B. 48 × 32 × 80).
4. **Kartenvorlagen** `data/maps/*.json`:
   - Inhalt (Abschnitt 8.4): ID, Name, Größe, Zellgröße, Startwert, Generatorversion, Biome, Startgebiet, geografische Breite (für 1.3), Meer ja/nein.
   - Die heutige Welt wird die Vorlage „Lichtung (klein, wie v0.6)“.
   - Neues-Spiel-Dialog mit Kartenwahl und Startwert.
5. **Speicherformat 6:**
   - Kopf plus ein Abschnitt je Modul mit eigener Abschnittsversion;
   - Weltänderungen als Chunk-Deltas gegenüber dem Generator (Grundlage für 1.2);
   - Migration 5→6 mit einem **echten v0.6.1-Spielstand**: Prüfling vor jeder Codeänderung erzeugen, auch einen aus der Testszene Werkzeugkette mitten in einer Kette.
6. **Zufallsströme je Modul** (Weltstartwert + Modul-ID), damit neue Module bestehende Abläufe nicht verschieben.
7. **Leistungsmessung je Modul**:
   - `PerformanceMonitor` erweitert;
   - Werkzeug `tools/benchmark_world.gd` mit Bericht (Bildzeit, Simulationszeit je Modul, Speicher, Objektzahlen).
8. **Versionsumstellung** auf `alpha-1.1` (Abschnitt 4), Startbildschirm, Versionszweig.
9. **Windows-Exportprofil** (`export_presets.cfg`, experimentell). Ein Build, falls Exportvorlagen ladbar sind, sonst Blocker und Anleitung für den Nutzer.

**Nicht:** neue Spielinhalte, größere Karte (1.2), neue Physik.

**Abnahme:**
- alle bisherigen Tests auf 4.7.2 und 4.5 grün;
- neue Tests:
  - Modulreihenfolge und Abhängigkeitsfehler;
  - Speicherabschnitte im Rundlauf;
  - Migration 5→6 mit echtem Spielstand;
  - Kartenvorlage lädt, nicht-quadratische Karte;
  - Determinismus je Modul (gleicher Startwert → gleiche Messwerte);
- Beobachtungslauf vor und nach dem Umbau mit vergleichbaren Messwerten;
- `world_expansion.md` vorhanden.

**Leitlinie:** +0. **Risiko:** Umbau bricht Verhalten. **Gegenmaßnahme:** Module zuerst nur „einhüllen“, dann umziehen; Vergleichsläufe.

### Alpha 1.2 – Große Welt I: Chunk-Streaming, große Karte, Biome
**Ziel:** Eine deutlich größere, gestreamte Welt mit Biomen. 50 Wesen laufen darauf flüssig, und nichts verschwindet außerhalb der Kamera.
**Quellen:** Zusatz Weltarchitektur §3–5, §12 (Körpergröße vorbereitet), §13, §15–17; Excel-Biome (Wald, Wiese, Berg, Seeufer, Pilzwald); D3.

**Muss:**
1. **Chunk-Speicher** (Abschnitt 8.4):
   - Chunkgröße wird gemessen (Vorschlag 32 × 32 × 32 Zellen).
   - Kompakte Speicherung: homogen, Palette plus Bits oder RLE.
   - Laden und Entladen nach Interessenpunkten (Kamera, aktive Akteure).
   - Ungeladene Bereiche sind **keine Luft**: Ein Höhenfeld ersetzt sie.
2. **Generator-Pipeline je Chunk**, deterministisch aus Startwert und Generatorversion:
   - Höhe → Biome → Gewässer (Seen, Bäche) → Startvegetation (heutige Pflanzen) → Startgebiet.
   - Die Generatorversion wird gespeichert, alte Regionen werden nie unbemerkt neu gestaltet.
3. **Standardkarte** mit etwa 20-facher Fläche (Weltarchitektur §3):
   - Seiten × √20 (32 m → etwa 143 m, auf Chunkgrenzen gerundet).
   - Höhe so, dass Hügel, Gruben und begrenzter Untergrund möglich sind (Vorschlag 48 m).
   - Die Startpopulation bleibt 50.
4. **Größere Vorlagen zum Messen**, z. B. „Tal 256 m“ und „experimentell 512 m“. Ziel ist, die tragfähige Obergrenze für 1.17 zu finden.
5. **Blockgrößenvergleich 0,50 m und 0,25 m** bei gleicher physischer Kartengröße (Weltarchitektur §4):
   - gemessen werden Bildzeit, Simulationszeit, Speicher, Mesh- und Kollisionsdauer;
   - die Entscheidung wird dokumentiert;
   - ist das feinere Profil nicht tragfähig, bleibt es experimentell.
6. **Hintergrundarbeit:**
   - Generierung und Netze im `WorkerThreadPool`;
   - Übergabe an Szenenbaum und Physik nur im Hauptthread mit Budget je Bild;
   - Fern-Darstellung (vereinfachte Netze oder Höhenfeld) für die Sichtweite.
7. **Navigation hierarchisch** (Abschnitt 8.7): Chunk-Portale plus lokales A*. Neu berechnet werden nur betroffene Chunks. Körpergrößenklassen sind vorbereitet.
8. **Erkundungswissen:**
   - Wesen kennen nur gesehene oder mitgeteilte Orte und Gebiete; das Gedächtnis wird um Orte und Gebiete erweitert.
   - Die Startgruppe beginnt in einem geeigneten zusammenhängenden Gebiet (Weltarchitektur §13).
9. **Simulationszonen A/B/C** als Grundgerüst (Abschnitt 8.6). Wesen außerhalb der Kamera simulieren weiter, mit gleicher Bilanz.
10. **Kartenvorlagen zur Wahl** (z. B. Waldtal, Seenland, Hügelland), Übersichtskarte für den Spieler. Sie ist Spielerwissen und kein Wissen der Wesen.
11. **Spielstand:** nur geänderte Chunks. Alte Welten bleiben in ihrer Größe, eine Erweiterung gibt es nur ausdrücklich (Weltarchitektur §15).
12. **Leistungsprobe für den Nutzer:**
    - Messszene plus Bericht `user://benchmark_report.txt`;
    - der Nutzer misst auf GTX 1660 Ti und RTX 3080;
    - die Ergebnisse gehen in `docs/test_results.md` ein.

**Nicht:** Abbau und Bau (1.4), Jahreszeiten (1.3), neue Lebewesen.

**Abnahme:**
- Weltarchitektur §17 Punkte 1, 2, 13, 14, 15, 16, 17;
- unveränderte Chunks reproduzierbar, Änderungen an Chunkgrenzen bleiben erhalten;
- entfernte Regionen neu laden;
- 10-Minuten-Lauf mit 50 Wesen auf der großen Karte;
- nichts verschwindet außerhalb der Kamera;
- Grafik- und Simulationskosten getrennt gemessen.

**Leitlinie:** +0. **Risiko:** GDScript zu langsam für Voxelmengen. **Gegenmaßnahme:** Messen. Eine GDExtension (C++) für Chunkspeicher und Mesher kommt nur bei nachgewiesenem Engpass (Weltarchitektur §5).

### Alpha 1.3 – Zeit, Himmel und Klima
**Ziel:** Die Welt bekommt Jahreslauf, Mond, Sterne und Wetter. Pflanzen und Wesen spüren Licht, Wärme, Kälte und Regen.
**Quellen:** D2; Leitlinien-Lücke „Jahreszeiten, Himmel“; Prompt 8 §5 (Sonnenlicht als Energieeintrag); Weltarchitektur §11 (Wasser).

**Muss:**
1. **Kalender** aus der Simulationszeit, Werte konfigurierbar:
   - Spieltag (heute 600 s) → Jahreszeit → Jahr;
   - Vorschlag: 4 Jahreszeiten × 8 Spieltage = 32 Spieltage je Jahr ≈ 5,3 Stunden Echtzeit bei 1×;
   - Kalenderanzeige für den Spieler.
2. **Zeitraffer** (2×, 5×, 10×) nach Prompt 13 §9: nur für Module freigegeben, deren Bilanzen bei Beschleunigung geprüft sind; Prüftest je Modul.
3. **Sonnenstand** aus geografischer Breite (Kartenvorlage) und Datum:
   - Tageslänge und Lichtstärke (das vorhandene Photosynthesemodell nutzt sie), Schattenrichtung.
4. **Mond:**
   - Umlauf (Vorschlag 8 Spieltage), Phasen, Mondlicht in der Nacht (Wahrnehmung).
5. **Sterne:**
   - fester Sternenhimmel je Welt mit Sternbildern, Drehung in der Nacht, Sichtbarkeit nach Jahreszeit.
6. **Gezeiten** nur auf Karten mit Meer (Vorlage „Küste“): Der Meeresspiegel schwankt periodisch mit dem Mond (einfaches, dokumentiertes Modell).
7. **Temperatur:**
   - Tages- und Jahresgang, Höhe, Gewässer, Bodentemperatur;
   - Wirkung auf Wesen: Kälte senkt Stoffwechsel und Wachstum, Hitze erhöht den Wasserbedarf;
   - Eis auf Gewässern im Winter, wenn das Phasenmodell es trägt, sonst als offen kennzeichnen.
8. **Wetter:**
   - Wolken, Regen, Wind (Richtung, Stärke), Gewitter mit Blitz;
   - der Blitz zündet erst ab 1.10, bis dahin ist er Ereignis mit Licht und Schall;
   - Schnee optional.
9. **Wasserkreislauf** einfach: Regen → Bodenfeuchte und Gewässer, Verdunstung. Der Austausch mit der Atmosphäre ist als externer Fluss dokumentiert (Bilanz).
10. **Wahrnehmung und Gedächtnis:**
    - Wesen nehmen Tageszeit, Jahreszeitmerkmale, Mondphase und Wetter wahr;
    - Regelmäßigkeiten können als Vermutung entstehen (vorhandenes Überzeugungsmodell), z. B. „nach den kalten Tagen kommen Blätter“;
    - es gibt **kein** vorgegebenes Kalenderwissen.

**Nicht:** Pflanzenwachstum nach Jahreszeit (1.5), Kalender als Aufzeichnung der Wesen (1.16), Navigation nach Sternen (später).

**Abnahme:**
- Kalenderrechnung;
- Tageslänge im Winter kürzer als im Sommer (Breite 50°);
- Mondphasen periodisch;
- Gezeiten nur mit Meer;
- Temperaturkurve plausibel;
- Regenmenge = Wasserzuwachs (Bilanz);
- Datum und Wetter im Spielstand;
- Determinismus;
- Zeitraffer ändert keine Bilanz;
- Leistung.

**Leitlinie:** +5 (Jahreslauf), z. B. Sonnenlauf beobachten, Saatkalender (Rest kommt mit 1.16).

### Alpha 1.4 – Gelände und Geologie
**Ziel:** Wesen graben, tragen und bauen mit echten Erdmengen. Der Untergrund hat Schichten mit Ton, Sand, Feuerstein, Kalk, Ocker und Erz.
**Quellen:** Zusatz Weltarchitektur §6–12, §14, §16–17; Prompt 6B (Graben und Verdichten vorbereitet); Leitlinie: Erz im Gelände, Gesteinsschichten, Fossilien.

**Muss:**
1. **Blockmaterialien** in `data/materials/` mit Quellen oder Annahmen (Weltarchitektur §6):
   - Erde, Lehm/Ton, Sand, Kies, Kalkstein/Kreide, Fels, Erzgestein;
   - je Material: Dichte, Porosität, Festigkeit, Bindigkeit, Böschungswinkel;
   - 1 m³ Erde ≠ 1 m³ Stein.
2. **Geologie im Generator:**
   - Schichtenfolge nach Biom und Höhe;
   - Feuersteinknollen in Kreide, Tonlinsen an Seeufern, Sand an Ufern, Ocker;
   - Kupfererz (Malachit) und gediegenes Kupfer in Felsgebieten, Zinnerz selten (Flusssand), gediegenes Gold selten (Flusssand);
   - Fossilien in Kalk als Fundobjekte;
   - Erdbeben **nicht**.
3. **Handlungen:**
   - `dig` und `compact` aktivieren (aus 6B vorbereitet), Abschnitt §7;
   - neu: Schüttgut aufnehmen und tragen (Hände; Behälter ab 1.8), aufschütten, platzieren;
   - Arbeitsfortschritt je Block: zwei Wesen erzeugen nie doppelte Mengen;
   - Werkzeugeinfluss (Grabstock, Hammer, später Picke).
4. **Massenbilanz:**
   - Abbau → Schüttgut mit gleicher Masse;
   - Verdichten ändert das Volumen, nicht die Masse;
   - Platzieren verbraucht reale Mengen.
5. **Stabilität und Einsturz** (§10):
   - Böschungswinkel je Material, Überhänge;
   - Tunnel brauchen Abstützung (Holzstützen);
   - das Modell ist dokumentiert.
6. **Gruben, Tunnel und Wasser** (§11): Das vorhandene Spaltenmodell wird erweitert, Grundwasser optional.
7. **Navigation** aktualisiert betroffene Wege. Kleine Tunnel bleiben für große Körper unpassierbar (§12).
8. **Autonome Nutzung** (§14) aus eigenem Bedarf über `WorkSystem` und `DecisionSystem`: Weg freimachen, Graben, Wall, Grube, Baumaterial gewinnen. Ollama darf nur vorschlagen.
9. **Göttermenü:** Blockbearbeitung durch den Spieler ist als göttlicher Eingriff bzw. Entwicklermodus gekennzeichnet (§14).
10. **Oberfläche** (§16): Materialanzeige beim Zeigen auf Blöcke (Spielerwissen), Arbeitsfortschritt am Block.

**Nicht:** Ton formen oder brennen (1.13), Verhütten (1.15), Behälter aus Geflecht (1.8).

**Abnahme:**
- Weltarchitektur §17 Punkte 3–12;
- Geologie reproduzierbar;
- Erz, Ton, Sand und Feuerstein abbaubar und als Material vorhanden;
- Fossilien sind Fundobjekte;
- Abbau im Spielstand erhalten;
- 50 Wesen mit Grabtätigkeit ohne Leistungseinbruch.

**Leitlinie:** +42, z. B. Grabstock, Fallgrube, Feuersteinbergbau an der Oberfläche, Ockergewinnung, Malachit erkennen.

### Alpha 1.5 – Ökosystem I: Pflanzen und Pilze
**Ziel:** Pflanzen und Pilze wachsen, vermehren sich, konkurrieren und zersetzen sich im Jahreslauf. Die Nahrung der Wesen stammt aus diesem Kreislauf.
**Quellen:** Prompt 8 §1–6, §15, §17–20 (Schritte 1–2); Excel: 20 Pflanzenarten (Eiche, Kiefer, Birke, Weide, Ahorn, Apfelbaum, Beerenstrauch, Himbeerstrauch, Pilz Rot, Pilz Braun, Grasbüschel, Klee, Farn, Moos, Alge, Schilf, Wurzelknolle, Heilkraut, Giftpflanze, Leuchtmoos).

**Muss:**
1. **Ressourcenmodell** (Prompt 8 §5), dokumentiert:
   - Licht als Energie;
   - Wasser im Boden;
   - Bodennährstoffe je Bodenzelle (Gitter, Vorschlag 2 × 2 m);
   - Biomasse je Pflanze, tote Biomasse;
   - Austauschflüsse mit Atmosphäre und Grundwasser.
2. **Ablauf:** zuerst **eine Pflanze vollständig** (Beerenstrauch), dann ein Pilz mit Substratverbrauch, dann alle kompatiblen Excel-Arten (Prompt 8 §3, §20). Übersicht „importiert / darstellbar / spielbar“.
3. **Wachstum** nach Licht, Wasser, Temperatur und Jahreszeit (1.3): Austrieb, Blüte, Frucht, Laubfall, Winterruhe. Sichtbare Wachstumsstufen.
4. **Vermehrung:**
   - Samen als reale Objekte (Fallen, Wind; Tiere ab 1.9), Keimung nach Bedingungen;
   - Ausläufer und Sporen je Art.
5. **Zersetzung:** tote Biomasse → Bodennährstoffe (Zeitkonstanten je Material). Pilze wachsen auf Substrat und verbrauchen es.
6. **Konkurrenz und Dichte:** Licht- und Nährstoffkonkurrenz. **Verarmung ist möglich**, ohne versteckte Wiederherstellung (§17).
7. **Nahrung:**
   - `FoodSource` und `FoodItem` werden an echte Pflanzenteile gebunden (Früchte, Knollen, Blätter, Pilze);
   - Ernte entfernt reale Masse, keine Doppelernte;
   - Biomasse ist nie gleichzeitig Nahrung und Baumressource.
8. **Wirkstoffe:** Heilkraut heilt, Giftpflanze schadet, über das vorhandene Gesundheitsmodell. Die Wesen lernen das aus eigener Erfahrung und durch Weitergabe.
9. **Fernsimulation:** Pflanzen außerhalb der aktiven Zonen werden als Biomassefelder je Zelle simuliert (gleiche Bilanz). Einzelpflanzen entstehen erst bei Annäherung, deterministisch.
10. **Oberfläche:** Ökosystem-Übersicht für den Spieler (Bestände, Bodenzustand), Pflanzeninspektor.
11. **Sandbox-Modus** (§17) nur ausdrücklich: Er ergänzt Arten oder Ressourcen sichtbar und protokolliert das.

**Nicht:** Tiere (1.9), Landwirtschaft (1.11), Waldbrand (1.10).

**Abnahme:**
- Prompt 8 §21, Pflanzen- und Pilzteil;
- kein Wachstum ohne Ressourcen;
- Bilanz über ein Spieljahr;
- Jahreszeitenwirkung;
- Verarmung bei Übernutzung;
- keine Doppelernte;
- Speichern und Laden mitten im Wachstum;
- Leistung auf großer Karte.

**Leitlinie:** +13, z. B. Samen ausklopfen, Heilende Blätter verzehren, Schäftung mit Pech.

### Alpha 1.6 – Lebensbaum und Nachwuchs (Prompt 7, Teil 1)
**Ziel:** Der Lebensbaum wird biologischer Ursprung. Er nimmt Ressourcen auf und bildet Keimlinge, die zu handlungsfähigen Wesen heranwachsen. Ein weiterer Baum kann gegründet werden.
**Quellen:** Prompt 7 §1–2, §4, §6–8, §12–17, §18 (Nachwuchsteil).

**Muss:**
- **Baumressourcen:** Licht plus Bodenstoffe aus dem 1.5-Modell plus kontrollierte Aufnahme über das Wurzelbeet (§6–7). Ressourcenaufnahme ist getrennt von Merkmalsaufnahme (Merkmale: 1.7). Kupfer, Stein und Prothesen werden nie zu Biomasse.
- **Nachwuchs-Ablauf** (§8): Voraussetzungen → Platz → Bauplan → Ressourcen je Phase → Keimling sichtbar → Wachstum → Freigabe. Bei Mangel pausiert die Entwicklung.
- **Jungwesen** erben **kein Wissen**. Sie lernen durch Beobachtung und Unterricht (vorhandene Systeme).
- **Bevölkerungsgrenze** (§15):
  - technisches Entwicklungslimit, konfigurierbar, konservativ (z. B. 80);
  - beim Limit pausieren neue Starts, es wird nichts gelöscht;
  - der Grund wird angezeigt.
- **Gründungsprojekt weiterer Lebensbaum** (§12):
  - genau 50 gültig registrierte Opfer, jedes Wesen zählt nur einmal und nur für ein Projekt;
  - Standort und Ressourcen werden getrennt geprüft, die Gründung ist atomar;
  - Testausführung klar gekennzeichnet; **keine** organisierte oder erzwungene Opferung als Gesellschaftssystem.
- **Abstammung** als Grundgerüst (§13), neue Handlungen (§14), Oberfläche mit Baumfenster (Ressourcen, Keimlinge, Projekte) (§16), Speichern (§17).

**Nicht:** Vererbung und Mutationen (1.7), Tiere als Merkmalsquelle (1.9).

**Abnahme:**
- Prompt 7 §18, Nachwuchsteil;
- Masse und Ressourcen passen zusammen, kein sofortiger Körper;
- Limit pausiert ohne Löschung;
- Opferzählung korrekt, Gründung atomar;
- Speichern mitten in einer Entwicklung;
- Beobachtungslauf über 2 Spieljahre mit Bevölkerungsverlauf als Messwert.

**Leitlinie:** +0 (Fortpflanzung erscheint in der Leitlinie nur zusammen mit späteren Grundlagen).

### Alpha 1.7 – Vererbung und Mutationen (Prompt 7, Teil 2)
**Ziel:** Nachkommen unterscheiden sich sichtbar und funktional. Mutationen haben Nutzen **und** Kosten.
**Quellen:** Prompt 7 §3, §5, §9–11, §13, §16–18; Excel `genetics` (6), `breeding` (2), `body_parts` (80), `components`.

**Muss:**
- **Merkmalsdefinitionen aus der Excel** (Importer erweitern, §5). Nicht unterstützte Merkmale bleiben aus. Aus der unklaren Angabe „20+ / 20−“ wird keine Regel erfunden, stattdessen gilt eine dokumentierte, konfigurierbare Standardverteilung.
- **Vererbung** (§9): Grundbauplan, aufgenommene Merkmale, Auswahlgewichte, Kompatibilität. Ungültige Baupläne werden vor der Geburt abgefangen. Keine unsichtbare Verbesserung.
- **Mutationen** (§10): Blattgröße, Proportionen, Pigment, Gewebe, Energiebedarf, Wachstum. Mit Kosten, mit Rate und mit Entwicklermodus-Auslösung (gekennzeichnet). **Keine** Strahlung als Ursache vor 1.20.
- **Sichtbare Unterschiede** (§11) über `CreatureView` und Animator. Nur Körperformen mit passenden Animationen.
- **Merkmalsaufnahme** über das Wurzelbeet (§7): kompatible biologische Teile; die Herkunftsstruktur für Tiere ist vorbereitet.
- **Abstammungsansicht:** Der Spieler sieht alles, die Wesen nur Wahrgenommenes oder Mitgeteiltes (§13).

**Abnahme:**
- Prompt 7 §18, Vererbungsteil;
- Mutation wirkt messbar in der Simulation (z. B. größere Blätter → mehr Licht, mehr Wasserbedarf);
- Animationen passen;
- Speichern.

**Leitlinie:** +0.

### Alpha 1.8 – Steinwerkzeuge, Schneiden, Fasern und Werfen; Erfindungs-Chronik
**Ziel:** Der nächste eigene Entwicklungsschritt der Wesen. Dazu gehören gezielt geschlagene Steinwerkzeuge, Schneiden, Schaben, Bohren, Schleifen, Schnüre und Geflechte, Werfen sowie Farbe und Klang. Dazu kommen die **Erfindungs-Chronik** und der **Ideenkatalog** (D4).
**Quellen:** Leitlinien-Zwischenschritte „Werkzeugformen und spanende Bearbeitung“ und „Fasern, Seil und Textil“ (Schnur, Flechten), „Werfen“, aus „Licht, Messen, Zeit, Zeichen“ Farbe und Klang; Prompt 6 (Versuche, Werkzeuge, Wissen), 6B (Arbeitsketten); D1, D4.

**Muss:**
1. **Gezieltes Abschlagen:**
   - Das Bruchmodell wird um Schlagpunkt, Schlagwinkel, Kraft und Gefüge erweitert (muscheliger Bruch bei Feuerstein und Obsidian).
   - Ergebnisse: Abschlag mit Masse, Kantenlänge und Schärfe, Kernstein. Retusche heißt kleine Abschläge an der Kante.
   - **Die Geometrie bestimmt die Funktion** (Schneide, Spitze, Faustkeil), nicht ein Name.
2. **Materialabtrag als Handlungen** mit Abtragsmodell (Härteverhältnis, Druck, Zeit):
   - Schneiden und Schaben (Holz, Rinde, Pflanzen; Fleisch und Haut ab 1.9);
   - Bohren (Drehbewegung);
   - Schleifen und Polieren (Sand, Sandstein, Wasser).
3. **Schnur drehen** aus Fasern, mit Zugfestigkeit. **Flechten:** Korb, Matte, Netz. Der Korb wird **Behälter für Schüttgut** (verbindet 1.4).
4. **Werfen** von Stein, Stock und Speer: Flugbahn und Wucht aus der vorhandenen Physik. Der Speer ist ein Stock mit geschäfteter Spitze.
5. **Farbe** (Ocker mahlen, auftragen) und **Klang** (Trommeln) als Ausdruck. Andere Wesen nehmen ihn wahr; keine Bedeutung vorgegeben.
6. **Problemlöse-Schleife** als eigenes Modul (Abschnitt 9.2):
   - Bedarf → Hindernis → Ideen aus eigenem Wissen, Beobachtung, Analogie oder Modellvorschlag → Versuch → Bewertung → Gedächtnis und Weitergabe;
   - erweitert die Versuche aus Prompt 6 und die Arbeitsketten aus 6B, ohne zweiten Entscheider.
7. **Erfindungs-Chronik** (D4):
   - Erkenner für Leitlinien-Erfindungen auf Basis **tatsächlicher Ergebnisse** (z. B. Faustkeil = beidseitig retuschierter Stein mit langer Schneide);
   - Eintrag mit Wesen, Zeitpunkt und Herkunft (selbst entdeckt / gelernt / Modellvorschlag);
   - **unbekannte neue Verfahren** werden als „eigene Erfindung“ mit Beschreibung des Ablaufs festgehalten; der Spieler darf sie benennen.
8. **Ideenkatalog** (D4):
   - `tools/build_leitlinie.py --json` erzeugt `data/generated/leitlinie/erfindungen.json` (Name, Funktion, Kette, Spielstand);
   - Nutzung 1: Hinweise für Ollama-Versuchs- und Arbeitsanfragen, nur Erfindungen, die im Spiel physikalisch möglich sind;
   - Nutzung 2: Nachschlagewerk für den Spieler;
   - **keine Freischaltung**, Ausführung nur über geprüfte Handlungen.

**Abnahme:**
- Abschlag erhält Masse, Schärfe folgt aus der Geometrie, Retusche ändert die Kante;
- Schneiden braucht Härteunterschied;
- Schnur reißt bei Überlast, Korb trägt Schüttgut;
- Wurf trifft nach Physik;
- Chronik erkennt nur echte Ergebnisse;
- Ideenkatalog wirkt nur als Vorschlag (SIMULIERT getestet);
- Beobachtungslauf: eigenständige Entdeckungen als Messwert.

**Leitlinie:** +92, z. B. Kernstein, Faustkeil, Einfacher Schaber, Angespitzter Stock, Trommeln auf Holz.

### Alpha 1.9 – Ökosystem II: Tiere, Jagd, tierische Werkstoffe
**Ziel:** Wildtiere mit eigenem Körper und Verhalten bevölkern die Welt, und Nahrungsketten entstehen. Die Wesen können fliehen, sich verteidigen, jagen und tierische Werkstoffe nutzen.
**Quellen:** Prompt 8 §3–4, §7–10, §15–20 (Schritte 3–4, 9); Excel `species`: 91 Tiere (45 Pflanzen-, 30 Allesfresser, 16 Fleischfresser; Stufen L1–L12) und 15 Pilzwesen; Prompt 7 §7 (Merkmale von Tieren); Leitlinie: Tierische Werkstoffe, Nähen, Kleidung, Bogen.

**Muss:**
1. **Gemeinsame Akteursbasis** für Wesen und Tiere (Körper, Wahrnehmung, Bewegung, Handlungen, ein Entscheider je Akteur). Keine Parallelimplementierung.
2. **Ablauf** (Prompt 8 §20):
   - ein Pflanzenfresser vollständig (Nahrungssuche, Stoffwechsel, Flucht, Fortpflanzung, Tod);
   - dann Allesfresser, dann Fleischfresser;
   - dann alle kompatiblen Excel-Arten (Übersicht „importiert / darstellbar / spielbar“).
3. **Bis zu 10 Entwicklungsstufen** datengetrieben (§9). Fortschritt durch Fressen nur nach tatsächlich verzehrter Menge, Wachstum an Ressourcen gebunden.
4. **Nahrungsketten, Populationsdynamik, Dichte, Revier.** Technische Grenzen sind getrennt von ökologischen, und es gibt **keine heimliche Löschung** (§17).
5. **Fernsimulation:** Tiere außerhalb der aktiven Zonen als Herden oder Populationen mit Position und Bilanz.
6. **Tod und Kadaver** mit realen Teilen: Fleisch, Knochen, Geweih/Horn, Haut/Fell, Sehne, Fett. Zersetzung (1.5) und Aasfresser.
7. **Wesen und Tiere:**
   - Gefahr wahrnehmen, Flucht, Verteidigung;
   - Jagd mit vorhandenen Werkzeugen (Speer, Werfen aus 1.8);
   - Zerlegen durch Schneiden.
8. **Tierische Werkstoffe:**
   - Knochen und Geweih als Werkzeug (Ahle, Nadel, Picke);
   - Haut schaben, Sehne als Schnur;
   - **Nähen**;
   - einfache **Körperhülle** gegen Kälte (1.3).
9. **Bogen:** elastische Energie (Federmodell von Bogenstab und Sehne).
10. **Merkmalsaufnahme von Tieren** über das Wurzelbeet (Prompt 7 §7) mit Herkunft.
11. **Pilzwesen** aus der Excel, soweit definiert. Offene Körperformen werden ausdrücklich gekennzeichnet (§3).

**Abnahme:**
- Prompt 8 §21, Tierteil;
- Masse und Energie der Tiere, kein Bissen doppelt;
- Stufen nicht ohne Ressourcen;
- Jagd nach Physik;
- Kadaverteile ergeben die Körpermasse;
- Speichern;
- Leistung mit Tieren und 50+ Wesen.

**Leitlinie:** +47, z. B. Ahle, Knochennadel mit Öhr, Harpune, Fellkleidung, Genähte Kleidung.

### Alpha 1.10 – Feuer
**Ziel:** Feuer wird physikalisch. Es entsteht durch Blitz oder Reibung, braucht Brennstoff und Luft, gibt Wärme und Licht ab, gart Nahrung und kann sich ausbreiten.
**Quellen:** Prompt 12 §3, §6–8, §17 (**vorgezogen**, nur Verbrennung und Oxidation); Leitlinien-Zwischenschritt „Feuer, Ton und eigener Ofen“ (Teil Feuer, Holzkohle); Blitz aus 1.3.

**Muss:**
1. **Verbrennung** als begrenzte Reaktion (Prompt 12 §6):
   - Brennstoff, Zündtemperatur, Abbrandrate, Wärmeleistung, Produkte (Asche, Rauch, Gase);
   - **Atmosphärenreservoir** dokumentiert (§7);
   - vorhandene Materialdaten (`combustion`) nutzen.
2. **Wärmeübertragung** an Nachbarobjekte, Boden und Wesen (Verbrennung, Wärme im Winter). Flamme und Rauch gibt es nur, solange der Prozess läuft (§7).
3. **Natürliches Feuer:**
   - Ein Blitz (1.3) zündet trockenes Material.
   - Ausbreitung nach Trockenheit und Wind mit Grenzen, Regen löscht.
   - **Wesen können Feuer zuerst in der Natur beobachten** (organischer Anlass).
4. **Feuer nutzen:** Glut tragen (Behälter), unterhalten (nachlegen), Feuerstelle.
5. **Feuer machen:**
   - Feuerbohrer: Reibungswärme an Holz, Arbeit nötig;
   - Schlagfeuer mit Feuerstein und Pyrit (Pyrit wird in der Geologie ergänzt).
6. **Garen und Rösten:**
   - Nahrung ändert Eigenschaften (Verdaulichkeit, Haltbarkeit);
   - Wasser erhitzen mit heißen Steinen.
7. **Licht** in der Nacht (Wahrnehmung), **Wärme** als Kälteschutz.
8. **Holzkohle:** Verkohlen unter Luftabschluss (abgedeckte Grube), Ausbeute und Brennwert dokumentiert.
9. **Gefahr:** Verbrennungen (vorhandenes Schadensmodell), Brand von Bauwerken und Pflanzen.

**Nicht:** Ofen mit Luftzufuhr (1.13), Metallverhüttung (1.15), allgemeines Reaktionssystem über Verbrennung und Oxidation hinaus.

**Abnahme:**
- Prompt 12 §21, Verbrennungsteil: Verbrauch, Ende ohne Voraussetzungen, Energie, Produkte;
- Blitz zündet nur trockenen Brennstoff;
- Ausbreitung begrenzt, Regen löscht;
- Reibungsfeuer braucht Arbeit;
- Garen ändert Nahrung;
- Holzkohle-Ausbeute;
- laufende Feuer im Spielstand.

**Leitlinie:** +34, z. B. Feuer nutzen, Glut tragen, Feuerstelle, Feuerbohren, Schlagfeuer, Fackel.

### Alpha 1.11 – Zähmung, Zucht, Landwirtschaft, Haltbarmachen (Prompt 8, Teil 3)
**Ziel:** Wesen gewöhnen Tiere an sich, züchten sie, nutzen Lasttiere, säen und ernten. Eine sesshafte Lebensweise wird möglich.
**Quellen:** Prompt 8 §10–14, §16, §20 (Schritte 5–8, 10); Leitlinie: Trocknen, Räuchern, Gerben, Öl und Fett.

**Muss:**
- **Gewöhnung und Zähmung** (§11): Vertrauen des Tiers, Futter, Annäherung, Rückschläge.
- **Zucht über Generationen** (§10): Merkmale der Arten aus 1.9, Auslese durch die Wesen.
- **Erste praktische Tiernutzung** (§12):
  - Lasttier mit Tragegeschirr;
  - Handlungen `attach_carrying_gear`, `load_animal`, `unload_animal`, `feed_animal`, `approach_animal`.
- **Landwirtschaft** (§13):
  - Handlungen `collect_seed`, `prepare_soil`, `sow_seed`, `water_plant`, `harvest_part`, `transport_harvest`;
  - Säen verbraucht echte Samen;
  - Bewässern braucht Wasser und ein Gefäß (Korb mit Abdichtung, Haut; Keramik ab 1.13);
  - Felder entstehen nur durch Handlungen.
- **Verbindung zum Lebensbaum** (§16).
- **Begrenzte Planung und Wissen** (§14): Erfolge lernen und unterrichten, Ollama nur über geprüfte Handlungen.
- **Haltbarmachen:**
  - Trocknen an Luft und Sonne, Räuchern am Feuer (1.10), Haltbarkeit messbar;
  - Gerben (Haut + Gerbstoff oder Rauch);
  - Fett auslassen, Öl pressen.

**Abnahme:**
- Prompt 8 §21: Zähmung, Lasttier, Landwirtschaft;
- kein globaler Freischalter;
- Zucht verändert die Population messbar;
- Vorräte verderben ohne Haltbarmachen schneller;
- Speichern.

**Leitlinie:** +108, z. B. Ackerbau, Saatgut auswählen, Hund als Begleiter, Räuchern, Trockengestell.

### Alpha 1.12 – Siedlungen und gemeinsames Bauen (Prompt 9); Hebel; Spinnen und Weben
**Ziel:** Aus wiederholter Nutzung entstehen Orte, Lager und Bauten. Wesen planen gemeinsam, teilen Arbeit, beanspruchen Besitz und tauschen.
**Quellen:** Prompt 9 vollständig (§1–20); Prompt 12 §11 (**Hebel vorgezogen**); Leitlinie: Spinnen und Weben.

**Muss:**
- **Prompt 9 §2–19:**
  - Orte und Siedlungsbildung ohne allwissende Bewertung;
  - Vorratshaltung;
  - Bauen aus echten Materialien: Holz, Stein, Lehm und Erde (1.4), Fasern, Häute;
  - Gebäudenutzung: Schutz vor Regen und Kälte aus 1.3 messbar;
  - Bauplanung, gemeinsame Projekte, Aufgabenkoordination, Arbeitsteilung und Fähigkeiten;
  - Besitzansprüche, Tausch, Kommunikation mit Ollama, Lastentiere.
- Die vorhandenen Module aus 6B (Lager, Baustelle „Steinreihe“) werden **erweitert, nicht ersetzt**.
- **Hebel und Schlitten** für schwere Lasten: Kraftverstärkung über Hebelarm, Gleitreibung. Rollen und Rad kommen erst mit 1.18.
- **Spinnen** (Spindel) und **Weben** (einfacher Webrahmen) aus Fasern und Wolle. Textil mit Fläche, Masse und Festigkeit.

**Abnahme:**
- Prompt 9 §19;
- Hebelgesetz (Kraft × Arm);
- Schlitten senkt die nötige Kraft;
- Textil trägt Last bis zum Reißen;
- Siedlung entsteht nur aus tatsächlicher Nutzung (Beobachtungslauf).

**Leitlinie:** +151, z. B. Stock als Hebel, Stangenhütte, Grubenhütte, Speerschleuder.

### Alpha 1.13 – Ton, Keramik und eigener Ofen
**Ziel:** Wesen formen und brennen Ton, bauen Öfen mit Luftzufuhr und **schmelzen Kupfer selbst**. Der Testofen wird im normalen Spiel ersetzbar.
**Quellen:** Leitlinien-Zwischenschritt „Feuer, Ton und eigener Ofen“; Prompt 6/6B (Schmelzen, Gießen, Tiegel, Gussform); Prompt 12 §6 (Kalkbrennen als begrenzte Reaktion).

**Muss:**
- **Ton gewinnen** (1.4). **Plastisches Formmodell:** Wassergehalt, Formbarkeit, Wulst- und Plattentechnik.
- **Trocknen** mit Schwund und Rissgefahr.
- **Brennen:**
  - Temperatur und Zeit bestimmen die Keramik (Festigkeit, Porosität);
  - erst Grubenbrand, dann Töpferofen mit getrennter Brennkammer.
- **Töpferscheibe** (Drehen).
- **Keramikgefäße** zum Kochen, Lagern und für Wasser (sie dienen auch der Bewässerung aus 1.11).
- **Eigene Tiegel und Gussformen.**
- **Ofen mit Luftzufuhr:**
  - Blasrohr und Blasebalg (Leder aus 1.9) bringen über 1.100 °C;
  - damit **Kupfer schmelzen und gießen im normalen Spiel**.
- **Kalk brennen** → Kalkmörtel. **Lehmziegel und gebrannte Ziegel.**
- Der Testofen bleibt nur im Testbereich, unverändert.

**Abnahme:**
- Brennergebnis hängt von Temperatur und Zeit ab;
- ungebrannte Gefäße weichen im Wasser auf, gebrannte halten;
- Ofentemperatur nur mit Luftzufuhr über dem Schmelzpunkt von Kupfer;
- Kupferguss im normalen Spiel: gezielter Test plus Beobachtungslauf als Messwert;
- Kalkbilanz.

**Leitlinie:** +91, z. B. Tongefäß, Grubenbrand, Töpferofen, Kochgefäß über dem Feuer, Backofen aus Lehm.

### Alpha 1.14 – Gemeinschaften, Regeln, Religion, Konflikte (Prompt 10)
**Ziel:** Gemeinschaften, Regeln, Führung, religiöse Deutung, Rituale, Konflikte und Abspaltungen entstehen aus Interaktionen. Es gibt keine vorgegebene Geschichte.
**Quellen:** Prompt 10 vollständig (§1–21); Leitlinie: Wunden versorgen, Hygiene.

**Muss:**
- **Prompt 10 §2–20:**
  - Gemeinschaften, Wissensverbreitung, gemeinsame Regeln, Führung und Macht;
  - Religion und Deutung göttlicher Eingriffe (verbindet das Göttermenü), Rituale und Opfergaben;
  - Unterschiede, Vorurteile, Solidarität;
  - Ehrlichkeit, Irrtum, Täuschung (bisher bewusst nicht umgesetzt; jetzt nach §11);
  - Konflikte und Deeskalation;
  - Gefangenschaft und Zwangszustände nur nach §13–14;
  - Abspaltungen, Verbindung zur Baumgründung (§16, Prompt 7 §12).
- **Fürsorge:**
  - Wunden reinigen, abdecken und schonen; die Heilwirkung kommt aus dem Gesundheitsmodell;
  - einfache Hygiene (Abfall- und Wasserplätze getrennt);
  - Krankheiten gibt es bisher **nicht**, wird gekennzeichnet.

**Abnahme:** Prompt 10 §20; Heilwirkung messbar und ohne Wunderheilung.

**Leitlinie:** +139, z. B. Rangordnung, Gegenseitige Pflege, Gemeinsame Abwehr, Wunde mit Harz verschließen.

### Alpha 1.15 – Erz, Verhüttung, Bronze, Metallwerkzeuge, Bergbau
**Ziel:** Vom Erz zum Metall und zur Legierung. Wesen erkennen Erz, bauen es ab, verhütten es mit Holzkohle, legieren Bronze und gießen Werkzeuge, auch **Abbauwerkzeuge**.
**Quellen:** Leitlinien-Zwischenschritt „Erz und Legierungen“; Prompt 12 §5–6 (Material- und Reaktionsdefinitionen, **vorgezogen für die Reduktion**); Weltarchitektur (Bergbau, Stollen); Wunsch des Nutzers „Steinhammer → Schmelzen → Legieren → Abbauwerkzeuge“.

**Muss:**
- **Erzarten** aus 1.4 nutzbar: Malachit, gediegenes Kupfer, Kassiterit (Zinnerz), Bleiglanz, gediegenes Gold und Silber.
- **Aufbereitung:** zerkleinern, waschen, rösten.
- **Verhüttung** als begrenzte Reaktion: Reduktion mit Holzkohle (1.10) bei Ofentemperatur (1.13), Schlacke. Stoff- und Energiebilanz.
- **Zinn gewinnen.** **Legieren:** Mischschmelze Kupfer + Zinn → Bronze. Die Eigenschaften folgen dem Anteil (Härte, Schmelzpunkt, Gießbarkeit).
- **Zweiteilige Gussformen**, Kaltverfestigen, Glühen.
- **Metallwerkzeuge:** Beil, Meißel, Messer, **Pickel**. Der Pickel baut hartes Gestein physikalisch schneller ab als Geweih (Härte, Schneide; 1.4).
- **Bergbau** mit Stollen und Abstützung (1.4), Feuersetzen (1.10).

**Abnahme:**
- Stoff- und Massenbilanz der Verhüttung;
- kein Metall ohne Erz, Holzkohle und Temperatur;
- Legierungsanteil bestimmt die Eigenschaften;
- Pickel schneller als Geweihpicke;
- Speichern;
- Entwicklungslinie Steinhammer → Bronzepickel im Beobachtungslauf als Messwert.

**Leitlinie:** +63, z. B. Kupferverhüttung, Schlacke abtrennen, Arsenkupfer, Goldwaschen, **Bronzepickel**.

### Alpha 1.16 – Zeichen, Zählen, Maße, Schrift und Bücher (Prompt 11)
**Ziel:** Wesen halten Wissen außerhalb des Gedächtnisses fest. Zählen, Maße und Kalender werden möglich.
**Quellen:** Prompt 11 vollständig (§1–24); Leitlinie: Messen, Tinte; Himmelsmodell aus 1.3.

**Muss:**
- **Prompt 11 §2–23:**
  - Markierungen, Zeichensysteme, Lesen lernen;
  - Schreibträger: Holz, Stein, Ton (1.13), Rinde, Haut;
  - Dokumente, Bücher, Abschreiben mit Quellen, Unterricht;
  - Wissenssammlungen, Verlust und Wiederentdeckung, Weiterentwicklung von Verfahren, Beschädigung.
- **Zählen:** Kerbholz, Zahlzeichen.
- **Messen:** Längenmaß, Balkenwaage (Hebel aus 1.12), Gewichte.
- **Kalender** als Aufzeichnung beobachteter Himmelsregeln (1.3). Er ist nicht vorgegeben.

**Abnahme:**
- Prompt 11 §23;
- Waage vergleicht Massen korrekt;
- Kalenderaufzeichnung stimmt mit dem Himmelsmodell überein, wenn sie richtig beobachtet wurde, sonst bleibt sie falsch;
- kein Wissen durch Nähe zu einem Buch.

**Leitlinie:** +109, z. B. Kerbholz, Mondphasen verfolgen, Felsgravur, Zählsteine, Stempelsiegel.

---

## 7. Ausblick 1.17 – 1.21 und danach
Grob geplant. Detailplanung erst nach 1.16. Die Reihenfolge darf sich nach den Erfahrungen bis dahin ändern.

| Version | Inhalt | Quelle | +Leitlinie |
|---|---|---|---|
| **1.17 Große Welt II** | **Weltkarte** (Makrokarte: Kontinente, Klimazonen, Biome, Meere; verschiedene Breiten → verschiedene Jahreszeiten), **mehrere Regionen/Karten** mit Übergängen, Reisen und Wanderung von Wesen und Tieren zwischen Regionen, Fernsimulation ganzer Regionen, Regionenwahl in der Oberfläche; **Wasserwege**: Auftrieb, Floß, Einbaum, Paddel | D3, Weltarchitektur §13, Abschnitt 8 | +18 |
| 1.18 Mechanik II | Rollen, Rad und Achse, Wagen, Winde und Flaschenzug, gekoppelte Drehsysteme | Prompt 12 §11 | +41 |
| 1.19 Eisen und Stahl | Eisenerz, Rennofen, Luppe, Warmschmieden, Aufkohlen, Härten | Leitlinie | +171 |
| 1.20 Strahlung und Elektrik | Strahlungsquelle, Abschirmung, biologische Folgen (dann auch Mutationen durch Strahlung), Gleichstromkreise, Bauteile, Gefahren | Prompt 12 §9–10, §12–14 | +29 |
| 1.21 Gesamtaudit und Export | Funktionsaudit, Hauptszene, Langzeitläufe (≥ 1 h mit 50 Wesen), Balance, Leistungsstufen 100/250/500/1.000 Wesen, Ollama-Abschlussprüfung, **Windows-Export**, ehrliche Versionsbezeichnung | Prompt 13 | 0 |

**Danach** wird nach der Leitlinie weitergeplant. 1.413 Erfindungen sind noch nicht eingeplant, etwa:
- Messen, Optik und Zeitmessung;
- Wasser- und Windkraft, Segeln;
- Glas und Chemie, Heilen und Medizin;
- Papier und Druck;
- Wärmekraft, Elektrotechnik, Elektronik.

Welche Gruppe als nächste kommt, entscheidet der Engpass, den die Leitlinie dann zeigt (Blatt „Zwischenschritte“).

## 8. Zielarchitektur: Modularisierung und große Welten
### 8.1 Ziele
1. Neue Systeme (Klima, Ökologie, Feuer, Siedlungen …) werden als **Module** ergänzt, ohne bestehende umzubauen.
2. Die Welt kann **beliebig groß** werden, bis zur Weltkarte mit mehreren Regionen. Voll aufgelöst ist nur, was gerade gebraucht wird.
3. Der Spielstand ist **je Modul versioniert**. Alte Stände bleiben ladbar.
4. Leistung ist **je Modul messbar**.

### 8.2 Schichten
| Schicht | Inhalt | Regel |
|---|---|---|
| Kern | Simulationsuhr, Kalender (1.3), IDs, Ereignisse, Modulregister, Zufallsströme, Einstellungen | kennt keine Spielinhalte |
| Welt | Weltkarte → Region → Chunk, Generator, `WorldAccess`, Wasser, Geologie, Navigation | **einziger** Zugriff auf Gelände |
| Simulation | Module: Klima, Ökologie (Pflanzen, Tiere), Leben, Geist, Soziales, Kommunikation/KI, Technik und Reaktionen, Arbeit, Siedlung, Gemeinschaft, Schrift, Göttermenü | Module reden über Ereignisse und Abfragen, nicht über fremde interne Felder |
| Akteure | gemeinsame Basis für Wesen und Tiere: Körper, Wahrnehmung, Bewegung, Handlungen | ein Entscheider je Akteur |
| Darstellung | Chunk-Netze, Fern-LOD, Akteur-Ansichten, Himmel, Wetter, Oberfläche | liest nur Zustand |
| Speichern | Kopf + Abschnitte je Modul + Chunk-Deltas je Region | Migration je Abschnitt |
| Daten | `data/materials`, `data/maps`, `data/config`, `data/generated/*` | Handgeschriebenes und Erzeugtes getrennt |

### 8.3 Modulvertrag (Entwurf, wird in 1.1 festgelegt)
```gdscript
class_name SimModule extends RefCounted
var id: String                      # eindeutig, z. B. "ecology.plants"
var depends_on: Array[String] = []  # Reihenfolge ergibt sich daraus
var tick_hz := {"A": 0.0, "B": 2.0, "C": 0.2}   # 0 = jedes Simulationsbild
func setup(ctx: LifeContext) -> void: pass
func tick(dt: float, zone: int) -> void: pass   # Zone A/B/C (8.6)
func save_section() -> Dictionary: return {"v": 1}
func load_section(d: Dictionary) -> void: pass   # inkl. Migration der Abschnittsversion
func metrics() -> Dictionary: return {}          # Zeit je Tick, Objektzahlen
```
Das Register prüft Abhängigkeiten (Zyklen = Fehler), ruft in fester Reihenfolge auf und misst die Zeit je Modul. Spielszene und Tests nutzen **denselben** Pfad wie heute `LifeSimulation`.

### 8.4 Welt: Weltkarte → Region → Chunk
- **Weltkarte** (ab 1.17): grobes Raster (Vorschlag 1 Feld = 256 m) mit Höhe, Klima, Biom und Meer. Sie definiert, wo Regionen liegen.
- **Region** = eine spielbare Karte:
  - aus einer Kartenvorlage oder als Ausschnitt der Weltkarte;
  - Zellgröße fest je Welt (0,5 m oder 0,25 m nach Messung in 1.2), eigener Ordner im Spielstand.
- **Chunk** = Würfel aus Zellen (Vorschlag 32³), kompakt gespeichert, nur bei Bedarf geladen.
- **Koordinaten:** `(Region-ID, Zelle als Vector3i)`. Weltmeter = Regionsursprung + Zelle × Zellgröße. Kein Teil des Spiels nimmt eine feste Kartengröße an.
- **`WorldAccess`** (Entwurf):
  - Abfragen: `is_loaded(cell)`, `material_at(cell)`, `is_solid(cell)`, `surface_height(x, z)` (auch ungeladen, aus dem Höhenfeld), `water_at(cell)`, `raycast(from, to)`;
  - Änderungen: `set_material(cell, mat, ursache)` als einziger Schreibweg, mit Ereignis, Mesh-Auftrag, Navigation, Abstützung, Wasser.
- **Kartenvorlage** `data/maps/<id>.json` (Entwurf):
```json
{
  "schema_version": 1, "id": "waldtal", "name": "Waldtal",
  "cell_size_m": 0.5, "size_m": [144, 48, 144], "seed": 12345, "generator_version": 1,
  "latitude_deg": 50, "sea": false,
  "biomes": {"Wald": 0.45, "Wiese": 0.25, "Seeufer": 0.15, "Berg": 0.1, "Pilzwald": 0.05},
  "start_area": {"biome": "Wiese", "near_water": true, "radius_m": 6},
  "geology_profile": "mitteleuropa_einfach"
}
```
- **Generator-Pipeline**, deterministisch aus `(Weltstartwert, Generatorversion, Region, Chunk)`: Höhe → Biome → Geologie (1.4) → Gewässer → Startvegetation → Startgebiet. Eine neue Generatorversion gilt nur für **neue** Welten oder neue, noch nie erzeugte Bereiche. Das wird dokumentiert.

### 8.5 Streaming und Darstellung
- **Ladezonen** um die Kamera und um aktive Akteure, mit Vorladen in Blickrichtung. Beim Entladen werden geänderte Chunks gespeichert.
- **Hintergrundaufträge** (`WorkerThreadPool`) für Generierung und Netze. Szenenbaum und Physik werden nur im Hauptthread mit Budget je Bild geändert. Aufträge sind priorisiert (sichtbar und nah zuerst).
- **Fern-LOD:** vergröberte Netze oder Höhenfeld-Netze bis zur Sichtweite. Kollision gibt es nur in geladenen Chunks.

### 8.6 Simulationszonen
| Zone | Wo | Was läuft | Takt |
|---|---|---|---|
| A aktiv | um die Kamera und um laufende kritische Vorgänge (Kampf, Feuer, Geburt, Bau) | alles in voller Auflösung | jedes Simulationsbild |
| B nah | geladene Chunks außerhalb von A | Akteure, Pflanzen, Wasser ohne Darstellung | 1–4 Hz |
| C fern | nicht geladene Bereiche und Regionen | Bestands- und Bilanzmodelle: Biomassefelder, Herden, Tagesabläufe der Wesen als Zeitblöcke | 0,1–1 Hz |

**Regeln:**
- gleiche Zeit-, Stoff- und Energiebilanz in allen Zonen;
- Übergänge C→B→A werden deterministisch rekonstruiert;
- kritische Vorgänge heben die Zone an;
- **nichts verschwindet außerhalb der Kamera** (Weltarchitektur §13, Prompt 13 §10).

### 8.7 Navigation
- Hierarchisch:
  - Chunk-Graph mit Portalen für lange Wege, lokales A* innerhalb der Chunks;
  - Körpergrößenklassen (klein, mittel, groß);
  - Wegkosten (Steigung, Wasser, bekannte Gefahr).
- Nach Terrainänderungen nur betroffene Chunks neu berechnen.
- **Wesen planen nur über bekanntes Gebiet** (Erkundungswissen, 1.2). Unbekanntes wird erkundet.

### 8.8 Spielstand (Format 6)
```
saves/<name>/meta.json             Kopf: format_version 6, game_version, Startwert, Generatorversionen, Definitions-Fingerabdruck
saves/<name>/modules.json          Abschnitte je Modul {"<modul-id>": {"v": n, ...}}
saves/<name>/regions/<id>/chunks/  nur geänderte Chunks (komprimiert)
saves/<name>/regions/<id>/far.json Zustand der Fernsimulation (Biomassefelder, Herden …)
```
Beim Laden wird jeder Abschnitt einzeln von seiner Version auf die aktuelle migriert. Vorher wird das Original gesichert. Für jede Version gibt es Prüflinge aus echten Spielständen (`tests/fixtures/`). Die Migration 5→6 überführt die heutige Einzeldatei.

### 8.9 Leistungsziele (Richtwerte, in jeder Version gemessen)
| Profil | Ziel |
|---|---|
| GTX 1660 Ti, 1080p, Standardkarte, 50 Wesen + Ökosystem | ≥ 30 Bilder/s; Simulation ≤ 8 ms je Bild bei 1×; Arbeitsspeicher ≤ 4 GB; Laden ≤ 30 s |
| RTX 3080 | größere Sichtweite, größere Karten (Messung) |
| Bevölkerung | 50 Standard; 100/250/500/1.000 nur als getestete Profile (Prompt 13 §10) |

Gemessen wird auf dem PC des Nutzers (Messszene ab 1.2). Die Arbeitsumgebung der KI misst nur Simulationszeiten ohne Grafikkarte.

### 8.10 Wohin die heutigen Teile wandern (1.1)
| Heute | Ziel |
|---|---|
| `scripts/world/voxel_data.gd`, `voxel_chunk.gd`, `world_generator.gd`, `voxel_world.gd`, `water_system.gd`, `support_system.gd`, `navigation_service.gd` | Welt-Schicht hinter `WorldAccess`; Generator als Pipeline |
| `scripts/world/life_simulation.gd`, `life_context.gd` | Kern-Simulationspfad mit `ModuleRegistry` |
| `scripts/world/day_night_system.gd` | Modul Zeit/Himmel (wird in 1.3 zum Kalender- und Himmelsmodul) |
| `scripts/ecology/*` | Modul Ökologie (wird in 1.5/1.9 ausgebaut) |
| `scripts/agents/*`, `scripts/biology/*` | Akteursbasis (in 1.9 gemeinsam für Tiere) |
| `scripts/mind/*`, `scripts/social/*`, `scripts/ai/*`, `scripts/technology/*`, `scripts/settlement/*`, `scripts/god/*` | je ein Modul oder eine Modulgruppe, Inhalt unverändert |
| `scripts/persistence/*` | Speicherformat 6 mit Abschnitten |
| `scripts/rendering/*`, `scripts/ui/*`, `scripts/animation/*` | Darstellung (liest nur) |

## 9. Lebendige Welt: wie sich die Wesen selbst entwickeln
### 9.1 Wie organisch? (Entscheidung nach D1)
- **Die Welt stellt Möglichkeiten bereit, nicht Ziele.** Jede Version bringt Physik, Stoffe und Handlungen. Welche Wesen was wann entdecken, entscheidet die Simulation. Es gibt keine Pflicht-Erfindungen und keine Vorgabe der Art „bis Version X müssen sie Y können“.
- **Anlässe kommen aus der Welt:**
  - Hunger, Kälte, Regen, Dunkelheit, Gefahr, harte Nahrung, weite Wege, Überfluss;
  - natürliche Vorbilder: Blitzfeuer, scharfe Bruchkanten, Tierbauten, Treibholz.
- **Wege zur Entdeckung:**
  - Neugier und Versuch (Prompt 6);
  - Zufall bei der Arbeit;
  - Beobachtung natürlicher Vorgänge und anderer Wesen, Nachahmung;
  - Unterricht;
  - Modellvorschläge (Ollama) als ungeprüfte Ideen.
- **Wissen ist individuell und kann verloren gehen:** Wer stirbt, nimmt nicht Weitergegebenes mit. Ab 1.16 gibt es Aufzeichnungen.
- **Rückschritte sind möglich:** Verarmung, Wissensverlust, Konflikte. Das System verhindert sie nicht heimlich.

### 9.2 Problemlöse-Schleife (ab 1.8, in jeder Version erweitert)
```
Bedarf (z. B. Kälte, harte Nuss, Wasser weit weg)
  → Hindernis erkennen (was fehlt: Wärme, Kraft, Gefäß, Weg)
  → Ideen sammeln: eigenes Wissen · Beobachtung · Analogie zu ähnlichem Problem · Hörensagen · Modellvorschlag (Ollama, geprüft)
  → Versuch planen (nur vorhandene Handlungen)  → ausführen  → Ergebnis messen (Physik)
  → bewerten (besser als vorher?)  → Gedächtnis (Verfahren mit Erfolgsrate)  → weitergeben / verbessern
```
Die Schleife ist eine **Option im einzigen Entscheider** (`DecisionSystem`), kein zweiter Entscheider. Jede neue Version meldet ihre neuen Möglichkeiten an, ohne die Schleife umzubauen: neue Bedarfe (z. B. Kälte ab 1.3), neue Handlungen, neue Bewertungsgrößen.

### 9.3 Eigene Erfindungen der Wesen (D1)
- Erfindungen, die **nicht** in der Leitlinie stehen, sind erwünscht. Erkannt werden sie als neues Verfahren mit messbarem Nutzen:
  - neue Kombination von Material, Werkzeug und Handlungsfolge;
  - neue Funktion.
- Die Chronik (1.8) beschreibt sie als Ablauf (Material → Schritte → Ergebnis). Der Spieler darf sie benennen. Sie gelten im Spiel genauso wie Leitlinien-Erfindungen.

### 9.4 Leitlinie im Spiel (D4)
| Nutzung | Ab | Regel |
|---|---|---|
| Erfindungs-Chronik (Spieleransicht) | 1.8 | Erkennen nur an tatsächlichen Ergebnissen, nie an Namen |
| Ideenkatalog für Ollama | 1.8 | Hinweise nur aus Erfindungen, die im Spiel physikalisch möglich sind; Ergebnis bleibt Hypothese, Ausführung nur über geprüfte Handlungen |
| Nachschlagewerk | 1.8 | Spielerwissen; Wesen sehen es nicht |
| Freischaltung | **nie** | Leitprinzip 1 |

## 10. Leitlinie und Alpha-Plan
- **Quelle der Zuordnung:** `tools/leitlinie/vokabular.py`:
  - `ALPHA_VERSIONEN`: Liste der Versionen;
  - `ALPHA_PLAN_VERFAHREN` und `ALPHA_PLAN_MATERIALIEN`: ab welcher Version ein Verfahren oder Material im normalen Spiel verfügbar sein soll.
- Eine Erfindung ist ab der **spätesten** Version ihrer Verfahren und Materialien eingeplant (Spalte „geplant möglich ab (Alpha-Plan)“, Blätter „Alpha-Plan“ und „Alpha-Zeitalter“ der Leitlinien-Excel).
- **Ein Test prüft:** Alles, was die vorliegenden Prompts bringen (WA, P7–P12), ist eingeplant, und nur Sprengen ist „nie“.
- **Nach jeder Version:**
  1. Tatsächlich spielbare Codes in `VERFAHREN`/`MATERIALIEN` auf `"A"` setzen. Den Text in `STATUS_BESCHREIBUNG["A"]` ergänzen (z. B. „in Alpha 1.4“).
  2. Abweichungen vom Plan hier im Änderungsprotokoll festhalten und `ALPHA_PLAN_*` anpassen.
  3. `python3 tools/build_leitlinie.py`, Python-Tests.
- **Zuordnung der Zwischenschritte zu Versionen:**

| Zwischenschritt der Leitlinie | Version |
|---|---|
| Jahreszeiten, Himmel und Erdgeschichte im Weltmodell | 1.3 (Jahreslauf), 1.4 (Gesteinsschichten, Fossilien; **keine** Erdbeben) |
| Werkzeugformen und spanende Bearbeitung | 1.8 (Abschlagen, Schneiden, Bohren, Schleifen), 1.13 (Drehen/Töpferscheibe) |
| Fasern, Seil und Textil | 1.8 (Schnur, Flechten), 1.9 (Nähen, Kleidung), 1.12 (Spinnen, Weben) |
| Werfen und elastische Energie | 1.8 (Werfen), 1.9 (Bogen) |
| Tierische Werkstoffe | 1.9 (Gerben 1.11) |
| Feuer, Ton und eigener Ofen | 1.10 (Feuer, Holzkohle), 1.13 (Ton, Keramik, Ofen, Luftzufuhr, Schmelzen/Gießen, Kalk, Ziegel) |
| Pflanzenstoffe, Haltbarmachen und Gärung | 1.5 (Harz, Wirkstoffe), 1.11 (Trocknen, Öl); Gären, Extrahieren, Destillieren: offen |
| Erz und Legierungen | 1.4 (Erz im Gelände), 1.15 (Verhütten, Legieren, Zinn, Bronze, Gold, Silber, Blei), 1.19 (Eisen, Stahl, Schmieden, Härten) |
| Heilen, Hygiene und Medizin | 1.5 (Wirkstoffe), 1.14 (Wunden, Hygiene); Chirurgie, Diagnose, Impfen: offen |
| Licht, Messen, Zeit und Zeichen | 1.8 (Farbe, Klang), 1.16 (Messen, Tinte); Optik, Uhrwerk, Navigation, Papier, Druck: offen |
| Wasser- und Windkraft, Schwimmen | 1.17 (Auftrieb); Rest offen |
| Chemie und Baustoffe | 1.13 (Mörtel); Rest offen |
| Wärmekraft, Elektrotechnik über P12, Elektronik, Biotechnik, Hochtechnologie | offen |
| Sprengen | nie (Projektregel) |

## 11. Querschnitt: Tests, Leistung, Spielstände, Ollama, Doku
- **Tests:**
  - jede Version: alle alten Tests grün auf 4.7.2 und 4.5, neue Tests für jede neue Funktion;
  - Szenentests für neue Szenen, Beobachtungsläufe mit Messwerten;
  - Python-Tests für Werkzeuge.
- **Gezielt vs. eigenständig:** Testszenen mit Knöpfen beweisen Regeln. Beobachtungsläufe (feste Startwerte) messen eigenständiges Verhalten. Beides wird getrennt berichtet.
- **Leistung:** Messbericht in jeder Version (Simulation je Modul in der Arbeitsumgebung; Grafik beim Nutzer ab 1.2).
- **Spielstände:** Prüflinge je Version in `tests/fixtures/`. Migrationen werden nie ohne echten Spielstand der Vorversion getestet.
- **Ollama:**
  - Die Anfragearten wachsen mit den Versionen (Versuch, Arbeit, später Bau, Landwirtschaft, Gemeinschaft, Schrift);
  - jede Antwort ist geprüft und wirkt nur über Handlungen;
  - echte Tests beim Nutzer (`tools/ollama_live_test.gd`) bleiben offen, bis er sie macht.
- **Doku je Version:** README, CHANGELOG, HANDOVER, dieses Dokument (Status-Spalte unten), `docs/test_results.md`, `docs/plan_alpha_1_N.md`, Fachdoku (`docs/architecture.md` u. a.), Leitlinie.

**Status der Versionen** (nach jeder Lieferung aktualisieren):

| Version | Status | Datum | Commit | Bemerkung |
|---|---|---|---|---|
| 1.1 | geplant | – | – | – |
| 1.2 | geplant | – | – | – |
| 1.3 | geplant | – | – | – |
| 1.4 | geplant | – | – | – |
| 1.5 | geplant | – | – | – |
| 1.6 | geplant | – | – | – |
| 1.7 | geplant | – | – | – |
| 1.8 | geplant | – | – | – |
| 1.9 | geplant | – | – | – |
| 1.10 | geplant | – | – | – |
| 1.11 | geplant | – | – | – |
| 1.12 | geplant | – | – | – |
| 1.13 | geplant | – | – | – |
| 1.14 | geplant | – | – | – |
| 1.15 | geplant | – | – | – |
| 1.16 | geplant | – | – | – |
| 1.17–1.21 | Ausblick | – | – | – |

## 12. Risiken und Gegenmaßnahmen
| Risiko | Wirkung | Gegenmaßnahme |
|---|---|---|
| GDScript zu langsam für große Voxelwelten | 1.2 verfehlt Ziele | messen; gröberes Profil liefern; GDExtension nur bei nachgewiesenem Engpass |
| Umbau 1.1 bricht Verhalten | Funktionsverlust | Module erst einhüllen, dann umziehen; Vergleichsläufe; Versionsvergleich |
| Bevölkerungswachstum (1.6) + Tiere (1.9) überlasten | Ruckeln, Abstürze | technische Grenzen sichtbar; Zonenmodell; Profile 100/250/… erst nach Messung |
| Fernsimulation weicht von Nahsimulation ab | Bilanzfehler | gleiche Bilanzformeln; Tests Nah ↔ Fern ↔ Nah |
| Ökosystem kippt (Aussterben, Überwucherung) | unspielbar | Balance-Läufe mit festen Startwerten; Sandbox nur sichtbar; keine heimliche Hilfe |
| Wesen entdecken nichts eigenständig | „tote“ Entwicklung | Anlässe in der Welt (9.1), Problemlöse-Schleife, Beobachtung natürlicher Vorgänge; Messwerte statt Zwang |
| Spielstände groß | Ladezeit, Speicher | nur Chunk-Deltas, komprimiert, Fernzustand kompakt |
| Prompt-Text und Plan widersprechen sich | Unklarheit | Prompt-Text gilt für Inhalte; dieser Plan für Reihenfolge; Widerspruch im Änderungsprotokoll klären oder beim Nutzer nachfragen |
| Chat wird komprimiert oder neu begonnen | Wissensverlust | HANDOVER + dieses Dokument + `docs/plan_alpha_1_N.md` vor jeder Pause pushen |

## 13. Annahmen, die der Nutzer jederzeit ändern kann
Diese Punkte hat Claude nach D1 entschieden. Sie sind keine offenen Fragen; der Nutzer kann sie jederzeit ändern.

1. **„Verschiedene Maps“:**
   - ab 1.2 mehrere wählbare Kartenvorlagen;
   - ab 1.17 eine Weltkarte mit mehreren Regionen, zwischen denen Wesen und Tiere reisen;
   - 1.17 kann vorgezogen werden (frühestens nach 1.9).
2. **Jahreslänge** 32 Spieltage (4 × 8), Mondumlauf 8 Spieltage. Beides ist konfigurierbar.
3. **Feuer vor Prompt 12** (Alpha 1.10), weil es organisch in die Altsteinzeit gehört.
4. **Prompt 7 und Prompt 8 sind geteilt und verschränkt:** Pflanzen (1.5) → Nachwuchs (1.6) → Vererbung (1.7) → Tiere (1.9) → Zähmung und Landwirtschaft (1.11).
5. **Prompt 11 (Schrift)** nach Prompt 9 und 10, wie früher entschieden.
6. **Windows-Build** wird ab 1.1 versucht, zusätzlich zum Projekt-ZIP.
7. Die **Bevölkerungsgrenze** ist anfangs konservativ (z. B. 80) und steigt nur nach Messung.

## 14. Pflege dieses Dokuments und Änderungsprotokoll
- **Nach jeder Version:**
  - Statustabelle (Abschnitt 11) ausfüllen;
  - Abweichungen unten eintragen;
  - Alpha-Plan in der Leitlinie nachziehen (Abschnitt 10).
- **Ändert sich die Reihenfolge,** werden Abschnitt 5, der betroffene Abschnitt 6/7 und `ALPHA_PLAN_*` angepasst, und hier wird der Grund vermerkt.
- **Neue Wünsche des Nutzers** kommen sofort in Abschnitt 1 (mit Datum und Wortlaut) und in die betroffene Version.

| Datum | Änderung | Grund |
|---|---|---|
| 25.11.2026 | Erste Fassung: Alpha 1.1–1.16 im Detail, 1.17–1.21 Ausblick, Alpha-Plan in der Leitlinien-Excel | Entscheidungen D1–D6 des Nutzers |
