extends SceneTree
## Nur die Tests von Alpha 1.1 (Module, Kartenvorlagen, Speicherformat 6): godot --headless --path . -s res://tools/run_module_tests.gd -- [--only=NAME]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var tm := TestModules.new()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var res: Array = tm.run_all(only)
	var passed := 0
	for r in res:
		if r["ok"]:
			passed += 1
		print("%s %s%s" % ["PASS" if r["ok"] else "FAIL", r["name"], (" | " + r["detail"]) if r["detail"] != "" else ""])
	for n in tm.notes:
		print("- " + n)
	print("ERGEBNIS Module: %d von %d" % [passed, res.size()])
	quit(0 if passed == res.size() else 1)
