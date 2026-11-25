class_name CreatureAnimator
extends RefCounted
## Prozedurale Animationen für den definierten Zweibeiner (KR002), gesteuert über Gelenkpunkte.
## Unterstützt: idle (Excel A001), walk (A002), grasp (≈ A003), eat = „zum Mund führen“ (≈ A004),
## raise_arms = „Arme heben“ (Prompt 4, neutrale Ausdruckshandlung; nur vorhandene Oberarme).
## Prompt 6B – antriebsgesteuerte Arbeitsposen (Phase und Fortschritt kommen aus der laufenden Handlung,
## a.state["anim"]; die Animation liest nur und löst nie selbst eine Wirkung aus):
##   walk_short (Anlauf zum Arbeitsplatz), carry / carry_two (halten bzw. mit zwei Händen aufnehmen und
##   tragen), grasp (Werkzeug/Stück greifen), put_down(_two) (ablegen), place(_two) (einsetzen in Lager,
##   Bauwerk, Gefäß), strike (Ausholen → Kontakt → Rückkehr), assemble / assemble_one (verbinden, auch
##   einarmig), operate_heater (Testofen beschicken), pour (gießen).
##   dig / compact sind als Namen vorbereitet, werden aber abgewiesen (keine Grab-/Verdichtungshandlung).
## Die Gelenkwinkel der Arbeitsposen folgen WorkPose – derselben Geometrie, mit der die Handlungen den
## Standpunkt wählen. Bewegt werden ausschließlich Gelenke, die in der Darstellung existieren. Fehlt ein
## benötigter Teil, wird die Animation verständlich abgelehnt oder auf ein ausdrücklich unterstütztes
## Ersatzverhalten umgestellt (andere Hand, Hakengriff, einarmige Variante).
## Keine universelle Animation beliebiger Körperformen.

const ANIMS := ["idle", "walk", "grasp", "eat", "raise_arms",
	"walk_short", "carry", "carry_two", "put_down", "put_down_two", "place", "place_two", "strike",
	"assemble", "assemble_one", "operate_heater", "pour", "dig", "compact"]
## Arbeitsposen (Prompt 6B); "grasp" ist zusätzlich arbeitsgesteuert, sobald Antriebsdaten vorliegen.
const WORK_ANIMS := ["walk_short", "carry", "carry_two", "put_down", "put_down_two", "place", "place_two", "strike",
	"assemble", "assemble_one", "operate_heater", "pour"]
const TWO_HAND_ANIMS := ["carry_two", "put_down_two", "place_two", "assemble"]
const PREPARED_ONLY := {
	"dig": "Graben ist als Pose vorbereitet, aber nicht freigegeben: es gibt noch keine Grabhandlung (Weltarchitektur-Zusatz).",
	"compact": "Verdichten ist als Pose vorbereitet, aber nicht freigegeben: es gibt noch keine Verdichtungshandlung (Weltarchitektur-Zusatz).",
}
const RAISE_PERIOD := 3.0
const WALK_PERIOD := 1.2   # Excel A002 Dauer_Sek
const GRASP_PERIOD := 1.6
const EAT_PERIOD := 1.5    # Excel A004 Dauer_Sek
const BLEND_S := 0.3       # Zurückblenden nach Ende/Abbruch einer Arbeitspose
const ASSEMBLE_HZ := 1.4
const DEMO_PERIOD := 2.4   # Vorführung ohne Handlung (Vorschau)

