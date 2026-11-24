extends SceneTree
## Lädt jedes Skript unter res://scripts und meldet Kompilierfehler (schneller Syntaxcheck).
## godot --headless --path . -s res://tools/check_scripts.gd
func _initialize() -> void:
	var bad := 0
	for d in ["res://scripts"]:
		bad += _scan(d)
	print("FERTIG, Fehler: ", bad)
	quit(0)

func _scan(dir: String) -> int:
	var n := 0
	var da := DirAccess.open(dir)
	for f in da.get_files():
		if f.ends_with(".gd"):
			var s = load(dir + "/" + f)
			if s == null or not (s as Script).can_instantiate():
				print("FEHLER: ", dir + "/" + f)
				n += 1
	for sub in da.get_directories():
		n += _scan(dir + "/" + sub)
	return n
