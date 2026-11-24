class_name StorageSystem
extends RefCounted
## Lagerplätze (Prompt 6B). Einzige Stelle, die Stücke einem Lager zuordnet oder daraus entfernt.
## Regeln (vom Audit geprüft):
##   - ein Stück liegt in höchstens einem Lager und dann nicht zugleich in Hand, Verbund, Behälter, Bauwerk
##   - Masse und Volumen der Inhalte ≤ Kapazität; Inhalte liegen im Bereich des Lagers
##   - Einlagern nur einzelner, fester, nicht heißer Stücke; Temperatur und Zustand bleiben am Stück
##   - kein globales Inventar: Wesen kennen ein Lager nur durch Wahrnehmung (Creature.tech.objects)

const SLOT_M := 0.2


static func lc(ctx: LifeContext) -> Dictionary:
	return ctx.tc("storage")


static func create(ctx: LifeContext, pos: Vector3, size: Vector2, label: String, origin: String, created_by: int = 0) -> StoragePlace:
	var s := StoragePlace.new()
	s.position = pos
	s.size_m = size
	s.label = label
	s.origin = origin
	s.created_by = created_by
	s.created_t = ctx.now()
	var c := lc(ctx)
	s.capacity_kg = float(c.get("capacity_kg_per_m2", 40.0)) * size.x * size.y
	s.capacity_m3 = float(c.get("capacity_m3_per_m2", 0.03)) * size.x * size.y
	s.id = ctx.sim.add_entity(s, "storage_place")
	ctx.storages[s.id] = s
	s.add_history(ctx.now(), "angelegt (%s)" % origin)
	ctx.log_event("storage_created", [s.id], {"label": label, "origin": origin, "capacity_kg": s.capacity_kg})
	return s


static func used(ctx: LifeContext, s: StoragePlace) -> Dictionary:
	var kg := 0.0
	var m3 := 0.0
	for pid in s.contents:
		var p: MaterialPiece = ctx.material_pieces.get(int(pid), null)
		if p != null:
			kg += p.mass_kg
			m3 += p.volume_m3()
	return {"kg": kg, "m3": m3, "count": s.contents.size()}


## Prüft, ob ein (gehaltenes) Stück eingelagert werden kann. Ohne Seiteneffekte.
static func check_accept(ctx: LifeContext, s: StoragePlace, piece_id: int) -> ActionResult:
	if ctx.assemblies.has(piece_id):
		return ActionResult.fail("unsupported_item", "Zusammengesetzte Gegenstände werden in diesem Stand nicht eingelagert (nur einzelne Stücke).")
	var p: MaterialPiece = ctx.material_pieces.get(piece_id, null)
	if p == null:
		return ActionResult.fail("target_lost", "Stück #%d fehlt." % piece_id)
	if p.liquid_fraction() > 0.0:
		return ActionResult.fail("liquid", "Flüssiges Material lässt sich nicht einlagern.")
	var max_k := float(lc(ctx).get("max_temperature_k", 333.0))
	if p.temperature_k() > max_k:
		return ActionResult.fail("too_hot", "#%d ist zu heiß zum Einlagern (%s)." % [piece_id, ToolUseSystem.temperature_category(ctx, p.temperature_k())])
	var u := used(ctx, s)
	if float(u["kg"]) + p.mass_kg > s.capacity_kg + 1e-9:
		return ActionResult.fail("storage_full", "Lager #%d ist voll (Masse %.2f + %.2f kg > %.2f kg)." % [s.id, float(u["kg"]), p.mass_kg, s.capacity_kg])
	if float(u["m3"]) + p.volume_m3() > s.capacity_m3 + 1e-12:
		return ActionResult.fail("storage_full", "Lager #%d ist voll (Volumen)." % s.id)
	if free_slot(ctx, s) == null:
		return ActionResult.fail("storage_full", "Kein freier Platz mehr im Bereich von Lager #%d." % s.id)
	return ActionResult.success()


## Nächster freier Ablageplatz im Raster (Mitte einer 0,2-m-Zelle, die kein Inhalt belegt) oder null.
static func free_slot(ctx: LifeContext, s: StoragePlace):
	var nx := maxi(1, int(s.size_m.x / SLOT_M))
	var nz := maxi(1, int(s.size_m.y / SLOT_M))
	for iz in nz:
		for ix in nx:
			var q := s.position + Vector3((ix + 0.5) * SLOT_M - s.size_m.x * 0.5, 0.0, (iz + 0.5) * SLOT_M - s.size_m.y * 0.5)
			var taken := false
			for pid in s.contents:
				var p: MaterialPiece = ctx.material_pieces.get(int(pid), null)
				if p != null and ctx.distance_xz(p.position, q) < SLOT_M * 0.45:
					taken = true
					break
			if not taken:
				return q
	return null


static func inside(s: StoragePlace, pos: Vector3, margin: float = 0.0) -> bool:
	return absf(pos.x - s.position.x) <= s.size_m.x * 0.5 + margin and absf(pos.z - s.position.z) <= s.size_m.y * 0.5 + margin


