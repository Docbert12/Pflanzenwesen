class_name WaterSystem
extends RefCounted
## EINFACHES MENGENBASIERTES WASSER-HÖHENMODELL – keine Flüssigkeitsphysik.
## Je Terrainspalte (x, z) wird eine Wassermenge in m³ geführt. Sie liegt auf der höchsten
## festen Zelle der Spalte. Wasserspiegel = Bodenhöhe + Menge / Spaltenfläche.
## Pro Schritt fließt zwischen 4-Nachbarn Wasser vom höheren zum niedrigeren Spiegel.
## Erhaltung: jede Übertragung wird paarweise gebucht (−q / +q); Mengen werden nie negativ,
## weil jede Spalte pro Schritt höchstens ¼ ihres Wassers je Nachbar abgibt.
## Feste Barrieren: liegt der Boden des Nachbarn über dem eigenen Spiegel, fließt nichts hinüber.
## Grenzen: nur EINE Wasserschicht je Spalte; Höhlen und Überhänge (Luft unter festen Zellen)
## werden nicht gefüllt; kein Druck, keine Strömungsgeschwindigkeit, keine Verdunstung.

var w: int
var d: int
var cell: float
var area: float
var flow_rate: float = 2.0   # Anteil der Spiegeldifferenz pro Sekunde (Spielparameter)
var amount := PackedFloat64Array()
var ground := PackedInt32Array()  # Bodenhöhe in Zellen
var initial_total: float = 0.0
var steps: int = 0


func setup(data: VoxelData, palette: VoxelPalette, initial: PackedFloat64Array, rate: float) -> void:
	w = data.size.x
	d = data.size.z
	cell = data.cell_size
	area = cell * cell
	flow_rate = rate
	amount = initial.duplicate()
	ground.resize(w * d)
	for z in d:
		for x in w:
			ground[x + w * z] = data.column_top(x, z, palette.solid)
	initial_total = total()
	steps = 0


func update_column(data: VoxelData, palette: VoxelPalette, x: int, z: int) -> void:
	if x < 0 or z < 0 or x >= w or z >= d:
		return
	ground[x + w * z] = data.column_top(x, z, palette.solid)


func level_m(i: int) -> float:
	return ground[i] * cell + amount[i] / area


func depth_m(i: int) -> float:
	return amount[i] / area


func total() -> float:
	var s := 0.0
	for a in amount:
		s += a
	return s


## Ein Schritt. Gibt die insgesamt bewegte Menge [m³] zurück.
func step(dt: float) -> float:
	steps += 1
	var n := w * d
	var flow_e := PackedFloat64Array()
	var flow_s := PackedFloat64Array()
	flow_e.resize(n)
	flow_s.resize(n)
	var k := minf(flow_rate * dt, 0.25)
	for z in d:
		for x in w:
			var i := x + w * z
			var li := ground[i] * cell + amount[i] / area
			if x + 1 < w:
				flow_e[i] = _pair_flow(i, i + 1, li, k)
			if z + 1 < d:
				flow_s[i] = _pair_flow(i, i + w, li, k)
	var moved := 0.0
	for z in d:
		for x in w:
			var i := x + w * z
			var qe := flow_e[i]
			if qe != 0.0:
				amount[i] -= qe
				amount[i + 1] += qe
				moved += absf(qe)
			var qs := flow_s[i]
			if qs != 0.0:
				amount[i] -= qs
				amount[i + w] += qs
				moved += absf(qs)
	return moved


func _pair_flow(i: int, j: int, li: float, k: float) -> float:
	var lj := ground[j] * cell + amount[j] / area
	var dl := li - lj
	if dl > 1e-9:
		return minf(k * dl * area, amount[i] * 0.25)
	elif dl < -1e-9:
		return -minf(k * -dl * area, amount[j] * 0.25)
	return 0.0
