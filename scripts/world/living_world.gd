class_name LivingWorld
extends Node3D
## Spielbare Lebenssimulation: Welt, Lebensbaum, Nahrung, 50 Pflanzenwesen, Beobachtungsfenster,
## Pause, Speichern/Laden und Entwicklermodus. Die Logik liegt vollständig in LifeSimulation;
## diese Szene stellt nur dar und leitet Bedienung weiter.
##
## Takt: _physics_process (fester Physiktakt) → LifeSimulation.step. Pause hält den SceneTree und
## die Simulationsuhr an; Kamera und Oberfläche laufen mit PROCESS_MODE_ALWAYS weiter.

## Startauftrag aus dem Menü: {"mode": "new"} oder {"mode": "load", "path": …}
static var pending: Dictionary = {"mode": "new"}

const SCENE := "res://scenes/living_world.tscn"

@onready var sim: Simulation = $Simulation
@onready var camera: LabCamera = $LabCamera
@onready var world: VoxelWorld = $VoxelWorld

var db := DefinitionDB.new()
var life := LifeSimulation.new()
var objects_root: Node3D
var creature_root: Node3D
var item_root: Node3D
var views: Dictionary = {}           # Wesen-ID -> {"view": CreatureView, "version": int, "anim": String}
var item_nodes: Dictionary = {}      # Gegenstand-ID -> MeshInstance3D
var selected_id: int = 0
var start_message: String = ""
var start_ok: bool = false
var errors: Array = []
var voxel_size: float = 0.02
var save_path: String = SaveManager.path_for()   # Tests verwenden einen eigenen Pfad
var loaded_time_s: float = -1.0      # Simulationszeit direkt nach Start/Laden (Prüfung: keine Offline-Zeit)

var _sun: DirectionalLight3D
var _env: Environment
var _marker: MeshInstance3D
var _inspector: CreatureInspector
var _population: PopulationPanel
var _events: EventViewer
var _perf: PerformanceMonitor
var _dev_panel: PanelContainer
var _top_label: Label
var _msg: Label
var _pause_btn: Button
var _dev_btn: Button
var _refill_box: CheckBox
var _behavior_box: CheckBox
var _side_opt: OptionButton
var _ui_accum := 0.0
var _item_mesh: SphereMesh
var _god: GodMenu
var _god_btn: Button
var _compare: PanelContainer
var _compare_a: RichTextLabel
var _compare_b: RichTextLabel
var compare_id: int = 0
var _god_ev_accum: int = 0
var piece_nodes: Dictionary = {}     # oberstes Objekt (Stück oder Verbund) -> Node3D (ObjectGenerator)
var heater_nodes: Dictionary = {}    # Testheizung -> MeshInstance3D
var _exp: ExperimentInspector
var _know: KnowledgeViewer
var _ws_panel: PanelContainer
var _work_panel: PanelContainer
var work_labels: Dictionary = {}     # Wesen-ID -> Label3D (Arbeitsanzeige über dem Wesen, Prompt 6B)
var effect_nodes: Dictionary = {}    # Eingriffs-ID -> MeshInstance3D (Leuchten)
var storage_nodes: Dictionary = {}   # Lager-ID -> Node3D (Bodenrahmen + Beschriftung)
var site_nodes: Dictionary = {}      # Bauwerk-ID -> Node3D (Platzmarken + Beschriftung)
var social_labels: Dictionary = {}   # Wesen-ID -> Label3D (Symbol der sozialen Handlung)
var effect_root: Node3D
## Für Tests: feste KI-Anbindung statt der Anwendungseinstellungen (z. B. AIService.disabled()).
static var ai_service_override: AIService = null
var _ai_panel: AIStatusPanel
var _conv: ConversationViewer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	sim.initialize()
	sim.set_physics_process(false)          # Takt kommt ausschließlich aus LifeSimulation.step
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	if not db.load_all():
		errors.append_array(db.errors)
	voxel_size = float(db.config("world").get("voxel_sizes_m", {}).get("creature", 0.02))
	objects_root = Node3D.new()
	objects_root.name = "Weltobjekte"
	add_child(objects_root)
	creature_root = Node3D.new()
	creature_root.name = "Wesen"
	add_child(creature_root)
	item_root = Node3D.new()
	item_root.name = "Nahrungsportionen"
	add_child(item_root)
	effect_root = Node3D.new()
	effect_root.name = "Eingriffe"
	add_child(effect_root)
	_build_env()
	_build_ui()
	if not sim.is_ready() or not errors.is_empty():
		_fail("Initialisierung fehlgeschlagen:\n" + "\n".join(sim.init_errors + errors))
		return
	if not life.setup(sim, db, world, objects_root, _ai_service()):
		_fail("Lebenssimulation nicht startbar:\n" + "\n".join(life.errors))
		return
	var mode := str(pending.get("mode", "new"))
	if mode == "load":
		var path := str(pending.get("path", SaveManager.path_for()))
		save_path = path if not path.ends_with(".bak") else SaveManager.path_for()
		var r := SaveManager.load_into(life, path)
		if not r["ok"]:
			var bak := SaveManager.backup_path(path)
			var extra := ""
			if r.get("code", "") == "corrupt" and FileAccess.file_exists(bak) and SaveManager.read_file(bak)["ok"]:
				extra = "\n\nEine gültige Sicherung (%s) ist vorhanden – im Menü „Sicherung laden“ wählen." % bak
			_fail("Spielstand konnte nicht geladen werden:\n%s%s" % [r["message"], extra])
			return
		start_message = r["message"]
		if not r.get("cancelled_actions", []).is_empty():
			start_message += " Beim Laden abgebrochen: " + ", ".join(r["cancelled_actions"])
	elif mode == "workshop":
		var seed_w := int(pending.get("seed", db.config("world").get("seed", 12345)))
		save_path = SaveManager.path_for("werkstatt")
		var rw := life.new_workshop(seed_w, bool(pending.get("behavior", false)))
		if not rw.get("ok", false):
			_fail("Testwerkstatt konnte nicht erzeugt werden:\n" + str(rw.get("message", "")))
			return
		start_message = "TESTWERKSTATT (Testausrüstung, nicht im normalen Spiel): %s" % rw["message"]
	elif mode == "werkzeugkette":
		var seed_k := int(pending.get("seed", db.config("world").get("seed", 12345)))
		save_path = SaveManager.path_for("werkzeugkette")
		var rk := life.new_work_scene(seed_k, bool(pending.get("behavior", false)))
		if not rk.get("ok", false):
			_fail("Testszene Werkzeugkette konnte nicht erzeugt werden:\n" + str(rk.get("message", "")))
			return
		start_message = "TESTSZENE WERKZEUGKETTE (Testausrüstung, nicht im normalen Spiel): %s Ketten unten links gezielt auslösen." % rk["message"]
	else:
		var seed_value := int(pending.get("seed", db.config("world").get("seed", 12345)))
		var r2 := life.new_game(seed_value)
		if not r2["ok"]:
			_fail("Neues Spiel konnte nicht erzeugt werden:\n" + str(r2["message"]))
			return
		start_message = "Neues Spiel: %s Startwert %d." % [r2["message"], seed_value]
	pending = {"mode": "new"}
	start_ok = true
	loaded_time_s = life.ctx.now()
	var tp: Vector3 = life.tree_node.position
	camera.target = tp + Vector3(0, 1.0, 0)
	camera.distance = 22.0
	if not life.workshop.is_empty():
		var wa := life.ctx.creature(int(life.workshop["a"]))
		if wa != null:
			camera.target = wa.position + Vector3(0, 0.3, 0)
			camera.distance = 4.5
			selected_id = wa.id
	camera.pitch = -0.55
	camera.yaw = 0.6
	camera._apply()
	camera.object_picked.connect(_on_pick)
	_sync_views(0.0)
	_msg.text = start_message
	_refresh_ui()


