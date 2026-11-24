class_name MaterialRegistry
extends RefCounted
## Lädt und validiert Materialdefinitionen aus data/materials/*.json.
## Ungültige Dateien werden mit verständlichen Meldungen abgewiesen.

const SUPPORTED_SCHEMA := 1
const VALID_KINDS := ["reference", "assumed", "derived", "game", "not_applicable"]
const VALID_FRACTURE := ["ductile", "brittle", "fibrous", "soft", "not_applicable"]
const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const REQUIRED_PROPERTIES := [
	"density_kg_m3", "specific_heat_solid_j_kgk", "specific_heat_liquid_j_kgk",
	"thermal_conductivity_w_mk", "melting_point_k", "latent_heat_fusion_j_kg",
	"model_valid_min_k", "model_valid_max_k",
]

var _materials: Dictionary = {}
var errors: Array = []


func load_directory(dir_path: String) -> bool:
	errors.clear()
	_materials.clear()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		errors.append("Materialordner nicht lesbar: %s" % dir_path)
		return false
	var files: Array = []
	for f in dir.get_files():
		# Im Export können Dateien als .json.remap o. ä. erscheinen – nur echte .json verwenden.
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	if files.is_empty():
		errors.append("Keine Materialdateien (*.json) in %s gefunden." % dir_path)
		return false
	for f in files:
		var path := dir_path.path_join(f)
		var loaded := JsonUtil.load_json(path)
		if not loaded["ok"]:
			errors.append(loaded["error"])
			continue
		var result := validate(loaded["data"], f.get_basename())
		if not result["ok"]:
			for e in result["errors"]:
				errors.append("%s: %s" % [f, e])
			continue
		var def: MaterialDefinition = result["definition"]
		if _materials.has(def.id):
			errors.append("%s: doppelte Material-ID '%s'." % [f, def.id])
			continue
		_materials[def.id] = def
	return errors.is_empty()


func get_material(id: String) -> MaterialDefinition:
	return _materials.get(id, null)


func has_material(id: String) -> bool:
	return _materials.has(id)


func ids() -> Array:
	var k := _materials.keys()
	k.sort()
	return k


