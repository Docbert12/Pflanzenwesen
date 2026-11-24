#!/usr/bin/env python3
"""Vergleicht zwei Projektstände und listet auf, was ENTFERNT oder geändert wurde.

Zweck: Vor jeder Lieferung prüfen, dass beim Ausbau nichts unbemerkt verloren geht.

Stände können sein:
  - ein Ordner                      z. B.  ../alt
  - eine ZIP-Datei                  z. B.  Pflanzenwesen_v0.5.0_prompt05.zip
  - eine Git-Version (im Repo)      z. B.  git:v0.5.0   oder   git:HEAD

Aufruf:
  python3 tools/compare_versions.py git:v0.5.0 .            # letzte Version gegen Arbeitsstand
  python3 tools/compare_versions.py alt.zip neu.zip --md bericht.md

Geprüft wird:
  - Dateien: neu / entfernt / geändert
  - GDScript: entfernte class_name, entfernte Funktionen (je Datei)
  - Tests: entfernte Prüfungen (Texte in _check("…") unter tests/)
  - Konfiguration: entfernte Schlüssel in data/config/*.json und data/settings/*.json (bis Tiefe 2)

Rückgabe 0 = nichts entfernt, 1 = Entfernungen gefunden (bewusst begründen!), 2 = Fehler.
"""
import argparse
import hashlib
import io
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path

IGNORE_PARTS = {".git", ".godot", "__pycache__"}
IGNORE_SUFFIX = {".pyc", ".tmp", ".uid"}
FUNC_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.M)
CLASS_RE = re.compile(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
CHECK_RE = re.compile(r'_check\(\s*"((?:[^"\\]|\\.)*)"')


def _keep(path: str) -> bool:
    parts = Path(path).parts
    if any(p in IGNORE_PARTS for p in parts):
        return False
    return Path(path).suffix not in IGNORE_SUFFIX


def load(spec: str) -> dict:
    """Gibt {relativer_pfad: bytes} zurück."""
    files = {}
    if spec.startswith("git:"):
        ref = spec[4:]
        names = subprocess.run(["git", "ls-tree", "-r", "--name-only", ref], capture_output=True, text=True, check=True).stdout.splitlines()
        for n in names:
            if _keep(n):
                files[n] = subprocess.run(["git", "show", f"{ref}:{n}"], capture_output=True, check=True).stdout
        return files
    p = Path(spec)
    if p.is_file() and p.suffix.lower() == ".zip":
        with zipfile.ZipFile(p) as z:
            for n in z.namelist():
                if not n.endswith("/") and _keep(n):
                    files[n.lstrip("./")] = z.read(n)
        return files
    if p.is_dir():
        for f in p.rglob("*"):
            rel = f.relative_to(p).as_posix()
            if f.is_file() and _keep(rel):
                files[rel] = f.read_bytes()
        return files
    raise FileNotFoundError(spec)


def _text(b: bytes) -> str:
    return b.decode("utf-8", errors="replace")


def _keys(obj, prefix="", depth=0, out=None):
    out = set() if out is None else out
    if isinstance(obj, dict) and depth < 2:
        for k, v in obj.items():
            if str(k).startswith("_"):
                continue
            key = f"{prefix}{k}"
            out.add(key)
            _keys(v, key + ".", depth + 1, out)
    return out


def compare(old: dict, new: dict) -> dict:
    r = {"added": sorted(set(new) - set(old)), "removed": sorted(set(old) - set(new)),
         "changed": sorted(f for f in set(old) & set(new) if hashlib.sha256(old[f]).digest() != hashlib.sha256(new[f]).digest()),
         "removed_classes": [], "removed_funcs": {}, "removed_checks": [], "removed_config_keys": {}}
    old_classes = {c: f for f, b in old.items() if f.endswith(".gd") for c in CLASS_RE.findall(_text(b))}
    new_classes = {c for f, b in new.items() if f.endswith(".gd") for c in CLASS_RE.findall(_text(b))}
    r["removed_classes"] = sorted(f"{c} ({old_classes[c]})" for c in old_classes if c not in new_classes)
    for f, b in old.items():
        if not f.endswith(".gd"):
            continue
        of = set(FUNC_RE.findall(_text(b)))
        nf = set(FUNC_RE.findall(_text(new[f]))) if f in new else set()
        gone = sorted(of - nf)
        if gone and f in new:
            r["removed_funcs"][f] = gone
    oc = {c for f, b in old.items() if f.startswith("tests/") and f.endswith(".gd") for c in CHECK_RE.findall(_text(b))}
    nc = {c for f, b in new.items() if f.startswith("tests/") and f.endswith(".gd") for c in CHECK_RE.findall(_text(b))}
    r["removed_checks"] = sorted(oc - nc)
    r["checks_old"], r["checks_new"] = len(oc), len(nc)
    for f, b in old.items():
        if not (f.startswith("data/config/") or f.startswith("data/settings/")) or not f.endswith(".json") or f not in new:
            continue
        try:
            ok, nk = _keys(json.loads(_text(b))), _keys(json.loads(_text(new[f])))
        except json.JSONDecodeError:
            continue
        gone = sorted(ok - nk)
        if gone:
            r["removed_config_keys"][f] = gone
    return r


def has_removals(r: dict) -> bool:
    return bool(r["removed"] or r["removed_classes"] or r["removed_funcs"] or r["removed_checks"] or r["removed_config_keys"])


def markdown(r: dict, old: str, new: str) -> str:
    L = [f"# Versionsvergleich `{old}` → `{new}`", "",
         f"Dateien: **{len(r['added'])} neu**, **{len(r['removed'])} entfernt**, **{len(r['changed'])} geändert** · "
         f"Testprüfungen (Texte): {r['checks_old']} → {r['checks_new']}", ""]
    L.append("## Entfernt (bitte jede Zeile begründen)")
    if not has_removals(r):
        L.append("- nichts")
    for f in r["removed"]:
        L.append(f"- Datei: `{f}`")
    for c in r["removed_classes"]:
        L.append(f"- Klasse: `{c}`")
    for f, fs in r["removed_funcs"].items():
        L.append(f"- Funktionen in `{f}`: " + ", ".join(f"`{x}`" for x in fs))
    for c in r["removed_checks"]:
        L.append(f"- Testprüfung: „{c}“")
    for f, ks in r["removed_config_keys"].items():
        L.append(f"- Konfiguration `{f}`: " + ", ".join(f"`{k}`" for k in ks))
    L += ["", "## Neu"] + [f"- `{f}`" for f in r["added"]] or ["- nichts"]
    L += ["", "## Geändert"] + [f"- `{f}`" for f in r["changed"]]
    return "\n".join(L) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("--md", help="Bericht als Markdown-Datei schreiben")
    a = ap.parse_args(argv)
    try:
        r = compare(load(a.old), load(a.new))
    except Exception as e:  # noqa: BLE001
        print(f"Fehler: {e}", file=sys.stderr)
        return 2
    md = markdown(r, a.old, a.new)
    if a.md:
        Path(a.md).write_text(md, encoding="utf-8")
    print(md)
    return 1 if has_removals(r) else 0


if __name__ == "__main__":
    sys.exit(main())