var view: CreatureView
var state: String = "idle"
var side: String = "r"
var t: float = 0.0
var message: String = ""
var phase_offset: float = 0.0
## Antrieb (Prompt 6B): a.state["anim"] der laufenden Handlung (nur lesend). Leer → Vorführung.
var drive_data: Dictionary = {}
## Von der Darstellung im Körperrahmen berechnet: target_local (Vector3 oder null), tool_h, hold_mode, moving.
var drive_info: Dictionary = {}
## Zuletzt angewandte Arbeitsparameter {phi, crouch, walk, arms:{s:{alpha, beta, splay}}} (Tests, HUD).
var last_params: Dictionary = {}
var _touched: Dictionary = {}
var _contact_cache: Dictionary = {}
var _blend: Dictionary = {}


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
	if PREPARED_ONLY.has(anim):
		return _deny(str(PREPARED_ONLY[anim]))
	var caps := view.plan.capabilities()
	match anim:
		"idle":
			pass
		"walk", "walk_short":
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
	if anim in WORK_ANIMS and anim != "walk_short":
		var n := 0
		for k in caps["grasp"]:
			if str(caps["grasp"][k]) in ["hand", "hook"]:
				n += 1
		if anim in TWO_HAND_ANIMS:
			if n < 2:
				return _deny("%s braucht zwei greiffähige Hände (vorhanden: %d)." % [_label(anim), n])
			message = "%s mit beiden Händen" % _label(anim)
		else:
			var s3 := _pick_side(caps["grasp"], wanted_side, ["hand", "hook"])
			if s3 == "":
				return _deny("%s nicht möglich: keine Hand und keine Hakenprothese vorhanden." % _label(anim))
			message = "%s mit %s %s%s" % [_label(anim), "linker" if s3 == "l" else "rechter", "Hand" if caps["grasp"][s3] == "hand" else "Hakenprothese",
				" (einarmige Variante)" if anim == "assemble_one" else ""]
			wanted_side = s3
	if anim == "raise_arms":
		if not view.pivots.has("arm_l_upper") and not view.pivots.has("arm_r_upper"):
			return _deny("Arme heben nicht möglich: kein Oberarm vorhanden.")
		message = "Arme heben (vorhandene Arme)"
	if anim == "idle":
		message = "Ruhehaltung"
	elif anim == "walk":
		message = "Gehen (auf der Stelle, keine Fortbewegung in der Welt)"
	elif anim == "walk_short":
		message = "Anlauf zum Arbeitsplatz"
	# Ende einer Arbeitspose → kontrolliert zurückblenden (auch bei Abbruch)
	if _is_working() and not (anim in WORK_ANIMS) and not last_params.is_empty():
		_blend = {"from": last_params.duplicate(true), "t": 0.0}
	if anim != state:
		_contact_cache.clear()
	state = anim
	side = wanted_side
	t = 0.0
	return {"ok": true, "message": message, "side": side}


static func _label(anim: String) -> String:
	return {"carry": "Tragen", "carry_two": "Aufnehmen/Tragen", "put_down": "Ablegen", "put_down_two": "Ablegen",
		"place": "Einsetzen", "place_two": "Einsetzen", "strike": "Schlagen", "assemble": "Verbinden",
		"assemble_one": "Verbinden", "operate_heater": "Ofen beschicken", "pour": "Gießen", "grasp": "Greifen"}.get(anim, anim)


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


func _is_working() -> bool:
	return state in WORK_ANIMS or (state == "grasp" and not drive_data.is_empty())


func update(delta: float) -> void:
	if view == null:
		return
	t += delta
	_touched.clear()
	_reset_pose()
	var tt := t + phase_offset
	var working := _is_working()
	# Grundbewegung: Atmen + Blattbewegung (immer)
	var breathe := sin(tt * TAU / 3.2)
	if not working:
		_rot("torso", Vector3(0.015 * breathe, 0, 0))
	var li := 0
	for pid in view.plan.leaf_ids():
		_rot(pid, Vector3(0.05 * sin(tt * 2.1 + li), 0, 0.07 * sin(tt * 1.7 + li * 1.3)))
		li += 1
	for s in ["l", "r"]:
		var sx := -1.0 if s == "l" else 1.0
		_rot("arm_%s_upper" % s, Vector3(0.04 * breathe, 0, sx * 0.1))
	var stand := float(view.plan.genes.get("stand_height_m", 0.35))
	view.hips.position.y = stand
	match state:
		"walk":
			_walk_cycle(tt, {})
		"grasp":
			if working:
				_update_work(tt)
			else:
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
		_:
			if working:
				_update_work(tt)
	if not working and not _blend.is_empty():
		_apply_blend(delta, tt)


