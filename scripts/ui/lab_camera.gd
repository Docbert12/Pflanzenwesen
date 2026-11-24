class_name LabCamera
extends Camera3D
## Orbitkamera. Bleibt während der Pause bedienbar (PROCESS_MODE_ALWAYS).
## Rechte Maustaste: drehen · Mittlere Maustaste oder Umschalt+Rechts: verschieben
## Mausrad: zoomen · WASD/Pfeiltasten: verschieben · Q/E: hoch/runter
## Linksklick: Objekt auswählen (Umschalt+Linksklick: Zweitauswahl)

signal object_picked(origin: Vector3, direction: Vector3, additive: bool)

var target: Vector3 = Vector3(0.0, 0.4, 0.0)
var yaw: float = 0.0
var pitch: float = -0.42
var distance: float = 10.0
var _rotating := false
var _panning := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	near = 0.01
	far = 200.0
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = maxf(0.2, distance * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = minf(60.0, distance * 1.1)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					object_picked.emit(project_ray_origin(mb.position), project_ray_normal(mb.position), mb.shift_pressed)
		_apply()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning or (_rotating and mm.shift_pressed):
			_pan(Vector2(-mm.relative.x, mm.relative.y) * distance * 0.0015)
		elif _rotating:
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch - mm.relative.y * 0.006, -1.5, 0.25)
		_apply()


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y -= 1.0
	var vertical := 0.0
	if Input.is_key_pressed(KEY_E):
		vertical += 1.0
	if Input.is_key_pressed(KEY_Q):
		vertical -= 1.0
	if move != Vector2.ZERO or vertical != 0.0:
		var speed := maxf(1.0, distance) * delta
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		target += (right * move.x + fwd * move.y) * speed + Vector3.UP * vertical * speed
		_apply()


func _pan(d: Vector2) -> void:
	var b := global_transform.basis
	target += b.x * d.x + b.y * d.y


func focus_on(p: Vector3) -> void:
	target = p
	distance = minf(distance, 1.5)
	_apply()


func _apply() -> void:
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	global_position = target + rot * Vector3(0, 0, distance)
	look_at(target, Vector3.UP)
