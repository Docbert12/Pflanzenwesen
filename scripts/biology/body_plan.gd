class_name BodyPlan
extends RefCounted
## Körperbauplan eines Wesens – reine Simulationsdaten (keine Nodes, keine Netze).
##
## Jeder Körperteil (Dictionary) hat:
##   id (stabil, lokal eindeutig) · type · function · material_id (Physikmaterial)
##   shape · size [x, y, z] in m (angezeigte Abmessung) · parent · attach [x, y, z] (Anschluss im
##   Elternteil-Gelenkraum) · joint · extent ("up"/"down") · side ("l"/"r"/"") · status
##   (present/removed/replaced) · optional rot [x, y, z], replaced_by, replaces, excel_ref
##
## Volumen:
##   angezeigte Größe   = size (Hüllquader)
##   Modellvolumen      = size.x · size.y · size.z · Formfaktor  → Grundlage der Masse
##   geometr. Volumen   = Anzahl der Darstellungsvoxel · Voxelvolumen (nur Anzeige; weicht durch
##                        die Voxelauflösung vom Modellvolumen ab)
## Masse = Modellvolumen · Dichte des Physikmaterials (MaterialRegistry).

const SCHEMA_VERSION := 1
const STATUS_PRESENT := "present"
const STATUS_REMOVED := "removed"
const STATUS_REPLACED := "replaced"
const STATUSES := [STATUS_PRESENT, STATUS_REMOVED, STATUS_REPLACED]
## Formfaktor = Modellvolumen / Hüllquadervolumen
const SHAPE_FACTOR := {
	"box": 1.0,
	"foot": 0.85,                # Quader mit abgerundeter Spitze (Näherung)
	"ellipsoid": PI / 6.0,
	"cylinder": PI / 4.0,
	"leaf": 0.6,                 # Blattumriss füllt ca. 60 % des Hüllrechtecks (Näherung)
	"hook": 0.35,                # dünner Schaft + Haken (Näherung)
}
const REQUIRED := ["id", "type", "function", "material_id", "shape", "size", "parent", "attach", "joint", "extent", "side"]
const MAX_LEAVES := 8

var id: int = 0                  # Entitäts-ID, wenn im EntityRegistry registriert
var species_id: String = "KR002"
var plan_seed: int = 0
var genes: Dictionary = {}
var parts: Dictionary = {}       # part id -> Dictionary
var order: Array = []            # Reihenfolge des Anlegens
var history: Array = []          # Änderungsprotokoll {action, part, detail}
var counters: Dictionary = {}    # fortlaufende Nummern für neue IDs (Blätter, Prothesen)


func add_part(p: Dictionary) -> String:
	for k in REQUIRED:
		if not p.has(k):
			return "Körperteil ohne Pflichtfeld '%s'." % k
	var pid := str(p["id"])
	if pid == "" or parts.has(pid):
		return "Doppelte oder leere Körperteil-ID '%s'." % pid
	if p["parent"] != "" and not parts.has(p["parent"]):
		return "Körperteil '%s': Elternteil '%s' existiert nicht." % [pid, p["parent"]]
	if not SHAPE_FACTOR.has(p["shape"]):
		return "Körperteil '%s': unbekannte Form '%s'." % [pid, p["shape"]]
	var q := p.duplicate(true)
	if not q.has("status"):
		q["status"] = STATUS_PRESENT
	parts[pid] = q
	order.append(pid)
	return ""


func root_id() -> String:
	for pid in order:
		if parts[pid]["parent"] == "":
			return pid
	return ""


