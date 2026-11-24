class_name MaterialVisuals
extends RefCounted
## Darstellung von Materialien. Farben leiten sich aus dem Physikmaterial ab
## (MaterialDefinition.color). Eine Darstellungsvariante (z. B. „grass“ für Erde)
## ändert NUR das Aussehen und ist fest an ein Material gebunden – ein sichtbarer
## Gegenstand kann so keine anderen Materialeigenschaften vortäuschen als sein
## Simulationsobjekt.

## Variante -> erlaubtes Physikmaterial und Farbe (Herkunft dokumentiert).
const VARIANTS := {
	"soil": {"material": "soil", "color": "#6D4C33"},
	"grass": {"material": "soil", "color": "#5E9E3A", "note": "Grasdecke auf Erde"},
	"root_bed": {"material": "soil", "color": "#3E2A1E", "note": "dunkles Wurzelbeet"},
	"stone": {"material": "stone", "color": "#8A8A85"},
	"bedrock": {"material": "stone", "color": "#55555A"},
	"wood": {"material": "wood", "color": "#8B5A2B"},
	"bark": {"material": "wood", "color": "#5D4037", "note": "Excel F004 Braun"},
	"root": {"material": "wood", "color": "#6B4A35"},
	"plant": {"material": "plant_tissue", "color": "#2E7D32", "note": "Excel F001"},
	"leaf": {"material": "plant_tissue", "color": "#4C9A3F"},
	"leaf_light": {"material": "plant_tissue", "color": "#81C784", "note": "Excel F002"},
	"berry": {"material": "plant_tissue", "color": "#B3263A"},
	"mushroom_cap_red": {"material": "plant_tissue", "color": "#E53935", "note": "Excel F006; Pilzgewebe vorläufig als Pflanzengewebe modelliert"},
	"mushroom_cap_brown": {"material": "plant_tissue", "color": "#8D5B3A"},
	"mushroom_stalk": {"material": "plant_tissue", "color": "#EDE3CF"},
	"copper": {"material": "copper", "color": "#B87333"},
	"water": {"material": "water", "color": "#3A7BD5"},
}

static var _mat_cache: Dictionary = {}


## Farbe für Material + Variante. Gibt {"color": Color, "ok": bool, "error": String} zurück.
static func resolve(materials: MaterialRegistry, material_id: String, variant: String = "") -> Dictionary:
	var mat := materials.get_material(material_id) if materials != null else null
	if mat == null:
		return {"color": Color.MAGENTA, "ok": false, "error": "Unbekanntes Material '%s'." % material_id}
	if variant == "" or variant == material_id:
		return {"color": mat.color, "ok": true, "error": ""}
	var v: Dictionary = VARIANTS.get(variant, {})
	if v.is_empty():
		return {"color": Color.MAGENTA, "ok": false, "error": "Unbekannte Darstellungsvariante '%s'." % variant}
	if v["material"] != material_id:
		return {"color": Color.MAGENTA, "ok": false, "error": "Variante '%s' gehört zu '%s', nicht zu '%s'." % [variant, v["material"], material_id]}
	return {"color": Color.html(v["color"]), "ok": true, "error": ""}


static func color(materials: MaterialRegistry, material_id: String, variant: String = "") -> Color:
	var r := resolve(materials, material_id, variant)
	if not r["ok"]:
		push_warning("MaterialVisuals: " + r["error"])
	return r["color"]


## Gemeinsames Material für Voxelnetze mit Vertexfarben.
static func vertex_color_material(transparent: bool = false, emissive: bool = false) -> StandardMaterial3D:
	var key := "vc_%s_%s" % [transparent, emissive]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.1
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		m.emission_enabled = true
	_mat_cache[key] = m
	return m
