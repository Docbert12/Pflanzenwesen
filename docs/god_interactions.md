# Göttermenü und Eingriffe (Stand 0.4.0-prototype – Prompt 4)

Dateien:
- `scripts/god/god_commands.gd`: Befehle, Prüfung, Vorschau.
- `scripts/god/intervention_system.gd`: Ausführung, Protokoll, Bilanz.
- `scripts/god/reward_association.gd`: Deutung durch Wesen.
- `scripts/ui/god_menu.gd`: Oberfläche.

## Grundsätze
- Der Spieler **spricht nicht** mit Wesen und gibt **keine Befehle**. Er verändert die Welt sichtbar.
- Drei getrennte Dinge:
  1. **Absicht des Spielers:** gewählte Art und optional „als Reaktion auf Ereignis X“. Sie wird nur im Eingriffsprotokoll gespeichert (`record.player`), für Diagnose und Auswertung. Sie gelangt **nie** in den Geist eines Wesens (getestet: kein `linked_event` im Geist).
  2. **Sichtbarer Eingriff:** Weltänderung plus Ereignis `food_appeared`, `material_appeared` oder `healed` mit Sichtweite 14 m, dazu ein leuchtendes Zeichen für 4 s.
  3. **Deutung je Beobachter:** Nur Wesen, die den Eingriff tatsächlich wahrnehmen (Reichweite, Sichtlinie, lebend), deuten ihn, jedes nach eigenen Handlungen und eigenem Bedarf. Abwesende wissen nichts (Test C).

## Bedienung
1. Im Spiel **G** oder „Göttermenü (G)“ öffnet das gelb umrandete Feld.
2. **Eingriff** wählen:

   | Eingriff | Einstellungen |
   |---|---|
   | **Nahrung schenken** | Beeren (N001) oder Pilz (N002), 0,05–1,0 kg |
   | **Material platzieren** | Stein, Holz, Kupfer oder **Pflanzenfasern** (seit 0.6.0). Formen: Würfel mit 12 cm Kante (Stein, Holz, Kupfer), kleiner Block 5 cm (Stein, Kupfer), Stab 40 cm × 2,5 cm (Holz, Kupfer), Faserbündel (Pflanzenfasern). Die Masse ist Dichte × Volumen, ein Kupferwürfel z. B. 15,5 kg. Ein Stück liegt bei Umgebungstemperatur. |
   | **Verletzung heilen** | bis zu 0,1–1,0 Schadensanteil |

3. **Ziel** wählen:
   - „beim ausgewählten Wesen“: Das Wesen vorher anklicken; die Gabe erscheint 0,55 m vor ihm. Heilen gilt immer dem ausgewählten Wesen.
   - „angeklickte Position“: „Position wählen“ drücken und in die Welt klicken. Der Strahl trifft das Gelände.
4. Optional ein **Ereignis** zuordnen: Die Liste zeigt kürzlich geschehene Ereignisse (Arme heben, Nahrung gegeben, Bitte abgelehnt, gegessen …), wahlweise nur die des ausgewählten Wesens. Ein Eintrag anklicken setzt „als Reaktion auf ausgewähltes Ereignis“.
5. Die **Vorschau** zeigt vor der Ausführung Eingriffsart, Ziel bzw. Position, Menge bzw. Umfang und das zugeordnete Ereignis (gekennzeichnet als „nur Spielerwissen“). Ist der Eingriff nicht ausführbar, steht der Grund dort.
6. **„Eingriff ausführen“**. Die Meldung nennt die Eingriffs-ID und wie viele Wesen ihn wahrgenommen haben.

## Prüfungen
**Position:**
- im Feld und begehbarer Boden;
- kein Baumstamm, kein tiefes Wasser, nicht in festem Gelände;
- mindestens 0,35 m Abstand zu jedem Wesenkörper.