# ── Arbeitsposen (Prompt 6B) ─────────────────────────

## Pose aus Antriebsdaten (oder Vorführung) berechnen und anwenden.
func _update_work(tt: float) -> void:
	_blend.clear()
	var d := drive_data
	var inf := drive_info
	if d.is_empty():
		var demo := _demo()
		d = demo["d"]
		inf = demo["info"]
	var phase := str(d.get("phase", "hold"))
	var u := clampf(float(d.get("u", 0.0)), 0.0, 1.0)
	var b := WorkPose.body(view.plan, side)
	var h := float(inf.get("tool_h", 0.0))
	var tl = inf.get("target_local", null)
	var hold := _hold_params(str(inf.get("hold_mode", "")))
	var moving := bool(inf.get("moving", false))
	var P := hold
	if state in ["walk_short", "carry"] or phase in ["approach", "hold"]:
		# Anlauf, Tragen, Halten: Haltung je nach Gehaltenem, Beine gehen, wenn sich das Wesen bewegt
		P = hold.duplicate(true)
		P["walk"] = moving
		_apply_params(P, tt)
		return
	match state:
		"grasp", "carry_two", "put_down", "put_down_two", "place", "place_two":
			var two := state in TWO_HAND_ANIMS
			var cp := _contact(b, 0.0, tl, "place", phase)
			var C := _params_from(cp, two)
			match phase:
				"prepare":
					P = _lerp_params(hold, C, _smooth(u))
				"work", "contact":
					P = C
					if state == "grasp" and view.pivots.has("hand_%s" % side):
						(view.pivots["hand_%s" % side] as Node3D).scale = Vector3(1.0 - 0.18 * _smooth(u), 1.0, 1.0 + 0.1 * _smooth(u))
				_:
					P = _lerp_params(C, hold, _smooth(u))
		"strike":
			var cps := _contact(b, h, tl, "strike", phase)
			var Cs := _params_from(cps, false)
			var W := _params_from(WorkPose.windup(cps), false)
			var R := _params_from(WorkPose.rest_hold(), false)
			match phase:
				"work":
					var start := Cs if int(d.get("contacts", 0)) > 0 else R
					if u < 0.6:
						P = _lerp_params(start, W, _smooth(u / 0.6))
					else:
						var k := (u - 0.6) / 0.4
						P = _lerp_params(W, Cs, k * k)   # beschleunigter Abschwung bis zum Kontakt
				"contact":
					P = Cs
				_:
					P = _lerp_params(Cs, R, _smooth(u))
		"assemble", "assemble_one":
			var two2 := state == "assemble"
			var cpa := _contact(b, 0.0, tl, "place", phase)
			var Ca := _params_from(cpa, two2)
			match phase:
				"prepare":
					P = _lerp_params(hold, Ca, _smooth(u))
				"work", "contact":
					P = Ca.duplicate(true)
					var amp := 0.16 if two2 else 0.24   # einarmig: größere Wickelbewegung einer Hand
					for s in (P["arms"] as Dictionary):
						var off := 0.0 if s == side else PI
						var arm: Dictionary = P["arms"][s]
						arm["alpha"] = float(arm["alpha"]) + amp * sin(tt * TAU * ASSEMBLE_HZ + off)
						arm["beta"] = float(arm["beta"]) + amp * 1.6 * cos(tt * TAU * ASSEMBLE_HZ + off)
				_:
					P = _lerp_params(Ca, hold, _smooth(u))
		"operate_heater":
			var cpo := _contact(b, h, tl, "place", phase)
			var Co := _params_from(cpo, false)
			if u < 0.35:
				P = _lerp_params(hold, Co, _smooth(u / 0.35))
			elif u < 0.65:
				P = Co
			else:
				P = _lerp_params(Co, hold, _smooth((u - 0.65) / 0.35))
		"pour":
			var cpp := _contact(b, h, tl, "pour", phase)
			var Cp := _params_from(cpp, false)
			if u < 0.15:
				P = _lerp_params(hold, Cp, _smooth(u / 0.15))
			else:
				P = Cp.duplicate(true)
				var tilt := 0.9 * _smooth((u - 0.15) / 0.45) * (1.0 - _smooth((u - 0.85) / 0.15))
				var arm2: Dictionary = P["arms"][side]
				arm2["beta"] = float(arm2["beta"]) + tilt   # Gefäß kippen
	_apply_params(P, tt)


