# Handgeschriebene Konfiguration

Alles in diesem Ordner wird von Hand gepflegt und **nie** vom Excel-Importer überschrieben.
Vom Importer erzeugte Dateien liegen getrennt in `data/generated/excel/`.

| Datei | Inhalt |
|---|---|
| `implementation_status.json` | Was im Spiel tatsächlich umgesetzt ist (Excel-Einträge aktivieren nichts von selbst) |
| `material_mapping.json` | Vorläufige Zuordnung von Excel-Materialnamen zu Physikmaterialien (`data/materials/`) |
| `world.json` | Weltgröße, Zellgröße, Chunkgröße, Generatorparameter |
| `voxel_palette.json` | Terrain-Voxeltypen mit stabilen Byte-IDs und Physikmaterial |
| `creature_defaults.json` | Standardproportionen des Pflanzenwesens (nicht in der Excel enthalten) |
| `life.json` | Spielwerte der Lebenssimulation: Wahrnehmung, Verhalten, Bewegung, Navigation, Stoffwechsel, Photosynthese, Nahrung, Gesundheit, Fähigkeiten je Körperteilfunktion, Handlungen (Erklärung: `docs/life_simulation.md`). Änderungen machen alte Spielstände unladbar (`docs/save_format.md`). |

| `mind.json` | Spielwerte des Geistes (Prompt 4): Persönlichkeit, Wahrnehmung von Ereignissen, Erinnerung, Überzeugungen, Lernen, Beziehungen, soziale Handlungen, Entscheidung, „Arme heben“, Göttermenü (Erklärung: `docs/mind_and_learning.md`, `docs/god_interactions.md`). |

Die Startanzahl der Wesen steht nur in `data/settings/simulation.json → initial_population`.
