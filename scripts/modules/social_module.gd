class_name SocialModule
extends SimModule
## Soziales: Bitten, Geben, Angebote (SocialInteractionSystem).

func _init() -> void:
	id = "social"
	has_section = true
	title = "Soziales (Bitten, Geben)"
	depends_on = ["mind.decision"]
	load_order = 60


func tick(_dt: float, _zone: int) -> void:
	ctx.social.tick(ctx.now(), float(ctx.m("social").get("request_expire_s", 10.0)))


func save_section() -> Dictionary:
	return {"social": ctx.social.to_dict()}


func load_section(d: Dictionary) -> Dictionary:
	ctx.social = SocialInteractionSystem.from_dict(d.get("social", {}))
	return {"ok": true}


func metrics() -> Dictionary:
	return ctx.social.stats.duplicate() if "stats" in ctx.social else {}
