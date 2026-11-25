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