## Vollständige Prüfung. materials darf null sein (dann ohne Materialprüfung).
func validate(materials: MaterialRegistry) -> Array:
	var errs: Array = []
	var roots := 0
	for pid in parts:
		var p: Dictionary = parts[pid]
		for k in REQUIRED:
			if not p.has(k):
				errs.append("'%s': Pflichtfeld '%s' fehlt." % [pid, k])
		if str(p.get("id", "")) != pid:
			errs.append("'%s': ID im Eintrag passt nicht zum Schlüssel." % pid)
		if not p.get("status", "") in STATUSES:
			errs.append("'%s': ungültiger Status '%s'." % [pid, p.get("status", "")])
		if not SHAPE_FACTOR.has(p.get("shape", "")):
			errs.append("'%s': unbekannte Form." % pid)
		var sz = p.get("size", [])
		if typeof(sz) != TYPE_ARRAY or sz.size() != 3 or float(sz[0]) <= 0.0 or float(sz[1]) <= 0.0 or float(sz[2]) <= 0.0:
			errs.append("'%s': Größe muss drei positive Werte haben." % pid)
		if materials != null and not materials.has_material(str(p.get("material_id", ""))):
			errs.append("'%s': unbekanntes Material '%s'." % [pid, p.get("material_id", "")])
		var par: String = str(p.get("parent", ""))
		if par == "":
			roots += 1
		elif not parts.has(par):
			errs.append("'%s': ungültige Verbindung zu fehlendem Elternteil '%s'." % [pid, par])
	if roots != 1:
		errs.append("Körperplan braucht genau einen Wurzelteil (gefunden: %d)." % roots)
	# Zyklen
	for pid in parts:
		var seen := {}
		var cur: String = pid
		while cur != "":
			if seen.has(cur):
				errs.append("Zyklische Körperhierarchie bei '%s'." % pid)
				break
			seen[cur] = true
			cur = str(parts.get(cur, {}).get("parent", ""))
	return errs


## Teil ist wirksam vorhanden, wenn es selbst und alle Vorfahren „present“ sind.
func is_present(pid: String) -> bool:
	var cur := pid
	var guard := 0
	while cur != "" and guard < 64:
		var p: Dictionary = parts.get(cur, {})
		if p.is_empty() or p["status"] != STATUS_PRESENT:
			return false
		cur = p["parent"]
		guard += 1
	return true


func present_ids() -> Array:
	return order.filter(func(pid): return is_present(pid))


func children(pid: String) -> Array:
	return order.filter(func(c): return parts[c]["parent"] == pid)


func descendants(pid: String) -> Array:
	var res: Array = []
	for c in children(pid):
		res.append(c)
		res.append_array(descendants(c))
	return res


func model_volume(pid: String) -> float:
	var p: Dictionary = parts[pid]
	return float(p["size"][0]) * float(p["size"][1]) * float(p["size"][2]) * float(SHAPE_FACTOR[p["shape"]])


func part_mass(pid: String, materials: MaterialRegistry) -> float:
	return model_volume(pid) * materials.get_material(parts[pid]["material_id"]).density


func total_mass(materials: MaterialRegistry) -> float:
	var s := 0.0
	for pid in present_ids():
		s += part_mass(pid, materials)
	return s


func present_of_type(type: String) -> Array:
	return present_ids().filter(func(pid): return parts[pid]["type"] == type)


## Entfernt einen Teil samt aller daran hängenden Teile.
func remove_part(pid: String, reason: String) -> Dictionary:
	if not parts.has(pid):
		return {"ok": false, "message": "Körperteil '%s' existiert nicht." % pid}
	if parts[pid]["parent"] == "":
		return {"ok": false, "message": "Der Rumpf kann nicht entfernt werden."}
	if not is_present(pid):
		return {"ok": false, "message": "'%s' ist bereits nicht mehr vorhanden." % pid}
	var removed: Array = [pid]
	parts[pid]["status"] = STATUS_REMOVED
	for d in descendants(pid):
		if parts[d]["status"] == STATUS_PRESENT:
			parts[d]["status"] = STATUS_REMOVED
			removed.append(d)
	history.append({"action": "remove", "part": pid, "detail": {"reason": reason, "removed": removed}})
	return {"ok": true, "removed": removed}