func _exit_tree() -> void:
	life.dispose()


func _fail(text: String) -> void:
	start_ok = false
	errors.append(text)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(c)
	var p := Nav.panel(c)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(620, 0)
	p.add_child(v)
	Nav.label(v, text, 15).modulate = Color(1, 0.7, 0.6)
	Nav.back_button(v, self)
	push_warning(text)


# ── Takt ──────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not start_ok:
		return
	if get_tree().paused:
		if life.ctx.ai != null:
			life.ctx.ai.update(true)     # Pause: Netzwerk weiter abfragen, aber nichts senden oder anwenden
		return
	life.step(delta)


func _process(delta: float) -> void:
	if not start_ok:
		return
	_sync_views(0.0 if get_tree().paused else delta)
	_update_light()
	_ui_accum += delta
	if _ui_accum >= 0.25:
		_ui_accum = 0.0
		_refresh_ui()


# ── Darstellung ───────────────────────────────────

func _sync_views(delta: float) -> void:
	var ctx := life.ctx
	for id in ctx.creatures:
		var cr: Creature = ctx.creatures[id]
		var e: Dictionary = views.get(id, {})
		if e.is_empty():
			var v := CreatureGenerator.build_view(cr.plan, sim.materials, voxel_size)
			v.name = "Wesen_%d" % id
			v.set_process(false)          # Animation wird hier passend zur Handlung getaktet
			v.set_meta("creature_id", id)
			creature_root.add_child(v)
			e = {"view": v, "version": cr.body_version, "anim": "", "dead_pose": false}
			views[id] = e
		var view: CreatureView = e["view"]
		if int(e["version"]) != cr.body_version:
			view.rebuild()                 # nur bei Körperänderung, nicht pro Bild
			e["version"] = cr.body_version
			e["anim"] = ""
		view.position = cr.position
		view.rotation.y = cr.heading
		if not cr.alive:
			if not e["dead_pose"]:
				view.animator.request("idle")
				view.animator.update(0.0)
				view.rotation.z = PI * 0.5   # liegender, inaktiver Körper
				view.position.y += 0.12
				e["dead_pose"] = true
			continue
		var anim := "idle"
		var side := "r"
		var rate := 1.0
		var drive := {}
		var holding := cr.held_object_id != 0
		var hold_mode := (cr.hold_mode if cr.hold_mode != "" else "one") if holding else ""
		var hold_side := cr.hold_side if cr.hold_side != "" else str(cr.caps.get("grasp_side", "r"))
		var walk_rate := clampf(cr.speed_now / float(ctx.c("locomotion").get("base_speed_m_s", 1.0)), 0.2, 1.5)
		e["anim_src"] = ""
		if ctx.executor.running.has(id):
			var a: GameAction = ctx.executor.running[id]
			e["anim_src"] = a.type          # Handlung, aus der die Animation in diesem Bild abgeleitet wurde
			var ad: Dictionary = a.state.get("anim", {})
			if str(ad.get("pose", "")) != "":
				# Prompt 6B: Arbeitshandlung liefert Pose, Phase und Fortschritt (nur lesend)
				anim = str(ad["pose"])
				side = hold_side
				drive = ad
				if anim == "walk_short" and cr.speed_now > 0.05:
					rate = walk_rate
			else:
				match a.type:
					"move_to":
						if holding:
							anim = "carry_two" if hold_mode == "two" else "carry"
							side = hold_side
							drive = {"pose": anim, "phase": "approach", "u": 0.0}
							rate = walk_rate if cr.speed_now > 0.05 else 1.0
						elif cr.speed_now > 0.05:
							anim = "walk"
							rate = walk_rate
					"pick_up":
						anim = "grasp"
						side = str(a.state.get("side", cr.caps.get("grasp_side", "r")))
					"eat":
						if a.state.get("mode", "") == "carried":
							anim = "eat"
							side = str(a.state.get("side", cr.caps.get("feeding_side", "r")))
					"raise_arms":
						anim = "raise_arms"
					"give_food", "offer_food":
						anim = "grasp"
						side = str(cr.caps.get("grasp_side", "r"))
		if anim == "idle" and holding:
			# Gehaltenes bleibt sichtbar in der Hand (Haltepose statt Ruhehaltung)
			anim = "carry_two" if hold_mode == "two" else "carry"
			side = hold_side
			drive = {"pose": anim, "phase": "hold", "u": 0.0}
		if anim != e["anim"]:
			var r := view.animator.request(anim, side)
			if not r.get("ok", false):
				view.animator.request("idle")   # Bewegung für diesen Körper nicht implementiert → Ruhehaltung
				anim = "idle"
				drive = {}
			e["anim"] = anim
		var info := {"tool_h": WorkPose.tool_reach(ctx, cr.held_object_id) if holding else 0.0, "hold_mode": hold_mode,
			"moving": cr.speed_now > 0.05, "target_local": null}
		if drive.has("target"):
			var tg: Array = drive["target"]
			info["target_local"] = WorkPose.to_local(cr.position, cr.heading, Vector3(float(tg[0]), float(tg[1]), float(tg[2])))
		view.animator.drive_data = drive
		view.animator.drive_info = info
		view.animator.update(delta * rate)
	# Nahrungsquellen: Größe zeigt Restmenge
	for fid in life.plant_nodes:
		var n: Node3D = life.plant_nodes[fid]
		if not is_instance_valid(n):
			continue
		var f: FoodSource = ctx.foods[fid]
		var s := lerpf(0.3, 1.0, clampf(f.fraction(), 0.0, 1.0))
		if f.amount_kg <= 1e-6:
			s = 0.22
		n.scale = Vector3.ONE * s
	# Portionen (getragen oder am Boden)
	for iid in ctx.items:
		var it: FoodItem = ctx.items[iid]
		var node: MeshInstance3D = item_nodes.get(iid, null)
		if node == null:
			node = MeshInstance3D.new()
			node.mesh = _item_mesh
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.75, 0.15, 0.3) if it.food_id == "N001" else Color(0.85, 0.75, 0.55)
			node.material_override = m
			item_root.add_child(node)
			item_nodes[iid] = node
		var p := it.position + Vector3(0, 0.05, 0)
		if it.carrier_id != 0 and ctx.creatures.has(it.carrier_id):
			var cr2: Creature = ctx.creatures[it.carrier_id]
			var fwd := Vector3(sin(cr2.heading), 0, cos(cr2.heading))
			p = cr2.position + fwd * 0.18 + Vector3(0, float(cr2.plan.genes.get("stand_height_m", 0.35)) + 0.12, 0)
		node.position = p
		node.scale = Vector3.ONE * clampf(pow(it.mass_kg / 0.1, 1.0 / 3.0), 0.3, 1.2)
	for iid in item_nodes.keys():
		if not ctx.items.has(iid):
			item_nodes[iid].queue_free()
			item_nodes.erase(iid)
	_sync_social_labels()
	_sync_work_labels()
	_sync_pieces_and_effects()
	if selected_id != 0 and ctx.creatures.has(selected_id):
		_marker.visible = true
		_marker.position = ctx.creatures[selected_id].position + Vector3(0, 0.03, 0)
	else:
		_marker.visible = false


