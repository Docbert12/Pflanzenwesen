class_name VoxelMesher
extends RefCounted
## Baut aus einem Voxelgitter ein zusammengefasstes Netz (ein ArrayMesh pro Gitter/Chunk).
## - Es entstehen nur sichtbare Außenflächen (Fläche nur, wenn der Nachbar nicht fest ist).
## - Kein Node und kein Physikkörper pro Voxel.
## - Gleichzeitig werden die Dreiecke für die Kollision geliefert (dieselben Flächen),
##   damit Darstellung und Kollision dieselbe Geometrie haben.
## Gitterindex: x + dims.x * (y + dims.y * z). Zellwert 0 = leer.

# Normalen und Flächenachsen (u × v = n), Ecke = basis + u·a + v·b (Einheitswürfel)
const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const BASE := [Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, 0)]
const U := [Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
const V := [Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0)]
const SHADE := [0.86, 0.86, 1.0, 0.62, 0.93, 0.93]  # leichte Richtungsabschattung (nur Darstellung)


## dims: Gittergröße; cells: Typ je Zelle; colors: Farbe je Typ (Index = Typ);
## solid: 1 = fest (blockiert Nachbarflächen); collide: 1 = erzeugt Kollisionsdreiecke;
## outside: Callable(x, y, z) -> int für Zellen außerhalb des Gitters (Chunk-Nachbarn); leer = Luft.
## Rückgabe: {"mesh": ArrayMesh|null, "collision": PackedVector3Array, "faces": int, "solid_cells": int}
static func build(dims: Vector3i, cells: PackedByteArray, colors: PackedColorArray, voxel_size: float,
		origin: Vector3, solid: PackedByteArray, collide: PackedByteArray, outside: Callable = Callable(),
		jitter: float = 0.05, below_is_solid: bool = false) -> Dictionary:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var coll := PackedVector3Array()
	var sx := dims.x
	var sy := dims.y
	var sz := dims.z
	var plane := sx * sy
	var faces := 0
	var solid_cells := 0
	var has_outside := outside.is_valid()
	for z in sz:
		for y in sy:
			var row := sx * (y + sy * z)
			for x in sx:
				var t: int = cells[row + x]
				if t == 0:
					continue
				solid_cells += 1
				var base_col: Color = colors[t]
				if jitter > 0.0:
					var h := ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) & 1023
					base_col = base_col.lightened(0.0) * (1.0 - jitter + 2.0 * jitter * (h / 1023.0))
					base_col.a = colors[t].a
				var does_collide: bool = collide[t] == 1
				for d in 6:
					var dir: Vector3i = DIRS[d]
					var nx := x + dir.x
					var ny := y + dir.y
					var nz := z + dir.z
					var nt := 0
					if nx >= 0 and nx < sx and ny >= 0 and ny < sy and nz >= 0 and nz < sz:
						nt = cells[nx + sx * (ny + sy * nz)]
					elif ny < 0 and below_is_solid:
						nt = 1
					elif has_outside:
						nt = outside.call(nx, ny, nz)
					if nt != 0 and solid[nt] == 1:
						continue
					# Transparente/nicht feste Nachbarn gleichen Typs verdecken sich gegenseitig
					if nt == t:
						continue
					faces += 1
					var p0: Vector3 = origin + (Vector3(x, y, z) + BASE[d]) * voxel_size
					var u: Vector3 = U[d] * voxel_size
					var v: Vector3 = V[d] * voxel_size
					var p1 := p0 + u
					var p2 := p0 + u + v
					var p3 := p0 + v
					# Uhrzeigersinn von außen gesehen (Godot-Vorderseite)
					verts.append_array([p0, p3, p2, p0, p2, p1])
					var c: Color = base_col * SHADE[d]
					c.a = base_col.a
					cols.append_array([c, c, c, c, c, c])
					var n := Vector3(dir)
					norms.append_array([n, n, n, n, n, n])
					if does_collide:
						coll.append_array([p0, p3, p2, p0, p2, p1])
	var mesh: ArrayMesh = null
	if verts.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "collision": coll, "faces": faces, "solid_cells": solid_cells}


## Zählt sichtbare Außenflächen eines Gitters ohne Netz zu bauen (für Prüfungen).
static func count_exposed_faces(dims: Vector3i, cells: PackedByteArray, solid: PackedByteArray, below_is_solid: bool) -> int:
	var n := 0
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				var t: int = cells[x + dims.x * (y + dims.y * z)]
				if t == 0:
					continue
				for d in 6:
					var dir: Vector3i = DIRS[d]
					var nx := x + dir.x
					var ny := y + dir.y
					var nz := z + dir.z
					var nt := 0
					if nx >= 0 and nx < dims.x and ny >= 0 and ny < dims.y and nz >= 0 and nz < dims.z:
						nt = cells[nx + dims.x * (ny + dims.y * nz)]
					elif ny < 0 and below_is_solid:
						nt = 1
					if (nt != 0 and solid[nt] == 1) or nt == t:
						continue
					n += 1
	return n
