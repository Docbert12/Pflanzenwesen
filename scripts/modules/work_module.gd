class_name WorkModule
extends SimModule
## Arbeit: Arbeitsketten aus eigenem Bedarf (WorkSystem) und die Rollen der Testszenen (workshop).

func _init() -> void:
	id = "work"
	has_section = true
	title = "Arbeit (Arbeitsketten)"
	depends_on = ["technology"]
	load_order = 50
	after_load_order = 30


func tick(_dt: float, _zone: int) -> void:
	ctx.work.tick(ctx)


func save_section() -> Dictionary:
	return {"work": ctx.work.to_dict() if ctx.work != null else {}, "workshop": life.workshop.duplicate()}


func load_section(d: Dictionary) -> Dictionary:
	ctx.work = WorkSystem.new()
	ctx.work.from_dict(d.get("work", {}))
	life.workshop = {}
	for k in d.get("workshop", {}):
		life.workshop[str(k)] = int(d["workshop"][k])
	return {"ok": true}


func after_load() -> Array:
	ctx.work.after_load(ctx)
	return []


func audit() -> Array:
	return ctx.work.audit(ctx) if ctx.work != null else []
