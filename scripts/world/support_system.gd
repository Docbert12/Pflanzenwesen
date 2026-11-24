class_name SupportSystem
extends RefCounted
## VEREINFACHTE ABSTÜTZUNG – keine Baustatik.
## Regel: Eine feste Zelle gilt als gestützt, wenn sie über 6er-Nachbarschaft mit einer
## verankerten Zelle (Grundgestein, unterste Lage) verbunden ist.
## Nach dem Entfernen einer Zelle werden ihre Nachbarverbände geprüft:
##  - Verband erreicht eine verankerte Zelle → bleibt stehen.
##  - Verband größer als max_fragment_cells → bleibt ohne weitere Prüfung stehen
##    (Grenze; große Überhänge halten sich im Modell selbst).
##  - sonst → wird als bewegliches Bruchstück abgetrennt (falls die Höchstzahl
##    gleichzeitiger Bruchstücke nicht erreicht ist; sonst bleibt er stehen und es wird protokolliert).
## Material, Festigkeit und Lasten spielen in dieser Regel KEINE Rolle.

const N6 := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var max_fragment_cells: int = 256


## Gibt die abgetrennten Verbände zurück: Array[{"cells": Array[Vector3i], "status": "detach"|"too_large"}]
func check_after_removal(data: VoxelData, palette: VoxelPalette, removed: Vector3i) -> Array:
	var results: Array = []
	var visited := {}
	for d in N6:
		var start: Vector3i = removed + d
		if visited.has(start) or not data.in_bounds(start.x, start.y, start.z):
			continue
		if palette.solid[data.get_cell(start.x, start.y, start.z)] != 1:
			continue
		var comp := _flood(data, palette, start, visited)
		if comp["anchored"]:
			continue
		results.append({"cells": comp["cells"], "status": "too_large" if comp["too_large"] else "detach"})
	return results


func _flood(data: VoxelData, palette: VoxelPalette, start: Vector3i, visited: Dictionary) -> Dictionary:
	var queue: Array = [start]
	var local := {start: true}
	var head := 0
	var anchored := false
	var too_large := false
	while head < queue.size():
		var c: Vector3i = queue[head]
		head += 1
		var t := data.get_cell(c.x, c.y, c.z)
		if c.y == 0 or palette.is_anchored(t):
			anchored = true
			break
		if queue.size() > max_fragment_cells:
			too_large = true
			break
		for d in N6:
			var n: Vector3i = c + d
			if local.has(n) or not data.in_bounds(n.x, n.y, n.z):
				continue
			if palette.solid[data.get_cell(n.x, n.y, n.z)] != 1:
				continue
			local[n] = true
			queue.append(n)
	for c in local:
		visited[c] = true
	return {"cells": queue if not (anchored or too_large) else [], "anchored": anchored, "too_large": too_large}