## Validiert ein Material-Dictionary. expected_id: Dateiname ohne Endung ("" = nicht prüfen).
## Rückgabe: {"ok": bool, "errors": Array[String], "definition": MaterialDefinition|null}
static func validate(data, expected_id: String = "") -> Dictionary:
	var errs: Array = []
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["Inhalt ist kein JSON-Objekt."], "definition": null}
	if data.get("schema_version", null) != SUPPORTED_SCHEMA and not (JsonUtil.is_number(data.get("schema_version", null)) and int(data["schema_version"]) == SUPPORTED_SCHEMA):
		errs.append("schema_version muss %d sein (gefunden: %s)." % [SUPPORTED_SCHEMA, str(data.get("schema_version", "fehlt"))])
	var id = data.get("id", null)
	var re := RegEx.new()
	re.compile(ID_PATTERN)
	if typeof(id) != TYPE_STRING or re.search(id) == null:
		errs.append("Ungültige ID '%s' (erlaubt: Kleinbuchstaben, Ziffern, Unterstrich; Beginn mit Buchstabe)." % str(id))
	elif expected_id != "" and id != expected_id:
		errs.append("ID '%s' passt nicht zum Dateinamen '%s'." % [id, expected_id])
	for key in ["display_name", "description"]:
		if typeof(data.get(key, null)) != TYPE_STRING or String(data.get(key, "")).strip_edges() == "":
			errs.append("Feld '%s' fehlt oder ist leer." % key)
	var phase_model = data.get("phase_model", null)
	if phase_model != MaterialDefinition.PHASE_SOLID_ONLY and phase_model != MaterialDefinition.PHASE_SOLID_LIQUID:
		errs.append("phase_model '%s' wird nicht unterstützt (erlaubt: solid_only, solid_liquid)." % str(phase_model))

	var sources: Array = data.get("sources", []) if typeof(data.get("sources", null)) == TYPE_ARRAY else []
	var source_ids: Array = []
	for s in sources:
		if typeof(s) == TYPE_DICTIONARY and typeof(s.get("id", null)) == TYPE_STRING:
			source_ids.append(s["id"])

	var props = data.get("properties", null)
	if typeof(props) != TYPE_DICTIONARY:
		errs.append("Abschnitt 'properties' fehlt.")
		props = {}
	var values: Dictionary = {}
	for key in REQUIRED_PROPERTIES:
		if not props.has(key):
			errs.append("Eigenschaft '%s' fehlt (nicht anwendbare Werte explizit mit kind=not_applicable angeben)." % key)
			continue
		var r := _check_value_entry(key, props[key], source_ids)
		errs.append_array(r["errors"])
		values[key] = r["value"]

	# Physikalische Plausibilität
	_require_positive(values, "density_kg_m3", errs)
	_require_positive(values, "specific_heat_solid_j_kgk", errs)
	_require_positive(values, "thermal_conductivity_w_mk", errs)
	_require_positive(values, "model_valid_min_k", errs)
	_require_positive(values, "model_valid_max_k", errs)
	var vmin = values.get("model_valid_min_k", null)
	var vmax = values.get("model_valid_max_k", null)
	if JsonUtil.is_number(vmin) and JsonUtil.is_number(vmax) and float(vmin) >= float(vmax):
		errs.append("model_valid_min_k (%s) muss kleiner als model_valid_max_k (%s) sein." % [vmin, vmax])
	if phase_model == MaterialDefinition.PHASE_SOLID_LIQUID:
		_require_positive(values, "melting_point_k", errs)
		_require_positive(values, "latent_heat_fusion_j_kg", errs)
		_require_positive(values, "specific_heat_liquid_j_kgk", errs)
		var tm = values.get("melting_point_k", null)
		if JsonUtil.is_number(tm) and JsonUtil.is_number(vmin) and JsonUtil.is_number(vmax):
			if float(tm) <= float(vmin) or float(tm) >= float(vmax):
				errs.append("Schmelzpunkt %s K liegt nicht im Gültigkeitsbereich des Modells." % tm)
	elif phase_model == MaterialDefinition.PHASE_SOLID_ONLY:
		for key in ["melting_point_k", "latent_heat_fusion_j_kg", "specific_heat_liquid_j_kgk"]:
			if values.get(key, null) != null:
				errs.append("'%s' muss bei phase_model=solid_only als nicht anwendbar (null) angegeben werden." % key)

	var mech = data.get("mechanical", null)
	var fracture := "not_applicable"
	var toughness := 0.0
	var max_frag := 1
	if typeof(mech) != TYPE_DICTIONARY:
		errs.append("Abschnitt 'mechanical' fehlt.")
	else:
		var fb = mech.get("fracture_behavior", {}).get("value", null) if typeof(mech.get("fracture_behavior", null)) == TYPE_DICTIONARY else null
		if not fb in VALID_FRACTURE:
			errs.append("mechanical.fracture_behavior '%s' ungültig." % str(fb))
		else:
			fracture = fb
		var tg = mech.get("toughness_j_kg", {}).get("value", null) if typeof(mech.get("toughness_j_kg", null)) == TYPE_DICTIONARY else null
		if fracture != "not_applicable":
			if not JsonUtil.is_number(tg) or float(tg) <= 0.0:
				errs.append("mechanical.toughness_j_kg muss > 0 sein.")
			else:
				toughness = float(tg)
		var mf = mech.get("max_fragments", {}).get("value", null) if typeof(mech.get("max_fragments", null)) == TYPE_DICTIONARY else null
		if not JsonUtil.is_number(mf) or int(mf) < 1 or int(mf) > 4:
			errs.append("mechanical.max_fragments muss zwischen 1 und 4 liegen.")
		else:
			max_frag = int(mf)

	# Optionaler Abschnitt „working“ (Prompt 6): jeder Eintrag {value: Zahl ≥ 0, kind}
	var working := {}
	var wk = data.get("working", null)
	if wk != null:
		if typeof(wk) != TYPE_DICTIONARY:
			errs.append("Abschnitt 'working' muss ein Objekt sein.")
		else:
			for key in wk:
				if str(key).begins_with("_"):
					continue
				var r2 := _check_value_entry("working." + str(key), wk[key], source_ids)
				errs.append_array(r2["errors"])
				if r2["value"] != null:
					if float(r2["value"]) < 0.0:
						errs.append("'working.%s' darf nicht negativ sein." % key)
					else:
						working[str(key)] = float(r2["value"])
	var render = data.get("render", {})
	var col_text = render.get("color", "") if typeof(render) == TYPE_DICTIONARY else ""
	if typeof(col_text) != TYPE_STRING or not Color.html_is_valid(col_text):
		errs.append("render.color muss eine Hex-Farbe sein.")

	if not errs.is_empty():
		return {"ok": false, "errors": errs, "definition": null}

	var def := MaterialDefinition.new()
	def.id = id
	def.display_name = data["display_name"]
	def.description = data["description"]
	def.model_material = str(data.get("model_material", ""))
	def.phase_model = phase_model
	def.density = float(values["density_kg_m3"])
	def.cp_solid = float(values["specific_heat_solid_j_kgk"])
	def.conductivity = float(values["thermal_conductivity_w_mk"])
	def.valid_min_k = float(values["model_valid_min_k"])
	def.valid_max_k = float(values["model_valid_max_k"])
	if def.has_melting():
		def.cp_liquid = float(values["specific_heat_liquid_j_kgk"])
		def.melting_point = float(values["melting_point_k"])
		def.latent_heat_fusion = float(values["latent_heat_fusion_j_kg"])
	def.fracture_behavior = fracture
	def.toughness_j_kg = toughness
	def.max_fragments = max_frag
	var comb = data.get("combustion", {})
	if typeof(comb) == TYPE_DICTIONARY:
		var cv = comb.get("combustible", {})
		def.combustible = typeof(cv) == TYPE_DICTIONARY and cv.get("value", false) == true
		var dv = comb.get("decomposition_onset_k", {})
		if typeof(dv) == TYPE_DICTIONARY and JsonUtil.is_number(dv.get("value", null)):
			def.decomposition_onset_k = float(dv["value"])
		def.combustion_simulated = comb.get("simulated", false) == true
	def.color = Color.html(col_text)
	var lc = render.get("liquid_color", col_text)
	def.liquid_color = Color.html(lc) if typeof(lc) == TYPE_STRING and Color.html_is_valid(lc) else def.color
	def.working = working
	def.raw = data.duplicate(true)
	return {"ok": true, "errors": [], "definition": def}


