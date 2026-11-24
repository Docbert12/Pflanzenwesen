class_name CreatureAnimator
extends RefCounted
## Prozedurale Animationen für den definierten Zweibeiner (KR002), gesteuert über Gelenkpunkte.
## Unterstützt: idle (Excel A001), walk (A002), grasp (≈ A003), eat = „zum Mund führen“ (≈ A004),
## raise_arms = „Arme heben“ (Prompt 4, neutrale Ausdruckshandlung; nur vorhandene Oberarme).
## Bewegt werden ausschließlich Gelenke, die in der Darstellung existieren – also nur wirksam
## vorhandene Körperteile. Fehlt ein benötigter Teil, wird die Animation verständlich abgelehnt
## oder auf ein ausdrücklich unterstütztes Ersatzverhalten umgestellt (andere Hand, Hakengriff).
## Keine universelle Animation beliebiger Körperformen.

const ANIMS := ["idle", "walk", "grasp", "eat", "raise_arms"]
const RAISE_PERIOD := 3.0
const WALK_PERIOD := 1.2   # Excel A002 Dauer_Sek
const GRASP_PERIOD := 1.6
const EAT_PERIOD := 1.5    # Excel A004 Dauer_Sek

var view: CreatureView
var state: String = "idle"
var side: String = "r"
var t: float = 0.0
var message: String = ""
var phase_offset: float = 0.0
var _touched: Dictionary = {}


func bind(v: CreatureView) -> void:
	view = v
	# Nach einem Umbau prüfen, ob die laufende Animation noch möglich ist
	var r := request(state, side)
	if not r["ok"]:
		state = "idle"


## Fordert eine Animation an. Rückgabe {"ok", "message", "side"}.
func request(anim: String, wanted_side: String = "r") -> Dictionary:
	if not anim in ANIMS:
		return _deny("Unbekannte Animation '%s'." % anim)
	var caps := view.plan.capabilities()
	match anim:
		"idle":
			pass
		"walk":
			if not caps["walk"]:
				return _deny("Gehen nicht möglich: ein Bein ist nicht vollständig vorhanden. Hinken (Excel A002 Sonderfall) ist nicht implementiert.")
		"grasp":
			var s := _pick_side(caps["grasp"], wanted_side, ["hand", "hook"])
			if s == "":
				return _deny("Greifen nicht möglich: keine Hand und keine Hakenprothese vorhanden.")
			var how: String = caps["grasp"][s]
			message = "Greifen mit %s %s%s" % ["linker" if s == "l" else "rechter", "Hand" if how == "hand" else "Hakenprothese (Ersatz: Hakengriff, ohne Fingerbewegung)",
				" (Ersatz: gewünschte Seite nicht verfügbar)" if s != wanted_side else ""]
			wanted_side = s
		"eat":
			var s2 := _pick_side(caps["grasp"], wanted_side, ["hand"])
			if s2 == "":
				return _deny("Zum Mund führen nicht möglich: keine Hand vorhanden (Prothesen unterstützen diese Bewegung nicht).")
			message = "Zum Mund führen mit %s Hand%s" % ["linker" if s2 == "l" else "rechter", " (Ersatz: andere Hand)" if s2 != wanted_side else ""]
			wanted_side = s2
	if anim == "raise_arms":
		if not view.pivots.has("arm_l_upper") and not view.pivots.has("arm_r_upper"):
			return _deny("Arme heben nicht möglich: kein Oberarm vorhanden.")
		message = "Arme heben (vorhandene Arme)"
	if anim == "idle":
		message = "Ruhehaltung"
	elif anim == "walk":
		message = "Gehen (auf der Stelle, keine Fortbewegung in der Welt)"
	state = anim
	side = wanted_side
	t = 0.0
	return {"ok": true, "message": message, "side": side}


func _pick_side(grasp: Dictionary, wanted: String, allowed: Array) -> String:
	if grasp.get(wanted, "") in allowed:
		return wanted
	var other := "l" if wanted == "r" else "r"
	if grasp.get(other, "") in allowed:
		return other
	return ""


func _deny(msg: String) -> Dictionary:
	message = msg
	return {"ok": false, "message": msg, "side": side}


## IDs der Körperteile, deren Gelenke im letzten update() bewegt wurden.
func used_part_ids() -> Array:
	return _touched.keys()


