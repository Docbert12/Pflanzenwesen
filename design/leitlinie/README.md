# Quellen der Leitlinien-Excel „Steinzeit → Zukunft“

Diese Textdateien sind die **Quelle** der Datei `design/Leitlinie_Steinzeit_bis_Zukunft.xlsx`.
Die Excel wird mit `python3 tools/build_leitlinie.py` daraus erzeugt und geprüft; Änderungen bitte hier
eintragen (oder in der Excel, dann hier nachziehen), damit die Prüfungen weiter greifen.

Eine Datei je Zeitalter (`zeitalter_01.txt` … `zeitalter_24.txt`), eine Erfindung je Zeile:

```
Name | Kategorie | Materialien | Verfahren | Funktion | Vorläufer | Stand | Hinweis
```

- **Kategorie:** ein Buchstabe – W Wissenschaft, B Bergbau, L Agra, A Architektur, T Werkzeug, M Mechanik,
  K Militär, V Transport, G Gesellschaft, D Medizin, E Energie, C Kommunikation (wie in der Erfindungs-Excel des Nutzers).
- **Materialien / Verfahren:** Codes aus `tools/leitlinie/vokabular.py`, mit Komma getrennt; `-` = keine.
- **Funktion:** was die Erfindung physikalisch leistet (keine Boni, keine Prozentwerte).
- **Vorläufer:** Namen früherer Erfindungen (gleiches oder früheres Zeitalter), mit `;` getrennt; optional.
  Das ist **kein Technologiebaum**: Nichts wird freigeschaltet. Es zeigt nur, was physikalisch vorher da sein muss.
- **Stand:** leer = historisch belegt, `entw` = in Entwicklung/erst teilweise verwirklicht, `spek` = spekulativ.
- **Hinweis:** frei, z. B. Besonderheiten für Pflanzenwesen.
- Zeilen mit `#` am Anfang sind Kommentare.

Projektregel: Für Sprengstoffe und Schießpulverwaffen stehen nur Name und Funktion, **keine** Stoffe oder Rezepte.

Materialien der Art „Weltmodell“ (`jahreslauf`, `geologie`) sind keine Stoffe, sondern etwas, das die Welt bieten muss
(Jahreszeiten, Mond, Sterne, Gezeiten; Gesteinsschichten, Fossilien, Erdbeben).

Wie Spielstand, Lücken und Testbereich abgeleitet werden, Zahlen und offene Entscheidungen: `docs/leitlinie.md`.