const SOCIAL_SYMBOL := {"request_food": "? Nahrung", "give_food": "→ gibt", "offer_food": "→ bietet an", "decline_request": "× nein", "raise_arms": "Arme heben", "talk": "„…“ spricht"}


## Kurze Symbole über Wesen während sozialer/ausdrucksvoller Handlungen (nur Darstellung).
func _sync_social_labels() -> void:
	var ctx := life.ctx
	var want := {}
	for id in ctx.executor.running:
		var a: GameAction = ctx.executor.running[id]
		if SOCIAL_SYMBOL.has(a.type):
			want[id] = SOCIAL_SYMBOL[a.type] + ((" #%d" % a.target_id) if a.target_id != 0 else "")
	for id in social_labels.keys():
		if not want.has(id):
			social_labels[id].queue_free()
			social_labels.erase(id)
	for id in want:
		var l: Label3D = social_labels.get(id, null)
		if l == null:
			l = Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.font_size = 40
			l.pixel_size = 0.004
			l.outline_size = 8
			l.no_depth_test = true
			l.modulate = Color(1, 0.95, 0.6)
			add_child(l)
			social_labels[id] = l
		l.text = want[id]
		l.position = ctx.creatures[id].position + Vector3(0, 1.25, 0)


## Prompt 6B: kurze Arbeitsanzeige über Wesen mit laufender Arbeitskette (Ziel, Handlung, Werkzeug, Last).
func _sync_work_labels() -> void:
	var ctx := life.ctx
	var want := {}
	if ctx.work != null:
		for aid in ctx.work.by_actor:
			var cr := ctx.creature(int(aid))
			if cr == null or not cr.alive:
				continue
			var v := ctx.work.status_view(cr, ctx)
			if v.is_empty():
				continue
			var line := "%s · %s" % [str(v["ziel"]), str(v["handlung"])]
			var extra: Array = []
			if int(v["werkzeug"]) != 0:
				extra.append("Werkzeug #%d" % int(v["werkzeug"]))
			if float(v["getragen_kg"]) > 0.0:
				extra.append("trägt %.2f kg" % float(v["getragen_kg"]))
			extra.append("%.0f %%" % (float(v["fortschritt"]) * 100.0))
			want[int(aid)] = line + "\n" + " · ".join(extra)
	for id in work_labels.keys():
		if not want.has(id):
			work_labels[id].queue_free()
			work_labels.erase(id)
	for id in want:
		var l: Label3D = work_labels.get(id, null)
		if l == null:
			l = Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.font_size = 34
			# feste Bildschirmgröße (≈ 16 px), damit die Anzeige nah nicht das Bild verdeckt und fern lesbar bleibt
			l.fixed_size = true
			l.pixel_size = 0.0008
			l.outline_size = 8
			l.no_depth_test = true
			l.modulate = Color(0.75, 0.95, 1.0)
			add_child(l)
			work_labels[id] = l
		l.text = want[id]
		l.position = ctx.creatures[id].position + Vector3(0, 1.45, 0)


