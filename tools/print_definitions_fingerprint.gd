extends SceneTree
## Gibt den Fingerabdruck der Definitionsdateien aus (für SaveMigrations.V2_SHIPPED_DEFINITIONS
## bei einer neuen Version). godot --headless --path . -s res://tools/print_definitions_fingerprint.gd

func _initialize() -> void:
	print("Definitionen: ", SaveSchema.definitions_fingerprint()["hash"])
	quit(0)
