class_name PopulationSpawner
extends RefCounted
## Erzeugt die Startpopulation – ausschließlich bei „Neues Spiel“, nie beim Laden.
## Anzahl: data/settings/simulation.json → initial_population (einzige Quelle).
## Körper: CreatureGenerator (reproduzierbar aus Weltstartwert + seed_offset + laufende Nummer).
## Startpositionen: Ring um den Lebensbaum (population.spawn_ring_m), nur begehbare Spalten
## (NavigationService: kein Baum, kein tiefes Wasser, Kopffreiheit), Mindestabstand zueinander,
## Abstand zu Nahrungsquellen ≥ 0,5 m, Füße exakt auf der Bodenoberfläche.
## Die 50 Figuren der Kreaturenvorschau sind davon völlig getrennt und werden nie gezählt.

static var spawn_calls: int = 0      # Prüfzähler: Laden darf ihn nicht erhöhen


## Rückgabe {"ok", "ids": Array, "attempts", "rejected": {Grund: Anzahl}, "message"}
static func spawn(ctx: LifeContext, count: int, base_seed: int, center: Vector3) -> Dictionary:
	spawn_calls += 1
	var pc: Dictionary = ctx.c("population")
	var mc: Dictionary = ctx.c("metabolism")
	var ring: Array = pc.get("spawn_ring_m", [2.6, 11.0])
	var spacing := float(pc.get("min_spacing_m", 0.8))
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed
	var placed: Array = []          # Vector3
	var ids: Array = []
	var rejected := {"nicht_begehbar": 0, "zu_nah_an_wesen": 0, "zu_nah_an_nahrung": 0, "ausserhalb": 0}
	var attempts := 0
	var max_attempts := count * 400
	while placed.size() < count and attempts < max_attempts:
		attempts += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(float(ring[0]) * float(ring[0]), float(ring[1]) * float(ring[1])))
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var col := ctx.nav.world_to_col(p)
		if not ctx.nav.in_bounds(col):
			rejected["ausserhalb"] += 1
			continue
		if not ctx.nav.is_walkable(col):
			rejected["nicht_begehbar"] += 1
			continue
		p.y = ctx.nav.ground_y(col)
		var ok := true
		for q in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < spacing:
				ok = false
				break
		if not ok:
			rejected["zu_nah_an_wesen"] += 1
			continue
		for fid in ctx.foods:
			if ctx.distance_xz(p, ctx.foods[fid].position) < 0.5:
				ok = false
				break
		if not ok:
			rejected["zu_nah_an_nahrung"] += 1
			continue
		placed.append(p)
	if placed.size() < count:
		return {"ok": false, "ids": [], "attempts": attempts, "rejected": rejected,
			"message": "Nur %d von %d gültigen Startpositionen gefunden (%d Versuche)." % [placed.size(), count, attempts]}
	for i in count:
		var cr := Creature.new()
		var seed_i := base_seed + i * 7919
		cr.plan_seed = seed_i
		cr.base_genes = CreatureGenerator.make_genes(seed_i, ctx.db)
		cr.plan = CreatureGenerator.build_plan(cr.base_genes, seed_i, ctx.db)
		cr.position = placed[i]
		cr.heading = rng.randf() * TAU
		cr.rng.seed = seed_i ^ 0x5bd1e995
		ctx.sim.add_entity(cr, "creature")
		cr.display_name = "Wesen %02d" % (i + 1)
		cr.refresh_body(ctx)
		cr.personality = Personality.generate(seed_i, ctx.mind_cfg)
		cr.mind_since_t = ctx.now()
		cr.learning["base_window_t"] = ctx.now() + float(i % 12)
		cr.metabolism.setup(cr.mass_kg, rng.randf_range(float(mc.get("start_fraction_min", 0.4)), float(mc.get("start_fraction_max", 0.75))), ctx.cfg)
		# Wahrnehmung und Entscheidungen zeitlich versetzt (nicht alle im selben Takt)
		cr.next_perception_t = ctx.now() + float(i % 20) * 0.05
		cr.next_decision_t = ctx.now() + 0.2 + float(i % 10) * 0.05
		cr.behavior_state = "neu"
		cr.behavior_reason = "Gerade erzeugt."
		ctx.creatures[cr.id] = cr
		ids.append(cr.id)
	ctx.log_event("population_spawned", ids.slice(0, 3), {"count": count, "attempts": attempts, "rejected": rejected, "seed": base_seed})
	return {"ok": true, "ids": ids, "attempts": attempts, "rejected": rejected, "message": "%d Wesen erzeugt." % count}