func _sync_pieces_and_effects() -> void:
	var ctx := life.ctx
	# Gegenstände (Prompt 6): einzelne Stücke und Verbünde aus den tatsächlichen Daten (ObjectGenerator)
	var want := {}
	for pid in ctx.material_pieces:
		var mp: MaterialPiece = ctx.material_pieces[pid]
		if mp.assembly_id == 0:
			want[pid] = ObjectGenerator.signature(mp)
	for aid in ctx.assemblies:
		want[aid] = ObjectGenerator.assembly_signature(ctx.assemblies[aid], ctx)
	for id in want:
		var n: Node3D = piece_nodes.get(id, null)
		if n != null and str(n.get_meta("signature", "")) != str(want[id]):
			n.queue_free()
			n = null
		if n == null:
			n = ObjectGenerator.build_assembly(ctx.assemblies[id], ctx) if ctx.assemblies.has(id) else ObjectGenerator.build_piece(ctx.material_pieces[id], sim.materials)
			effect_root.add_child(n)
			piece_nodes[id] = n
		var carrier := ConstructionSystem.carrier_of(ctx, id)
		var pos = ctx.position_of(id)
		if pos == null:
			continue
		if carrier != 0 and ctx.creatures.has(carrier):
			var cr: Creature = ctx.creatures[carrier]
			if not _place_held(n, cr, id):
				n.position = pos
				n.rotation = Vector3(0.0, cr.heading - PI * 0.5, 0.35)
		else:
			n.position = pos
			n.rotation = Vector3.ZERO
	_sync_storages_and_sites()
	for pid in piece_nodes.keys():
		if not want.has(pid):
			piece_nodes[pid].queue_free()
			piece_nodes.erase(pid)
	for hid in ctx.heaters:
		var h: TestHeater = ctx.heaters[hid]
		var hn: MeshInstance3D = heater_nodes.get(hid, null)
		if hn == null:
			hn = MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.22, 0.12, 0.22)
			hn.mesh = bm
			hn.material_override = StandardMaterial3D.new()
			effect_root.add_child(hn)
			heater_nodes[hid] = hn
		hn.position = h.position + Vector3(0, 0.06, 0)
		var hm: StandardMaterial3D = hn.material_override
		var on := h.slot_id != 0
		hm.albedo_color = Color(0.25, 0.25, 0.28)
		hm.emission_enabled = on
		hm.emission = Color(1.0, 0.35, 0.1)
		hm.emission_energy_multiplier = 1.2
	var now := ctx.now()
	var live := {}
	for e in ctx.interventions.effects:
		live[e["id"]] = true
		var n: MeshInstance3D = effect_nodes.get(e["id"], null)
		if n == null:
			n = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.35
			sm.height = 0.7
			n.mesh = sm
			var em := StandardMaterial3D.new()
			em.albedo_color = Color(1.0, 0.9, 0.4, 0.35)
			em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			em.emission_enabled = true
			em.emission = Color(1.0, 0.85, 0.3)
			em.emission_energy_multiplier = 2.0
			em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			n.material_override = em
			effect_root.add_child(n)
			effect_nodes[e["id"]] = n
		var left := float(e["until_t"]) - now
		n.position = (e["pos"] as Vector3) + Vector3(0, 0.3, 0)
		n.scale = Vector3.ONE * (0.6 + 0.4 * absf(sin(left * 3.0)))
	for k in effect_nodes.keys():
		if not live.has(k):
			effect_nodes[k].queue_free()
			effect_nodes.erase(k)


## Prompt 6B: gehaltenen Gegenstand an den Griffpunkt der tatsächlich animierten Hand setzen
## (einhändig: Griffrahmen der Hand bzw. des Hakens; zweihändig: zwischen beiden Händen, mittig).
## false → kein passendes Gelenk (Ersatzdarstellung an der Simulationsposition).
func _place_held(n: Node3D, cr: Creature, id: int) -> bool:
	var e: Dictionary = views.get(cr.id, {})
	if e.is_empty() or not cr.alive or cr.held_object_id != id:
		return false
	var view: CreatureView = e["view"]
	if not view.is_inside_tree():
		return false
	var half_h := 0.0
	var rod_len := 0.0
	for p in ConstructionSystem.parts_of(life.ctx, id):
		half_h = maxf(half_h, (p as MaterialPiece).dims_m.y * 0.5)
	if life.ctx.material_pieces.has(id) and (life.ctx.material_pieces[id] as MaterialPiece).shape == "rod":
		rod_len = (life.ctx.material_pieces[id] as MaterialPiece).dims_m.x
	if cr.hold_mode == "two":
		var gl := view.animator.grip_frame("l")
		var gr := view.animator.grip_frame("r")
		if not gl["ok"] or not gr["ok"]:
			return false
		var mid: Vector3 = ((gl["xform"] as Transform3D).origin + (gr["xform"] as Transform3D).origin) * 0.5
		n.global_transform = view.global_transform * Transform3D(Basis.IDENTITY, mid + Vector3(0.0, -half_h, 0.0))
		return true
	var s := cr.hold_side if cr.hold_side != "" else str(cr.caps.get("grasp_side", "r"))
	var g := view.animator.grip_frame(s)
	if not g["ok"]:
		return false
	# Verbund: Ursprung = Griffpunkt; Stab: am Ende gegriffen; sonstiges Stück: mittig in der Hand
	var off := Vector3.ZERO
	if not life.ctx.assemblies.has(id):
		off = Vector3(rod_len * 0.5, -half_h, 0.0)
	n.global_transform = view.global_transform * (g["xform"] as Transform3D) * Transform3D(Basis.IDENTITY, off)
	return true


