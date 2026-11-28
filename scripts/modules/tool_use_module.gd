class_name ToolUseModule
extends SimModule
## Technik, Teil Werkzeuggebrauch: gehaltene Gegenstände, Tragen, Schläge (ToolUseSystem.tick).
## Läuft nach den Handlungen und vor den Wesen (Reihenfolge wie bis v0.6.1).

func _init() -> void:
	id = "technology.tools"
	title = "Technik: Werkzeuggebrauch"
	depends_on = ["actions"]


func tick(dt: float, _zone: int) -> void:
	ToolUseSystem.tick(ctx, dt)
