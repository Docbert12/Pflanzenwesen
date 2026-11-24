class_name MaterialProcessSystem
extends RefCounted
## Laboroperationen Teilen und Zusammenführen.
## „Zusammenführen“ ist eine ausdrücklich bezeichnete LABOROPERATION und keine
## spielbare Schweiß- oder Herstellungsfunktion.
## Beide Operationen erhalten Masse und thermische Energie exakt.

const MIN_PART_KG := 1.0e-4
const MIN_FRACTION := 0.05


func split(sim, id: int, fraction: float) -> Dictionary:
	var obj: PhysicalObject = sim.registry.get_entity(id) as PhysicalObject
	if obj == null:
		return _reject(sim, [id], "Objekt %d existiert nicht." % id)
	if fraction < MIN_FRACTION or fraction > 1.0 - MIN_FRACTION:
		return _reject(sim, [id], "Anteil muss zwischen %.2f und %.2f liegen." % [MIN_FRACTION, 1.0 - MIN_FRACTION])
	if obj.liquid_fraction() > 0.0:
		return _reject(sim, [id], "Flüssige oder schmelzende Proben können nicht geteilt werden (Flüssigkeitsverhalten nicht modelliert).")
	var m1 := obj.mass_kg * fraction
	var m2 := obj.mass_kg - m1
	if m1 < MIN_PART_KG or m2 < MIN_PART_KG:
		return _reject(sim, [id], "Teilmenge wäre kleiner als %.4f kg." % MIN_PART_KG)
	var e1 := obj.thermal_energy_j * fraction
	var e2 := obj.thermal_energy_j - e1
	var ids: Array = []
	var parts := [[m1, e1], [m2, e2]]
	for i in 2:
		var p := PhysicalObject.create_from_mass_energy(obj.material(), parts[i][0], parts[i][1])
		p.station = obj.station
		p.damage = obj.damage
		p.deformed = obj.deformed
		p.label = "Teil %s von #%d" % ["A" if i == 0 else "B", obj.id]
		p.origin = "split"
		p.parent_ids = [obj.id]
		ids.append(sim.add_object(p))
	sim.remove_object(id)
	sim.event_log.add("sample_split", [id] + ids, {"fraction": fraction, "mass_kg": obj.mass_kg, "lab_operation": true})
	return {"ok": true, "ids": ids}


func merge(sim, id_a: int, id_b: int) -> Dictionary:
	var a: PhysicalObject = sim.registry.get_entity(id_a) as PhysicalObject
	var b: PhysicalObject = sim.registry.get_entity(id_b) as PhysicalObject
	if a == null or b == null:
		return _reject(sim, [id_a, id_b], "Beide Proben müssen existieren.")
	if id_a == id_b:
		return _reject(sim, [id_a], "Eine Probe kann nicht mit sich selbst zusammengeführt werden.")
	if a.material_id != b.material_id:
		return _reject(sim, [id_a, id_b], "Nur Proben desselben Materials können zusammengeführt werden (%s ≠ %s)." % [a.material_id, b.material_id])
	if a.liquid_fraction() > 0.0 or b.liquid_fraction() > 0.0:
		return _reject(sim, [id_a, id_b], "Nur vollständig feste Proben können zusammengeführt werden.")
	var m := a.mass_kg + b.mass_kg
	var merged := PhysicalObject.create_from_mass_energy(a.material(), m, a.thermal_energy_j + b.thermal_energy_j)
	merged.damage = (a.damage * a.mass_kg + b.damage * b.mass_kg) / m
	merged.deformed = a.deformed or b.deformed
	merged.station = a.station
	merged.label = "Zusammengeführt aus #%d + #%d" % [id_a, id_b]
	merged.origin = "merge"
	merged.parent_ids = [id_a, id_b]
	var new_id: int = sim.add_object(merged)
	sim.remove_object(id_a)
	sim.remove_object(id_b)
	sim.event_log.add("samples_merged", [id_a, id_b, new_id], {"mass_kg": m, "temperature_k": merged.temperature_k(), "lab_operation": true})
	return {"ok": true, "id": new_id}


func _reject(sim, ids: Array, message: String) -> Dictionary:
	sim.event_log.add("process_rejected", ids, {"reason": message}, "warning")
	return {"ok": false, "message": message}


# ══ Prompt 6: Verarbeitung von Materialstücken der Lebenswelt ═══════════════════════════════
# Alle drei Vorgänge erhalten Masse und thermische Energie exakt. Die mechanischen Größen sind
# ein dokumentiertes SPIELMODELL (docs/tools_and_construction.md), keine Werkstoffsimulation.

const MIN_PIECE_KG := 1.0e-4
const MAX_STRAIN_PER_STRIKE := 0.2


