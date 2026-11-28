class_name SimModule
extends RefCounted
## Modulvertrag der Simulation (Alpha 1.1, docs/ROADMAP_ALPHA.md Abschnitt 8.3).
## Ein Modul kapselt EIN Teilsystem: Takt, Speicherabschnitt, Messwerte, Konsistenzprüfung.
## Das ModuleRegistry ordnet Module nach `depends_on`, ruft sie in fester Reihenfolge auf und misst
## die Zeit je Modul. Spielszene, Werkzeuge und Tests nutzen denselben Pfad (LifeSimulation.step).
##
## Zwei Arten von Takt:
##   tick(dt, zone)        – einmal je Simulationsbild (bzw. im eigenen Takt `tick_hz`).
##   actor_tick(cr, dt)    – nur wenn `per_actor` = true: einmal je lebendem Akteur. Aufeinander folgende
##                           Akteur-Module bilden eine Gruppe; je Akteur laufen sie nacheinander
##                           (Körper → Wahrnehmung → Entscheidung), damit die Reihenfolge je Wesen stimmt.
## Speichern: save_section() liefert {"v": Abschnittsversion, …}; load_section() übernimmt genau das.
## Ein Modul greift nicht auf interne Felder fremder Module zu, sondern auf den LifeContext.

const ZONE_A := 0   # aktiv (volle Auflösung, jedes Simulationsbild)
const ZONE_B := 1   # nah (geladen, ohne Darstellung) – ab Alpha 1.2
const ZONE_C := 2   # fern (Bestands- und Bilanzmodelle) – ab Alpha 1.2

var id: String = ""                      # eindeutig, z. B. "ecology.food"
var title: String = ""                   # deutscher Anzeigename
var depends_on: Array[String] = []       # Taktreihenfolge: läuft NACH diesen Modulen
var per_actor: bool = false              # true → actor_tick je lebendem Akteur
var tick_hz := {"A": 0.0, "B": 2.0, "C": 0.2}   # 0 = jedes Simulationsbild
var has_section: bool = false            # true → das Modul besitzt einen Speicherabschnitt
var section_version: int = 1             # Version des eigenen Speicherabschnitts
var section_optional: bool = false       # true → ein Spielstand ohne diesen Abschnitt lädt mit Startzustand
var load_order: int = 100                # Reihenfolge beim Laden (klein zuerst)
var after_load_order: int = 100          # Reihenfolge der Nacharbeit nach dem Laden
var ctx: LifeContext
var life                                  # LifeSimulation (untypisiert: keine zyklische Typabhängigkeit)


func setup(p_life, p_ctx: LifeContext) -> void:
	life = p_life
	ctx = p_ctx


## Einmal je Simulationsbild (dt = simulierter Zeitschritt, > 0).
func tick(_dt: float, _zone: int) -> void:
	pass


## Nur für per_actor-Module: ein lebender Akteur.
func actor_tick(_cr: Creature, _dt: float) -> void:
	pass


## Pause: Simulation steht, Netzwerk o. Ä. darf weiterlaufen. Kein Zustand der Welt ändert sich.
func tick_paused() -> void:
	pass


## Speicherabschnitt (nur Daten). Leeres Dictionary = Modul hat keinen Zustand.
func save_section() -> Dictionary:
	return {}


## Übernimmt einen Abschnitt (bereits auf section_version migriert). {"ok", "code", "message"}
func load_section(_d: Dictionary) -> Dictionary:
	return {"ok": true}


## Hebt einen Abschnitt älterer Version an. Rückgabe {"ok", "section", "message"}.
func migrate_section(d: Dictionary, from_v: int) -> Dictionary:
	if from_v == section_version:
		return {"ok": true, "section": d}
	return {"ok": false, "section": {}, "message": "Modul %s: keine Migration des Abschnitts von Version %d nach %d." % [id, from_v, section_version]}


## Nacharbeit, wenn ALLE Abschnitte geladen sind (Verweise zwischen Modulen). Rückgabe: Hinweise.
func after_load() -> Array:
	return []


## Messwerte des Moduls (Objektzahlen u. Ä.); die Zeit je Takt misst das Register.
func metrics() -> Dictionary:
	return {}


## Konsistenzprüfung. Leere Liste = in Ordnung.
func audit() -> Array:
	return []


## Gibt Verweise frei (Szenenwechsel, erneutes Laden).
func dispose() -> void:
	ctx = null
	life = null