## Unterarm einer Seite entfernen (Testeingriff der Vorschau; Excel V001 „Armverlust“).
func remove_forearm(side: String) -> Dictionary:
	var pid := "arm_%s_lower" % side
	var pros := present_prosthesis(side)
	if pros != "":
		return remove_part(pros, "Prothese abgenommen")
	return remove_part(pid, "Unterarm entfernt (Vorschau)")


func present_prosthesis(side: String) -> String:
	for pid in present_ids():
		if parts[pid]["type"] == "prosthesis" and parts[pid]["side"] == side:
			return pid
	return ""


## Bringt eine einfache Unterarmprothese an (Holz: Stütze ohne Greiffunktion, Kupfer: Haken).
func attach_prosthesis(side: String, material_id: String, materials: MaterialRegistry) -> Dictionary:
	var upper := "arm_%s_upper" % side
	var lower := "arm_%s_lower" % side
	if not is_present(upper):
		return {"ok": false, "message": "Oberarm %s fehlt – keine Befestigung möglich." % side}
	if is_present(lower):
		return {"ok": false, "message": "Unterarm %s ist vorhanden; erst entfernen." % side}
	if materials != null and not materials.has_material(material_id):
		return {"ok": false, "message": "Unbekanntes Prothesenmaterial '%s'." % material_id}
	var old := present_prosthesis(side)
	if old != "":
		parts[old]["status"] = STATUS_REPLACED
	var n: int = counters.get("prosthesis_%s" % side, 0) + 1
	counters["prosthesis_%s" % side] = n
	var pid := "prosthesis_arm_%s_%d" % [side, n]
	var lo: Dictionary = parts[lower]
	var hand: Dictionary = parts.get("hand_%s" % side, {})
	var length: float = float(lo["size"][1]) + (float(hand["size"][1]) * 0.5 if not hand.is_empty() else 0.0)
	var th: float = float(lo["size"][0])
	var p := {
		"id": pid, "type": "prosthesis", "material_id": material_id, "parent": upper,
		"attach": lo["attach"].duplicate(), "joint": "elbow_%s" % side, "extent": "down", "side": side,
		"excel_ref": "KT014",
	}
	if material_id == "copper":
		p["function"] = "haken"
		p["shape"] = "hook"
		p["size"] = [th * 1.25, length, th * 1.25]
	else:
		p["function"] = "stuetze"
		p["shape"] = "cylinder"
		p["size"] = [th * 0.85, length * 0.92, th * 0.85]
	p["replaces"] = [lower, "hand_%s" % side] if not hand.is_empty() else [lower]
	var err := add_part(p)
	if err != "":
		return {"ok": false, "message": err}
	for r in p["replaces"]:
		if parts.has(r) and parts[r]["status"] == STATUS_REMOVED:
			parts[r]["status"] = STATUS_REPLACED
			parts[r]["replaced_by"] = pid
	history.append({"action": "attach_prosthesis", "part": pid, "detail": {"material": material_id, "replaced_previous": old}})
	return {"ok": true, "id": pid}


func leaf_ids() -> Array:
	return present_of_type("leaf")


## Fügt ein Kopfblatt hinzu (stabile neue ID). Position nach dem goldenen Winkel.
func add_leaf() -> Dictionary:
	if not is_present("head"):
		return {"ok": false, "message": "Kein Kopf vorhanden."}
	if leaf_ids().size() >= MAX_LEAVES:
		return {"ok": false, "message": "Höchstens %d Blätter (Excel 13_Vererbung: Kopfblätter 0–8)." % MAX_LEAVES}
	var n: int = counters.get("leaf", 0) + 1
	counters["leaf"] = n
	var p := _leaf_part(n)
	var err := add_part(p)
	if err != "":
		return {"ok": false, "message": err}
	history.append({"action": "add_leaf", "part": p["id"], "detail": {}})
	return {"ok": true, "id": p["id"]}


func remove_leaf() -> Dictionary:
	var leaves := leaf_ids()
	if leaves.is_empty():
		return {"ok": false, "message": "Keine Blätter vorhanden."}
	return remove_part(leaves[leaves.size() - 1], "Blatt entfernt (Vorschau)")


