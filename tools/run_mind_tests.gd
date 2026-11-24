extends SceneTree
## Nur die Prüfungen zu Geist/Soziales/Göttermenü/Migration (Entwicklungslauf).
## godot --headless --path . -s res://tools/run_mind_tests.gd

func _initialize() -> void:
	create_timer(1500.0, true, false, true).timeout.connect(func(): printerr("ABBRUCH: Zeitlimit"); quit(3))
	_run.call_deferred()


func _run() -> void:
	var t := TestMind.new()
	var res := t.run_all()
	var ok := 0
	for r in res:
		if r["ok"]:
			ok += 1
		print("%s %s%s" % ["PASS" if r["ok"] else "FAIL", r["name"], (" | " + str(r["detail"])) if str(r["detail"]) != "" else ""])
	for n in t.notes:
		print("- ", n)
	print("ERGEBNIS %d/%d" % [ok, res.size()])
	quit(0 if ok == res.size() else 1)
