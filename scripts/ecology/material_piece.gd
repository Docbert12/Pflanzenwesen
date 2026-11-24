class_name MaterialPiece
extends PhysicalObject
## Ein einzelner Materialgegenstand in der Lebenswelt (Göttereingriff, Testwerkstatt, Bruchstück,
## Guss, abgetrennter Faserrest). Seit Prompt 6 ein PhysicalObject: Masse und thermische Energie
## sind die Quelle der Wahrheit, Temperatur und Flüssiganteil werden daraus abgeleitet, Wärme- und
## Phasensystem behandeln das Stück wie jedes andere Objekt (Umgebungsaustausch, Heizung, Kontakte).
##
## GEOMETRIE (Spielmodell): shape + dims_m (Außenmaße x, y = Höhe, z). Volumen aus der Form:
##   block/ingot: x·y·z · rod: π/4·d²·L (L = x, d = y = z) · lump: π/6·x³ · bundle: x·y·z
##   cup/mold: x·y·z − cavity_m3 (Hohlraum).
## Bei der Erzeugung gilt Masse = Dichte · Formvolumen. Verformung erhält das Volumen (nur dims ändern sich).
## Ein Stück ist ENTWEDER einzeln ODER Bauteil eines Verbunds (assembly_id ≠ 0) – nie beides.

const SHAPES := ["block", "rod", "lump", "bundle", "cup", "mold", "ingot"]

var shape: String = "block"
var dims_m := Vector3(0.12, 0.12, 0.12)
var size_m: float = 0.12             # größte Kante (Altfeld, Darstellung/Göttermenü)
var position := Vector3.ZERO
var cavity_m3: float = 0.0           # Behälter/Form: nutzbarer Hohlraum
var carrier_id: int = 0              # Wesen hält dieses einzelne Stück
var assembly_id: int = 0             # Bauteil von Verbund #
var role: String = ""                # Rolle im Verbund: handle, head, binding, cup, grip
var container_id: int = 0            # liegt in Behälter/Form (Stück-ID) bzw. Testheizung (Heizungs-ID)
var strain: float = 0.0              # akkumulierte plastische Stauchung (wahre Dehnung, Spielmodell)
var wear: float = 0.0                # Oberflächenverschleiß 0..1 (Werkzeugkopf)
var test_equipment: bool = false     # ausdrücklich platzierte Testausrüstung
var storage_id: int = 0              # Prompt 6B: liegt eingelagert in Lager # (StorageSystem)
var structure_id: int = 0            # Prompt 6B: ist verbautes Teil von Bauwerk # (StructureSystem)
var reserved_by: int = 0             # Reservierung (Handlungssystem)
var created_t: float = 0.0
var history: Array = []              # kurze Bearbeitungsgeschichte [{t, what}]
var visual_version: int = 0          # nur Darstellung (nicht gespeichert)


## Erzeugt ein Stück mit Masse = Dichte · Formvolumen bei Temperatur temperature_k.
## Gibt null zurück (errors gefüllt), wenn Form/Maße/Material ungültig sind.
## volume_override > 0: exaktes Volumen in doppelter Genauigkeit (Vector3 ist einfach genau), z. B.
## Göttermenü-Würfel s³ – dann gilt Masse = Dichte · s³ ohne Rundung über die Maße.
static func make(materials: MaterialRegistry, material_id: String, p_shape: String, p_dims: Vector3, temperature_k: float, errors: Array, p_cavity: float = 0.0, volume_override: float = -1.0) -> MaterialPiece:
	var mat := materials.get_material(material_id)
	if mat == null:
		errors.append("Unbekanntes Material '%s'." % material_id)
		return null
	if not (p_shape in SHAPES):
		errors.append("Unbekannte Form '%s'." % p_shape)
		return null
	if p_dims.x <= 0.0 or p_dims.y <= 0.0 or p_dims.z <= 0.0:
		errors.append("Maße müssen > 0 sein.")
		return null
	var mp := MaterialPiece.new()
	mp.bind_material(mat)
	mp.material_id = material_id
	mp.shape = p_shape
	mp.dims_m = p_dims
	mp.cavity_m3 = maxf(0.0, p_cavity)
	var v := mp.shape_volume_m3() if volume_override <= 0.0 else volume_override
	if not (v > 0.0):
		errors.append("Formvolumen muss > 0 sein (Hohlraum zu groß?).")
		return null
	if temperature_k < mat.valid_min_k or temperature_k > mat.valid_max_k:
		errors.append("Temperatur %.1f K außerhalb des Modellbereichs von %s." % [temperature_k, material_id])
		return null
	mp.mass_kg = mat.density * v
	mp.thermal_energy_j = mp.mass_kg * mat.enthalpy_from_temperature(temperature_k, 0.0)
	mp.size_m = maxf(p_dims.x, maxf(p_dims.y, p_dims.z))
	return mp


static func volume_of(p_shape: String, d: Vector3, cavity: float) -> float:
	match p_shape:
		"rod":
			return PI * 0.25 * d.y * d.z * d.x
		"lump":
			return PI / 6.0 * d.x * d.y * d.z
		"cup", "mold":
			return d.x * d.y * d.z - cavity
		_:
			return d.x * d.y * d.z


