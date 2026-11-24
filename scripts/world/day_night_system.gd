class_name DayNightSystem
extends RefCounted
## Tag-Nacht-Zyklus auf Basis der Simulationszeit (nicht der Bildrate, nicht der Kamera).
## Tageszeit t ∈ [0,1): 0 = Mitternacht, 0,25 = Sonnenaufgang, 0,5 = Mittag, 0,75 = Sonnenuntergang.
## Licht = max(0, sin(2π(t − 0,25))) – nachts 0. Spielwert, kein astronomisches Modell.

var day_length_s: float = 600.0
var start_time_of_day: float = 0.3


func setup(cfg: Dictionary) -> void:
	var d: Dictionary = cfg.get("day_night", {})
	day_length_s = float(d.get("day_length_s", 600.0))
	start_time_of_day = float(d.get("start_time_of_day", 0.3))


func time_of_day(sim_time: float) -> float:
	return fposmod(start_time_of_day + sim_time / day_length_s, 1.0)


func day_number(sim_time: float) -> int:
	return int(floor(start_time_of_day + sim_time / day_length_s)) + 1


func light(sim_time: float) -> float:
	return maxf(0.0, sin(TAU * (time_of_day(sim_time) - 0.25)))


func phase_name(sim_time: float) -> String:
	var t := time_of_day(sim_time)
	if t < 0.22 or t >= 0.80:
		return "Nacht"
	if t < 0.32:
		return "Morgen"
	if t < 0.68:
		return "Tag"
	return "Abend"


func clock_text(sim_time: float) -> String:
	var minutes := int(time_of_day(sim_time) * 1440.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## Richtung des Sonnenlichts (für die Darstellung).
func sun_rotation_deg(sim_time: float) -> Vector3:
	var a := (time_of_day(sim_time) - 0.25) * 360.0
	return Vector3(-clampf(sin(deg_to_rad(a)) * 75.0, -10.0, 80.0) - 5.0, a - 90.0, 0.0)
