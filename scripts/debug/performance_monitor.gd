class_name PerformanceMonitor
extends PanelContainer
## Leistungsanzeige: Bildrate, Simulationstakt (Mittel/Max der letzten 120 Takte), Wegsuchen,
## Objekte und Speicher. Misst nur – verändert nichts an der Simulation.

var label: Label


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.8)
	sb.set_content_margin_all(5)
	add_theme_stylebox_override("panel", sb)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 11)
	add_child(label)


static func tick_stats(life: LifeSimulation) -> Dictionary:
	var win: Array = life.perf["window"]
	var s := 0
	var mx := 0
	for v in win:
		s += v
		mx = maxi(mx, v)
	return {"avg_ms": (float(s) / maxf(win.size(), 1)) / 1000.0, "max_ms": mx / 1000.0, "total_avg_ms": float(life.perf["sum_us"]) / maxf(life.perf["ticks"], 1) / 1000.0}


func refresh(life: LifeSimulation) -> void:
	var t := tick_stats(life)
	var nav: Dictionary = life.ctx.nav.stats
	label.text = "FPS %d · Bild %.1f ms\nSim-Takt Ø %.2f ms (max %.2f) · gesamt Ø %.2f ms · Takte %d\nWegsuchen %d (Knoten %d) · Objekte %d · Speicher %.0f MB" % [
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		t["avg_ms"], t["max_ms"], t["total_avg_ms"], int(life.perf["ticks"]), int(nav["requests"]), int(nav["expansions"]),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]
