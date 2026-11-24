class_name ConstructionSystem
extends RefCounted
## Gegenstände der Lebenswelt (Prompt 6): Materialstücke anlegen, verbinden, lösen, brechen lassen.
## Einzige Stelle, die Verbünde (Assembly) erzeugt oder auflöst und Bauteile zuordnet.
##
## Erhaltungsregeln (vom Audit geprüft):
##   - jedes Stück ist höchstens in EINEM Verbund und dann nicht einzeln greifbar
##   - Verbundmasse = Σ Bauteilmassen (der Verbund hat keine eigene Masse)
##   - Faserverbrauch: die verwendete Fasermenge wird als Bauteil (binding) Teil des Gegenstands,
##     ein Rest bleibt als eigenes Stück liegen – Gesamtmasse bleibt exakt erhalten
##   - Bruch: Verbund aufgelöst, alle Bauteile bleiben Weltobjekte (Fasern als zerrissenes Stück)


## Legt ein Materialstück an und registriert es (Simulation + LifeContext).
static func new_piece(ctx: LifeContext, material_id: String, shape: String, dims: Vector3, temperature_k: float, pos: Vector3,
		origin: String, label: String = "", test_equipment: bool = false, cavity_m3: float = 0.0, volume_override: float = -1.0) -> Dictionary:
	var errs: Array = []
	var mp := MaterialPiece.make(ctx.sim.materials, material_id, shape, dims, temperature_k, errs, cavity_m3, volume_override)
	if mp == null:
		return {"ok": false, "message": "; ".join(errs)}
	mp.position = pos
	mp.origin = origin
	mp.label = label
	mp.station = "world"
	mp.test_equipment = test_equipment
	mp.created_t = ctx.now()
	if ctx.sim.add_object(mp) < 0:
		return {"ok": false, "message": "Registrierung fehlgeschlagen."}
	ctx.material_pieces[mp.id] = mp
	return {"ok": true, "piece": mp, "id": mp.id}


## Registriert ein aus Masse/Energie erzeugtes Stück (Teilmenge, Bruchstück, Guss).
static func add_piece(ctx: LifeContext, mp: MaterialPiece) -> int:
	mp.station = "world"
	if mp.created_t == 0.0:
		mp.created_t = ctx.now()
	var id: int = ctx.sim.add_object(mp)
	if id > 0:
		ctx.material_pieces[id] = mp
	return id


static func remove_piece(ctx: LifeContext, id: int) -> void:
	ctx.material_pieces.erase(id)
	ctx.sim.remove_object(id)


# ── Abfragen ─────────────────────────────────────

## Oberstes Objekt: Bauteil → sein Verbund, sonst das Stück selbst. 0 wenn unbekannt.
static func top_id(ctx: LifeContext, id: int) -> int:
	if ctx.assemblies.has(id):
		return id
	if ctx.material_pieces.has(id):
		var mp: MaterialPiece = ctx.material_pieces[id]
		return mp.assembly_id if mp.assembly_id != 0 else id
	return 0


static func is_object(ctx: LifeContext, id: int) -> bool:
	return ctx.assemblies.has(id) or ctx.material_pieces.has(id)


## Bauteile eines Objekts (Verbund: alle Teile; Stück: [Stück]).
static func parts_of(ctx: LifeContext, id: int) -> Array:
	if ctx.assemblies.has(id):
		var r: Array = []
		for pid in (ctx.assemblies[id] as Assembly).part_ids:
			if ctx.material_pieces.has(pid):
				r.append(ctx.material_pieces[pid])
		return r
	if ctx.material_pieces.has(id):
		return [ctx.material_pieces[id]]
	return []


static func mass_of(ctx: LifeContext, id: int) -> float:
	var s := 0.0
	for p in parts_of(ctx, id):
		s += (p as MaterialPiece).mass_kg
	return s


static func carrier_of(ctx: LifeContext, id: int) -> int:
	if ctx.assemblies.has(id):
		return (ctx.assemblies[id] as Assembly).carrier_id
	if ctx.material_pieces.has(id):
		return (ctx.material_pieces[id] as MaterialPiece).carrier_id
	return 0


