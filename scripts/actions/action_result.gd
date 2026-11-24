class_name ActionResult
extends RefCounted
## Ergebnis einer Prüfung oder Ausführung. code ist ein stabiler Maschinencode
## (für spätere Lernsysteme und Ollama), message ein verständlicher Text.

var ok: bool = true
var code: String = "ok"
var message: String = ""
var data: Dictionary = {}


static func success(msg: String = "", d: Dictionary = {}) -> ActionResult:
	var r := ActionResult.new()
	r.ok = true
	r.message = msg
	r.data = d
	return r


static func fail(c: String, msg: String, d: Dictionary = {}) -> ActionResult:
	var r := ActionResult.new()
	r.ok = false
	r.code = c
	r.message = msg
	r.data = d
	return r


func to_dict() -> Dictionary:
	return {"ok": ok, "code": code, "message": message, "data": data.duplicate(true)}