func shape_volume_m3() -> float:
	return volume_of(shape, dims_m, cavity_m3)


## Setzt die Maße für eine neue Masse bei gleicher Form und gleichen Seitenverhältnissen
## (Teilmenge eines Faserbündels, Gussrest). Volumen = Masse / Dichte.
func rescale_to_mass() -> void:
	var target := mass_kg / material().density
	var cur := shape_volume_m3()
	if cur <= 0.0 or target <= 0.0:
		return
	if shape in ["cup", "mold"]:
		return   # Behälter werden nicht skaliert
	var f := pow(target / cur, 1.0 / 3.0)
	dims_m *= f
	size_m = maxf(dims_m.x, maxf(dims_m.y, dims_m.z))
	visual_version += 1


## Höhe des Innenbodens über der Unterkante (Gefäß/Form), passend zum Voxelmodell des ObjectGenerator:
## Gefäß: Wandstärke ≈ 17 % der Breite; Form: Gesamthöhe − Tiefe des Hohlraums (Grundfläche 60 % × 60 %).
func inner_floor_m() -> float:
	match shape:
		"cup":
			return dims_m.x * 0.17
		"mold":
			var a := dims_m.x * 0.6 * dims_m.z * 0.6
			return clampf(dims_m.y - cavity_m3 / a, 0.0, dims_m.y) if a > 0.0 else 0.0
	return 0.0


## Kleinste Querschnittsabmessung (Greifbarkeit).
func grip_width_m() -> float:
	match shape:
		"rod":
			return dims_m.y
		_:
			var a := [dims_m.x, dims_m.y, dims_m.z]
			a.sort()
			return a[0] if shape == "bundle" else a[1]


## Oberfläche aus der Form (statt Würfelnäherung) – genauer für Stiele und Platten.
func surface_area_m2() -> float:
	var d := dims_m
	if shape == "rod":
		return PI * d.y * d.x + PI * 0.5 * d.y * d.y
	if shape == "lump":
		return PI * pow(d.x * d.y * d.z, 2.0 / 3.0)
	return 2.0 * (d.x * d.y + d.y * d.z + d.z * d.x)


func is_free() -> bool:
	return carrier_id == 0 and assembly_id == 0 and container_id == 0 and structure_id == 0


func add_history(t: float, what: String) -> void:
	history.append({"t": t, "what": what})
	while history.size() > 12:
		history.pop_front()


func shape_label() -> String:
	return {"block": "Block", "rod": "Stab", "lump": "Klumpen", "bundle": "Bündel", "cup": "Tiegel", "mold": "Gussform", "ingot": "Gussstück"}.get(shape, shape)


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d.erase("derived")
	d.merge({"shape": shape, "dims_m": [dims_m.x, dims_m.y, dims_m.z], "size_m": size_m,
		"position": [position.x, position.y, position.z], "cavity_m3": cavity_m3, "carrier_id": carrier_id,
		"assembly_id": assembly_id, "role": role, "container_id": container_id, "strain": strain, "wear": wear,
		"test_equipment": test_equipment, "storage_id": storage_id, "structure_id": structure_id, "created_t": created_t, "history": history.duplicate(true)}, true)
	return d


static func from_dict(d: Dictionary, materials: MaterialRegistry = null) -> MaterialPiece:
	var m := MaterialPiece.new()
	m.id = int(d["id"])
	m.material_id = str(d["material_id"])
	if materials != null:
		m.bind_material(materials.get_material(m.material_id))
	m.shape = str(d.get("shape", "block"))
	m.size_m = float(d.get("size_m", 0.12))
	var dm: Array = d.get("dims_m", [m.size_m, m.size_m, m.size_m])
	m.dims_m = Vector3(float(dm[0]), float(dm[1]), float(dm[2]))
	m.mass_kg = float(d["mass_kg"])
	m.thermal_energy_j = float(d.get("thermal_energy_j", 0.0))
	m.damage = float(d.get("damage", 0.0))
	m.deformed = bool(d.get("deformed", false))
	m.label = str(d.get("label", ""))
	m.origin = str(d.get("origin", ""))
	m.station = str(d.get("station", "world"))
	m.parent_ids = d.get("parent_ids", []).duplicate()
	m.position = Vector3(d["position"][0], d["position"][1], d["position"][2])
	m.cavity_m3 = float(d.get("cavity_m3", 0.0))
	m.carrier_id = int(d.get("carrier_id", 0))
	m.assembly_id = int(d.get("assembly_id", 0))
	m.role = str(d.get("role", ""))
	m.container_id = int(d.get("container_id", 0))
	m.strain = float(d.get("strain", 0.0))
	m.wear = float(d.get("wear", 0.0))
	m.test_equipment = bool(d.get("test_equipment", false))
	m.storage_id = int(d.get("storage_id", 0))
	m.structure_id = int(d.get("structure_id", 0))
	m.created_t = float(d.get("created_t", 0.0))
	m.history = d.get("history", []).duplicate(true)
	return m
