class_name ResourceLedger
extends RefCounted
## Weltweite Nahrungsbilanz [kg]:
##   Anfangsmenge + Testauffüllung + göttliche Gaben = Σ Quellen + Σ Gegenstände + gegessen
##   gegessen = assimiliert + Abfall (Abfall wird nur bilanziert, nicht als Weltobjekt erzeugt)

var initial_kg: float = 0.0
var refill_kg: float = 0.0
var god_kg: float = 0.0          # externe Zufuhr durch Göttereingriffe (Prompt 4)
var taken_from_sources_kg: float = 0.0
var eaten_kg: float = 0.0
var assimilated_kg: float = 0.0
var waste_kg: float = 0.0
var digest_efficiency: float = 0.8


func balance_error(ctx: LifeContext) -> float:
	var s := 0.0
	for id in ctx.foods:
		s += ctx.foods[id].amount_kg
	for id in ctx.items:
		s += ctx.items[id].mass_kg
	return (initial_kg + refill_kg + god_kg) - (s + eaten_kg)


func sources_total(ctx: LifeContext) -> float:
	var s := 0.0
	for id in ctx.foods:
		s += ctx.foods[id].amount_kg
	return s


func to_dict() -> Dictionary:
	return {"initial_kg": initial_kg, "refill_kg": refill_kg, "god_kg": god_kg, "taken_from_sources_kg": taken_from_sources_kg, "eaten_kg": eaten_kg,
		"assimilated_kg": assimilated_kg, "waste_kg": waste_kg, "digest_efficiency": digest_efficiency}


static func from_dict(d: Dictionary) -> ResourceLedger:
	var l := ResourceLedger.new()
	for k in d:
		l.set(k, float(d[k]))
	return l
