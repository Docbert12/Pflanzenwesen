#!/usr/bin/env python3
"""HTTP-ATTRAPPE der Ollama-Abfrage-API – KEIN Ollama, KEIN Sprachmodell.

Nur für automatische Tests des echten HTTP-Transports (Verbindung, Kopfzeilen, JSON).
Antwortet ausschließlich lokal (127.0.0.1) auf:
  GET /api/version, GET /api/tags, GET /api/ps, POST /api/chat
Die Chat-Antwort ist regelbasiert (wie MockOllama.default_answer) und wählt nur angebotene Kandidaten.

Aufruf: python3 tools/ollama_attrappe.py --port 11999
"""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = "attrappe:klein"


def answer(ctx: dict) -> dict:
    req = ctx.get("anfrage", {})
    rid = int(req.get("request_id", 0))
    aid = int(ctx.get("ich", {}).get("id", 0))
    cand = ctx.get("kandidaten", {})
    if req.get("art") == "talk":
        topics = cand.get("themen", [])
        lid = int(ctx.get("zuhoerer", {}).get("id", 0))
        if not topics:
            return {"request_id": rid, "speaker_id": aid, "listener_id": lid, "intent": "none", "subject_id": 0,
                    "referenced_memory_ids": [], "expressed_certainty": 0.0}
        t = topics[0]
        return {"request_id": rid, "speaker_id": aid, "listener_id": lid, "intent": t.get("absicht", "none"),
                "subject_id": int(t.get("thema_id", 0)), "referenced_memory_ids": [],
                "expressed_certainty": float(t.get("eigene_sicherheit", 0.5)), "optional_text": "(Attrappe)"}
    foods = cand.get("nahrung", [])
    hunger = float(ctx.get("beduerfnisse", {}).get("hunger", 0.0))
    grasp = bool(ctx.get("faehigkeiten", {}).get("greifen", False))
    if hunger >= 0.4 and foods:
        f = int(foods[0]["id"])
        steps = [{"action": "go_to", "target_id": f}]
        steps += [{"action": "pick_up", "target_id": f}, {"action": "eat", "target_id": 0}] if grasp else [{"action": "eat", "target_id": f}]
        return {"request_id": rid, "actor_id": aid, "goal_type": "food", "proposed_steps": steps, "referenced_memory_ids": [],
                "uncertainty": 0.3, "interpretation": "none", "short_explanation": "(Attrappe) Nahrung aufsuchen."}
    return {"request_id": rid, "actor_id": aid, "goal_type": "explore", "proposed_steps": [{"action": "explore", "target_id": 0}],
            "referenced_memory_ids": [], "uncertainty": 0.6, "interpretation": "none", "short_explanation": "(Attrappe) Erkunden."}


class Handler(BaseHTTPRequestHandler):


    def log_message(self, *args):
        pass

    def _send(self, code: int, obj: dict) -> None:
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/version":
            self._send(200, {"version": "0.0.0-ATTRAPPE"})
        elif self.path == "/api/tags":
            self._send(200, {"models": [{"name": MODEL, "model": MODEL, "size": 1, "details": {"parameter_size": "Attrappe", "quantization_level": "-"}}]})
        elif self.path == "/api/ps":
            self._send(200, {"models": []})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/chat":
            self._send(404, {"error": "not found"})
            return
        n = int(self.headers.get("Content-Length", "0"))
        try:
            body = json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            self._send(400, {"error": "invalid json"})
            return
        if body.get("model") != MODEL:
            self._send(404, {"error": f"model '{body.get('model')}' not found"})
            return
        ctx = {}
        for m in reversed(body.get("messages", [])):
            if m.get("role") == "user":
                try:
                    ctx = json.loads(m.get("content", "{}"))
                except Exception:
                    ctx = {}
                break
        content = json.dumps(answer(ctx), ensure_ascii=False)
        self._send(200, {"model": MODEL, "created_at": "ATTRAPPE", "done": True, "done_reason": "stop",
                         "message": {"role": "assistant", "content": content}, "eval_count": len(content) // 4, "total_duration": 1000000})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=11999)
    a = ap.parse_args()
    ThreadingHTTPServer(("127.0.0.1", a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
