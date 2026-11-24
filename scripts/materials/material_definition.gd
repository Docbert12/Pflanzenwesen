class_name MaterialDefinition
extends RefCounted
## Unveränderliche Materialdefinition (aus JSON geladen und validiert).
## Enthält das Enthalpiemodell: spezifische Enthalpie h [J/kg] bezogen auf
## den Festkörper bei 0 K mit konstanter Wärmekapazität je Phase.
##   fest:      h = cp_s · T                         (T < Tm)
##   schmelzend h_s0 = cp_s·Tm ≤ h ≤ h_s0 + L         (T = Tm)
##   flüssig:   h = cp_s·Tm + L + cp_l·(T − Tm)      (T > Tm)
## Nur Enthalpie-DIFFERENZEN sind physikalisch aussagekräftig.

const PHASE_SOLID_ONLY := "solid_only"
const PHASE_SOLID_LIQUID := "solid_liquid"

var id: String = ""
var display_name: String = ""
var description: String = ""
var model_material: String = ""
var phase_model: String = PHASE_SOLID_ONLY
var density: float = 0.0             # kg/m³
var cp_solid: float = 0.0            # J/(kg·K)
var cp_liquid: float = 0.0           # J/(kg·K), 0 wenn nicht anwendbar
var conductivity: float = 0.0        # W/(m·K)
var melting_point: float = -1.0      # K, -1 wenn nicht anwendbar
var latent_heat_fusion: float = 0.0  # J/kg
var valid_min_k: float = 1.0
var valid_max_k: float = 1.0e9
var fracture_behavior: String = "not_applicable"
var toughness_j_kg: float = 0.0
var max_fragments: int = 1
var combustible: bool = false
var decomposition_onset_k: float = -1.0
var combustion_simulated: bool = false
var color: Color = Color.WHITE
var liquid_color: Color = Color.WHITE
var raw: Dictionary = {}  # Originaldaten inkl. Herkunftsangaben
## Bearbeitungsparameter (Prompt 6, optionaler Abschnitt "working"; alle Werte Spielparameter):
## hardness, flow_stress_mpa, hardening_mpa_per_strain, max_cold_strain, hot_softening_min, plastic,
## binding_energy_j_per_kg, binding_fatigue. Fehlende Werte → w(key, Vorgabe).
var working: Dictionary = {}


## Bearbeitungsparameter mit Vorgabewert.
func w(key: String, fallback: float = 0.0) -> float:
	return float(working.get(key, fallback))


func is_plastic() -> bool:
	return w("plastic", 0.0) > 0.0


func has_melting() -> bool:
	return phase_model == PHASE_SOLID_LIQUID


func melt_start_h() -> float:
	return cp_solid * melting_point


func melt_end_h() -> float:
	return melt_start_h() + latent_heat_fusion


## Spezifische Enthalpie für Temperatur T. liquid_fraction wird nur genau am
## Schmelzpunkt benötigt (sonst ergibt sich der Zustand aus T).
func enthalpy_from_temperature(temperature_k: float, liquid_fraction: float = 0.0) -> float:
	if not has_melting():
		return cp_solid * temperature_k
	if temperature_k < melting_point:
		return cp_solid * temperature_k
	if is_equal_approx(temperature_k, melting_point):
		return melt_start_h() + clampf(liquid_fraction, 0.0, 1.0) * latent_heat_fusion
	return melt_end_h() + cp_liquid * (temperature_k - melting_point)


func temperature_from_enthalpy(h: float) -> float:
	if not has_melting():
		return h / cp_solid
	var hs := melt_start_h()
	var he := melt_end_h()
	if h < hs:
		return h / cp_solid
	if h <= he:
		return melting_point
	return melting_point + (h - he) / cp_liquid


func liquid_fraction_from_enthalpy(h: float) -> float:
	if not has_melting():
		return 0.0
	var hs := melt_start_h()
	if h <= hs:
		return 0.0
	if h >= melt_end_h():
		return 1.0
	return (h - hs) / latent_heat_fusion


## Effektive Wärmekapazität [J/(kg·K)] im aktuellen Zustand (für Stabilitätsabschätzung).
func cp_at_enthalpy(h: float) -> float:
	if has_melting() and h >= melt_end_h():
		return cp_liquid
	return cp_solid


func to_summary() -> String:
	var s := "%s (%s) ρ=%.1f kg/m³ cp=%.0f J/(kg·K) k=%.3f W/(m·K)" % [display_name, id, density, cp_solid, conductivity]
	if has_melting():
		s += " Tm=%.2f K L=%.0f J/kg" % [melting_point, latent_heat_fusion]
	return s