static func set_carrier(ctx: LifeContext, id: int, carrier: int) -> void:
	if ctx.assemblies.has(id):
		(ctx.assemblies[id] as Assembly).carrier_id = carrier
	elif ctx.material_pieces.has(id):
		(ctx.material_pieces[id] as MaterialPiece).carrier_id = carrier


static func container_of(ctx: LifeContext, id: int) -> int:
	if ctx.assemblies.has(id):
		return (ctx.assemblies[id] as Assembly).container_id
	if ctx.material_pieces.has(id):
		return (ctx.material_pieces[id] as MaterialPiece).container_id
	return 0


static func label_of(ctx: LifeContext, id: int) -> String:
	if ctx.assemblies.has(id):
		var a: Assembly = ctx.assemblies[id]
		return "#%d %s" % [id, a.label if a.label != "" else "Verbund"]
	if ctx.material_pieces.has(id):
		var mp: MaterialPiece = ctx.material_pieces[id]
		var mat := mp.material()
		var nm := mat.display_name.split(" (")[0] if mat != null else mp.material_id
		return "#%d %s-%s%s" % [id, nm, mp.shape_label(), (" „%s“" % mp.label) if mp.label != "" and not mp.label.begins_with("Teil") else ""]
	return "#%d" % id


## Griffteil (für Temperatur und Greifbarkeit).
static func grip_piece(ctx: LifeContext, id: int) -> MaterialPiece:
	if ctx.assemblies.has(id):
		return ctx.material_pieces.get((ctx.assemblies[id] as Assembly).grip_part_id, null)
	return ctx.material_pieces.get(id, null)


## Höchste Temperatur aller Teile [K].
static func max_temperature_k(ctx: LifeContext, id: int) -> float:
	var t := 0.0
	for p in parts_of(ctx, id):
		t = maxf(t, (p as MaterialPiece).temperature_k())
	return t


# ── Verbinden ────────────────────────────────────

## Verbindet Stiel und Kopf mit Fasern (lashing). Prüft die Methode über ConnectionDefinition.
## actor_id: Erbauer (0 = Testausrüstung). Fasern über dem Bedarf bleiben als eigenes Stück liegen.
static func connect_lashing(ctx: LifeContext, actor_id: int, handle_id: int, head_id: int, fiber_id: int, skill_level: String, label: String = "", quality: float = 1.0) -> Dictionary:
	var handle: MaterialPiece = ctx.material_pieces.get(handle_id, null)
	var head: MaterialPiece = ctx.material_pieces.get(head_id, null)
	var fiber: MaterialPiece = ctx.material_pieces.get(fiber_id, null)
	var chk := ConnectionDefinition.check_lashing(ctx, handle, head, fiber, skill_level)
	if not chk["ok"]:
		return chk
	if quality < 1.0:
		# Prompt 6B: einarmige Variante – Umwicklung weniger straff (dokumentierter Spielparameter)
		chk["capacity_j"] = float(chk["capacity_j"]) * quality
		chk["fit"] = float(chk["fit"]) * quality
	var binding := fiber
	var rest_id := 0
	var use := float(chk["fiber_use_kg"])
	if fiber.mass_kg - use > MaterialProcessSystem.MIN_PIECE_KG:
		var tp := MaterialProcessSystem.take_portion(ctx, fiber, use, false)
		if not tp["ok"]:
			return {"ok": false, "code": "split_failed", "message": tp["message"]}
		binding = tp["piece"]
		rest_id = fiber.id
	var a := Assembly.new()
	a.label = label
	a.origin = "gebaut:#%d" % actor_id if actor_id != 0 else "test_equipment"
	a.created_by = actor_id
	a.created_t = ctx.now()
	a.position = handle.position if handle.carrier_id == 0 else ctx.position_of(handle.carrier_id)
	if ctx.sim.add_entity(a, "assembly") < 0:
		return {"ok": false, "code": "register_failed", "message": "Verbund konnte nicht registriert werden."}
	ctx.assemblies[a.id] = a
	var L := handle.dims_m.x
	_attach(ctx, a, handle, "handle", L * 0.5)
	_attach(ctx, a, head, "head", L - minf(head.dims_m.x, L * 0.25) * 0.5)
	_attach(ctx, a, binding, "binding", L - minf(head.dims_m.x, L * 0.25) * 0.5)
	a.grip_part_id = handle.id
	a.head_part_id = head.id
	var carrier := 0
	for p in [handle, head, fiber]:
		if p.carrier_id != 0:
			carrier = p.carrier_id
	for p in [handle, head, binding, fiber]:
		p.carrier_id = 0
	a.connections.append({"id": 1, "a": handle.id, "b": head.id, "method": "lashing", "binding_id": binding.id,
		"capacity_j": float(chk["capacity_j"]), "quality": float(chk["fit"]) * float(chk["skill"]), "fit": float(chk["fit"]),
		"skill": float(chk["skill"]), "fatigue": float(chk["fatigue"]), "wear": 0.0, "strikes": 0, "created_t": ctx.now()})
	a.add_history(ctx.now(), "verbunden (%s, %.3f kg Fasern)" % [ConnectionDefinition.label("lashing"), binding.mass_kg])
	if carrier != 0:
		var cr := ctx.creature(carrier)
		if cr != null:
			cr.held_object_id = a.id
			a.carrier_id = carrier
	sync_positions(ctx)
	ctx.log_event("parts_connected", [actor_id, a.id] if actor_id != 0 else [a.id],
		{"assembly": a.id, "parts": a.part_ids.duplicate(), "method": "lashing", "fiber_kg": binding.mass_kg, "rest_piece": rest_id,
		"capacity_j": chk["capacity_j"], "mass_kg": mass_of(ctx, a.id)})
	return {"ok": true, "code": "ok", "assembly": a, "id": a.id, "rest_piece": rest_id, "check": chk,
		"message": "Verbund #%d: Stiel #%d + Kopf #%d, %.3f kg Fasern (Belastbarkeit %.1f J je Schlag)." % [a.id, handle.id, head.id, binding.mass_kg, float(chk["capacity_j"])]}


