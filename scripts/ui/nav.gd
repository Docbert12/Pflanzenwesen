class_name Nav
extends RefCounted
## Szenenwechsel zwischen Startbildschirm, Lebenssimulation und den Vorschau-/Testbereichen.

const MENU := "res://scenes/main.tscn"
const LAB := "res://scenes/tests/physics_lab.tscn"
const WORLD := "res://scenes/world_preview.tscn"
const CREATURES := "res://scenes/tools/creature_preview.tscn"
const LIVING := "res://scenes/living_world.tscn"
const MIND_LAB := "res://scenes/tests/mind_lab.tscn"


static func go(tree: SceneTree, path: String) -> void:
	tree.paused = false   # Pause darf nicht in die nächste Szene „mitgenommen“ werden
	tree.change_scene_to_file(path)


static func back_button(parent: Control, tree_owner: Node) -> Button:
	var b := Button.new()
	b.text = "◀ Startbildschirm"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Nav.go(tree_owner.get_tree(), MENU))
	parent.add_child(b)
	return b


static func panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.86)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


static func label(parent: Control, text: String = "", size: int = 13, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap and not (parent is HBoxContainer):
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


static func button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
