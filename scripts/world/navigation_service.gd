class_name NavigationService
extends RefCounted
## Navigation auf dem Voxelgelände: Raster-A* über Terrainspalten (64 × 64).
## Entscheidung (docs/life_simulation.md): Godots NavigationMesh müsste nach jeder Terrainänderung
## neu gebacken werden und kennt die Voxeldaten nicht. Ein Spaltenraster passt 1:1 zur Welt
## (eine Oberfläche je Spalte), lässt sich spaltenweise aktualisieren und ist deterministisch.
## Begehbar: im Feld, nicht vom Baum belegt, Kopffreiheit, Wassertiefe ≤ Grenzwert.
## Schritt zwischen Spalten: höchstens max_step_up_cells hinauf, max_drop_cells hinab.
## 8er-Nachbarschaft; Diagonalen nur, wenn beide Orthogonalen passierbar (keine Eckenabkürzung).
## Begrenzung: höchstens max_expansions Knoten je Suche, höchstens max_path_requests_per_tick Suchen je Takt.

var world: VoxelWorld
var w: int
var d: int
var cell: float
var ground := PackedInt32Array()
var blocked := PackedByteArray()
var max_up: int = 1
var max_drop: int = 2
var max_water: float = 0.25
var max_expansions: int = 2500
var budget_max: int = 4
var budget: int = 4
var version: int = 0
var stats := {"requests": 0, "found": 0, "failed": 0, "expansions": 0, "column_updates": 0}


func setup(p_world: VoxelWorld, life_cfg: Dictionary, blocked_cols: Dictionary) -> void:
	world = p_world
	w = world.data.size.x
	d = world.data.size.z
	cell = world.data.cell_size
	var lc: Dictionary = life_cfg.get("locomotion", {})
	var nc: Dictionary = life_cfg.get("navigation", {})
	max_up = int(lc.get("max_step_up_cells", 1))
	max_drop = int(lc.get("max_drop_cells", 2))
	max_water = float(lc.get("max_water_depth_m", 0.25))
	max_expansions = int(nc.get("max_expansions", 2500))
	budget_max = int(nc.get("max_path_requests_per_tick", 4))
	ground.resize(w * d)
	blocked.resize(w * d)
	blocked.fill(0)
	for c in blocked_cols:
		if in_bounds(c):
			blocked[c.x + w * c.y] = 1
	for z in d:
		for x in w:
			ground[x + w * z] = world.data.column_top(x, z, world.palette.solid)


## Nur die geänderte Spalte neu berechnen (keine Neuberechnung der ganzen Welt).
func on_terrain_changed(c: Vector3i) -> void:
	if c.x < 0 or c.z < 0 or c.x >= w or c.z >= d:
		return
	ground[c.x + w * c.z] = world.data.column_top(c.x, c.z, world.palette.solid)
	version += 1
	stats["column_updates"] += 1


func begin_tick() -> void:
	budget = budget_max


func take_request_budget() -> bool:
	if budget <= 0:
		return false
	budget -= 1
	return true


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < d


func world_to_col(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell), floori(p.z / cell))


func ground_y(c: Vector2i) -> float:
	return ground[c.x + w * c.y] * cell


func col_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * cell, ground_y(c), (c.y + 0.5) * cell)


func water_depth(c: Vector2i) -> float:
	return world.water.depth_m(c.x + w * c.y)


func is_walkable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var i := c.x + w * c.y
	if blocked[i] == 1:
		return false
	var g := ground[i]
	if g <= 0 or g >= world.data.size.y - 2:
		return false
	return world.water.depth_m(i) <= max_water


func why_not_walkable(c: Vector2i) -> String:
	if not in_bounds(c):
		return "außerhalb der Welt"
	var i := c.x + w * c.y
	if blocked[i] == 1:
		return "vom Lebensbaum belegt"
	if world.water.depth_m(i) > max_water:
		return "Wasser %.2f m tief" % world.water.depth_m(i)
	return "keine Standfläche/Kopffreiheit"


func can_step(a: Vector2i, b: Vector2i) -> bool:
	var dh := ground[b.x + w * b.y] - ground[a.x + w * a.y]
	return dh <= max_up and -dh <= max_drop