## Testausrüstung: zwei Stücke fest montieren (z. B. Tiegel + Holzgriff). Nicht für Wesen.
static func connect_fixture(ctx: LifeContext, grip_id: int, body_id: int, label: String) -> Dictionary:
	var grip: MaterialPiece = ctx.material_pieces.get(grip_id, null)
	var body: MaterialPiece = ctx.material_pieces.get(body_id, null)
	if grip == null or body == null or grip.assembly_id != 0 or body.assembly_id != 0:
		return {"ok": false, "message": "Teile fehlen oder sind schon verbunden."}
	var fc: Dictionary = ctx.tc("connection").get("test_fixture", {})
	var a := Assembly.new()
	a.label = label
	a.origin = "test_equipment"
	a.test_equipment = true
	a.created_t = ctx.now()
	a.position = grip.position
	ctx.sim.add_entity(a, "assembly")
	ctx.assemblies[a.id] = a
	_attach(ctx, a, grip, "grip", grip.dims_m.x * 0.5)
	_attach(ctx, a, body, "cup" if body.shape == "cup" else "body", grip.dims_m.x + body.dims_m.x * 0.5)
	a.grip_part_id = grip.id
	a.connections.append({"id": 1, "a": grip.id, "b": body.id, "method": "test_fixture", "binding_id": 0,
		"capacity_j": float(fc.get("capacity_j", 200.0)), "quality": 1.0, "fit": 1.0, "skill": 1.0,
		"fatigue": float(fc.get("fatigue", 0.0005)), "wear": 0.0, "strikes": 0, "created_t": ctx.now()})
	ctx.sim.thermal.add_contact_g(grip, body, float(fc.get("thermal_conductance_w_k", 0.002)), "Griff↔%s #%d" % [body.shape_label(), a.id], true)
	sync_positions(ctx)
	return {"ok": true, "assembly": a, "id": a.id}


static func _attach(_ctx: LifeContext, a: Assembly, p: MaterialPiece, role: String, offset: float) -> void:
	p.assembly_id = a.id
	p.role = role
	a.part_ids.append(p.id)
	a.offsets[p.id] = offset


