class_name GodCommands
extends RefCounted
## Definition, Prüfung und Vorschau der Göttereingriffe (Spielerseite).
## Ein Befehl ist ein Dictionary:
##   {"kind": "gift_food" | "place_material" | "heal",
##    "target_id": int (Wesen, optional bei gift_food/place_material; Pflicht bei heal),
##    "position": Vector3 (optional; sonst vor dem Ziel-Wesen),
##    "amount_kg": float (gift_food), "food_id": "N001"|"N002",
##    "material_id": String, "size_m": float (place_material),
##    "heal_amount": float 0…1 (heal),
##    "linked_event": {seq, type, actor, t} (optional – privates Spielerwissen, nur Diagnose)}
## Der Spieler kann nicht sprechen und keine Befehle an Wesen geben; ein Eingriff verändert nur
## die Welt sichtbar. Wie ein Wesen ihn deutet, entscheidet allein dessen Geist.

## Formen für „Material platzieren“ (Prompt 6). Maße in m; Masse = Dichte · Formvolumen.
## Stab und Bündel haben feste, kleine Maße (greifbar); der Würfel nutzt size_m.
const PIECE_SHAPES := {
	"block": {"label": "Würfel", "materials": ["stone", "wood", "copper"]},
	"small_block": {"label": "kleiner Block (5 cm)", "materials": ["stone", "copper"], "dims": [0.05, 0.05, 0.05]},
	"rod": {"label": "Stab (40 cm)", "materials": ["wood", "copper"], "dims": [0.4, 0.025, 0.025]},
	"bundle": {"label": "Faserbündel", "materials": ["plant_fiber"], "dims": [0.12, 0.04, 0.06]},
}

const KINDS := {"gift_food": "Nahrung schenken", "place_material": "Material platzieren", "heal": "Verletzung heilen"}
const FOODS := ["N001", "N002"]


static func label(kind: String) -> String:
	return KINDS.get(kind, kind)


static func cfg(ctx: LifeContext) -> Dictionary:
	return ctx.m("god")


## Gültige Ablageposition: im Feld, begehbare Spalte (kein Baum, kein tiefes Wasser, Kopffreiheit),
## nicht im Gelände, mindestens min_creature_clearance_m von jedem Wesenkörper entfernt.
static func valid_drop_position(ctx: LifeContext, pos: Vector3) -> Dictionary:
	var col := ctx.nav.world_to_col(pos)
	if not ctx.nav.in_bounds(col):
		return {"ok": false, "reason": "außerhalb der Welt"}
	if not ctx.nav.is_walkable(col):
		return {"ok": false, "reason": "kein freier Boden (%s)" % ctx.nav.why_not_walkable(col)}
	var p := Vector3(pos.x, ctx.nav.ground_y(col), pos.z)
	if ctx.terrain.is_solid_at(p + Vector3(0, 0.05, 0)):
		return {"ok": false, "reason": "Position liegt in festem Gelände"}
	var clear := float(cfg(ctx).get("min_creature_clearance_m", 0.35))
	for oid in ctx.nearby_creatures(p, clear + 1.0):
		if ctx.distance_xz(ctx.creatures[oid].position, p) < clear:
			return {"ok": false, "reason": "zu nah an Wesen #%d (Körper)" % oid}
	return {"ok": true, "reason": "", "pos": p}


## Position vor einem Wesen (in Blickrichtung), sonst ringsum gesucht.
static func position_near(ctx: LifeContext, cr: Creature) -> Dictionary:
	var d := float(cfg(ctx).get("gift_distance_m", 0.55))
	for k in 12:
		var a := cr.heading + k * TAU / 12.0
		var p := cr.position + Vector3(sin(a), 0, cos(a)) * d
		var v := valid_drop_position(ctx, p)
		if v["ok"]:
			return v
	return {"ok": false, "reason": "kein freier Platz neben #%d" % cr.id}


