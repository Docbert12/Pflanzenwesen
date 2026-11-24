# Ollama einrichten (Prompt 5)

> **Stand der Prüfung:** Im Entwicklungsarbeitsbereich (Linux-Cloud, 2 CPU-Kerne, keine Grafikkarte) war **kein Ollama erreichbar** (`127.0.0.1:11434` – Verbindung abgelehnt). Die echte Verbindung ist deshalb **noch nicht verifiziert**. Alles Übrige ist mit einem **simulierten Testdienst** und einer lokalen **HTTP-Attrappe** geprüft (siehe `docs/test_results.md`). Das Spiel startet, lädt, löscht oder stoppt **nie** Modelle oder den Dienst.

## 1. Voraussetzungen auf deinem Rechner

| | GTX 1660 Ti (6 GB) – jetziger Rechner | RTX 3080 (10 GB) – zweiter Rechner |
|---|---|---|
| sinnvolle Modellgröße | **3–4 Mrd. Parameter**, 4-Bit-quantisiert (ca. 2–3,5 GB Grafikspeicher) | **7–9 Mrd. Parameter**, 4-Bit (ca. 5–6,5 GB) |
| erwartete Antwortzeit je Anfrage (Schätzung, nicht gemessen) | einige Sekunden; erste Anfrage länger (Modell wird geladen) | meist schneller |
| Spieleinstellung | 1 gleichzeitige Anfrage, 8 Anfragen/min (Vorgabe) | kann nach Messung erhöht werden |

Ollama-Version: strukturierte Ausgabe per JSON-Schema (Feld `format`) gibt es seit Ollama 0.5. Bitte eine aktuelle Version verwenden. Die Version zeigt das KI-Panel nach „Verbindung testen“ an.

## 2. Prüfen, was installiert ist (Windows, PowerShell)

```powershell
ollama --version
ollama list                      # installierte Modelle (Name, Größe)
ollama ps                        # gerade geladene Modelle (GPU/CPU-Anteil)
Invoke-RestMethod http://127.0.0.1:11434/api/version
Invoke-RestMethod http://127.0.0.1:11434/api/tags
```

Läuft der Dienst nicht: Ollama-App starten (Startmenü) oder `ollama serve`.

## 3. Modell wählen

Nimm ein **bereits installiertes** Modell aus `ollama list`. Gut geeignet sind kleine Anweisungsmodelle, die JSON zuverlässig einhalten. Beispiele (Verfügbarkeit und genaue Namen bitte in der Ollama-Bibliothek bzw. mit `ollama list` prüfen):

- 1660 Ti: z. B. `qwen2.5:3b`, `llama3.2:3b`, `gemma3:4b`, `qwen3:4b`
- 3080: z. B. `qwen2.5:7b`, `llama3.1:8b`, `qwen3:8b`

Modelle mit Denkmodus (z. B. qwen3): das Spiel sendet standardmäßig `"think": false` (schneller, kürzer). Falls dein Modell dabei einen Fehler meldet, setze in `user://ai_settings.json` `"think": null`.

Fehlt ein passendes Modell, lade es **selbst** (das Spiel tut das nie), z. B. `ollama pull qwen2.5:3b`.

## 4. Im Spiel einschalten

1. Neues Spiel oder Fortsetzen → **Taste K** (oder Knopf „KI (K)“).
2. „KI-Anbindung einschalten“ anhaken, Adresse `http://127.0.0.1:11434` lassen.
3. **Verbindung testen** → Zustand, Ollama-Version und die Liste der installierten Modelle erscheinen.
4. Modell in der Liste wählen → **Übernehmen + speichern**. Zustand muss „verbunden“ zeigen, Kopfzeile „ECHT – Ollama unter …“.

Gespeichert wird in `user://ai_settings.json` (Windows: `%APPDATA%\Godot\app_userdata\Pflanzenwesen\ai_settings.json`). Das ist eine **Anwendungseinstellung**, kein Teil des Spielstands.

## 5. Verbindung außerhalb des Spiels testen (Live-Test)

```powershell
cd C:\Pflanzenwesen
godot --headless --path . -s res://tools/ollama_live_test.gd -- --model=qwen2.5:3b --minutes=3
# mit Ausfallprüfung (du beendest und startest Ollama, wenn das Werkzeug dazu auffordert):
godot --headless --path . -s res://tools/ollama_live_test.gd -- --model=qwen2.5:3b --minutes=3 --unterbrechung
```

Das Werkzeug führt die fünf Live-Tests aus Prompt 5 aus (ein Plan, ein Gespräch, 50 Wesen mit Ratenbegrenzung, Ausfall, Wiederkehr) und schreibt `user://ollama_live_report.txt` mit Modell, Version, Umgebung, Antwortzeiten, Prüfergebnissen. Formulierungen des Modells sind nie identisch – bewertet werden Struktur, Prüfung und Wirkung.

## 6. Ollama auf dem anderen Rechner (RTX 3080) nutzen – nur bewusst

Standardmäßig erlaubt das Spiel **nur lokale Adressen**. Für einen zweiten Rechner im Heimnetz:
1. Dort Ollama auf das Netz lauschen lassen (Umgebungsvariable `OLLAMA_HOST=0.0.0.0`, Ollama neu starten). Ollama hat **keine eigene Anmeldung** – nur in einem vertrauenswürdigen Netz verwenden.
2. In `user://ai_settings.json`: `"allow_remote": true, "base_url": "http://192.168.x.y:11434"`.
3. Falls ein vorgeschalteter Dienst einen Schlüssel verlangt: `"auth_env_var": "NAME"` und den Schlüssel als Umgebungsvariable `NAME` setzen. Der Schlüssel wird nur zur Laufzeit gelesen, **nie** gespeichert, protokolliert oder in Spielstände geschrieben.

Es gibt **keine** automatische Ausweichverbindung (keine Cloud).

## 7. Häufige Meldungen

| Meldung im KI-Panel | Bedeutung / Abhilfe |
|---|---|
| „Ollama nicht erreichbar … Verbindung abgelehnt“ | Dienst läuft nicht oder falscher Port → Ollama starten |
| „Modell „X“ ist nicht installiert (installiert: …)“ | Namen aus der Liste wählen oder selbst `ollama pull X` |
| „verbunden – kein Modell gewählt“ | Modell im Panel wählen |
| „Zeitüberschreitung nach 90 s“ | Modell lädt noch (erste Anfrage) oder zu groß für die Karte → kleineres Modell, `timeout_s` erhöhen |
| „3 Fehler in Folge … Neue Anfragen pausiert“ | Unterbrecher aktiv; das Spiel prüft alle 15 s und macht danach automatisch weiter |
| viele „abgelehnt – Stufe 2/3/5“ | Modell hält das Schema schlecht ein → anderes Modell probieren; die Welt läuft trotzdem lokal |