func update(delta: float) -> void:
	if view == null:
		return
	t += delta
	_touched.clear()
	_reset_pose()
	var tt := t + phase_offset
	# Grundbewegung: Atmen + Blattbewegung (immer)
	var breathe := sin(tt * TAU / 3.2)
	_rot("torso", Vector3(0.015 * breathe, 0, 0))
	var li := 0
	for pid in view.plan.leaf_ids():
		_rot(pid, Vector3(0.05 * sin(tt * 2.1 + li), 0, 0.07 * sin(tt * 1.7 + li * 1.3)))
		li += 1
	for s in ["l", "r"]:
		var sx := -1.0 if s == "l" else 1.0
		_rot("arm_%s_upper" % s, Vector3(0.04 * breathe, 0, sx * 0.1))
	match state:
		"walk":
			var ph := tt * TAU / WALK_PERIOD
			for s in ["l", "r"]:
				var sg := 1.0 if s == "l" else -1.0
				var swing := sin(ph) * sg
				_rot("leg_%s_upper" % s, Vector3(-0.5 * swing, 0, 0))
				_rot("leg_%s_lower" % s, Vector3(0.75 * maxf(0.0, sin(ph * 1.0 + (0.0 if s == "l" else PI) + PI * 0.5)), 0, 0))
				_rot("foot_%s" % s, Vector3(-0.2 * swing, 0, 0))
				_rot("arm_%s_upper" % s, Vector3(0.38 * swing, 0, 0))
				_rot(_lower_arm(s), Vector3(-0.25, 0, 0))
			view.hips.position.y = float(view.plan.genes.get("stand_height_m", 0.35)) - 0.012 * absf(sin(ph))
			_rot("head", Vector3(0.03 * sin(ph * 2.0), 0, 0))
		"grasp":
			var k := _pulse(t, GRASP_PERIOD)
			_rot("arm_%s_upper" % side, Vector3(-1.15 * k, 0, 0))
			_rot(_lower_arm(side), Vector3(-0.35 * k, 0, 0))
			if view.pivots.has("hand_%s" % side):
				_rot("hand_%s" % side, Vector3(0.3 * k, 0, 0))
				(view.pivots["hand_%s" % side] as Node3D).scale = Vector3(1.0 - 0.18 * k, 1.0, 1.0 + 0.1 * k)
			_rot("torso", Vector3(0.12 * k, 0, 0))
			_rot("head", Vector3(0.18 * k, 0, 0))
		"eat":
			var k2 := _pulse(t, EAT_PERIOD)
			var sx2 := -1.0 if side == "l" else 1.0
			_rot("arm_%s_upper" % side, Vector3(-1.05 * k2, 0, -sx2 * 0.42 * k2))
			_rot(_lower_arm(side), Vector3(-1.95 * k2, 0, 0))
			_rot("hand_%s" % side, Vector3(-0.3 * k2, 0, 0))
			_rot("head", Vector3(0.12 * k2, 0, 0))
		"raise_arms":
			var k3 := smoothstep(0.0, 0.25, fmod(t, RAISE_PERIOD) / RAISE_PERIOD) * (1.0 - smoothstep(0.8, 1.0, fmod(t, RAISE_PERIOD) / RAISE_PERIOD))
			for s3 in ["l", "r"]:
				var sx3 := -1.0 if s3 == "l" else 1.0
				_rot("arm_%s_upper" % s3, Vector3(-2.6 * k3, 0, sx3 * 0.35 * k3))
				_rot(_lower_arm(s3), Vector3(-0.2 * k3, 0, 0))
			_rot("head", Vector3(-0.25 * k3, 0, 0))
	if state != "walk":
		view.hips.position.y = float(view.plan.genes.get("stand_height_m", 0.35))


func _lower_arm(s: String) -> String:
	if view.pivots.has("arm_%s_lower" % s):
		return "arm_%s_lower" % s
	for pid in view.pivots:
		if view.plan.parts[pid]["type"] == "prosthesis" and view.plan.parts[pid]["side"] == s:
			return pid
	return ""


## 0 → 1 → (halten) → 0 über eine Periode, weich.
static func _pulse(time: float, period: float) -> float:
	var f := fmod(time, period) / period
	if f < 0.35:
		return smoothstep(0.0, 0.35, f)
	if f < 0.65:
		return 1.0
	return 1.0 - smoothstep(0.65, 1.0, f)


func _reset_pose() -> void:
	for pid in view.pivots:
		var n: Node3D = view.pivots[pid]
		n.rotation = n.get_meta("rest_rotation", Vector3.ZERO)
		n.scale = Vector3.ONE


func _rot(pid: String, r: Vector3) -> void:
	if pid == "" or not view.pivots.has(pid):
		return   # Teil nicht vorhanden → wird nicht bewegt
	var n: Node3D = view.pivots[pid]
	n.rotation += r
	_touched[pid] = true
