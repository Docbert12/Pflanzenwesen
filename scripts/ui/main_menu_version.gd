class_name MainMenuVersion
extends RefCounted
## Anzeigename der Programmversion (Alpha 1.1): „alpha-1.1“ → „Alpha 1.1“. Eigene Klasse, damit
## Startbildschirm, Spielstand-Anzeige und Tests dieselbe Umrechnung nutzen.

static func text() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", "?"))
	if v.begins_with("alpha-"):
		return "Alpha " + v.substr(6)
	return "Entwicklungsstand " + v