## Prompt 6B: Schmelzen ist KEINE universelle Recyclingaktion. Unterstützt nur, wenn das Material ein
## Phasenmodell mit Schmelzpunkt hat und der Behälter darüber gültig bleibt. Brennbare Stoffe werden
## abgewiesen (Verbrennung ist nicht simuliert); Gestein/Keramik „schmelzen“ im Modell nicht.
static func melt_support(m: MaterialDefinition, container: MaterialDefinition = null) -> Dictionary:
	if m == null:
		return {"ok": false, "code": "unknown_material", "message": "Material unbekannt."}
	if not m.has_melting():
		if m.combustible:
			return {"ok": false, "code": "combustible", "message": "%s ist brennbar; Verbrennung ist noch nicht simuliert – Schmelzen abgewiesen." % m.display_name}
		return {"ok": false, "code": "not_meltable", "message": "%s schmilzt im unterstützten Modell nicht (nur fester Zustand modelliert) – abgewiesen." % m.display_name}
	if container != null and container.valid_max_k < m.melting_point + 50.0:
		return {"ok": false, "code": "container_incompatible", "message": "Behälter aus %s hält die Schmelztemperatur von %s (%.0f K) nicht." % [container.display_name, m.display_name, m.melting_point]}
	return {"ok": true, "code": "ok", "message": "schmelzbar (Schmelzpunkt %.0f K)" % m.melting_point}


## Teilmenge mass_kg von einem Stück abnehmen (Fasern fürs Umwickeln, Gussrest).
## Neues Stück: gleiche spezifische Enthalpie (gleiche Temperatur). Rückgabe {ok, piece, message}.
static func take_portion(ctx: LifeContext, src: MaterialPiece, mass_kg: float, allow_liquid: bool) -> Dictionary:
	if src == null:
		return {"ok": false, "message": "Stück fehlt."}
	if not allow_liquid and src.liquid_fraction() > 0.0:
		return {"ok": false, "message": "Flüssige Stücke können so nicht geteilt werden."}
	if mass_kg < MIN_PIECE_KG or src.mass_kg - mass_kg < MIN_PIECE_KG:
		return {"ok": false, "message": "Teilmenge wäre kleiner als %.4f kg." % MIN_PIECE_KG}
	var e := src.thermal_energy_j * mass_kg / src.mass_kg
	var p := MaterialPiece.new()
	p.bind_material(src.material())
	p.material_id = src.material_id
	p.mass_kg = mass_kg
	p.thermal_energy_j = e
	p.shape = src.shape
	p.dims_m = src.dims_m
	p.position = src.position
	p.origin = "teilmenge:#%d" % src.id
	p.label = src.label
	p.parent_ids = [src.id]
	p.test_equipment = src.test_equipment
	src.mass_kg -= mass_kg
	src.thermal_energy_j -= e
	p.rescale_to_mass()
	src.rescale_to_mass()
	if ConstructionSystem.add_piece(ctx, p) <= 0:
		src.mass_kg += mass_kg
		src.thermal_energy_j += e
		src.rescale_to_mass()
		return {"ok": false, "message": "Registrierung fehlgeschlagen."}
	ctx.log_event("piece_split", [src.id, p.id], {"mass_kg": mass_kg, "rest_kg": src.mass_kg})
	return {"ok": true, "piece": p}


## Fließspannung [Pa] eines plastischen Stücks: (σ0 + k·ε) · Warmentfestigung.
static func flow_stress_pa(mp: MaterialPiece) -> float:
	var m := mp.material()
	var s0 := m.w("flow_stress_mpa", 70.0) * 1.0e6
	var k := m.w("hardening_mpa_per_strain", 400.0) * 1.0e6
	var soft := 1.0
	if m.has_melting():
		soft = maxf(m.w("hot_softening_min", 0.12), 1.0 - (mp.temperature_k() - 293.15) / maxf(1.0, m.melting_point - 293.15))
	return (s0 + k * mp.strain) * minf(1.0, soft)