## Prüft einen Befehl und ergänzt aufgelöste Werte. Rückgabe {"ok", "errors": Array, "cmd": Dictionary, "text": String}
static func prepare(ctx: LifeContext, cmd_in: Dictionary) -> Dictionary:
	var cmd := cmd_in.duplicate(true)
	var gc := cfg(ctx)
	var errs: Array = []
	var kind := str(cmd.get("kind", ""))
	if not KINDS.has(kind):
		return {"ok": false, "errors": ["Unbekannte Eingriffsart '%s'." % kind], "cmd": cmd, "text": ""}
	var target := ctx.creature(int(cmd.get("target_id", 0)))
	if int(cmd.get("target_id", 0)) != 0 and target == null:
		errs.append("Ziel-Wesen #%d existiert nicht." % int(cmd["target_id"]))
	match kind:
		"gift_food", "place_material":
			var v: Dictionary
			if cmd.has("position") and cmd["position"] is Vector3:
				v = valid_drop_position(ctx, cmd["position"])
			elif target != null:
				v = position_near(ctx, target)
			else:
				v = {"ok": false, "reason": "weder Position noch Ziel-Wesen gewählt"}
			if v["ok"]:
				cmd["position"] = v["pos"]
			else:
				errs.append("Ungültige Position: " + str(v["reason"]))
			if kind == "gift_food":
				var kg := float(cmd.get("amount_kg", gc.get("food_default_kg", 0.2)))
				var lim: Array = gc.get("food_kg_range", [0.05, 1.0])
				if kg < float(lim[0]) or kg > float(lim[1]):
					errs.append("Menge %.2f kg außerhalb %.2f–%.2f kg." % [kg, float(lim[0]), float(lim[1])])
				cmd["amount_kg"] = kg
				var fid := str(cmd.get("food_id", "N001"))
				if not fid in FOODS or ctx.db.get_def("food", fid).is_empty():
					errs.append("Unbekannte Nahrung '%s'." % fid)
				cmd["food_id"] = fid
			else:
				var mat := str(cmd.get("material_id", "stone"))
				if not mat in gc.get("materials", ["stone", "wood", "copper"]) or not ctx.sim.materials.has_material(mat):
					errs.append("Material '%s' nicht erlaubt." % mat)
				cmd["material_id"] = mat
				var s := float(cmd.get("size_m", gc.get("material_size_m", 0.12)))
				cmd["size_m"] = clampf(s, 0.05, 0.3)
				var sh := str(cmd.get("shape", "bundle" if mat == "plant_fiber" else "block"))
				if mat == "plant_fiber":
					sh = "bundle"
				if not PIECE_SHAPES.has(sh):
					errs.append("Unbekannte Form '%s'." % sh)
				elif not mat in PIECE_SHAPES[sh]["materials"]:
					errs.append("Form „%s“ ist für %s nicht vorgesehen." % [PIECE_SHAPES[sh]["label"], mat])
				cmd["shape"] = sh
		"heal":
			if target == null:
				errs.append("Heilen braucht ein Ziel-Wesen.")
			elif not target.alive:
				errs.append("#%d ist tot – Heilen nicht möglich." % target.id)
			else:
				var amt := clampf(float(cmd.get("heal_amount", gc.get("heal_default", 0.5))), 0.0, float(gc.get("heal_max", 1.0)))
				cmd["heal_amount"] = amt
				var plan := heal_plan(target, amt)
				if plan["total"] <= 0.0:
					errs.append("#%d hat kein verletztes vorhandenes Gewebe (fehlende Teile werden nicht nachgebildet)." % target.id)
				cmd["heal_preview"] = plan
	return {"ok": errs.is_empty(), "errors": errs, "cmd": cmd, "text": describe(ctx, cmd)}