static func _check_value_entry(key: String, entry, source_ids: Array) -> Dictionary:
	var errs: Array = []
	if typeof(entry) != TYPE_DICTIONARY:
		return {"errors": ["'%s' muss ein Objekt mit value/kind sein." % key], "value": null}
	var kind = entry.get("kind", null)
	if not kind in VALID_KINDS:
		errs.append("'%s': kind '%s' ungültig (erlaubt: %s)." % [key, str(kind), ", ".join(VALID_KINDS)])
	var value = entry.get("value", "__missing__")
	if typeof(value) == TYPE_STRING and value == "__missing__":
		errs.append("'%s': value fehlt." % key)
		value = null
	if kind == "not_applicable" and value != null:
		errs.append("'%s': nicht anwendbare Werte müssen value=null haben." % key)
	if kind != "not_applicable" and kind in VALID_KINDS:
		if not JsonUtil.is_number(value):
			errs.append("'%s': value muss eine Zahl sein (oder kind=not_applicable mit null)." % key)
			value = null
		elif is_nan(float(value)) or is_inf(float(value)):
			errs.append("'%s': value ist keine endliche Zahl." % key)
			value = null
	if kind == "reference" or kind == "derived":
		var src = entry.get("source", null)
		if typeof(src) != TYPE_STRING or not src in source_ids:
			errs.append("'%s': Referenz-/abgeleiteter Wert braucht eine gültige Quelle aus 'sources' (gefunden: %s)." % [key, str(src)])
	return {"errors": errs, "value": value}


static func _require_positive(values: Dictionary, key: String, errs: Array) -> void:
	var v = values.get(key, null)
	if v == null:
		if not _already_reported(errs, key):
			errs.append("'%s' ist erforderlich und muss > 0 sein." % key)
		return
	if float(v) <= 0.0:
		errs.append("'%s' muss > 0 sein (gefunden: %s)." % [key, v])


static func _already_reported(errs: Array, key: String) -> bool:
	for e in errs:
		if String(e).begins_with("'%s'" % key) or String(e).find("'%s' fehlt" % key) >= 0:
			return true
	return false
