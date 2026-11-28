class_name LifeModule
extends SimModule
## Leben: Licht → Photosynthese, Stoffwechsel, Mangelschaden, Tod – je lebendem Wesen.

var _light: float = 1.0
var _mcfg: Dictionary = {}

func _init() -> void:
	id = "life"
	title = "Leben (Stoffwechsel, Photosynthese, Tod)"
	depends_on = ["technology.tools"]
	per_actor = true


func tick(_dt: float, _zone: int) -> void:
	_light = ctx.day_night.light(ctx.now())
	_mcfg = ctx.c("metabolism")


func actor_tick(cr: Creature, dt: float) -> void:
	var shade := Photosynthesis.shade_at(ctx, cr.position)
	var lw := Photosynthesis.power_w(float(cr.caps.get("leaf_area_m2", 0.0)), _light, shade, ctx.cfg)
	var aw := 0.0
	if ctx.executor.running.has(cr.id):
		var a: GameAction = ctx.executor.running[cr.id]
		aw = (ctx.executor.impls[a.type] as ActionImpl).power_w(a, ctx)
	var res := cr.metabolism.step(dt, cr.mass_kg, int(cr.caps.get("leaf_count", 0)), cr.tick_moved_m, aw, lw, ctx.cfg)
	cr.stats["light_j"] = float(cr.stats.get("light_j", 0.0)) + lw * dt
	if res["energy_empty"]:
		cr.health.starvation = minf(1.0, cr.health.starvation + float(_mcfg.get("starvation_damage_per_s", 0.004)) * dt)
	if res["nutrients_empty"]:
		cr.health.starvation = minf(1.0, cr.health.starvation + float(_mcfg.get("nutrient_starvation_damage_per_s", 0.002)) * dt)
	if cr.health.is_dead():
		var cause := "Verhungert (Energie leer)" if cr.metabolism.energy_j <= 0.0 else "Mangel an Nährstoffen"
		if cr.health.starvation < 1.0:
			cause = "Lebenswichtiges Körperteil zerstört"
		cr.die(cause, ctx)