## Prompt 6B: Lagerplätze (Bodenrahmen) und Baustellen (Platzmarken: leer/belegt) sichtbar machen.
func _sync_storages_and_sites() -> void:
	var ctx := life.ctx
	for sid in ctx.storages:
		var s: StoragePlace = ctx.storages[sid]
		var sn: Node3D = storage_nodes.get(sid, null)
		if sn == null:
			sn = Node3D.new()
			sn.name = "Lager_%d" % sid
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.55, 0.42, 0.25)
			for k in 4:
				var bar := MeshInstance3D.new()
				var bm := BoxMesh.new()
				var along_x := k < 2
				bm.size = Vector3(s.size_m.x if along_x else 0.03, 0.025, 0.03 if along_x else s.size_m.y)
				bar.mesh = bm
				bar.material_override = mat
				var sgn := -1.0 if k % 2 == 0 else 1.0
				bar.position = Vector3(0.0, 0.0125, sgn * s.size_m.y * 0.5) if along_x else Vector3(sgn * s.size_m.x * 0.5, 0.0125, 0.0)
				sn.add_child(bar)
			var lbl := Label3D.new()
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.font_size = 24
			lbl.fixed_size = true    # feste Bildschirmgröße (≈ 14 px)
			lbl.pixel_size = 0.001
			lbl.outline_size = 6
			lbl.position = Vector3(0, 0.3, 0)
			lbl.name = "Text"
			sn.add_child(lbl)
			effect_root.add_child(sn)
			storage_nodes[sid] = sn
		sn.position = s.position
		var u := StorageSystem.used(ctx, s)
		(sn.get_node("Text") as Label3D).text = "%s #%d · %.1f/%.0f kg" % [s.label, s.id, float(u.get("kg", 0.0)), s.capacity_kg]
	for sid in storage_nodes.keys():
		if not ctx.storages.has(sid):
			storage_nodes[sid].queue_free()
			storage_nodes.erase(sid)
	for bid in ctx.structures:
		var st: Structure = ctx.structures[bid]
		var bn: Node3D = site_nodes.get(bid, null)
		if bn == null or int(bn.get_meta("slots", -1)) != st.slots.size():
			if bn != null:
				bn.queue_free()
			bn = Node3D.new()
			bn.name = "Baustelle_%d" % bid
			bn.set_meta("slots", st.slots.size())
			for i in st.slots.size():
				var mk := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.07
				cm.bottom_radius = 0.07
				cm.height = 0.008
				mk.mesh = cm
				mk.material_override = StandardMaterial3D.new()
				mk.name = "Platz_%d" % i
				bn.add_child(mk)
			var lb := Label3D.new()
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.font_size = 24
			lb.fixed_size = true     # feste Bildschirmgröße (≈ 14 px)
			lb.pixel_size = 0.001
			lb.outline_size = 6
			lb.name = "Text"
			bn.add_child(lb)
			effect_root.add_child(bn)
			site_nodes[bid] = bn
		for i in st.slots.size():
			var mk2: MeshInstance3D = bn.get_node("Platz_%d" % i)
			mk2.position = StructureSystem.slot_world(st, i) + Vector3(0, 0.004, 0)
			var full := int(st.slots[i].get("part_id", 0)) != 0
			(mk2.material_override as StandardMaterial3D).albedo_color = Color(0.35, 0.75, 0.35) if full else Color(0.95, 0.85, 0.3)
		var lb2: Label3D = bn.get_node("Text")
		lb2.position = StructureSystem.slot_world(st, st.slots.size() / 2) + Vector3(0, 0.3, 0) if not st.slots.is_empty() else st.position + Vector3(0, 0.3, 0)
		lb2.text = "%s #%d · %d/%d · %s" % [st.label if st.label != "" else st.blueprint, st.id, st.filled(), st.slots.size(), st.status]
	for bid in site_nodes.keys():
		if not ctx.structures.has(bid):
			site_nodes[bid].queue_free()
			site_nodes.erase(bid)


func _update_light() -> void:
	var t := life.ctx.now()
	var l := life.ctx.day_night.light(t)
	_sun.rotation_degrees = life.ctx.day_night.sun_rotation_deg(t)
	_sun.light_energy = 0.05 + 1.0 * l
	_env.ambient_light_energy = 0.32 + 0.3 * l     # nachts gedimmt, aber beobachtbar (reine Darstellung)
	_env.background_color = Color(0.07, 0.09, 0.18).lerp(Color(0.55, 0.72, 0.88), l)


func _build_env() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.55, 0.72, 0.88)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.7, 0.72, 0.8)
	_env.ambient_light_energy = 0.55
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, -40, 0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)
	_marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.32
	tm.outer_radius = 0.4
	_marker.mesh = tm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1, 0.9, 0.2)
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = mm
	_marker.visible = false
	add_child(_marker)
	_item_mesh = SphereMesh.new()
	_item_mesh.radius = 0.05
	_item_mesh.height = 0.1
	_item_mesh.radial_segments = 8
	_item_mesh.rings = 4


# ── Auswahl ───────────────────────────────────────

func _on_pick(origin: Vector3, dir: Vector3, _additive: bool) -> void:
	if _god != null and _god.visible and _god.picking:
		var h := world.raycast(origin, dir, 200.0)
		if h["hit"]:
			_god.set_picked_position(origin + dir.normalized() * float(h["distance"]))
		else:
			_msg.text = "Kein Boden getroffen."
		return
	var best := 0
	var bd := 0.6
	for id in life.ctx.creatures:
		var cr: Creature = life.ctx.creatures[id]
		var c := cr.position + Vector3(0, 0.45, 0)
		var t := (c - origin).dot(dir)
		if t < 0.0:
			continue
		var d := (origin + dir * t).distance_to(c)
		if d < bd:
			bd = d
			best = id
	if best != 0:
		select(best)
		return
	# Gegenstände (Prompt 6): nächstes Objekt nahe am Strahl → Gegenstandsansicht
	var bo := 0
	var bdo := 0.25
	for id in piece_nodes:
		var p = life.ctx.position_of(id)
		if p == null:
			continue
		var c2: Vector3 = p + Vector3(0, 0.03, 0)
		var t2 := (c2 - origin).dot(dir)
		if t2 < 0.0:
			continue
		var d2 := (origin + dir * t2).distance_to(c2)
		if d2 < bdo:
			bdo = d2
			bo = id
	if bo != 0:
		_exp.object_id = bo
		_exp.visible = true
		_msg.text = "Gegenstand %s ausgewählt (Versuche/Gegenstand: Taste E)." % ConstructionSystem.label_of(life.ctx, bo)
		_refresh_ui()


