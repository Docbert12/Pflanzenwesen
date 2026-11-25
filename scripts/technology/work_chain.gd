class_name WorkChain
extends RefCounted
## Eine Arbeitskette eines Wesens (Prompt 6B): Ziel aus eigenem Bedarf oder gezielt ausgelöst,
## Schritte, Fortschritt, getragene/transportierte Menge, Abbruchgrund. Reine Daten; die Logik liegt
## in WorkSystem. Jeder Schritt läuft über den ActionExecutor (keine direkte Weltänderung).

var id: int = 0
var actor_id: int = 0
var goal: String = ""            # lagern | bauen | schmelzen
var goal_text: String = ""
var source: String = ""          # eigener Bedarf | gezielt ausgelöst (Testszene) | Modell (Ollama) | Modell (SIMULIERT)
var autonomous: bool = false     # aus eigener Entscheidung des Wesens gestartet
var status: String = "läuft"     # läuft | pausiert | abgeschlossen | fehlgeschlagen | abgebrochen
var steps: Array = []            # [{op, obj?, target?, dest?, mode?, status, note, …}]
var step_i: int = 0
var tool_id: int = 0             # benutztes bzw. hergestelltes Werkzeug (Verbund-ID)
var target_id: int = 0           # bearbeiteter Gegenstand (z. B. Steinblock, Kupferstück)
var dest_id: int = 0             # Lager / Bauwerk / Tiegel
var current_obj: int = 0         # gerade bearbeitetes oder getragenes Objekt (Anzeige)
var produced: Array = []         # Bruchstücke aus eigener Bearbeitung
var delivered: Array = []        # abgelieferte Stücke (eingelagert / verbaut / in den Tiegel gelegt)
var moved_kg: float = 0.0        # tatsächlich abgelieferte Masse
var rejected: Array = []         # [{id, reason}] – ungeeignete Stücke mit Grund
var replans: int = 0
var pending_action: int = 0      # ID der zuletzt angeforderten Handlung dieser Kette
var abort_reason: String = ""
var pause_reason: String = ""
var paused_t: float = -1.0
var started_t: float = 0.0
var ended_t: float = -1.0
var resumed_after_load: bool = false
var log: Array = []              # [{t, text}]
var result: Dictionary = {}
var knowledge: Array = []        # verbuchte Verfahrensschlüssel


func add_log(t: float, text: String) -> void:
	log.append({"t": snappedf(t, 0.01), "text": text})
	while log.size() > 60:
		log.pop_front()


func current_step() -> Dictionary:
	return steps[step_i] if step_i >= 0 and step_i < steps.size() else {}


func is_open() -> bool:
	return status == "läuft" or status == "pausiert"


func to_dict() -> Dictionary:
	return {"id": id, "actor_id": actor_id, "goal": goal, "goal_text": goal_text, "source": source, "autonomous": autonomous,
		"status": status, "steps": steps.duplicate(true), "step_i": step_i, "tool_id": tool_id, "target_id": target_id,
		"dest_id": dest_id, "current_obj": current_obj, "produced": produced.duplicate(), "delivered": delivered.duplicate(),
		"moved_kg": moved_kg, "rejected": rejected.duplicate(true), "replans": replans, "pending_action": pending_action,
		"abort_reason": abort_reason, "pause_reason": pause_reason, "paused_t": paused_t, "started_t": started_t,
		"ended_t": ended_t, "resumed_after_load": resumed_after_load, "log": log.duplicate(true), "result": result.duplicate(true),
		"knowledge": knowledge.duplicate()}


static func from_dict(d: Dictionary) -> WorkChain:
	var w := WorkChain.new()
	w.id = int(d["id"])
	w.actor_id = int(d["actor_id"])
	w.goal = str(d.get("goal", ""))
	w.goal_text = str(d.get("goal_text", ""))
	w.source = str(d.get("source", ""))
	w.autonomous = bool(d.get("autonomous", false))
	w.status = str(d.get("status", "läuft"))
	w.steps = d.get("steps", []).duplicate(true)
	w.step_i = int(d.get("step_i", 0))
	w.tool_id = int(d.get("tool_id", 0))
	w.target_id = int(d.get("target_id", 0))
	w.dest_id = int(d.get("dest_id", 0))
	w.current_obj = int(d.get("current_obj", 0))
	for x in d.get("produced", []):
		w.produced.append(int(x))
	for x in d.get("delivered", []):
		w.delivered.append(int(x))
	w.moved_kg = float(d.get("moved_kg", 0.0))
	w.rejected = d.get("rejected", []).duplicate(true)
	w.replans = int(d.get("replans", 0))
	w.pending_action = int(d.get("pending_action", 0))
	w.abort_reason = str(d.get("abort_reason", ""))
	w.pause_reason = str(d.get("pause_reason", ""))
	w.paused_t = float(d.get("paused_t", -1.0))
	w.started_t = float(d.get("started_t", 0.0))
	w.ended_t = float(d.get("ended_t", -1.0))
	w.resumed_after_load = bool(d.get("resumed_after_load", false))
	w.log = d.get("log", []).duplicate(true)
	w.result = d.get("result", {}).duplicate(true)
	for k in d.get("knowledge", []):
		w.knowledge.append(str(k))
	return w