## Haltung abhängig davon, was gehalten wird ("" nichts, "one" eine Hand, "two" beide Hände).
func _hold_params(hold_mode: String) -> Dictionary:
	match hold_mode:
		"one":
			return _params_from(WorkPose.rest_hold(), false)
		"two":
			return _params_from(WorkPose.carry_two_hold(), true)
	return {"phi": 0.0, "crouch": 0.0, "walk": false, "arms": {}}


## Einarmige WorkPose-Pose → Parameter für eine (Arbeitsseite) oder beide Seiten.
func _params_from(pose: Dictionary, two: bool) -> Dictionary:
	var arm := {"alpha": float(pose["alpha"]), "beta": float(pose["beta"]), "splay": 0.0}
	var arms := {}
	if two:
		arms["l"] = arm.duplicate()
		arms["r"] = arm.duplicate()
	else:
		arms[side] = arm
	return {"phi": float(pose["phi"]), "crouch": float(pose["crouch"]), "walk": false, "arms": arms}


## Kontaktpose zum Ziel (Körperrahmen). In der Rückkehrphase gilt die zuletzt berechnete Pose (das Ziel
## kann dann schon in der Hand liegen oder zerbrochen sein).
func _contact(b: Dictionary, h: float, tl, kind: String, phase: String) -> Dictionary:
	var key := kind
	if phase == "recover" and _contact_cache.has(key):
		return _contact_cache[key]
	var ty := 0.05
	if tl != null:
		ty = (tl as Vector3).y
	elif _contact_cache.has(key):
		return _contact_cache[key]
	var cp := WorkPose.contact(b, h, ty, kind)
	_contact_cache[key] = cp
	return cp


static func _lerp_params(p: Dictionary, q: Dictionary, k: float) -> Dictionary:
	var kk := clampf(k, 0.0, 1.0)
	var arms := {}
	var pa: Dictionary = p.get("arms", {})
	var qa: Dictionary = q.get("arms", {})
	for s in ["l", "r"]:
		if not pa.has(s) and not qa.has(s):
			continue
		var a0: Dictionary = pa.get(s, _free_arm(s))
		var a1: Dictionary = qa.get(s, _free_arm(s))
		arms[s] = {"alpha": lerpf(float(a0["alpha"]), float(a1["alpha"]), kk), "beta": lerpf(float(a0["beta"]), float(a1["beta"]), kk),
			"splay": lerpf(float(a0.get("splay", 0.0)), float(a1.get("splay", 0.0)), kk)}
	return {"phi": lerpf(float(p.get("phi", 0.0)), float(q.get("phi", 0.0)), kk), "crouch": lerpf(float(p.get("crouch", 0.0)), float(q.get("crouch", 0.0)), kk),
		"walk": bool(q.get("walk", false)) if kk >= 0.5 else bool(p.get("walk", false)), "arms": arms}


static func _free_arm(s: String) -> Dictionary:
	return {"alpha": 0.0, "beta": WorkPose.neutral_beta(0.0), "splay": 0.1 * (-1.0 if s == "l" else 1.0)}