## Verteilung einer Heilmenge auf verletzte, VORHANDENE Teile (größter Schaden zuerst).
static func heal_plan(cr: Creature, amount: float) -> Dictionary:
	var parts: Array = []
	for pid in cr.health.part_damage:
		if cr.plan.is_present(pid) and float(cr.health.part_damage[pid]) > 0.0:
			parts.append({"id": pid, "damage": float(cr.health.part_damage[pid])})
	parts.sort_custom(func(a, b): return a["damage"] > b["damage"])
	var left := amount
	var out: Array = []
	var total := 0.0
	for p in parts:
		if left <= 0.0:
			break
		var h := minf(left, float(p["damage"]))
		out.append({"id": p["id"], "from": p["damage"], "to": float(p["damage"]) - h})
		left -= h
		total += h
	return {"parts": out, "total": total}


## Lesbare Vorschau: Art, Ziel/Position, Menge/Umfang, zugeordnetes Ereignis.
static func describe(ctx: LifeContext, cmd: Dictionary) -> String:
	var L: Array = []
	var kind := str(cmd.get("kind", ""))
	L.append("Eingriff: %s" % label(kind))
	var tid := int(cmd.get("target_id", 0))
	var pos = cmd.get("position", null)
	var where := ""
	if tid != 0:
		where = "Wesen #%d" % tid
	if pos is Vector3:
		where += ("%s Position (%.1f, %.1f, %.1f)" % [", " if where != "" else "", pos.x, pos.y, pos.z])
	L.append("Ziel: %s" % (where if where != "" else "—"))
	match kind:
		"gift_food":
			var f := ctx.db.get_def("food", str(cmd.get("food_id", "")))
			L.append("Menge: %.2f kg %s" % [float(cmd.get("amount_kg", 0.0)), str(f.get("name", cmd.get("food_id", "")))])
		"place_material":
			var s := float(cmd.get("size_m", 0.12))
			var dens := 0.0
			if ctx.sim.materials.has_material(str(cmd.get("material_id", ""))):
				dens = ctx.sim.materials.get_material(str(cmd["material_id"])).density
			var sh := str(cmd.get("shape", "block"))
			var pd := piece_dims(cmd)
			L.append("Umfang: %s aus %s (%.2f kg)" % [PIECE_SHAPES.get(sh, {}).get("label", sh) if sh != "block" else "Würfel %.0f cm" % (s * 100), str(cmd.get("material_id", "")),
				dens * MaterialPiece.volume_of(piece_shape(cmd), pd, 0.0)])
		"heal":
			var hp: Dictionary = cmd.get("heal_preview", {})
			var parts: Array = []
			for p in hp.get("parts", []):
				parts.append("%s %.0f→%.0f %%" % [p["id"], float(p["from"]) * 100, float(p["to"]) * 100])
			L.append("Umfang: bis %.0f %% Schaden heilen%s" % [float(cmd.get("heal_amount", 0.0)) * 100, (" – " + ", ".join(parts)) if not parts.is_empty() else ""])
	var le: Dictionary = cmd.get("linked_event", {})
	if le.is_empty():
		L.append("Zugeordnetes Ereignis: keines")
	else:
		L.append("Zugeordnetes Ereignis: #%d %s von #%d bei t=%.0f s (nur Spielerwissen)" % [int(le.get("seq", 0)), str(le.get("type", "")), int(le.get("actor", 0)), float(le.get("t", 0.0))])
	return "\n".join(L)



## Form und Maße eines zu platzierenden Stücks (Göttermenü).
static func piece_shape(cmd: Dictionary) -> String:
	var sh := str(cmd.get("shape", "block"))
	return "block" if sh in ["block", "small_block"] else sh


static func piece_dims(cmd: Dictionary) -> Vector3:
	var sh := str(cmd.get("shape", "block"))
	var d: Array = PIECE_SHAPES.get(sh, {}).get("dims", [])
	if d.is_empty():
		var s := float(cmd.get("size_m", 0.12))
		return Vector3(s, s, s)
	return Vector3(d[0], d[1], d[2])