## A*-Suche. Ziel erreicht, wenn Knoten == to oder (radius > 0) Abstand der Spaltenmitten ≤ radius.
## Ist das Ziel selbst nicht begehbar, reicht eine angrenzende Spalte.
func find_path(from: Vector2i, to: Vector2i, arrive_radius_m: float = 0.0) -> Dictionary:
	stats["requests"] += 1
	if not in_bounds(from) or not in_bounds(to):
		return _fail("out_of_world", "Start oder Ziel außerhalb der Welt.", 0)
	var radius := arrive_radius_m
	if not is_walkable(to):
		radius = maxf(radius, cell * 1.5)
	var goal_center := Vector2((to.x + 0.5) * cell, (to.y + 0.5) * cell)
	var start_i := from.x + w * from.y
	var g_score := {start_i: 0.0}
	var came := {}
	var heap_f: Array = [_h(from, to)]
	var heap_n: Array = [start_i]
	var closed := {}
	var expansions := 0
	while heap_n.size() > 0:
		var cur: int = _pop(heap_f, heap_n)
		if closed.has(cur):
			continue
		closed[cur] = true
		expansions += 1
		var cx := cur % w
		var cz := cur / w
		var cc := Vector2i(cx, cz)
		var reached := cc == to
		if not reached and radius > 0.0:
			reached = Vector2((cx + 0.5) * cell, (cz + 0.5) * cell).distance_to(goal_center) <= radius
		if reached:
			stats["found"] += 1
			stats["expansions"] += expansions
			return {"ok": true, "path": _rebuild(came, cur, start_i), "code": "ok", "reason": "", "expansions": expansions}
		if expansions >= max_expansions:
			return _fail("search_limit", "Wegsuche nach %d Knoten abgebrochen (Ziel zu weit oder unerreichbar)." % expansions, expansions)
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var n := Vector2i(cx + dx, cz + dz)
				if not is_walkable(n) or not can_step(cc, n):
					continue
				if dx != 0 and dz != 0:
					var o1 := Vector2i(cx + dx, cz)
					var o2 := Vector2i(cx, cz + dz)
					if not is_walkable(o1) or not is_walkable(o2) or not can_step(cc, o1) or not can_step(cc, o2):
						continue
				var ni := n.x + w * n.y
				if closed.has(ni):
					continue
				var step_cost := 1.41421 if dx != 0 and dz != 0 else 1.0
				step_cost += 0.5 * absi(ground[ni] - ground[cur])
				var tentative: float = g_score[cur] + step_cost
				if tentative < float(g_score.get(ni, INF)):
					g_score[ni] = tentative
					came[ni] = cur
					_push(heap_f, heap_n, tentative + _h(n, to), ni)
	return _fail("unreachable", "Kein begehbarer Weg zum Ziel (Hindernisse, Wasser, Stufen > %d Zelle)." % max_up, expansions)


func _fail(code: String, reason: String, expansions: int) -> Dictionary:
	stats["failed"] += 1
	stats["expansions"] += expansions
	return {"ok": false, "path": [], "code": code, "reason": reason, "expansions": expansions}


func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dz := absi(a.y - b.y)
	return float(maxi(dx, dz)) + 0.41421 * float(mini(dx, dz))


func _rebuild(came: Dictionary, cur: int, start_i: int) -> Array:
	var path: Array = []
	while cur != start_i:
		path.push_front(Vector2i(cur % w, cur / w))
		cur = came[cur]
	return path


# Binärer Min-Heap auf zwei parallelen Arrays
func _push(hf: Array, hn: Array, f: float, n: int) -> void:
	hf.append(f)
	hn.append(n)
	var i := hf.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if hf[p] <= hf[i]:
			break
		var tf = hf[p]; hf[p] = hf[i]; hf[i] = tf
		var tn = hn[p]; hn[p] = hn[i]; hn[i] = tn
		i = p


func _pop(hf: Array, hn: Array) -> int:
	var top: int = hn[0]
	var last := hf.size() - 1
	hf[0] = hf[last]
	hn[0] = hn[last]
	hf.remove_at(last)
	hn.remove_at(last)
	var i := 0
	var n := hf.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and hf[l] < hf[m]:
			m = l
		if r < n and hf[r] < hf[m]:
			m = r
		if m == i:
			break
		var tf = hf[m]; hf[m] = hf[i]; hf[i] = tf
		var tn = hn[m]; hn[m] = hn[i]; hn[i] = tn
		i = m
	return top