## Löst einen Verbund auf (gewollt oder durch Bruch). Alle Teile bleiben als Weltobjekte erhalten.
## broken: Verbindung gerissen (Fasern beschädigt). keep_grip_carrier: Halter behält das Griffteil.
static func dissolve(ctx: LifeContext, assembly_id: int, reason: String, broken: bool, actor_id: int = 0) -> Dictionary:
	var a: Assembly = ctx.assemblies.get(assembly_id, null)
	if a == null:
		return {"ok": false, "message": "Verbund #%d existiert nicht." % assembly_id}
	var carrier := a.carrier_id
	var base := a.position
	var freed: Array = []
	for pid in a.part_ids:
		var p: MaterialPiece = ctx.material_pieces.get(pid, null)
		if p == null:
			continue
		p.assembly_id = 0
		var role := p.role
		p.role = ""
		p.carrier_id = 0
		p.container_id = 0
		var off := float(a.offsets.get(pid, 0.0))
		p.position = base + Vector3(off * 0.6, 0.0, 0.08 * freed.size())
		p.position.y = base.y if carrier == 0 else base.y - 0.25
		if role == "binding" and broken:
			p.damage = 1.0
			p.label = "zerrissene Fasern"
		p.add_history(ctx.now(), "%s (Verbund #%d)" % ["abgebrochen" if broken else "gelöst", assembly_id])
		p.visual_version += 1
		freed.append(pid)
	for c in a.connections:
		if c["method"] == "test_fixture":
			ctx.sim.thermal.remove_contact(ThermalSystem.contact_key(int(c["a"]), int(c["b"])))
	if carrier != 0:
		var cr := ctx.creature(carrier)
		if cr != null and cr.held_object_id == assembly_id:
			cr.held_object_id = 0
			var gp: MaterialPiece = ctx.material_pieces.get(a.grip_part_id, null)
			if gp != null and cr.alive and not broken:
				pass   # gewolltes Lösen: alles wird abgelegt
			elif gp != null and cr.alive and broken:
				gp.carrier_id = carrier   # beim Bruch bleibt der Stiel in der Hand
				cr.held_object_id = gp.id
	ctx.assemblies.erase(assembly_id)
	ctx.sim.registry.unregister(assembly_id)
	var ev_type := "connection_broken" if broken else "parts_disconnected"
	ctx.publish({"type": ev_type, "actor": actor_id if actor_id != 0 else carrier, "target": 0, "position": base,
		"consequences": {"assembly": assembly_id, "parts": freed, "reason": reason, "label": a.label},
		"visibility_m": float(ctx.tc("teaching").get("demo_visibility_m", 6.0))}, "warning" if broken else "info")
	sync_positions(ctx)
	return {"ok": true, "parts": freed, "message": "Verbund #%d %s: %s" % [assembly_id, "gebrochen" if broken else "gelöst", reason]}


## Positionen: Verbundteile folgen dem Griffpunkt, Behälterinhalte dem Behälter, Gehaltenes der Hand.
static func sync_positions(ctx: LifeContext) -> void:
	for aid in ctx.assemblies:
		var a: Assembly = ctx.assemblies[aid]
		if a.carrier_id != 0:
			var cr := ctx.creature(a.carrier_id)
			if cr != null:
				a.position = ToolUseSystem.hand_position(cr)
		elif a.container_id != 0 and ctx.heaters.has(a.container_id):
			a.position = (ctx.heaters[a.container_id] as TestHeater).slot_position()
		for pid in a.part_ids:
			var p: MaterialPiece = ctx.material_pieces.get(pid, null)
			if p != null:
				p.position = a.position + Vector3(float(a.offsets.get(pid, 0.0)), 0.0, 0.0)
	for mid in ctx.material_pieces:
		var mp: MaterialPiece = ctx.material_pieces[mid]
		if mp.assembly_id != 0:
			continue
		if mp.carrier_id != 0:
			var cr2 := ctx.creature(mp.carrier_id)
			if cr2 != null:
				mp.position = ToolUseSystem.hand_position(cr2)
	# Inhalte folgen ihrem Behälter (zweiter Durchlauf: Behälter können selbst Bauteile sein)
	for mid in ctx.material_pieces:
		var mp2: MaterialPiece = ctx.material_pieces[mid]
		if mp2.container_id != 0 and ctx.material_pieces.has(mp2.container_id):
			var c: MaterialPiece = ctx.material_pieces[mp2.container_id]
			mp2.position = c.position + Vector3(0, c.inner_floor_m() + 0.001, 0)


