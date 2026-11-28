class_name StructureSystem
extends RefCounted
## Baustellen und einfache Einzelbauwerke (Prompt 6B). Einzige Stelle, die Teile verbaut.
## Unterstützter, parametrisierter Bauplan (Spielparameter in data/config/technology.json, "structures"):
##   steinreihe – n Plätze in einer Reihe; je Platz ein einzelnes, festes Steinstück passender Masse.
## Funktion entsteht nur aus den tatsächlich verbauten Teilen (evaluate), nie aus dem Namen.
## Gemeinsames Siedlungsbauen, Projekte und Aufgabenverteilung sind NICHT umgesetzt (Prompt 9).


static func bp(ctx: LifeContext, blueprint: String) -> Dictionary:
	return ctx.tc("structures").get(blueprint, {})


static func create_site(ctx: LifeContext, blueprint: String, pos: Vector3, heading: float, initiator: int, origin: String, label: String = "") -> Structure:
	var b := bp(ctx, blueprint)
	if b.is_empty():
		return null
	var s := Structure.new()
	s.blueprint = blueprint
	s.label = label if label != "" else str(b.get("label", blueprint))
	s.position = pos
	s.heading = heading
	s.initiator = initiator
	s.origin = origin
	s.created_t = ctx.now()
	var n := int(b.get("slots", 3))
	var sp := float(b.get("spacing_m", 0.22))
	for i in n:
		s.slots.append({"local": [i * sp, 0.0, 0.0], "part_id": 0})
	s.id = ctx.sim.add_entity(s, "structure")
	ctx.structures[s.id] = s
	s.add_history(ctx.now(), "Baustelle angelegt (%s)" % origin)
	ctx.log_event("structure_site_created", [s.id, initiator] if initiator != 0 else [s.id], {"blueprint": blueprint, "origin": origin, "slots": n})
	ctx.publish({"type": "site_marked", "actor": initiator, "target": 0, "position": pos,
		"consequences": {"structure": s.id, "plätze": n}, "visibility_m": float(ctx.tc("teaching").get("demo_visibility_m", 6.0))})
	return s


static func slot_world(s: Structure, i: int) -> Vector3:
	var l: Array = s.slots[i]["local"]
	var c := cos(s.heading)
	var sn := sin(s.heading)
	return s.position + Vector3(float(l[0]) * c + float(l[2]) * sn, float(l[1]), -float(l[0]) * sn + float(l[2]) * c)


static func next_free_slot(s: Structure) -> int:
	for i in s.slots.size():
		if int(s.slots[i].get("part_id", 0)) == 0:
			return i
	return -1


## Eignung eines Stücks für einen Platz (Material, Form, Masse, Größe, Zustand). Ohne Seiteneffekte.
static func check_part(ctx: LifeContext, s: Structure, piece_id: int) -> ActionResult:
	var b := bp(ctx, s.blueprint)
	if ctx.assemblies.has(piece_id):
		return ActionResult.fail("unsuitable_part", "Ein zusammengesetzter Gegenstand ist kein Bauteil für %s." % s.label)
	var p: MaterialPiece = ctx.material_pieces.get(piece_id, null)
	if p == null:
		return ActionResult.fail("target_lost", "Stück #%d fehlt." % piece_id)
	if not (p.material_id in b.get("materials", ["stone"])):
		return ActionResult.fail("unsuitable_material", "%s ist für %s nicht geeignet (Bauplan verlangt %s)." % [p.material_id, s.label, ", ".join(b.get("materials", ["stone"]))])
	if not (p.shape in b.get("shapes", ["lump", "block"])):
		return ActionResult.fail("unsuitable_shape", "Form %s passt nicht (verlangt: %s)." % [p.shape_label(), ", ".join(b.get("shapes", ["lump", "block"]))])
	if p.mass_kg < float(b.get("min_kg", 0.1)):
		return ActionResult.fail("too_small", "#%d ist zu klein für einen Platz (%.3f kg < %.3f kg)." % [piece_id, p.mass_kg, float(b.get("min_kg", 0.1))])
	if p.mass_kg > float(b.get("max_kg", 2.5)):
		return ActionResult.fail("too_big", "#%d ist zu groß für einen Platz (%.2f kg > %.2f kg) – erst zerkleinern." % [piece_id, p.mass_kg, float(b.get("max_kg", 2.5))])
	if p.liquid_fraction() > 0.0 or p.temperature_k() > float(ctx.tc("storage").get("max_temperature_k", 333.0)):
		return ActionResult.fail("too_hot", "#%d ist zu heiß oder flüssig." % piece_id)
	return ActionResult.success()


## Tragfähiger Untergrund an einem Platz (vereinfachte Abstützung: begehbare Geländespalte darunter).
static func check_ground(ctx: LifeContext, pos: Vector3) -> ActionResult:
	if ctx.nav == null:
		return ActionResult.success()
	var c := ctx.nav.world_to_col(pos)
	if not ctx.nav.in_bounds(c):
		return ActionResult.fail("no_support", "Platz außerhalb der Welt.")
	if not ctx.nav.is_walkable(c):
		return ActionResult.fail("no_support", "Kein tragfähiger, freier Untergrund (%s)." % ctx.nav.why_not_walkable(c))
	return ActionResult.success()


