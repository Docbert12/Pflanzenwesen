# Ideenkatalog aus der Erfindungs-Excel

Quelle: `design/Erfindungen_nach_Kategorien_und_Stufen.xlsx` (nur gelesen, unverändert).
Erzeugt mit `python tools/import_inventions.py --write` → `data/generated/ideas/inventions_catalog.json`,
Bericht: `reports/inventions_import_report.md`.

## Was der Katalog ist
Eine **Ideenliste** für die Entwicklung: 24 Zeitalter (Tierwelt … Zukunft/Singularität), 12 Kategorien
(Wissenschaft, Bergbau, Agra, Architektur, Werkzeug, Mechanik, Militär, Transport, Gesellschaft, Medizin,
Energie, Kommunikation), 5498 Einträge, zusammengefasst zu **96 Grundbegriffen** (8 je Kategorie,
z. B. Werkzeug: Handwerkzeug, Herstellung, Mehrzwecktool, Montage, Schärfung, Präzisionswerkzeug, Gerät, Vorrichtung).

## Was der Katalog NICHT ist
- **Nichts ist aktiv.** Jeder Eintrag hat `game_status: "idea_only"`.
- Die Excel-Effekte („+75 % Produktion“, „Schaltet Wunder frei“ …) stehen nur als Originaltext
  `excel_effect_text` im Katalog und werden nie ausgewertet. Es gibt **keine globalen Boni, keine
  Zeitalter-Freischaltung und keine Forschungspunkte** – das widerspräche dem Projektgrundsatz.
- Eine Erfindung existiert im Spiel erst, wenn Wesen sie mit echten Materialien, Werkzeugen und
  Arbeitsschritten herstellen (spätere Prompts, z. B. Werkzeugherstellung, Schrift in Prompt 11).
- Der Katalog gehört nicht zum Definitionsfingerabdruck der Spielstände (ändert keine Spielwerte).

## Befund zur Datei
- Alle 5498 Beschreibungen sind derselbe Schablonensatz; die Namen sind überwiegend nummeriert.
- Ab Stufe 6 kehren die Begriffe als „Fortgeschrittene …“, ab 13 „Industrielle …“, ab 19 „Moderne …“,
  ab 23 „Zukunfts-…“ wieder.
- Mehrere Begriffe stehen in unpassend frühen Zeitaltern (z. B. Flug ab Frühe Steinzeit, Zug und Kraftwerk
  ab Altsteinzeit). Für eine echte Planung wäre eine bereinigte Liste mit konkreten Erfindungen, Materialien
  und Voraussetzungen nötig.
