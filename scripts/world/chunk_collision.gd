class_name ChunkCollision
extends RefCounted
## Kollision eines Chunks: ein statischer Körper mit EINER konkaven Form aus genau
## den Dreiecken des sichtbaren Netzes (gleiche Geometrie wie die Darstellung).


static func apply(body: StaticBody3D, triangles: PackedVector3Array) -> int:
	var cs: CollisionShape3D = body.get_node_or_null("Shape")
	if cs == null:
		cs = CollisionShape3D.new()
		cs.name = "Shape"
		body.add_child(cs)
	if triangles.is_empty():
		cs.shape = null
		cs.disabled = true
		return 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(triangles)
	cs.shape = shape
	cs.disabled = false
	return triangles.size() / 3
