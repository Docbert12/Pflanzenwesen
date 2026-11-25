# Animationen: vorhanden und fehlend (Stand v0.6.1, Prompt 6B)

Alle Animationen sind prozedural (`scripts/animation/creature_animator.gd`) und bewegen nur Gelenke, die im
Körperplan wirksam vorhanden sind. Fehlt ein benötigter Teil, wird auf eine ausdrücklich unterstützte Variante
ausgewichen (andere Hand, Hakengriff, einarmig) oder die Animation verständlich abgelehnt.

## Grundsatz für Arbeitsposen (Prompt 6B)

- Die **Handlung** ist für den Vorgang zuständig (Schaden, Verbrauch, Übergabe – genau einmal an einem festen Zeitpunkt).
  Sie schreibt `a.state["anim"] = {pose, phase, u, target, contacts, …}`. Die Animation **liest nur**.
- Phasen jeder aktiven Arbeitshandlung: `approach` (echte Bewegung zum Standpunkt) → `prepare` (Ausgangspose) →
  `work` / `contact` → `recover` (Rückkehr in eine gültige Pose). Abbruch: Pose blendet in 0,3 s weich zurück.
- Gelenkwinkel aus `scripts/animation/work_pose.gd` – **dieselbe Geometrie**, mit der die Handlung den Standpunkt
  wählt: Schulterhöhe, Ober-/Unterarm, Handlänge und Beinlängen aus dem Körperplan, Griff→Kopf-Abstand aus dem
  tatsächlich gehaltenen Werkzeug, Griffwinkel 45° in der Faust. Rumpfneigung φ, Hocke über die Knie (Füße bleiben am
  Boden, Beine gleichen die Rumpfneigung aus), Armwinkel α, Werkzeugwinkel β (Handgelenk bzw. Haken).
- Prüfung ohne Grafik: Die Gelenkkette der Animation trifft die WorkPose-Kontaktpunkte exakt (Test
  „Arbeitsposen: Gelenkkette …“), der sichtbare Hammerkopf liegt beim Kontakt ≤ 8 cm am Ziel (gemessen ≈ 2 cm,
  Logiktest und Szenentest in der echten Spielszene). Während der Arbeitsphase steht das Wesen (kein Fußgleiten).
- Gehaltene Gegenstände sitzen am **Griffpunkt der animierten Hand** (Verbund: Ursprung = Griffpunkt; Stab am Ende
  gegriffen; Stück mittig); zweihändig mittig zwischen beiden Händen.

## Liste

| Animation | Excel | Status | Ausgelöst durch | Körperbedingungen / Ersatz |
|---|---|---|---|---|
| `idle` Ruhehaltung | A001 Stehen | vorhanden | keine Handlung | – |
| `walk` Gehen | A002 Gehen | vorhanden (Takt ∝ Geschwindigkeit) | `move_to` | beide Beine vollständig; **Hinken fehlt** |
| `walk_short` Anlauf | (A002) | **neu 6B** | Anlaufphase jeder Arbeitshandlung | wie Gehen |
| `grasp` Greifen | A003 Aufheben | vorhanden; **6B:** mit Anlauf, Bücken, Griff am Gegenstand | `pick_up`, `equip_tool` | Hand oder Kupferhaken; andere Seite als Ersatz |
| `eat` Zum Mund führen | A004 Essen | vorhanden | `eat` (getragene Nahrung) | nur echte Hand |
| `raise_arms` Arme heben | – | vorhanden (Prompt 4) | `raise_arms` | vorhandene Oberarme |
| `carry` Tragen (eine Hand) | – | **neu 6B** | `move_to` mit gehaltenem Gegenstand, Halten ohne Handlung | eine Greifhand |
| `carry_two` Aufnehmen/Tragen mit zwei Händen | – | **neu 6B** | `equip_tool` (carry, zweihändig), Gehen mit zweihändig Gehaltenem | zwei Greifhände, sonst abgelehnt |
| `put_down` / `put_down_two` Ablegen | – | **neu 6B** | `drop` (Gegenstand) | eine bzw. zwei Greifhände |
| `place` / `place_two` Einsetzen | – | **neu 6B** | `deposit_in_storage`, `place_building_part`, `put_into_container` | eine bzw. zwei Greifhände |
| `strike` Hämmern/Schlagen | – | **neu 6B** (Ausholen → Kontakt → Rückkehr) | `strike_target`, `deform_material` | eine Greifhand (Hand oder Haken) |
| `assemble` Zusammenfügen | – | **neu 6B** | `connect_parts` | zwei Greifhände |
| `assemble_one` Zusammenfügen einarmig | – | **neu 6B** (Variante) | `connect_parts` mit einer Hand (Dauer ×1,8, Passung ×0,8) | eine Greifhand |
| `operate_heater` Erhitzen bedienen | – | **neu 6B** | `place_in_heater` | eine Greifhand |
| `pour` Vorsichtiges Gießen | – | **neu 6B** (langsames Kippen über die Gießdauer) | `pour_into_mold` | eine Greifhand, Tiegel mit Griff |
| `dig` Graben | – | **vorbereitet, abgewiesen** | – | Abbau mit Mengenbilanz fehlt (Zusatz Weltarchitektur) |
| `compact` Erde verdichten | – | **vorbereitet, abgewiesen** | – | Verdichten/Aufschütten mit Mengenbilanz fehlt |
| Vierbeiner-Ruhe | A005 Stehen (Vierbeiner) | **fehlt** | – | keine Vierbeiner im Spiel |

## Fehlend (bekannt, nicht in 6B)

- Hinken bzw. Kriechen bei verletztem Bein (Excel A002 Sonderfall).
- Ellbogenbeugung beim Arbeiten (vereinfacht: Ober- und Unterarm in einer Linie; Beugung im Handgelenk bzw. am Haken).
- Werfen, Klettern, Tragen auf dem Rücken, gemeinsames Tragen zu zweit (Prompt 9).
- Graben und Verdichten (siehe oben), Abbauwerkzeuge.
- Gesten außer „Arme heben“, Mimik.

## Vorführung im Kreaturen-Werkzeug

Startbildschirm → Kreaturenvorschau → „Animation“: neben Ruhe/Gehen/Greifen/Zum Mund die Arbeitsposen Schlagen,
Einsetzen, Ablegen 2H, Verbinden, Verbinden 1H, Gießen und Graben (abgewiesen). Ohne Handlung laufen sie als zyklische
Vorführung mit einem Ziel 30 cm vor dem Wesen.
