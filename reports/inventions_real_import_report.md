# Import Erfindungs-Excel „echte Namen“ → Erfindungskatalog (Prompt 6B)

Quelle: `design/Erfindungen_Echt_nach_Kategorien.xlsx` (SHA-256 `344dba106844e625…`, nur gelesen, unverändert)
Katalog: `data/generated/ideas/inventions_real_catalog.json` – geschrieben
Älterer Ideenkatalog (`inventions_catalog.json`, andere Excel) bleibt unverändert erhalten.

## Ergebnis
- Zeitalter (Stufen): 24 (Tierwelt … Zukunft / Singularität) – **nur Metadatum, keine Reihenfolge**
- Kategorien: 12 (Wissenschaft, Bergbau, Agra, Architektur, Werkzeug, Mechanik, Militär, Transport, Gesellschaft, Medizin, Energie, Kommunikation)
- Quellenzeilen: 5862
- Katalogeinträge nach Zusammenfassung (gleicher Name + gleiche Kategorie): 2785
  - echte Namen: 85 · redaktionelle Varianten „(verbessert)“: 92 · erzeugte Fantasienamen (Vorsilbe + Nummer): 2608
- Gleiche Namen in mehreren Kategorien (NICHT zusammengefasst, nur verwiesen): 11
- Beschreibungen nach demselben Schablonensatz „<Name> – konkrete Erfindung in der Kategorie …“: 5862 von 5862
- Verschiedene Effekttexte: 55 – **keiner wird angewendet** (nur Originaltext je Quellenzeile)
- Abweichungen von der Übersichtstabelle: 0

## Zusammenfassen (Herkunft bleibt erhalten)

Dieselbe Erfindung steht oft in vielen Zeitaltern hintereinander (z. B. „Feuer“ in Wissenschaft). Diese Zeilen werden zu EINEM Eintrag mit allen Quellenzeilen (Blatt, Zeile, Stufe, Effekttext) zusammengefasst. Gleiche Namen in verschiedenen Kategorien bleiben getrennt – ein gleicher Name beweist kein gleiches Verfahren.

| Eintrag | Kategorie | Quellenzeilen | Stufen |
|---|---|---|---|
| Feuer | Wissenschaft | 18 | 1–18 |
| Steinbruch | Bergbau | 18 | 1–18 |
| Sammeln | Agra | 18 | 1–18 |
| Höhle | Architektur | 18 | 1–18 |
| Stein-Handaxt | Werkzeug | 18 | 1–18 |
| Hebel | Mechanik | 18 | 1–18 |
| Kalender | Wissenschaft | 17 | 2–18 |
| Kupferbergbau | Bergbau | 17 | 2–18 |
| Jagd | Agra | 17 | 2–18 |
| Zelt | Architektur | 17 | 2–18 |
| Stein-Schaber | Werkzeug | 17 | 2–18 |
| Rad | Mechanik | 17 | 2–18 |

Beispiele gleicher Namen in mehreren Kategorien: Bogen (Architektur, Militär); Feuer (Wissenschaft, Energie); KI-gestützt Feuer 1 (Wissenschaft, Energie); Nano- Feuer 1 (Wissenschaft, Energie); Präzisions- Schrift 3 (Wissenschaft, Kommunikation); Quanten- Feuer 1 (Wissenschaft, Energie); Rad (Mechanik, Transport); Schrift (Wissenschaft, Kommunikation); Wasserrad (Mechanik, Energie); fortgeschritten Feuer 1 (Wissenschaft, Energie); fortgeschritten Schrift 3 (Wissenschaft, Kommunikation).

## Zeitalter-Angaben (Stufe nur Metadatum)

Einige Stufen liegen historisch deutlich zu früh. Das bestätigt, dass die Stufe keine Entwicklungsreihenfolge vorgeben darf (Leitlinie: Die Wesen entwickeln sich selbst, die Excel ist eine Leitlinie).