## Mechanische Arbeit work_j auf ein Stück anwenden (ein Schlag).
##   plastisch (Kupfer): Δε = W / (σ(ε) · V), höchstens 0,2 je Schlag; Höhe · e^(−Δε), Breite/Tiefe · e^(Δε/2)
##                       (Volumen bleibt gleich). Über max_cold_strain (kalt) → Risse (Schaden).
##   spröde/faserig/weich: Δd = W / (m · Zähigkeit); d ≥ 1 → Bruch in Fragmente (Masse/Energie exakt).
## Rückgabe {ok, kind: "deformed"|"damaged"|"fractured", d_strain, damage, fragment_ids, message}.
static func work_piece(ctx: LifeContext, mp: MaterialPiece, work_j: float) -> Dictionary:
	if mp == null:
		return {"ok": false, "code": "target_lost", "message": "Ziel fehlt."}
	if work_j <= 0.0:
		return {"ok": true, "kind": "none", "d_strain": 0.0, "damage": mp.damage, "message": "Keine wirksame Arbeit."}
	if mp.liquid_fraction() > 0.0:
		return {"ok": false, "code": "liquid", "message": "Flüssiges Material kann nicht geschlagen werden."}
	var m := mp.material()
	if m.fracture_behavior == "not_applicable":
		return {"ok": false, "code": "not_modelled", "message": "Bearbeitung von %s ist nicht modelliert." % m.display_name}
	if m.is_plastic():
		var v := mp.volume_m3()
		var de := minf(MAX_STRAIN_PER_STRIKE, work_j / (flow_stress_pa(mp) * v))
		mp.strain += de
		mp.dims_m = Vector3(mp.dims_m.x * exp(de * 0.5), mp.dims_m.y * exp(-de), mp.dims_m.z * exp(de * 0.5))
		mp.size_m = maxf(mp.dims_m.x, maxf(mp.dims_m.y, mp.dims_m.z))
		var cold := mp.temperature_k() < 0.5 * m.melting_point if m.has_melting() else true
		var mx := m.w("max_cold_strain", 1.6)
		if cold and mp.strain > mx:
			mp.damage = minf(1.0, mp.damage + de / mx * 0.5)
		if de > 1e-6:
			mp.deformed = true
		mp.visual_version += 1
		return {"ok": true, "kind": "deformed", "d_strain": de, "damage": mp.damage,
			"message": "Verformt: Δε = %.4f (gesamt %.3f)." % [de, mp.strain]}
	mp.damage = minf(1.0, mp.damage + work_j / (mp.mass_kg * m.toughness_j_kg))
	if mp.damage < 1.0:
		mp.visual_version += 1
		return {"ok": true, "kind": "damaged", "d_strain": 0.0, "damage": mp.damage, "message": "Beschädigt (%.0f %%)." % (mp.damage * 100.0)}
	return fracture_piece(ctx, mp)


## Bruch eines Weltstücks in 2..max_fragments Bruchstücke (gleiche Aufteilungsregel wie DamageSystem).
static func fracture_piece(ctx: LifeContext, mp: MaterialPiece) -> Dictionary:
	if mp.assembly_id != 0 and ctx.assemblies.has(mp.assembly_id):
		ConstructionSystem.dissolve(ctx, mp.assembly_id, "Bauteil #%d zerbrochen" % mp.id, true)
	var m := mp.material()
	var n: int = ctx.sim.rng.randi_range(2, maxi(2, m.max_fragments))
	var shares := DamageSystem.fragment_shares(ctx.sim.rng, mp.mass_kg, mp.thermal_energy_j, n)
	var ids: Array = []
	var mass_before := mp.mass_kg
	var carrier := mp.carrier_id
	for i in n:
		var f := MaterialPiece.new()
		f.bind_material(m)
		f.material_id = mp.material_id
		f.mass_kg = shares[i][0]
		f.thermal_energy_j = shares[i][1]
		f.shape = "lump"
		var d := pow(f.mass_kg / m.density / (PI / 6.0), 1.0 / 3.0)
		f.dims_m = Vector3(d, d, d)
		f.size_m = d
		f.position = mp.position + Vector3(0.04 * (i - n * 0.5), 0.0, 0.03 * i)
		f.origin = "bruch:#%d" % mp.id
		f.parent_ids = [mp.id]
		f.label = "Bruchstück %d/%d" % [i + 1, n]
		# Prompt 6B: relevante Zustände übertragen – Temperatur über die anteilige Wärmeenergie (oben),
		# Testausrüstungs-Kennzeichen, Behälter (Bruchstücke bleiben im Tiegel/in der Form), Herkunft.
		f.test_equipment = mp.test_equipment
		if mp.container_id != 0 and ctx.material_pieces.has(mp.container_id):
			f.container_id = mp.container_id
		f.add_history(ctx.now(), "Bruchstück von #%d (%.3f von %.3f kg, %.1f K übernommen)" % [mp.id, f.mass_kg, mass_before, f.temperature_k()])
		ids.append(ConstructionSystem.add_piece(ctx, f))
	if carrier != 0:
		var cr := ctx.creature(carrier)
		if cr != null and cr.held_object_id == mp.id:
			cr.held_object_id = 0
			cr.hold_mode = ""
			cr.hold_side = ""
	StorageSystem.forget_piece(ctx, mp.id)
	StructureSystem.forget_piece(ctx, mp.id)
	ConstructionSystem.remove_piece(ctx, mp.id)
	ctx.publish({"type": "object_fractured", "actor": 0, "target": 0, "position": mp.position,
		"consequences": {"piece": mp.id, "material": mp.material_id, "fragments": ids, "mass_kg": mass_before},
		"visibility_m": float(ctx.tc("teaching").get("demo_visibility_m", 6.0))}, "warning")
	return {"ok": true, "kind": "fractured", "fragment_ids": ids, "d_strain": 0.0, "damage": 1.0, "mass_before_kg": mass_before,
		"message": "Zerbrochen in %d Stücke." % n}


