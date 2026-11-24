class_name SimulationClock
extends RefCounted
## Simulationszeit in Sekunden. Läuft nur über advance() im festen Physiktakt.
## Zeitbeschleunigung ist bewusst NICHT implementiert (time_scale bleibt 1.0).

var sim_time_s: float = 0.0
var tick_count: int = 0
var paused: bool = false
const TIME_SCALE: float = 1.0


## Rückt die Uhr um einen festen Schritt vor. Gibt den tatsächlich simulierten
## Schritt zurück (0 bei Pause), damit Systeme nie im Pausezustand rechnen.
func advance(fixed_dt: float) -> float:
	if paused or fixed_dt <= 0.0:
		return 0.0
	var dt := fixed_dt * TIME_SCALE
	sim_time_s += dt
	tick_count += 1
	return dt


func reset() -> void:
	sim_time_s = 0.0
	tick_count = 0
	paused = false


func to_dict() -> Dictionary:
	return {"sim_time_s": sim_time_s, "tick_count": tick_count, "paused": paused, "time_scale": TIME_SCALE}
