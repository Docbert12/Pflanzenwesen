class_name ActionDefinition
extends RefCounted
## Handlungstypen und ihre Eigenschaften. Dieselbe Tabelle wird später für
## Ollama-Vorschläge verwendet: nur hier definierte Typen sind ausführbar.

const STATUS_PLANNED := "planned"
const STATUS_RUNNING := "running"
const STATUS_SUCCEEDED := "succeeded"
const STATUS_FAILED := "failed"
const STATUS_CANCELLED := "cancelled"
const FINAL := [STATUS_SUCCEEDED, STATUS_FAILED, STATUS_CANCELLED]

## capabilities: benötigte Körperfähigkeiten (BodyCapabilities), Wert > 0 nötig
## target: "position" | "entity" | "entity_or_carried" | "none"
## on_load: Verhalten beim Laden eines Spielstands (siehe docs/save_format.md)
const TYPES := {
	"move_to": {"capabilities": ["locomotion"], "target": "position", "interruptible": true, "reserves": false, "on_load": "replan",
		"description": "Zu einer Position gehen (Wegsuche über NavigationService)."},
	"pick_up": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": true, "on_load": "cancel",
		"description": "Eine Portion Nahrung von einer Quelle oder einen Gegenstand vom Boden aufnehmen."},
	"eat": {"capabilities": ["mouth"], "target": "entity_or_carried", "interruptible": true, "reserves": true, "on_load": "continue",
		"description": "Getragene Nahrung essen; ohne Greiffähigkeit direkt an der Quelle (langsamer)."},
	"drop": {"capabilities": [], "target": "none", "interruptible": false, "reserves": false, "on_load": "cancel",
		"description": "Getragenen Gegenstand am eigenen Standort ablegen."},
	"wait": {"capabilities": [], "target": "none", "interruptible": true, "reserves": false, "on_load": "continue",
		"description": "Eine bestimmte Zeit warten."},
	"request_food": {"capabilities": [], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Ein anderes Wesen in Reichweite (3 m) mit einer sichtbaren Geste um Nahrung bitten."},
	"offer_food": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": true, "on_load": "cancel",
		"description": "Getragene Portion einem anderen Wesen anbieten (reserviert, bis angenommen oder Zeitlimit)."},
	"give_food": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": true, "on_load": "cancel",
		"description": "Getragene Portion auf eine Bitte hin übergeben (Reichweite 1,4 m)."},
	"decline_request": {"capabilities": [], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Eine Bitte sichtbar ablehnen."},
	"raise_arms": {"capabilities": ["gesture"], "target": "none", "interruptible": true, "reserves": false, "on_load": "continue",
		"description": "Anhalten und die Arme heben (neutrale Ausdruckshandlung, kein festgelegter Zweck)."},
	"talk": {"capabilities": [], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Einem nahen Wesen (≤ 4 m) eine geprüfte, strukturierte Mitteilung machen (Prompt 5)."},
	# ── Prompt 6: Experimente, Werkzeuge, Gießen, Unterricht ──
	"inspect_object": {"capabilities": [], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Einen Gegenstand untersuchen (ansehen, beklopfen, anheben, Wärme prüfen) – nur wahrnehmbare Kategorien."},
	"equip_tool": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Einen Gegenstand in die Greifhand nehmen (Reichweite, Masse, Griff, Temperatur geprüft)."},
	"strike_target": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Mit dem gehaltenen Gegenstand (oder der Hand) einmal auf ein Materialstück schlagen."},
	"deform_material": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": true, "on_load": "cancel",
		"description": "Ein Materialstück durch mehrere Schläge verformen (jeder Schlag wirkt sofort, Abbruch behält den Zwischenstand)."},
	"connect_parts": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": true, "on_load": "cancel",
		"description": "Stiel (Ziel) und Kopf mit Pflanzenfasern umwickeln (unterstützte Verbindungsmethode lashing)."},
	"disconnect_parts": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Einen zusammengesetzten Gegenstand lösen; alle Teile bleiben erhalten."},
	"place_in_heater": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Einen Tiegel in die extern versorgte Testheizung setzen."},
	"pour_into_mold": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": true, "on_load": "cancel",
		"description": "Geschmolzenen Tiegelinhalt am Griff in eine Gussform gießen (Temperatur, Flüssiganteil, Kapazität geprüft)."},
	"demonstrate_procedure": {"capabilities": ["grasp"], "target": "none", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Ein selbst erfolgreich ausgeführtes Verfahren sichtbar vorführen (echter Vorgang mit echten Gegenständen)."},
	"practice_procedure": {"capabilities": ["grasp"], "target": "none", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Ein gehörtes oder gesehenes Verfahren selbst üben (eigener Versuch)."},
	# ── Prompt 6B: Werkzeug- und Materialkette (Lagern, Verbauen, in den Tiegel legen) ──
	"deposit_in_storage": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Gehaltenes Stück an einem freien Platz eines realen Lagers ablegen (Kapazität, Temperatur geprüft)."},
	"place_building_part": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Gehaltenes Stück an einer Baustelle auf einen freien Platz setzen (Bauplan, Untergrund geprüft)."},
	"put_into_container": {"capabilities": ["grasp"], "target": "entity", "interruptible": true, "reserves": false, "on_load": "cancel",
		"description": "Gehaltenes Stück in einen Tiegel legen (nur unterstützte Schmelzgüter, freies Volumen geprüft)."},
}


const LABELS := {"move_to": "Gehen", "pick_up": "Aufnehmen", "eat": "Essen", "drop": "Ablegen", "wait": "Warten",
	"request_food": "Um Nahrung bitten", "offer_food": "Nahrung anbieten", "give_food": "Nahrung geben",
	"decline_request": "Bitte ablehnen", "raise_arms": "Arme heben", "talk": "Sprechen",
	"inspect_object": "Untersuchen", "equip_tool": "In die Hand nehmen", "strike_target": "Schlagen", "deform_material": "Verformen",
	"connect_parts": "Verbinden", "disconnect_parts": "Lösen", "place_in_heater": "In die Heizung setzen", "pour_into_mold": "Gießen",
	"demonstrate_procedure": "Vorführen", "practice_procedure": "Üben",
	"deposit_in_storage": "Einlagern", "place_building_part": "Verbauen", "put_into_container": "In den Tiegel legen"}

const TECH_TYPES := ["inspect_object", "equip_tool", "strike_target", "deform_material", "connect_parts", "disconnect_parts",
	"place_in_heater", "pour_into_mold", "demonstrate_procedure", "practice_procedure",
	"deposit_in_storage", "place_building_part", "put_into_container"]


static func label(t: String) -> String:
	return LABELS.get(t, t)


static func has_type(t: String) -> bool:
	return TYPES.has(t)


static func info(t: String) -> Dictionary:
	return TYPES.get(t, {})