## Gießen: flüssigen Inhalt eines Tiegels in eine Form. Prüft Flüssiganteil, Form, Kapazität und
## Restmengen. Der Guss behält Masse und spezifische Enthalpie; ein Überschuss bleibt im Tiegel.
## Rückgabe {ok, cast, poured_kg, rest_kg, energy_before_j, energy_after_j, message}.
static func pour(ctx: LifeContext, sample: MaterialPiece, mold: MaterialPiece) -> Dictionary:
	var cc: Dictionary = ctx.tc("casting")
	if sample == null or mold == null:
		return {"ok": false, "code": "missing", "message": "Schmelze oder Form fehlt."}
	if mold.shape != "mold" or mold.cavity_m3 <= 0.0:
		return {"ok": false, "code": "no_mold", "message": "#%d ist keine Gussform." % mold.id}
	if sample.liquid_fraction() < float(cc.get("min_liquid_fraction", 0.95)):
		return {"ok": false, "code": "not_liquid", "message": "Nicht ausreichend geschmolzen (Flüssiganteil %.0f %%, nötig %.0f %%)." % [sample.liquid_fraction() * 100.0, float(cc.get("min_liquid_fraction", 0.95)) * 100.0]}
	var mm := mold.material()
	if mm.valid_max_k < sample.temperature_k():
		return {"ok": false, "code": "mold_incompatible", "message": "Formmaterial %s hält %.0f K nicht (Modellgrenze %.0f K)." % [mm.display_name, sample.temperature_k(), mm.valid_max_k]}
	var occupied := 0.0
	for c in ConstructionSystem.contents_of(ctx, mold.id):
		occupied += (c as MaterialPiece).volume_m3()
	var free := mold.cavity_m3 - occupied
	if free <= 1e-9:
		return {"ok": false, "code": "mold_full", "message": "Form #%d ist bereits gefüllt." % mold.id}
	var e_before := sample.thermal_energy_j
	var m_before := sample.mass_kg
	var vol := sample.volume_m3()
	var cast: MaterialPiece
	var rest := 0.0
	if vol <= free + 1e-12:
		cast = sample
		cast.container_id = 0
	else:
		var take := free * sample.material().density
		var tp := take_portion(ctx, sample, take, true)
		if not tp["ok"]:
			return {"ok": false, "code": "split_failed", "message": tp["message"]}
		cast = tp["piece"]
		rest = sample.mass_kg
	# Gussstück nimmt die Form des Hohlraums an (Grundfläche 60 % der Außenmaße, Höhe aus dem Volumen)
	var cx := mold.dims_m.x * 0.6
	var cz := mold.dims_m.z * 0.6
	cast.shape = "ingot"
	cast.dims_m = Vector3(cx, cast.volume_m3() / (cx * cz), cz)
	cast.size_m = maxf(cx, cz)
	cast.container_id = mold.id
	cast.position = mold.position + Vector3(0, mold.inner_floor_m() + 0.001, 0)
	cast.origin = "guss:#%d" % mold.id
	cast.strain = 0.0
	cast.deformed = false
	cast.visual_version += 1
	cast.add_history(ctx.now(), "in Form #%d gegossen" % mold.id)
	for k in ctx.sim.thermal.contacts.keys():
		var c2: Dictionary = ctx.sim.thermal.contacts[k]
		if (int(c2["a"]) == cast.id or int(c2["b"]) == cast.id) and str(c2["label"]).begins_with("Tiegel"):
			ctx.sim.thermal.remove_contact(k)
	ctx.sim.thermal.add_contact_g(cast, mold, float(cc.get("cast_mold_conductance_w_k", 2.0)), "Guss↔Form #%d" % mold.id, true)
	var e_after := cast.thermal_energy_j + (sample.thermal_energy_j if cast != sample else 0.0)
	return {"ok": true, "cast": cast, "poured_kg": cast.mass_kg, "rest_kg": rest, "mass_before_kg": m_before,
		"energy_before_j": e_before, "energy_after_j": e_after,
		"message": "%.3f kg gegossen%s." % [cast.mass_kg, (", %.3f kg Rest im Tiegel" % rest) if rest > 0.0 else ""]}