## Einlagern (vom Handlungssystem nach dem Ablegen am Platz aufgerufen).
static func put_in(ctx: LifeContext, s: StoragePlace, p: MaterialPiece, slot: Vector3, actor_id: int) -> void:
	p.storage_id = s.id
	p.position = Vector3(slot.x, ctx.nav.ground_y(ctx.nav.world_to_col(slot)) + 0.01 if ctx.nav != null and ctx.nav.in_bounds(ctx.nav.world_to_col(slot)) else slot.y, slot.z)
	if not (p.id in s.contents):
		s.contents.append(p.id)
	p.add_history(ctx.now(), "eingelagert in Lager #%d von #%d" % [s.id, actor_id])
	s.add_history(ctx.now(), "#%d eingelagert (%.3f kg, %s) von #%d" % [p.id, p.mass_kg, p.material_id, actor_id])
	ctx.publish({"type": "stored_in_storage", "actor": actor_id, "target": 0, "position": slot,
		"consequences": {"storage": s.id, "piece": p.id, "kg": p.mass_kg}, "visibility_m": float(ctx.tc("teaching").get("demo_visibility_m", 6.0))})


## Entnehmen (beim Aufnehmen durch ein Wesen). Das Stück bleibt dasselbe Weltobjekt.
static func take_out(ctx: LifeContext, p: MaterialPiece, actor_id: int) -> void:
	var s: StoragePlace = ctx.storages.get(p.storage_id, null)
	if s != null:
		s.contents.erase(p.id)
		s.add_history(ctx.now(), "#%d entnommen von #%d" % [p.id, actor_id])
	p.add_history(ctx.now(), "aus Lager #%d entnommen von #%d" % [p.storage_id, actor_id])
	p.storage_id = 0


## Stück verschwindet (Bruch, Schmelzen in Teilmengen): aus allen Lagern austragen.
static func forget_piece(ctx: LifeContext, pid: int) -> void:
	for sid in ctx.storages:
		(ctx.storages[sid] as StoragePlace).contents.erase(pid)


static func audit(ctx: LifeContext) -> Array:
	var p: Array = []
	var seen := {}
	for sid in ctx.storages:
		var s: StoragePlace = ctx.storages[sid]
		if not ctx.sim.registry.has_id(sid):
			p.append("Lager #%d nicht registriert" % sid)
		for pid in s.contents:
			if seen.has(pid):
				p.append("Stück #%d liegt in zwei Lagern" % pid)
			seen[pid] = sid
			var mp: MaterialPiece = ctx.material_pieces.get(int(pid), null)
			if mp == null:
				p.append("Lager #%d: Inhalt #%d fehlt" % [sid, pid])
				continue
			if mp.storage_id != sid:
				p.append("Lager #%d: Stück #%d verweist auf Lager #%d" % [sid, pid, mp.storage_id])
			if mp.carrier_id != 0 or mp.assembly_id != 0 or mp.container_id != 0 or mp.structure_id != 0:
				p.append("Lager #%d: Stück #%d ist zugleich gehalten/verbaut/im Behälter" % [sid, pid])
			if not inside(s, mp.position, 0.05):
				p.append("Lager #%d: Stück #%d liegt außerhalb des Bereichs" % [sid, pid])
		var u := used(ctx, s)
		if float(u["kg"]) > s.capacity_kg + 1e-6:
			p.append("Lager #%d über Kapazität (%.2f kg > %.2f kg)" % [sid, float(u["kg"]), s.capacity_kg])
	for mid in ctx.material_pieces:
		var mp2: MaterialPiece = ctx.material_pieces[mid]
		if mp2.storage_id != 0 and (not ctx.storages.has(mp2.storage_id) or not (mid in (ctx.storages[mp2.storage_id] as StoragePlace).contents)):
			p.append("Stück #%d verweist auf Lager #%d, das es nicht führt" % [mid, mp2.storage_id])
	return p


## Wahrnehmung: Lager in Sichtweite werden dem Wesen bekannt (Ort, sichtbarer Inhalt, Platz).
static func perceive(cr: Creature, ctx: LifeContext, radius: float) -> void:
	for sid in ctx.storages:
		var s: StoragePlace = ctx.storages[sid]
		var d := ctx.distance_xz(cr.position, s.position)
		if d > radius:
			continue
		var u := used(ctx, s)
		var objs: Dictionary = cr.tech["objects"]
		var e: Dictionary = objs.get(sid, {})
		e.merge({"id": sid, "seen_t": ctx.now(), "d": snappedf(d, 0.1), "aussehen": "Lagerplatz", "form": "Lager", "lager": true,
			"inhalt_sichtbar": int(u["count"]), "platz_frei": check_free_hint(ctx, s)}, true)
		objs[sid] = e


static func check_free_hint(ctx: LifeContext, s: StoragePlace) -> bool:
	return free_slot(ctx, s) != null and float(used(ctx, s)["kg"]) < s.capacity_kg * 0.98
