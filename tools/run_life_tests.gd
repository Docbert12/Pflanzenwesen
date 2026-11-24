extends SceneTree
## Nur die Lebenssimulations-Prüfungen (schneller Entwicklungslauf).
## godot --headless --path . -s res://tools/run_life_tests.gd -- [Dauerlauf-Sekunden, 0 = aus]

func _initialize() -> void:
	create_timer(1500.0, true, false, true).timeout.connect(func(): printerr("ABBRUCH: Zeitlimit"); quit(3))
	_run.call_deferred()


func _run() -> void:
	var secs := 0.0
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		secs = float(args[0])
	var t := TestLife.new()
	var res := t.run_all(secs)
	var ok := 0
	for r in res:
		if r["ok"]:
			ok += 1
		print("%s %s%s" % ["PASS" if r["ok"] else "FAIL", r["name"], (" | " + r["detail"]) if r["detail"] != "" else ""])
	for n in t.notes:
		print("- ", n)
	print("ERGEBNIS %d/%d" % [ok, res.size()])
	quit(0 if ok == res.size() else 1)