func select(id: int) -> void:
	selected_id = id
	if _god != null:
		_god.selected_id = id
		_god.refresh_events()
		_god.refresh_preview()
	_refresh_ui()


func toggle_god_menu() -> void:
	_god.visible = not _god.visible
	if _god.visible:
		_god.selected_id = selected_id
		_god.refresh_events()
		_god.refresh_preview()


func toggle_compare() -> void:
	_compare.visible = not _compare.visible
	if _compare.visible and compare_id == 0:
		compare_id = selected_id


# ── Bedienung ─────────────────────────────────────

func toggle_pause() -> void:
	var p := not get_tree().paused
	sim.set_paused(p)                       # hält Uhr UND SceneTree an (Wasser, Bruchstücke)
	get_tree().paused = p
	_pause_btn.text = "▶ Weiter (Leertaste)" if p else "⏸ Pause (Leertaste)"
	_msg.text = "Pausiert – Kamera und Oberfläche bleiben bedienbar." if p else "Simulation läuft."


func do_save() -> void:
	var r := SaveManager.save(life, save_path)
	_msg.text = r["message"]


func do_load() -> void:
	if not FileAccess.file_exists(save_path):
		_msg.text = "Kein Spielstand vorhanden."
		return
	var check := SaveManager.read_file(save_path)
	if not check["ok"]:
		_msg.text = "Laden nicht möglich: " + str(check["message"])
		return
	pending = {"mode": "load", "path": save_path}
	Nav.go(get_tree(), SCENE)                # frische Szene → keine doppelte Registrierung


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			toggle_pause()
		KEY_F5:
			do_save()
		KEY_F9:
			do_load()
		KEY_G:
			toggle_god_menu()
		KEY_V:
			toggle_compare()
		KEY_K:
			toggle_ai_panel()
		KEY_E:
			_exp.visible = not _exp.visible
			_refresh_ui()
		KEY_W:
			_know.visible = not _know.visible
			_refresh_ui()
		KEY_C:
			toggle_conversations()
		KEY_F:
			if selected_id != 0 and life.ctx.creatures.has(selected_id):
				camera.focus_on(life.ctx.creatures[selected_id].position)


static func _ai_service() -> AIService:
	return ai_service_override if ai_service_override != null else AIService.shared()


func _dev_ai(kind: String) -> void:
	var cr := life.ctx.creature(selected_id)
	if cr == null:
		_msg.text = "Entwicklermodus: zuerst ein Wesen auswählen."
		return
	var r := life.ctx.ai.request_now(cr, kind)
	_msg.text = "[ENTWICKLERMODUS] " + str(r["message"])


func toggle_ai_panel() -> void:
	_ai_panel.visible = not _ai_panel.visible
	if _ai_panel.visible:
		_ai_panel.load_fields()
		_ai_panel.refresh()


func toggle_conversations() -> void:
	_conv.visible = not _conv.visible
	if _conv.visible:
		_conv.refresh(life, selected_id)
	if _exp.visible:
		_exp.refresh(life, selected_id)
	if _know.visible:
		_know.refresh(life, selected_id)
	_ws_panel.visible = not life.workshop.is_empty() and not life.workshop.has("work_scene")
	_work_panel.visible = life.workshop.has("work_scene")