## Gelenkwinkel setzen: Rumpf φ, Hocke c über die Knie, Arme nach WorkPose (Ellbogen gestreckt, Beugung im
## Handgelenk bzw. am Haken), freie Arme hängen senkrecht, Beine gleichen die Rumpfneigung aus.
func _apply_params(P: Dictionary, tt: float) -> void:
	var phi := float(P.get("phi", 0.0))
	var c := float(P.get("crouch", 0.0))
	var stand := float(view.plan.genes.get("stand_height_m", 0.35))
	_set_rot("torso", Vector3(phi, 0, 0))
	var arms: Dictionary = P.get("arms", {})
	if bool(P.get("walk", false)):
		_walk_cycle(tt, arms)
		# Beine hängen am Rumpf: Neigung ausgleichen
		for s in ["l", "r"]:
			_rot("leg_%s_upper" % s, Vector3(-phi, 0, 0))
	else:
		view.hips.position.y = stand - c
		_crouch_legs(c, phi)
	for s in ["l", "r"]:
		var b := WorkPose.body(view.plan, s)
		if str(b["upper"]) == "":
			continue
		if arms.has(s):
			var arm: Dictionary = arms[s]
			var al := float(arm["alpha"])
			var ga := float(arm["beta"]) - WorkPose.GRIP_ANGLE
			_set_rot(str(b["upper"]), Vector3(al - phi, 0, float(arm.get("splay", 0.0))))
			if str(b["lower"]) != "":
				_set_rot(str(b["lower"]), Vector3.ZERO)
			if str(b["last"]) != "" and str(b["last"]) != str(b["upper"]) and str(b["last"]) != str(b["lower"]):
				_set_rot(str(b["last"]), Vector3(ga - al, 0, 0))
		elif not bool(P.get("walk", false)):
			# freier Arm hängt senkrecht trotz Rumpfneigung
			_rot(str(b["upper"]), Vector3(-phi, 0, 0))
	_rot("head", Vector3(-0.3 * phi, 0, 0))
	last_params = P.duplicate(true)


## Knie beugen, damit die Füße trotz Hocke c am Boden bleiben (Oberschenkel nach vorn, Unterschenkel zurück).
func _crouch_legs(c: float, phi: float) -> void:
	var lu := 0.0
	var ll := 0.0
	for s in ["l", "r"]:
		if view.plan.is_present("leg_%s_upper" % s):
			lu = maxf(lu, float(view.plan.parts["leg_%s_upper" % s]["size"][1]))
		if view.plan.is_present("leg_%s_lower" % s):
			ll = maxf(ll, float(view.plan.parts["leg_%s_lower" % s]["size"][1]))
	var th := 0.0
	if lu + ll > 1e-6 and c > 0.0:
		th = acos(clampf(1.0 - c / (lu + ll), 0.3, 1.0))
	for s in ["l", "r"]:
		_set_rot("leg_%s_upper" % s, Vector3(-phi - th, 0, 0))
		_set_rot("leg_%s_lower" % s, Vector3(2.0 * th, 0, 0))
		_set_rot("foot_%s" % s, Vector3(-th, 0, 0))


## Gehzyklus der Beine (und Armschwung der nicht haltenden Arme).
func _walk_cycle(tt: float, held_arms: Dictionary) -> void:
	var ph := tt * TAU / WALK_PERIOD
	for s in ["l", "r"]:
		var sg := 1.0 if s == "l" else -1.0
		var swing := sin(ph) * sg
		_rot("leg_%s_upper" % s, Vector3(-0.5 * swing, 0, 0))
		_rot("leg_%s_lower" % s, Vector3(0.75 * maxf(0.0, sin(ph * 1.0 + (0.0 if s == "l" else PI) + PI * 0.5)), 0, 0))
		_rot("foot_%s" % s, Vector3(-0.2 * swing, 0, 0))
		if not held_arms.has(s):
			_rot("arm_%s_upper" % s, Vector3(0.38 * swing, 0, 0))
			_rot(_lower_arm(s), Vector3(-0.25, 0, 0))
	view.hips.position.y = float(view.plan.genes.get("stand_height_m", 0.35)) - 0.012 * absf(sin(ph))
	_rot("head", Vector3(0.03 * sin(ph * 2.0), 0, 0))