## Teil verbauen (vom Handlungssystem aufgerufen, nachdem das gehaltene Stück abgelegt wurde).
static func place(ctx: LifeContext, s: Structure, i: int, p: MaterialPiece, actor_id: int) -> void:
	var w := slot_world(s, i)
	var gy := w.y
	if ctx.nav != null and ctx.nav.in_bounds(ctx.nav.world_to_col(w)):
		gy = ctx.nav.ground_y(ctx.nav.world_to_col(w))
	p.position = Vector3(w.x, gy + 0.01, w.z)
	p.structure_id = s.id
	s.slots[i]["part_id"] = p.id
	s.status = "fertig" if next_free_slot(s) == -1 else "im Bau"
	p.add_history(ctx.now(), "in Bauwerk #%d (Platz %d) verbaut von #%d" % [s.id, i + 1, actor_id])
	s.add_history(ctx.now(), "Platz %d: #%d (%.3f kg %s) von #%d" % [i + 1, p.id, p.mass_kg, p.material_id, actor_id])
	ctx.publish({"type": "part_built_in", "actor": actor_id, "target": 0, "position": p.position,
		"consequences": {"structure": s.id, "slot": i + 1, "piece": p.id, "status": s.status},
		"visibility_m": float(ctx.tc("teaching").get("demo_visibility_m", 6.0))})


## Messbare Funktion aus den tatsächlich verbauten Teilen (nicht aus dem Namen).
static func evaluate(ctx: LifeContext, s: Structure) -> Dictionary:
	var mass := 0.0
	var height := 0.0
	var parts: Array = []
	var contiguous := true
	var gap := false
	for sl in s.slots:
		var pid := int(sl.get("part_id", 0))
		if pid == 0:
			gap = true
			continue
		if gap:
			contiguous = false
		var p: MaterialPiece = ctx.material_pieces.get(pid, null)
		if p != null:
			mass += p.mass_kg
			height = maxf(height, p.dims_m.y)
			parts.append(pid)
	var b := bp(ctx, s.blueprint)
	var length := float(b.get("spacing_m", 0.22)) * maxf(0.0, s.slots.size() - 1) if not parts.is_empty() else 0.0
	var cell := ctx.terrain.cell_size() if ctx.terrain != null else 0.5
	return {"teile": parts.size(), "plaetze": s.slots.size(), "masse_kg": mass, "hoehe_m": height, "laenge_m": length,
		"zusammenhaengend": contiguous and parts.size() == s.slots.size(), "fertig": next_free_slot(s) == -1,
		"hindernis_fuer_wegsuche": height >= cell,
		"funktion": "markiert eine Linie am Boden (Höhe %.2f m); kein Hindernis für die Wegsuche, da niedriger als eine Geländezelle (%.2f m)" % [height, cell]}


static func audit(ctx: LifeContext) -> Array:
	var p: Array = []
	var seen := {}
	for sid in ctx.structures:
		var s: Structure = ctx.structures[sid]
		if not ctx.sim.registry.has_id(sid):
			p.append("Bauwerk #%d nicht registriert" % sid)
		for i in s.slots.size():
			var pid := int(s.slots[i].get("part_id", 0))
			if pid == 0:
				continue
			if seen.has(pid):
				p.append("Stück #%d ist in zwei Bauplätzen verbaut" % pid)
			seen[pid] = sid
			var mp: MaterialPiece = ctx.material_pieces.get(pid, null)
			if mp == null:
				p.append("Bauwerk #%d: Teil #%d fehlt" % [sid, pid])
				continue
			if mp.structure_id != sid:
				p.append("Bauwerk #%d: Teil #%d verweist auf #%d" % [sid, pid, mp.structure_id])
			if mp.carrier_id != 0 or mp.storage_id != 0 or mp.assembly_id != 0:
				p.append("Bauwerk #%d: Teil #%d ist zugleich gehalten/eingelagert/Bauteil" % [sid, pid])
			if ctx.distance_xz(mp.position, slot_world(s, i)) > 0.05:
				p.append("Bauwerk #%d: Teil #%d liegt nicht an seinem Platz" % [sid, pid])
	for mid in ctx.material_pieces:
		var mp2: MaterialPiece = ctx.material_pieces[mid]
		if mp2.structure_id != 0 and not seen.has(mid):
			p.append("Stück #%d verweist auf Bauwerk #%d, das es nicht führt" % [mid, mp2.structure_id])
	return p


## Wahrnehmung: Baustellen in Sichtweite (Ort, sichtbar belegte Plätze).
static func perceive(cr: Creature, ctx: LifeContext, radius: float) -> void:
	for sid in ctx.structures:
		var s: Structure = ctx.structures[sid]
		var d := ctx.distance_xz(cr.position, s.position)
		if d > radius:
			continue
		var objs: Dictionary = cr.tech["objects"]
		var e: Dictionary = objs.get(sid, {})
		e.merge({"id": sid, "seen_t": ctx.now(), "d": snappedf(d, 0.1), "aussehen": "Baustelle (%s)" % s.label, "form": "Baustelle",
			"bauwerk": true, "plaetze": s.slots.size(), "belegt": s.filled(), "eigene": s.initiator == cr.id}, true)
		objs[sid] = e


static func forget_piece(ctx: LifeContext, pid: int) -> void:
	for sid in ctx.structures:
		var s: Structure = ctx.structures[sid]
		for sl in s.slots:
			if int(sl.get("part_id", 0)) == pid:
				sl["part_id"] = 0
				s.status = "im Bau"
