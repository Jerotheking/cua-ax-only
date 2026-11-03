#!/usr/bin/python3
"""Lee un secreto de 1Password y lo escribe por AX en un campo, sin imprimirlo.

El inyector abre su propio MCP, resuelve el campo (pid/ventana/rol) y escribe.
El token no se pasa entre procesos porque los snapshots son por proceso.

Uso:
  op-inject.py --ref op://Vault/Item/password --app TextEdit --role AXTextArea
  op-inject.py --ref ... --pid 123 --window-id 456 --role AXTextField --name Buscar
  op-inject.py --ref ... --check          # solo verifica lectura (no imprime)
"""
import argparse
import json
import os
import selectors
import subprocess
import sys
import time

FORK = os.path.expanduser("~/Applications/CuaDriverFork.app/Contents/MacOS/cua-driver")
POLICY = os.path.expanduser("~/.cua-driver/ax-only.yaml")


def read_secret(ref):
    env = dict(os.environ)
    env["OP_INJECT"] = "1"
    try:
        p = subprocess.run(["op", "read", "--no-newline", ref],
                           capture_output=True, text=True, timeout=90, env=env)
    except Exception as e:
        return None, f"op falló: {e.__class__.__name__}"
    if p.returncode != 0:
        lines = (p.stderr or "").strip().splitlines()
        return None, lines[-1][:180] if lines else "op read falló"
    return p.stdout, None


class Mcp:
    def __init__(self):
        env = dict(os.environ)
        env["CUA_DRIVER_AX_ONLY"] = "1"
        env["CUA_DRIVER_POLICY_FILE"] = POLICY
        self.p = subprocess.Popen([FORK, "mcp", "--direct"], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, bufsize=1, env=env)
        self.sel = selectors.DefaultSelector()
        self.sel.register(self.p.stdout, selectors.EVENT_READ)
        self.i = 0
        self.call("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                 "clientInfo": {"name": "op-inject", "version": "2"}},
                  method=True)

    def _send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def _wait(self, i, secs=30):
        end = time.time() + secs
        while time.time() < end:
            if self.sel.select(0.2):
                line = self.p.stdout.readline().strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except Exception:
                    continue
                if msg.get("id") == i:
                    return msg
        return None

    def call(self, name, args=None, method=False):
        self.i += 1
        if method:
            self._send({"jsonrpc": "2.0", "id": self.i, "method": name, "params": args or {}})
        else:
            self._send({"jsonrpc": "2.0", "id": self.i, "method": "tools/call",
                        "params": {"name": name, "arguments": args or {}}})
        r = self._wait(self.i) or {}
        res = r.get("result") or {}
        text = "".join(c.get("text", "") for c in res.get("content") or [])
        return bool(res.get("isError")), res.get("structuredContent") or {}, text

    def close(self):
        try:
            self.p.terminate()
        except Exception:
            pass


def find_element(sc, role, name):
    for e in sc.get("elements") or []:
        r = (e.get("role") or "").lower()
        n = (e.get("label") or e.get("name") or "")
        if role.lower() in r and (not name or name.lower() in n.lower()):
            return e
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True)
    ap.add_argument("--app")
    ap.add_argument("--pid", type=int)
    ap.add_argument("--window-id", type=int)
    ap.add_argument("--role", default="AXTextArea")
    ap.add_argument("--name", default="")
    ap.add_argument("--mode", choices=["value", "text"], default="value")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    secret, err = read_secret(a.ref)
    if secret is None:
        print(json.dumps({"ok": False, "error": err}))
        return 1
    if a.check:
        print(json.dumps({"ok": True, "bytes": len(secret)}))
        return 0

    m = Mcp()
    try:
        err, sc, _ = m.call("list_windows")
        wins = sc.get("windows") or []
        if a.app:
            wins = [w for w in wins if w.get("app_name") == a.app]
        if a.pid:
            wins = [w for w in wins if w.get("pid") == a.pid]
        if a.window_id:
            wins = [w for w in wins if w.get("window_id") == a.window_id]
        if not wins:
            print(json.dumps({"ok": False, "error": "sin ventana objetivo"}))
            return 1
        w = wins[0]
        err, sc, _ = m.call("get_window_state", {
            "pid": w["pid"], "window_id": w["window_id"],
            "tree_format": "elements", "include_screenshot": False,
            "max_elements": 600})
        el = find_element(sc, a.role, a.name)
        if not el:
            print(json.dumps({"ok": False, "error": f"sin elemento role={a.role}"}))
            return 1
        if a.mode == "text":
            err, _, text = m.call("type_text", {
                "element_token": el["element_token"], "text": secret,
                "delivery_mode": "background"})
        else:
            err, _, text = m.call("set_value", {
                "element_token": el["element_token"], "value": secret})
        print(json.dumps({"ok": not err, "detail": (text or "")[:120]}))
        return 0 if not err else 1
    finally:
        m.close()


if __name__ == "__main__":
    sys.exit(main())
