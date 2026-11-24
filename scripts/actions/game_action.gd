class_name GameAction
extends RefCounted
## Eine konkrete Handlung (Instanz). Reine Daten – serialisierbar.

var id: int = 0
var actor_id: int = 0
var type: String = ""
var target_id: int = 0
var target_pos = null            # Vector3 oder null
var params: Dictionary = {}
var required_caps: Array = []
var resource_needs: Dictionary = {}   # z. B. {"food_kg": 0.1}
var status: String = ActionDefinition.STATUS_PLANNED
var progress: float = 0.0
var elapsed_s: float = 0.0
var timeout_s: float = 30.0
var reservation_id: int = 0
var result_code: String = ""
var result_message: String = ""
var started_t: float = 0.0
var ended_t: float = -1.0
var consumed: Dictionary = {}      # tatsächlich bewegte Mengen (Bilanz)
var state: Dictionary = {}         # interner Ausführungszustand der Implementierung


func is_final() -> bool:
	return status in ActionDefinition.FINAL


func summary() -> String:
	var tgt := ""
	if target_id != 0:
		tgt = " → #%d" % target_id
	elif target_pos != null:
		tgt = " → (%.1f, %.1f)" % [target_pos.x, target_pos.z]
	return "%s%s [%s, %.0f %%]" % [type, tgt, status, progress * 100.0]


func to_dict() -> Dictionary:
	var st := state.duplicate(true)
	if st.has("path"):
		st.erase("path")   # Wege werden beim Laden neu geplant
	return {"id": id, "actor_id": actor_id, "type": type, "target_id": target_id,
		"target_pos": [target_pos.x, target_pos.y, target_pos.z] if target_pos != null else null,
		"params": params.duplicate(true), "required_caps": required_caps.duplicate(), "resource_needs": resource_needs.duplicate(),
		"status": status, "progress": progress, "elapsed_s": elapsed_s, "timeout_s": timeout_s,
		"reservation_id": reservation_id, "result_code": result_code, "result_message": result_message,
		"started_t": started_t, "ended_t": ended_t, "consumed": consumed.duplicate(true), "state": st}


static func from_dict(d: Dictionary) -> GameAction:
	var a := GameAction.new()
	a.id = int(d["id"])
	a.actor_id = int(d["actor_id"])
	a.type = str(d["type"])
	a.target_id = int(d.get("target_id", 0))
	var tp = d.get("target_pos", null)
	a.target_pos = Vector3(tp[0], tp[1], tp[2]) if tp != null else null
	a.params = d.get("params", {}).duplicate(true)
	a.required_caps = d.get("required_caps", []).duplicate()
	a.resource_needs = d.get("resource_needs", {}).duplicate()
	a.status = str(d["status"])
	a.progress = float(d.get("progress", 0.0))
	a.elapsed_s = float(d.get("elapsed_s", 0.0))
	a.timeout_s = float(d.get("timeout_s", 30.0))
	a.reservation_id = int(d.get("reservation_id", 0))
	a.result_code = str(d.get("result_code", ""))
	a.result_message = str(d.get("result_message", ""))
	a.started_t = float(d.get("started_t", 0.0))
	a.ended_t = float(d.get("ended_t", -1.0))
	a.consumed = d.get("consumed", {}).duplicate(true)
	a.state = d.get("state", {}).duplicate(true)
	return a
