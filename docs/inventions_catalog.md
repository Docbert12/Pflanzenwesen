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

---

# Erfindungskatalog „echte Namen“ (Prompt 6B)

Quelle: `design/Erfindungen_Echt_nach_Kategorien.xlsx` (Datei des Nutzers, nur gelesen, unverändert; MD5 `914666d6…`).
Erzeugt mit `python tools/import_inventions_real.py --write` → `data/generated/ideas/inventions_real_catalog.json`,
Bericht: `reports/inventions_real_import_report.md`. Der ältere Ideenkatalog oben bleibt unverändert erhalten.
Leitlinie des Nutzers: Die Excel ist eine **Leitlinie** – die Wesen sollen sich selbst von der Steinzeit zur Zukunft
entwickeln (Stein → Werkzeug → Schmelzen → Legierung → Abbauwerkzeuge), nicht über einen Technologiebaum.
Die daraus gebaute Leitlinie mit physikalischen Ketten (2.680 Erfindungen, 24 Zeitalter) steht in `design/Leitlinie_Steinzeit_bis_Zukunft.xlsx`; ihr Blatt „Katalogabgleich“ ordnet die echten Namen dieses Katalogs zu (`docs/leitlinie.md`). Der Katalog selbst bleibt unverändert.

## Übernommen
- Name, Kategorie, Quellenzeile(n) (Blatt, Zeile), Beschreibung, Effekttext je Quellenzeile (nur Text), Stufe als **Metadatum**.
- 5.862 Quellenzeilen → **2.785 Katalogeinträge**: zusammengefasst wird nur bei **gleichem Namen UND gleicher Kategorie**
  (dieselbe Erfindung, in mehreren Zeitaltern wiederholt, z. B. „Feuer“ in Wissenschaft 18-mal). Jede Quellenzeile bleibt
  im Eintrag erhalten. Gleiche Namen in verschiedenen Kategorien (z. B. „Feuer“ in Wissenschaft und Energie, „Rad“ in
  Mechanik und Transport) bleiben **getrennt** und verweisen nur aufeinander – ein gleicher Name beweist kein gleiches Verfahren.
- Namensart: 85 echte Namen, 92 redaktionelle Varianten „… (verbessert)“, 2.608 erzeugte Fantasienamen
  („Quanten- Feuer 16“ = Vorsilbe + Grundbegriff + Nummer); alle mit Grundbegriff gekennzeichnet.

## Nicht übernommen / keine Wirkung
- **Stufe = keine Reihenfolge**, keine Freischaltung, keine Voraussetzung. Mehrere Stufen sind historisch zu früh
  (Dampfmaschine und Elektrizität ab Bronzezeit, Buchdruck ab Kupferzeit, Rad und Kalender ab Früher Steinzeit,
  Bronzelegierung ab Mittelsteinzeit) – im Bericht gekennzeichnet.
- **Effekte** (55 verschiedene Zufallsboni wie „+40 % Produktion“) werden nie angewendet.
- **Kein Startwissen:** Alle Einträge haben `game_status: "catalog"`; neue Wesen haben keine Verfahren (Test
  „Erfindungskatalog: … kein Startwissen“).
- Beschreibungen sind zu 100 % derselbe Schablonensatz.

## Fehlende Begriffe für die Werkzeug- und Materialkette
Hammer, Töpferei/Keramik, Blasebalg, Seil/Schnur, Guss, Lager, Korb, Tiegel, Gussform fehlen im Katalog. Die in Prompt 6/6B
umgesetzten Verfahren sind deshalb eigene Definitionen (siehe unten), mit dem Katalog nur als „verwandt“ oder „Vorstufe“ verknüpft.

## Aktivierte Definitionen (`data/config/inventions_activated.json`)
Strukturierte Beschreibung dessen, was **im Code tatsächlich existiert** – sie aktiviert nichts. Je Verfahren:
benötigte Materialien und Mengen, Körperfähigkeiten (Hände, einarmige Variante), Werkzeuge, Handlungen
(Verarbeitungsvorgänge), Arbeitsschritte, Zeit- und Energiebedarf (mit Verweis auf die Spielparameter in
`technology.json`), Ergebnisgeometrie, messbare Funktion, erforderliche Animationen, Implementierungsstatus, Tests.

| ID | Verfahren | Status | Katalogbezug |
|---|---|---|---|
| ACT_stone_strike | Stein als Schlagwerkzeug | umgesetzt | verwandt: Stein-Handaxt (Werkzeug) |
| ACT_lashing | Umwickeln mit Pflanzenfasern | umgesetzt (auch einarmig) | – (Seil/Schnur fehlt im Katalog) |
| ACT_hammer | Hammer aus Holzstiel, Steinkopf, Fasern | umgesetzt | Vorstufe/verwandt: Stein-Handaxt; verwandt: Keule (Militär) |
| ACT_break_stone | Stein mit dem Hammer zerschlagen | umgesetzt | verwandt: Steinbruch (Bergbau) |
| ACT_cold_work_copper | Kupfer kalt verformen | umgesetzt | Vorstufe: Kupferaxt (Werkzeug) |
| ACT_melt_cast_copper | Kupfer im Tiegel schmelzen und gießen | nur Testausrüstung | verwandt: Kupferverhüttung (kein Erz!) |
| ACT_storage | Lagerplatz nutzen | umgesetzt | – |
| ACT_stone_row | Steinreihe (Einzelbauwerk) | teilweise (Prompt 9: gemeinsames Bauen) | Vorstufe: Steinmauer (Architektur) |

Vorbereitet, nicht aktiv: Graben, Erde verdichten (keine Abbau-Mengenbilanz). Ein Konsistenztest prüft, dass alle
genannten Handlungen, Materialien, aktiven Animationen, Spielparameter und Katalogverweise existieren.
