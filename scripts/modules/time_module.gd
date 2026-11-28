class_name TimeModule
extends SimModule
## Zeit und Himmel: heute nur Tag/Nacht (DayNightSystem, aus der Simulationszeit abgeleitet, ohne
## eigenen Zustand). Wird in Alpha 1.3 zum Kalender- und Himmelsmodul (Jahreszeiten, Mond, Sterne).

var light: float = 1.0     # Lichtstärke dieses Simulationsbilds (0…1)

func _init() -> void:
	id = "time.sky"
	title = "Zeit und Himmel (Tag/Nacht)"
	depends_on = ["core"]


func tick(_dt: float, _zone: int) -> void:
	light = ctx.day_night.light(ctx.now())


func metrics() -> Dictionary:
	return {"uhrzeit": ctx.day_night.clock_text(ctx.now()), "phase": ctx.day_night.phase_name(ctx.now()), "licht": light}