func _dev(op: String, material_id: String = "wood") -> void:
	if selected_id == 0:
		_msg.text = "Entwicklermodus: zuerst ein Wesen auswählen."
		return
	var side := "l" if _side_opt.selected == 0 else "r"
	var r := life.dev_body_change(selected_id, op, side, material_id)
	_msg.text = "[ENTWICKLERMODUS] " + str(r.get("message", "ok" if r.get("ok", false) else "fehlgeschlagen"))
	_refresh_ui()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	# Kopfzeile
	var top := Nav.panel(root)
	top.offset_left = 10
	top.offset_top = 8
	var hb := HBoxContainer.new()
	top.add_child(hb)
	Nav.back_button(hb, self).text = "◀ Menü"
	_pause_btn = Nav.button(hb, "⏸ Pause (Leertaste)", toggle_pause)
	Nav.button(hb, "Speichern (F5)", do_save)
	Nav.button(hb, "Laden (F9)", do_load)
	_dev_btn = Nav.button(hb, "Entwicklermodus", func():
		life.ctx.dev_mode = not life.ctx.dev_mode
		_dev_panel.visible = life.ctx.dev_mode)
	_god_btn = Nav.button(hb, "Göttermenü (G)", toggle_god_menu)
	Nav.button(hb, "Vergleich (V)", toggle_compare)
	Nav.button(hb, "KI (K)", toggle_ai_panel)
	Nav.button(hb, "Gespräche (C)", toggle_conversations)
	Nav.button(hb, "Versuche (E)", func(): _exp.visible = not _exp.visible; _refresh_ui())
	Nav.button(hb, "Wissen (W)", func(): _know.visible = not _know.visible; _refresh_ui())
	_top_label = Nav.label(hb, "", 14, false)
	# Population links
	_population = PopulationPanel.new()
	root.add_child(_population)
	_population.position = Vector2(10, 56)
	_population.creature_selected.connect(select)
	# Inspektor rechts
	_inspector = CreatureInspector.new()
	root.add_child(_inspector)
	_inspector.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_inspector.offset_left = -410
	_inspector.offset_right = -10
	_inspector.offset_top = 56
	_inspector.offset_bottom = 640
	_inspector.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# Ereignisse unten
	_events = EventViewer.new()
	root.add_child(_events)
	_events.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_events.offset_left = 10
	_events.offset_top = -230
	_events.offset_bottom = -34
	_events.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Meldungszeile
	_msg = Label.new()
	_msg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_msg.offset_left = 12
	_msg.offset_top = -28
	_msg.offset_right = 1200
	_msg.add_theme_font_size_override("font_size", 13)
	_msg.modulate = Color(1, 0.95, 0.7)
	root.add_child(_msg)
	# Leistung
	_perf = PerformanceMonitor.new()
	root.add_child(_perf)
	_perf.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_perf.offset_left = -400
	_perf.offset_top = -70
	_perf.offset_right = -10
	_perf.offset_bottom = -8
	_perf.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_perf.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Entwicklermodus
	_dev_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.08, 0.05, 0.92)
	sb.border_color = Color(1, 0.5, 0.2)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	_dev_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_dev_panel)
	_dev_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dev_panel.offset_left = -820
	_dev_panel.offset_right = -420
	_dev_panel.offset_top = 56
	_dev_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dev_panel.visible = false
	var dv := VBoxContainer.new()
	_dev_panel.add_child(dv)
	Nav.label(dv, "ENTWICKLERMODUS – Testeingriffe, kein Spielinhalt", 14).modulate = Color(1, 0.7, 0.4)
	Nav.label(dv, "Wirkt auf das ausgewählte Wesen. Prothesen sind Entwicklungsobjekte; die Wesen stellen sie noch nicht her.", 11)
	var sr := HBoxContainer.new()
	dv.add_child(sr)
	Nav.label(sr, "Seite:", 12, false)
	_side_opt = OptionButton.new()
	_side_opt.add_item("links")
	_side_opt.add_item("rechts")
	_side_opt.focus_mode = Control.FOCUS_NONE
	sr.add_child(_side_opt)
	var g := GridContainer.new()
	g.columns = 2
	dv.add_child(g)
	Nav.button(g, "Unterarm entfernen", _dev.bind("remove_forearm"))
	Nav.button(g, "Bein verletzen", _dev.bind("injure_leg"))
	Nav.button(g, "Holzprothese anbringen", _dev.bind("attach_prosthesis", "wood"))
	Nav.button(g, "Kupferprothese anbringen", _dev.bind("attach_prosthesis", "copper"))
	Nav.button(g, "Blatt entfernen", _dev.bind("remove_leaf"))
	Nav.button(g, "Wesen töten (Test)", _dev.bind("kill"))
	Nav.button(g, "KI: Plan anfragen (Test)", _dev_ai.bind("plan"))
	Nav.button(g, "KI: Gespräch anfragen (Test)", _dev_ai.bind("talk"))
	_behavior_box = CheckBox.new()
	_behavior_box.text = "Verhalten des Wesens anhalten"
	_behavior_box.focus_mode = Control.FOCUS_NONE
	_behavior_box.toggled.connect(func(on):
		var cr := life.ctx.creature(selected_id)
		if cr != null:
			cr.behavior_enabled = not on)
	dv.add_child(_behavior_box)
	_refill_box = CheckBox.new()
	_refill_box.text = "TESTOPTION: Nahrung regelmäßig nachfüllen"
	_refill_box.focus_mode = Control.FOCUS_NONE
	_refill_box.toggled.connect(func(on):
		life.ctx.refill_enabled = on
		life.ctx.log_event("test_refill_toggled", [], {"enabled": on}, "warning"))
	dv.add_child(_refill_box)
	# Göttermenü
	_god = GodMenu.new()
	_god.life = life
	root.add_child(_god)
	_god.position = Vector2(330, 56)
	_god.visible = false
	# KI-Panel und Gesprächsansicht (Prompt 5)
	_ai_panel = AIStatusPanel.new()
	_ai_panel.service = _ai_service()
	root.add_child(_ai_panel)
	_ai_panel.position = Vector2(330, 56)
	_ai_panel.visible = false
	_conv = ConversationViewer.new()
	root.add_child(_conv)
	_conv.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_conv.offset_left = -280
	_conv.offset_right = 280
	_conv.offset_top = -560
	_conv.offset_bottom = -240
	_conv.visible = false
	# Versuche/Gegenstand und Wissen (Prompt 6)
	_exp = ExperimentInspector.new()
	root.add_child(_exp)
	_exp.position = Vector2(330, 56)
	_exp.visible = false
	_know = KnowledgeViewer.new()
	root.add_child(_know)
	_know.position = Vector2(650, 510)   # unten Mitte: neben der Ereignisliste (bis x ≈ 640), unter der Versuchsansicht
	_know.visible = false
	_build_workshop_panel(root)
	_build_work_panel(root)
	# Vergleichsansicht
	_compare = PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	cs.set_content_margin_all(8)
	_compare.add_theme_stylebox_override("panel", cs)
	root.add_child(_compare)
	_compare.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_compare.offset_left = -330
	_compare.offset_right = 330
	_compare.offset_top = -470
	_compare.offset_bottom = -240
	_compare.visible = false
	var cv := VBoxContainer.new()
	_compare.add_child(cv)
	var ch := HBoxContainer.new()
	cv.add_child(ch)
	Nav.label(ch, "Vergleich A ↔ B (B = ausgewähltes Wesen)", 13, false)
	Nav.button(ch, "Ausgewähltes als A", func(): compare_id = selected_id; _refresh_ui())
	var cols := HBoxContainer.new()
	cv.add_child(cols)
	for i in 2:
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.custom_minimum_size = Vector2(320, 190)
		rt.add_theme_font_size_override("normal_font_size", 11)
		cols.add_child(rt)
		if i == 0:
			_compare_a = rt
		else:
			_compare_b = rt