## Nach Ende oder Abbruch einer Arbeitspose: aus der letzten Pose weich in die Ruhehaltung zurück.
func _apply_blend(delta: float, tt: float) -> void:
	_blend["t"] = float(_blend["t"]) + delta
	var k := float(_blend["t"]) / BLEND_S
	if k >= 1.0:
		_blend.clear()
		return
	var from: Dictionary = _blend["from"]
	var to := {"phi": 0.0, "crouch": 0.0, "walk": false, "arms": {}}
	for s in (from.get("arms", {}) as Dictionary):
		to["arms"][s] = _free_arm(s)
	var P := _lerp_params(from, to, _smooth(k))
	P["walk"] = state == "walk"
	if state == "walk":
		# Gehzyklus läuft schon (aus dem walk-Zweig); nur Rumpf und Arme zurückblenden
		var phi := float(P["phi"])
		_set_rot("torso", Vector3(phi, 0, 0))
		for s in ["l", "r"]:
			_rot("leg_%s_upper" % s, Vector3(-phi, 0, 0))
		for s in (P["arms"] as Dictionary):
			var b := WorkPose.body(view.plan, s)
			if str(b["upper"]) != "":
				var arm: Dictionary = P["arms"][s]
				_set_rot(str(b["upper"]), Vector3(float(arm["alpha"]) - phi, 0, float(arm["splay"])))
				if str(b["last"]) != str(b["upper"]) and str(b["last"]) != str(b["lower"]) and str(b["last"]) != "":
					_set_rot(str(b["last"]), Vector3(float(arm["beta"]) - WorkPose.GRIP_ANGLE - float(arm["alpha"]), 0, 0))
		return
	_apply_params(P, tt)


## Vorführung ohne Handlung (Vorschau-Werkzeug): Phase und Ziel werden zyklisch erzeugt.
func _demo() -> Dictionary:
	var f := fmod(t, DEMO_PERIOD) / DEMO_PERIOD
	var b := WorkPose.body(view.plan, side)
	var tl := Vector3(0.0 if state in TWO_HAND_ANIMS else float(b["sx"]), 0.06, 0.3)
	var d := {"pose": state, "phase": "work", "u": f, "contacts": 1}
	match state:
		"strike":
			d["phase"] = "work"
		"put_down", "put_down_two", "place", "place_two", "grasp", "carry_two", "assemble", "assemble_one":
			if f < 0.3:
				d["phase"] = "prepare"
				d["u"] = f / 0.3
			elif f < 0.7:
				d["phase"] = "work"
				d["u"] = (f - 0.3) / 0.4
			else:
				d["phase"] = "recover"
				d["u"] = (f - 0.7) / 0.3
	var hold := "two" if state in ["carry_two", "put_down_two", "place_two"] else ("one" if state in ["carry", "strike", "put_down", "place", "operate_heater", "pour"] else "")
	return {"d": d, "info": {"target_local": tl, "tool_h": 0.0, "hold_mode": hold, "moving": false}}


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


static func _smooth(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


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


## Gelenk exakt auf Ruhelage + r setzen (Arbeitsposen: kein Aufsummieren mit Atem/Abspreizen).
func _set_rot(pid: String, r: Vector3) -> void:
	if pid == "" or not view.pivots.has(pid):
		return
	var n: Node3D = view.pivots[pid]
	n.rotation = n.get_meta("rest_rotation", Vector3.ZERO) + r
	_touched[pid] = true


## Griffpunkt-Rahmen (Ursprung im Griff, +x Werkzeugachse) einer Seite relativ zur Ansicht. Für die
## Darstellung gehaltener Gegenstände und für die Kontaktprüfung in Tests. Kein Gelenk → leer (ok=false).
func grip_frame(s: String) -> Dictionary:
	var b := WorkPose.body(view.plan, s)
	var last := str(b["last"])
	if last == "" or not view.pivots.has(last) or str(b["grasp"]) == "":
		return {"ok": false}
	return {"ok": true, "xform": view.chain_transform(last) * WorkPose.tool_frame(b), "body": b}
