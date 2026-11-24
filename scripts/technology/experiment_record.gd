class_name ExperimentRecord
extends RefCounted
## Ein Versuch eines Wesens (Prompt 6). Trennt strikt:
##   sim_*        – vollständige Simulationsdaten (exakte Temperaturen, Massen, Stauchung, Energie):
##                  SPIELERDIAGNOSE, als Debug-Wissen gekennzeichnet; das Wesen kennt sie nicht.
##   perceived_*  – was das Wesen ohne Messmittel bemerkt (Kategorien: „sichtbar flacher“, „glühend“ …).
## Ein Versuch ist nur dann Evidenz, wenn Schritte tatsächlich über das Handlungssystem ausgeführt wurden.

var id: int = 0
var actor_id: int = 0
var kind: String = ""                # inspect | strike | deform | connect | test_tool | cast | demonstrate | practice
var question: String = ""            # Fragestellung / erwartete Wirkung
var expected: String = ""
var source: String = "eigene Idee"   # eigene Idee | Verfahren | Modell (Ollama) | Modell (SIMULIERT) | Testwerkstatt (gezielt ausgelöst) | Übung | Vorführung
var hypothesis_id: int = 0
var procedure_key: String = ""
var learner_id: int = 0              # Vorführung: angesprochenes Wesen
var items: Array = []                # [{id, material, shape, mass_kg}]  (Simulation)
var sim_initial: Dictionary = {}     # id -> exakter Ausgangszustand (Debug)
var perceived_initial: Dictionary = {} # id -> wahrgenommene Kategorien
var proposed_steps: Array = []       # [{op, obj, target, tool, params}]
var executed_steps: Array = []       # [{i, op, action, status, code, message, t, data}]
var step_i: int = 0
var effort := {"duration_s": 0.0, "metabolic_j": 0.0, "mechanical_j": 0.0, "heater_j": 0.0, "strikes": 0}
var sim_results: Dictionary = {}     # exakte Endwerte (Debug)
var perceived_results: Array = []    # Beobachtungen des Wesens (Texte + Kategorien)
var failures: Array = []
var uncertainty: float = 0.8
var status: String = "laufend"       # laufend | abgeschlossen | fehlgeschlagen | abgebrochen | unterbrochen
var outcome: String = ""             # Erfolg | Fehlschlag | kein sichtbarer Effekt | ...
var started_t: float = 0.0
var ended_t: float = -1.0
var heater_j_start: float = 0.0
var waits: int = 0


func is_running() -> bool:
	return status == "laufend"


func to_dict() -> Dictionary:
	return {"id": id, "actor_id": actor_id, "kind": kind, "question": question, "expected": expected, "source": source,
		"hypothesis_id": hypothesis_id, "procedure_key": procedure_key, "learner_id": learner_id, "items": items.duplicate(true),
		"sim_initial": _keys_to_str(sim_initial), "perceived_initial": _keys_to_str(perceived_initial),
		"proposed_steps": proposed_steps.duplicate(true), "executed_steps": executed_steps.duplicate(true), "step_i": step_i,
		"effort": effort.duplicate(), "sim_results": sim_results.duplicate(true), "perceived_results": perceived_results.duplicate(true),
		"failures": failures.duplicate(true), "uncertainty": uncertainty, "status": status, "outcome": outcome,
		"started_t": started_t, "ended_t": ended_t, "heater_j_start": heater_j_start, "waits": waits}


static func _keys_to_str(d: Dictionary) -> Dictionary:
	var r := {}
	for k in d:
		r[str(k)] = d[k]
	return r


static func from_dict(d: Dictionary) -> ExperimentRecord:
	var e := ExperimentRecord.new()
	e.id = int(d["id"])
	e.actor_id = int(d["actor_id"])
	e.kind = str(d.get("kind", ""))
	e.question = str(d.get("question", ""))
	e.expected = str(d.get("expected", ""))
	e.source = str(d.get("source", ""))
	e.hypothesis_id = int(d.get("hypothesis_id", 0))
	e.procedure_key = str(d.get("procedure_key", ""))
	e.learner_id = int(d.get("learner_id", 0))
	e.items = d.get("items", []).duplicate(true)
	for k in d.get("sim_initial", {}):
		e.sim_initial[int(k)] = d["sim_initial"][k]
	for k in d.get("perceived_initial", {}):
		e.perceived_initial[int(k)] = d["perceived_initial"][k]
	e.proposed_steps = d.get("proposed_steps", []).duplicate(true)
	for s in e.proposed_steps:
		for f in ["obj", "target", "tool", "head", "fiber", "mold", "heater", "learner"]:
			if s.has(f):
				s[f] = int(s[f])
	e.executed_steps = d.get("executed_steps", []).duplicate(true)
	e.step_i = int(d.get("step_i", 0))
	e.effort = d.get("effort", e.effort).duplicate()
	e.sim_results = d.get("sim_results", {}).duplicate(true)
	e.perceived_results = d.get("perceived_results", []).duplicate(true)
	e.failures = d.get("failures", []).duplicate(true)
	e.uncertainty = float(d.get("uncertainty", 0.8))
	e.status = str(d.get("status", "abgeschlossen"))
	e.outcome = str(d.get("outcome", ""))
	e.started_t = float(d.get("started_t", 0.0))
	e.ended_t = float(d.get("ended_t", -1.0))
	e.heater_j_start = float(d.get("heater_j_start", 0.0))
	e.waits = int(d.get("waits", 0))
	return e
