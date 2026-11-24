# Versionsvergleiche

Erzeugt mit `tools/compare_versions.py`. Ab v0.5.1 wird vor jeder Lieferung ein Bericht gegen die vorherige Version abgelegt.

Die Berichte v0.1.0 → v0.5.0 wurden nachträglich erstellt. Die dort als „entfernt“ gelisteten Einträge sind bekannte Umbauten, kein Funktionsverlust:
- v0.1.0 → v0.2.0: `.import`-Dateien der Bildschirmfotos (von Godot erzeugt, nicht nötig).
- v0.2.0 → v0.3.0: `_register_masses` in die Lebenssimulation verlagert; zwei Testtexte umbenannt, weil sich das Verhalten geändert hat (Startbildschirm, Erzeugung von Wesen).
- v0.3.0 → v0.4.0: Entscheidungsteil von `BasicBehavior` in `DecisionSystem` verlagert (eine Entscheidungsinstanz), Hilfsfunktionen umbenannt; drei Testtexte angepasst (Migration, Ladeverhalten, Startbildschirm).
- v0.4.0 → v0.5.0: drei Migrations-Testtexte auf die Kette 1→2→3 angepasst.
