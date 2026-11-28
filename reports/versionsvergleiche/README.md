# Versionsvergleiche

Erzeugt mit `tools/compare_versions.py`. Ab v0.5.1 wird vor jeder Lieferung ein Bericht gegen die vorherige Version abgelegt.

Die Berichte v0.1.0 → v0.5.0 wurden nachträglich erstellt. Die dort als „entfernt“ gelisteten Einträge sind bekannte Umbauten, kein Funktionsverlust:
- v0.1.0 → v0.2.0: `.import`-Dateien der Bildschirmfotos (von Godot erzeugt, nicht nötig).
- v0.2.0 → v0.3.0: `_register_masses` in die Lebenssimulation verlagert; zwei Testtexte umbenannt, weil sich das Verhalten geändert hat (Startbildschirm, Erzeugung von Wesen).
- v0.3.0 → v0.4.0: Entscheidungsteil von `BasicBehavior` in `DecisionSystem` verlagert (eine Entscheidungsinstanz), Hilfsfunktionen umbenannt; drei Testtexte angepasst (Migration, Ladeverhalten, Startbildschirm).
- v0.4.0 → v0.5.0: drei Migrations-Testtexte auf die Kette 1→2→3 angepasst.
- v0.5.1 → v0.6.0: zwei Migrations-Testtexte angepasst (Kette 1→2→3→4, Fingerabdruck v0.6.0).

Ab v0.6.1:
- v0.6.0 → v0.6.1 (Prompt 6B): zwei Testtexte geändert und im CHANGELOG begründet – Werkstatt-Griffpunkt (strengere Prüfung: Modell am Griffrahmen der animierten Hand) und Migrationsstufen (Kette 1→2→3→4→5). Die Prüfung „ausgelieferte Definitionen v0.6.0“ behält ihren Text und prüft jetzt den echten v0.6.0-Spielstand; neu ist „… v0.6.1“. Keine Datei, Klasse, Funktion oder kein Konfigurationsschlüssel entfernt.
- v0.6.1 → Leitlinien-Excel (keine neue Version, 25.11.2026, `versionsvergleich_v0.6.1_zu_v0.6.1-leitlinie.md`): 33 neue Dateien (Excel, Quellen, Werkzeug, Tests, Doku), 6 geänderte Dokumente; nichts entfernt, keine Testprüfung geändert.
- v0.6.1 → Roadmap Alpha (keine neue Version, 25.11.2026, `versionsvergleich_v0.6.1_zu_v0.6.1-roadmap.md`): zusätzlich `docs/ROADMAP_ALPHA.md` und der Alpha-Plan in der Leitlinie; nichts entfernt, keine Testprüfung geändert.
- v0.6.1 (+ Roadmap) → **Alpha 1.1** (28.11.2026, `versionsvergleich_v0.6.1_zu_alpha-1.1.md`): 36 neue Dateien, 21 geänderte, keine Datei entfernt. Als „entfernt“ gelistet und begründet: die privaten Hilfsfunktionen `SaveManager._rng`, `_set_rng`, `_sorted` (ersetzt durch die öffentlichen `rng_to_dict`, `rng_from_dict`, `sorted_keys`, weil die Module sie brauchen) und der Testtext „Migrationsschnittstelle … Stufen 1→2→3→4→5“ (heißt jetzt „…→6“, die Prüfung erwartet die neue Stufe 5 → 6). Kein Funktionsverlust.
