#!/usr/bin/python3
"""Live AX smoke: click a Finder row by element_token (background, AX only).

Fails if the click errors or if the driver reports a pixel/CGEvent path.
Skips when no Finder window/row is available.
"""
import json
import os
import selectors
import subprocess
import sys
import time

C = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else
                       "~/Applications/CuaDriverFork.app/Contents/MacOS/cua-driver")
POLICY = os.path.expanduser("~/.cua-driver/ax-only.yaml")

env = dict(os.environ)
env["CUA_DRIVER_AX_ONLY"] = "1"
env["CUA_DRIVER_POLICY_FILE"] = POLICY
p = subprocess.Popen([C, "mcp", "--direct"], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                     text=True, bufsize=1, env=env)
sel = selectors.DefaultSelector()
sel.register(p.stdout, selectors.EVENT_READ)


def send(obj):
    p.stdin.write(json.dumps(obj) + "\n")
    p.stdin.flush()


def wait(i, secs=30):
    end = time.time() + secs
    while time.time() < end:
        if sel.select(0.2):
            line = p.stdout.readline().strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except Exception:
                continue
            if msg.get("id") == i:
                return msg
    return None


def call(i, name, args):
    send({"jsonrpc": "2.0", "id": i, "method": "tools/call",
          "params": {"name": name, "arguments": args}})
    r = wait(i) or {}
    res = r.get("result") or {}
    text = "".join(c.get("text", "") for c in res.get("content") or [])
    return bool(res.get("isError")), res.get("structuredContent") or {}, text


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2024-11-05", "capabilities": {},
    "clientInfo": {"name": "ax-smoke", "version": "1"}}})
if not wait(1):
    print("FAIL initialize")
    p.terminate()
    sys.exit(1)

err, sc, _ = call(2, "list_windows", {})
windows = [w for w in (sc.get("windows") or []) if w.get("app_name") == "Finder"]
if not windows:
    print("SKIP sin ventanas de Finder")
    p.terminate()
    sys.exit(0)

w = windows[0]
err, sc, _ = call(3, "get_window_state", {
    "pid": w["pid"], "window_id": w["window_id"],
    "tree_format": "elements", "include_screenshot": False, "max_elements": 300})
rows = [e for e in (sc.get("elements") or []) if e.get("role") == "AXRow"]
if not rows:
    print("SKIP sin AXRow")
    p.terminate()
    sys.exit(0)

err, sc, text = call(4, "click", {
    "element_token": rows[0]["element_token"], "delivery_mode": "background"})
if err:
    print("FAIL click: " + text[:160])
    p.terminate()
    sys.exit(1)
path = (sc or {}).get("path")
if path and "cgevent" in str(path):
    print(f"FAIL path={path} (se esperaba AX)")
    p.terminate()
    sys.exit(1)
print("PASS click AX en segundo plano")
p.terminate()