- Kalender (Wissenschaft): Erste Stufe 2 (Frühe Steinzeit) liegt vor der frühestens plausiblen Stufe 6 – Stufe ist nur Metadatum.
- Schrift (Wissenschaft): Erste Stufe 3 (Altsteinzeit) liegt vor der frühestens plausiblen Stufe 6 – Stufe ist nur Metadatum.
- Bronzelegierung (Bergbau): Erste Stufe 4 (Mittelsteinzeit) liegt vor der frühestens plausiblen Stufe 7 – Stufe ist nur Metadatum.
- Eisenverhüttung (Bergbau): Erste Stufe 5 (Jungsteinzeit / Steinzeit) liegt vor der frühestens plausiblen Stufe 8 – Stufe ist nur Metadatum.
- Hochofen (Bergbau): Erste Stufe 7 (Bronzezeit) liegt vor der frühestens plausiblen Stufe 9 – Stufe ist nur Metadatum.
- Rad (Mechanik): Erste Stufe 2 (Frühe Steinzeit) liegt vor der frühestens plausiblen Stufe 6 – Stufe ist nur Metadatum.
- Dampfmaschine (Mechanik): Erste Stufe 7 (Bronzezeit) liegt vor der frühestens plausiblen Stufe 16 – Stufe ist nur Metadatum.
- Rad (Transport): Erste Stufe 3 (Altsteinzeit) liegt vor der frühestens plausiblen Stufe 6 – Stufe ist nur Metadatum.
- Eisenbahn (Transport): Erste Stufe 8 (Eisenzeit) liegt vor der frühestens plausiblen Stufe 17 – Stufe ist nur Metadatum.
- Münzen (Gesellschaft): Erste Stufe 4 (Mittelsteinzeit) liegt vor der frühestens plausiblen Stufe 8 – Stufe ist nur Metadatum.
- Elektrizität (Energie): Erste Stufe 7 (Bronzezeit) liegt vor der frühestens plausiblen Stufe 17 – Stufe ist nur Metadatum.
- Schrift (Kommunikation): Erste Stufe 4 (Mittelsteinzeit) liegt vor der frühestens plausiblen Stufe 6 – Stufe ist nur Metadatum.
- Buchdruck (Kommunikation): Erste Stufe 6 (Kupferzeit) liegt vor der frühestens plausiblen Stufe 11 – Stufe ist nur Metadatum.
- Telegraf (Kommunikation): Erste Stufe 7 (Bronzezeit) liegt vor der frühestens plausiblen Stufe 17 – Stufe ist nur Metadatum.

## Für die Werkzeug- und Materialkette fehlende Begriffe

Im Katalog fehlen: Hammer, Töpferei, Keramik, Blasebalg, Seil, Schnur, Guss, Lager, Korb, Tiegel, Gussform. Die in Prompt 6/6B umgesetzten Verfahren (Hammer aus Stiel, Steinkopf und Fasern; Umwickeln; Lager; Gießen im Tiegel) sind daher eigene Definitionen ohne Katalogeintrag bzw. nur „verwandt“ mit Katalogeinträgen.

## Verknüpfung mit aktivierten Definitionen (`data/config/inventions_activated.json`)

- `INVR_architektur_steinmauer` Steinmauer (Architektur) ← ACT_stone_row (Vorstufe – eine Reihe einzelner Steine am Boden, keine Mauer)
- `INVR_bergbau_kupferverhuettung` Kupferverhüttung (Bergbau) ← ACT_melt_cast_copper (verwandt – hier wird gediegenes Kupfer geschmolzen, KEIN Erz reduziert)
- `INVR_bergbau_steinbruch` Steinbruch (Bergbau) ← ACT_break_stone (verwandt – hier nur einzelne lose Steine, kein Abbau aus dem Gelände)
- `INVR_militaer_keule` Keule (Militär) ← ACT_hammer (verwandt – Schlagwerkzeug mit Stiel)
- `INVR_werkzeug_kupferaxt` Kupferaxt (Werkzeug) ← ACT_cold_work_copper (Vorstufe – Formgebung von Kupfer, aber noch keine Axt als Ergebnis)
- `INVR_werkzeug_stein_handaxt` Stein-Handaxt (Werkzeug) ← ACT_stone_strike (verwandt – Faustkeil ist bearbeitet; hier wird ein unbearbeiteter Stein in der Hand benutzt), ACT_hammer (Vorstufe/verwandt – der Katalog kennt keinen Hammer)

Alle übrigen Einträge bleiben **Katalogeinträge** (game_status „catalog“): keine Freischaltung, kein Startwissen, keine Effekte. Eine Erfindung existiert im Spiel erst, wenn Wesen sie mit realen Materialien, Werkzeugen und Arbeitsschritten herstellen.

## Häufigste Effekttexte (nicht angewendet)

- +40% Produktion: 266
- +40% Wissenschaft: 255
- Schaltet Wunder frei: 194
- Schaltet Einheit frei: 185
- +20% Produktion: 180
- Reduziert Baukosten um 10%: 176
- +70% Nahrung: 173
- Schaltet Spezialgebäude frei: 170
- Erhöht Bewegungsgeschwindigkeit: 168
- +50% Produktion: 162
- +50% Energie: 159
- +20% Handel: 158
- +70% Produktion: 158
- +70% Militärstärke: 144
- +20% Militärstärke: 139