## Inhalt eines Behälters/einer Form (Stücke mit container_id = id).
static func contents_of(ctx: LifeContext, container_piece_id: int) -> Array:
	var r: Array = []
	for mid in ctx.material_pieces:
		if (ctx.material_pieces[mid] as MaterialPiece).container_id == container_piece_id:
			r.append(ctx.material_pieces[mid])
	return r


## Konsistenzprüfung der Gegenstände. Leere Liste = in Ordnung.
static func audit(ctx: LifeContext) -> Array:
	var p: Array = []
	var member := {}
	for aid in ctx.assemblies:
		var a: Assembly = ctx.assemblies[aid]
		if not ctx.sim.registry.has_id(aid):
			p.append("Verbund #%d nicht registriert" % aid)
		if a.part_ids.size() < 2:
			p.append("Verbund #%d hat weniger als zwei Teile" % aid)
		for pid in a.part_ids:
			if member.has(pid):
				p.append("Stück #%d gehört zu zwei Verbünden (#%d, #%d)" % [pid, member[pid], aid])
			member[pid] = aid
			var mp: MaterialPiece = ctx.material_pieces.get(pid, null)
			if mp == null:
				p.append("Verbund #%d: Teil #%d fehlt" % [aid, pid])
			elif mp.assembly_id != aid:
				p.append("Verbund #%d: Teil #%d verweist auf #%d" % [aid, pid, mp.assembly_id])
			elif mp.carrier_id != 0:
				p.append("Teil #%d von Verbund #%d wird zusätzlich einzeln gehalten" % [pid, aid])
		for c in a.connections:
			if not ConnectionDefinition.is_supported(str(c["method"])):
				p.append("Verbund #%d: unbekannte Verbindungsmethode %s" % [aid, c["method"]])
			if not (int(c["a"]) in a.part_ids and int(c["b"]) in a.part_ids):
				p.append("Verbund #%d: Verbindung verweist auf fremde Teile" % aid)
			if int(c.get("binding_id", 0)) != 0 and not (int(c["binding_id"]) in a.part_ids):
				p.append("Verbund #%d: Bindemittel #%d ist kein Bauteil" % [aid, int(c["binding_id"])])
			if float(c["wear"]) >= 1.0:
				p.append("Verbund #%d: verschlissene Verbindung besteht noch" % aid)
		if a.carrier_id != 0:
			var cr := ctx.creature(a.carrier_id)
			if cr == null or cr.held_object_id != aid:
				p.append("Verbund #%d: Träger #%d hält ihn nicht" % [aid, a.carrier_id])
	for mid in ctx.material_pieces:
		var mp2: MaterialPiece = ctx.material_pieces[mid]
		if not ctx.sim.registry.has_id(mid):
			p.append("Materialstück #%d nicht registriert" % mid)
		if mp2.assembly_id != 0 and not member.has(mid):
			p.append("Stück #%d verweist auf fehlenden Verbund #%d" % [mid, mp2.assembly_id])
		if not (mp2.mass_kg > 0.0):
			p.append("Stück #%d: Masse ≤ 0" % mid)
		if mp2.carrier_id != 0:
			var cr2 := ctx.creature(mp2.carrier_id)
			if cr2 == null or cr2.held_object_id != mid:
				p.append("Stück #%d: Träger #%d hält es nicht" % [mid, mp2.carrier_id])
		if mp2.container_id != 0 and mp2.container_id == mid:
			p.append("Stück #%d liegt in sich selbst" % mid)
	for cid in ctx.creatures:
		var c2: Creature = ctx.creatures[cid]
		if c2.held_object_id != 0:
			if not is_object(ctx, c2.held_object_id):
				p.append("Wesen #%d hält fehlenden Gegenstand #%d" % [cid, c2.held_object_id])
			elif carrier_of(ctx, c2.held_object_id) != cid:
				p.append("Wesen #%d: Halteverweis auf #%d inkonsistent" % [cid, c2.held_object_id])
			if not c2.alive:
				p.append("Totes Wesen #%d hält noch #%d" % [cid, c2.held_object_id])
	for hid in ctx.heaters:
		var h: TestHeater = ctx.heaters[hid]
		if h.slot_id != 0 and container_of(ctx, h.slot_id) != hid:
			p.append("Testheizung #%d: Inhalt #%d verweist nicht zurück" % [hid, h.slot_id])
	return p
