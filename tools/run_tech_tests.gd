extends SceneTree
## Nur die Technik-Tests (Prompt 6): godot --headless --path . -s res://tools/run_tech_tests.gd -- [--quick] [--only=NAME]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var tt := TestTechnology.new()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var res: Array = tt.run_all("--quick" in OS.get_cmdline_user_args(), only)
	var passed := 0
	for r in res:
		if r["ok"]:
			passed += 1
		print("%s %s%s" % ["PASS" if r["ok"] else "FAIL", r["name"], (" | " + r["detail"]) if r["detail"] != "" else ""])
	for n in tt.notes:
		print("- " + n)
	print("ERGEBNIS Technik: %d von %d" % [passed, res.size()])
	quit(0 if passed == res.size() else 1)
