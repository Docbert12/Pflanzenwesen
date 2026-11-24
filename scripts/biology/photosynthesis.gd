class_name Photosynthesis
extends RefCounted
## SPIELMODELL der Lichtenergie (keine reale Pflanzenphysiologie):
##   P [W] = k · wirksame Blattfläche [m²] · Licht (0…1) · Verschattung (0…1)
## wirksame Blattfläche: aus vorhandenen Blättern, gemindert durch deren Schaden (BodyCapabilities).
## Licht: DayNightSystem (unabhängig von Bildschirm, Kamera und Grafik).
## Verschattung: unter der Baumkrone Faktor shade_factor_under_crown, sonst 1.
## Licht liefert nur Energie, keine Nährstoffe.

static func power_w(leaf_area_m2: float, light: float, shade: float, cfg: Dictionary) -> float:
	var k := float(cfg.get("photosynthesis", {}).get("power_w_per_m2_full_light", 230.0))
	return maxf(0.0, k * leaf_area_m2 * clampf(light, 0.0, 1.0) * clampf(shade, 0.0, 1.0))


static func shade_at(ctx: LifeContext, pos: Vector3) -> float:
	var col := ctx.nav.world_to_col(pos)
	if ctx.shade_cols.has(col):
		return float(ctx.c("photosynthesis").get("shade_factor_under_crown", 0.35))
	return 1.0