func _leaf_part(n: int) -> Dictionary:
	var head: Dictionary = parts["head"]
	var hs: Array = head["size"]
	var ang := (n - 1) * 2.39996   # goldener Winkel
	var spread := 0.0 if n == 1 else 0.55
	var len_m: float = float(genes.get("leaf_length_m", 0.17)) * (1.0 - 0.06 * float((n - 1) % 3))
	return {
		"id": "leaf_%d" % n, "type": "leaf", "function": "photosynthese_dekor", "material_id": "plant_tissue",
		"shape": "leaf", "size": [len_m * 0.55, len_m, 0.02], "parent": "head",
		"attach": [sin(ang) * float(hs[0]) * 0.18 * spread * 2.0, float(hs[1]) * 0.94, cos(ang) * float(hs[2]) * 0.15 * spread * 2.0],
		"rot": [cos(ang) * spread * 0.9 - 0.1, ang, -sin(ang) * spread * 0.9], "joint": "leaf_%d" % n, "extent": "up", "side": "",
		"excel_ref": "KT012",
	}


## Was der Körper in seinem aktuellen Zustand kann (für Animation/Bedienung).
func capabilities() -> Dictionary:
	var grasp := {}
	for s in ["l", "r"]:
		if is_present("hand_%s" % s):
			grasp[s] = "hand"
		else:
			var pr := present_prosthesis(s)
			grasp[s] = "hook" if pr != "" and parts[pr]["function"] == "haken" else ""
	var legs_ok := true
	for s in ["l", "r"]:
		for seg in ["leg_%s_upper", "leg_%s_lower", "foot_%s"]:
			if not is_present(seg % s):
				legs_ok = false
	return {"walk": legs_ok, "grasp": grasp, "leaves": leaf_ids().size()}


func to_dict() -> Dictionary:
	var plist: Array = []
	for pid in order:
		plist.append(parts[pid].duplicate(true))
	return {"schema_version": SCHEMA_VERSION, "kind": "body_plan", "species_id": species_id, "seed": plan_seed,
		"genes": genes.duplicate(true), "parts": plist, "history": history.duplicate(true), "counters": counters.duplicate()}


## Lädt einen Körperplan und prüft ihn vollständig. Rückgabe {"ok", "plan", "errors"}.
static func from_dict(d, materials: MaterialRegistry) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY or d.get("kind", "") != "body_plan":
		return {"ok": false, "plan": null, "errors": ["Keine Körperplan-Datei."]}
	if int(d.get("schema_version", 0)) != SCHEMA_VERSION:
		return {"ok": false, "plan": null, "errors": ["Unbekannte schema_version %s." % str(d.get("schema_version"))]}
	var bp := BodyPlan.new()
	bp.species_id = str(d.get("species_id", "KR002"))
	bp.plan_seed = int(d.get("seed", 0))
	bp.genes = d.get("genes", {}).duplicate(true)
	bp.history = d.get("history", []).duplicate(true)
	for k in d.get("counters", {}):
		bp.counters[k] = int(d["counters"][k])
	var errs: Array = []
	# Teile zunächst ohne Elternprüfung übernehmen (Reihenfolge darf beliebig sein), dann validieren
	for p in d.get("parts", []):
		if typeof(p) != TYPE_DICTIONARY or not p.has("id"):
			errs.append("Ungültiger Körperteil-Eintrag.")
			continue
		if bp.parts.has(str(p["id"])):
			errs.append("Doppelte Körperteil-ID '%s'." % p["id"])
			continue
		bp.parts[str(p["id"])] = p.duplicate(true)
		bp.order.append(str(p["id"]))
	errs.append_array(bp.validate(materials))
	if not errs.is_empty():
		return {"ok": false, "plan": null, "errors": errs}
	return {"ok": true, "plan": bp, "errors": []}