func _refresh_ui() -> void:
	if not start_ok:
		return
	var ctx := life.ctx
	var t := ctx.now()
	_top_label.text = "  Tag %d · %s · %s · Licht %.0f %%%s%s" % [ctx.day_night.day_number(t), ctx.day_night.clock_text(t), ctx.day_night.phase_name(t),
		ctx.day_night.light(t) * 100, "  · PAUSE" if get_tree().paused else "", "  · ENTWICKLERMODUS" if ctx.dev_mode else ""]
	_population.refresh(life, selected_id)
	_inspector.show_creature(life, selected_id)
	_events.refresh(sim, selected_id)
	_perf.refresh(life)
	_dev_panel.visible = ctx.dev_mode
	var cr := ctx.creature(selected_id)
	if cr != null:
		_behavior_box.set_pressed_no_signal(not cr.behavior_enabled)
	_refill_box.set_pressed_no_signal(ctx.refill_enabled)
	if _compare.visible:
		_compare_a.text = CreatureInspector.compact(ctx, compare_id, selected_id)
		_compare_b.text = CreatureInspector.compact(ctx, selected_id, compare_id)
	if _ai_panel.visible:
		_ai_panel.ai = ctx.ai
		_ai_panel.refresh()
	if _conv.visible:
		_conv.refresh(life, selected_id)
	if _exp.visible:
		_exp.refresh(life, selected_id)
	if _know.visible:
		_know.refresh(life, selected_id)
	_ws_panel.visible = not life.workshop.is_empty() and not life.workshop.has("work_scene")
	_work_panel.visible = life.workshop.has("work_scene")
	if _god.visible:
		_god.refresh_preview()
		_god_ev_accum += 1
		if _god_ev_accum >= 8:          # Ereignisliste alle ~2 s neu (Auswahl bleibt erhalten)
			_god_ev_accum = 0
			_god.refresh_events()



## Testwerkstatt-Bedienfeld (nur im Werkstatt-Modus sichtbar): gezielte Versuche 1–6.
func _build_workshop_panel(root: Control) -> void:
	_ws_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.05, 0.92)
	sb.set_content_margin_all(6)
	_ws_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_ws_panel)
	# links zwischen Populationsfeld (bis y ≈ 412) und Ereignisliste: überdeckt weder Wesenfenster (rechts),
	# Versuchsansicht (Mitte oben) noch Wissensansicht (Mitte unten)
	_ws_panel.position = Vector2(10, 416)
	_ws_panel.custom_minimum_size = Vector2(312, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	_ws_panel.add_child(v)
	Nav.label(v, "TESTWERKSTATT – gezielt ausgelöst (Wesen A)", 11, true)
	for n in [1, 2, 3, 4, 5, 6]:
		var k: int = n
		_small(Nav.button(v, TestWorkshop.LABELS[k], func():
			var r := TestWorkshop.trigger(life, k)
			_msg.text = str(r["message"])
			_exp.visible = true
			_refresh_ui()))
	_small(Nav.button(v, "B übt das Verbinden (nach 6)", func():
		var r2 := TestWorkshop.trigger_practice(life)
		_msg.text = str(r2["message"])
		_refresh_ui()))
	_small(Nav.button(v, "Beobachtungslauf: eigenes Verhalten an/aus", func():
		var on := false
		for id in life.ctx.creatures:
			var cr: Creature = life.ctx.creatures[id]
			cr.behavior_enabled = not cr.behavior_enabled
			on = cr.behavior_enabled
		_msg.text = "Eigenständiges Verhalten der Testwesen %s (Versuche nur aus eigenem Antrieb)." % ("AN" if on else "AUS – nur gezielte Versuche")))
	_ws_panel.visible = false


## Testszene Werkzeugkette (Prompt 6B): Ketten und Fehlerfälle gezielt auslösen. Alles läuft über
## dieselben Systeme wie im normalen Spiel; die Knöpfe richten nur die Ausgangslage ein.
func _build_work_panel(root: Control) -> void:
	_work_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.1, 0.12, 0.93)
	sb.set_content_margin_all(6)
	_work_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_work_panel)
	_work_panel.position = Vector2(10, 416)
	_work_panel.custom_minimum_size = Vector2(610, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	_work_panel.add_child(v)
	Nav.label(v, "WERKZEUGKETTE – gezielt ausgelöst (Testwesen) · links Ketten, rechts Fehlerfälle", 11, true)
	# zwei Spalten, damit das Feld die Ereignisliste unten links nicht verdeckt
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 1)
	v.add_child(grid)
	# Knöpfe: [kurze Beschriftung, Aufruf, ausführlicher Hinweis]
	var left: Array = []
	for goal in ["lagern", "bauen", "schmelzen"]:
		var g: String = goal
		left.append([WorkChainScene.GOAL_BUTTONS[g], func():
			var r := WorkChainScene.trigger(life, g)
			_msg.text = str(r.get("message", ""))
			_refresh_ui(), WorkChainScene.GOALS[g]])
	left.append(["Speichern (F5) · Laden (F9) setzt fort", func(): do_save(), "Speichern mitten in der Kette; nach dem Laden (F9) wird die Kette beim nächsten offenen Schritt fortgesetzt"])
	var right: Array = []
	for case in ["material", "weg", "arm", "schwer", "unterbrechen", "ungeeignet", "ohne_ofen"]:
		var c: String = case
		right.append([WorkChainScene.CASE_BUTTONS[c], func():
			var r2 := WorkChainScene.trigger_case(life, c)
			_msg.text = str(r2.get("message", ""))
			_refresh_ui(), WorkChainScene.CASES[c]])
	for i in maxi(left.size(), right.size()):
		for col in [left, right]:
			if i < (col as Array).size():
				var b := Nav.button(grid, str(col[i][0]), col[i][1])
				_small(b)
				b.custom_minimum_size = Vector2(300, 21)
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.clip_text = true
				b.tooltip_text = str(col[i][2])
			else:
				grid.add_child(Control.new())
	_small(Nav.button(v, "Beobachtungslauf: eigenes Verhalten an/aus (autonom)", func():
		var on := false
		for id in life.ctx.creatures:
			var cr: Creature = life.ctx.creatures[id]
			cr.behavior_enabled = not cr.behavior_enabled
			on = cr.behavior_enabled
		_msg.text = "Eigenständiges Verhalten %s – Ketten nur noch aus eigenem Bedarf (Anzeige „autonom“)." % ("AN" if on else "AUS")))
	_work_panel.visible = false


func _small(b: Button) -> void:
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(0, 22)
	b.clip_text = true