**Mengen und Material:** Nahrung 0,05–1,0 kg, nur N001 oder N002. Material nur Stein, Holz, Kupfer oder Pflanzenfasern, und nur in einer für das Material vorgesehenen Form (sonst abgewiesen).

**Heilen:**
- Es repariert vorhandenes verletztes Gewebe, den größten Schaden zuerst, bis zur gewählten Menge.
- Fehlende Körperteile werden **nicht** nachgebildet; ein entfernter Unterarm bleibt entfernt.
- Mangelschaden durch Hunger wird nicht geheilt.
- Ohne verletztes Gewebe oder bei toten Wesen wird abgewiesen.

## Bilanz und Protokoll
- **IDs:** Jeder Eingriff erhält eine fortlaufende **ID** (1, 2, 3 …). Der Eintrag `god_intervention` im Ereignisprotokoll enthält Art, Ergebnis und zugeordnetes Ereignis.
- **Nahrung:** Sie entsteht als echte Portion (`FoodItem`) am Boden. Die Menge wird als externe Zufuhr `ResourceLedger.god_kg` gebucht; die Nahrungsbilanz bleibt geschlossen. Wesen können die Portion sehen, aufnehmen und essen.
- **Material:** Es entsteht ein `MaterialPiece` (seit 0.6.0 ein physikalisches Objekt mit Wärme und Phase), registriert im EntityRegistry. Die Masse je Material steht in `InterventionSystem.totals.material_kg`. **Seit 0.6.0 können Wesen Material benutzen**: untersuchen, in die Hand nehmen, damit schlagen, Kupfer verformen und Stiel und Kopf mit Fasern verbinden. Sie tun das nur aus eigenem Antrieb und begrenzt (`docs/experimentation.md`), eine Freischaltung gibt es nicht.
- **Heilung:** Die geheilte Schadensmenge steht in `totals.healed_damage`, der Verlauf in `Health.causes` mit negativem Betrag.
- **Beobachter:** Das Eingriffsprotokoll enthält auch die Liste der Beobachter (Weltseite, Diagnose). Diese Liste ist **nicht** das Wissen der Wesen.

## Beobachten, wie Wesen reagieren
- Im Beobachtungsfenster eines Wesens unter **„Wahrgenommene Eingriffe“** stehen Zeit, Art, „Wert für mich“ und die eigene Erklärung.
- **Unter VERMUTUNG** stehen die entstehenden Hypothesen, „Nach eigenem X folgte ein auffälliges Ereignis“, mit Häufigkeit und Konfidenz.
- **Vergleich (V):** Zwei Wesen nebeneinander zeigen, dass Empfänger, Beobachter und Abwesende Verschiedenes wissen.

**Ein Experiment:**
1. Ein Wesen auswählen und auf ein „Arme heben“ mehrmals kurz danach mit „Nahrung schenken“ reagieren.
2. Danach unter VERMUTUNG prüfen, ob Häufigkeit und Konfidenz steigen. Nach einer Gabe ist die Konfidenz höchstens 0,2.
3. Ob das Wesen „Arme heben“ später von selbst wählt, zeigt ENTSCHEIDUNG (`repeat:raise_arms`). Bei Hunger gewinnt die Nahrungssuche.
4. Wer die Gaben danach weglässt, sieht die Erwartung wieder sinken.

## Grenzen
- Eingriffe sind nur Nahrung, Material und Heilung. Kein Wetter, kein Feuer, keine Bestrafung.
- Material hat nur den Nutzen, den die Wesen selbst ausprobieren. Ob ein Wesen es untersucht, als Werkzeug benutzt oder verbindet, hängt von Neugier, Hunger, Zeitbudget und Wissen ab. Es gibt keine Garantie. Testheizung, Tiegel und Form gibt es nur in der Testwerkstatt, nicht über das Göttermenü.
- Es gibt keinen „Gott“ als Weltobjekt: Die Wesen kennen keine Gottheit. Sie verbinden Ereignisse nur mit eigenen Handlungen.
