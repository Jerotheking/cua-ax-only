#!/usr/bin/python3
"""Mide el árbol AX de una app antes/después de activar AXEnhancedUserInterface."""
import json
import os
import selectors
import subprocess
import sys
import time

FORK = os.path.expanduser("~/Applications/CuaDriverFork.app/Contents/MacOS/cua-driver")
POLICY = os.path.expanduser("~/.cua-driver/ax-only.yaml")
ENABLE = os.path.expanduser("~/Developer/cua-fork/tools/ax-enable")
APP = sys.argv[1] if len(sys.argv) > 1 else "Google Chrome"

env = dict(os.environ)
env["CUA_DRIVER_AX_ONLY"] = "1"
env["CUA_DRIVER_POLICY_FILE"] = POLICY
p = subprocess.Popen([FORK, "mcp", "--direct"], stdin=subprocess.PIPE,
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
    return bool(res.get("isError")), res.get("structuredContent") or {}


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2024-11-05", "capabilities": {},
    "clientInfo": {"name": "ax-probe", "version": "1"}}})
wait(1)

err, sc = call(2, "list_windows", {})
windows = [w for w in (sc.get("windows") or []) if w.get("app_name") == APP]
if not windows:
    print(f"SKIP: {APP} sin ventanas")
    p.terminate()
    sys.exit(0)

w = next((x for x in windows if x.get("title")), windows[0])


def measure(tag):
    err, sc = call(10, "get_window_state", {
        "pid": w["pid"], "window_id": w["window_id"],
        "tree_format": "elements", "include_screenshot": False,
        "max_elements": 2000})
    els = sc.get("elements") or []
    fields = [e for e in els if "textfield" in (e.get("role") or "").lower()
              or "textarea" in (e.get("role") or "").lower()]
    print(f"{tag}: elements={len(els)} textfields={len(fields)}")
    return len(els), len(fields)


base = measure("antes")
subprocess.run([ENABLE, str(w["pid"]), "on"], capture_output=True, text=True)
time.sleep(1.5)
after = measure("después")
subprocess.run([ENABLE, str(w["pid"]), "off"], capture_output=True, text=True)
print(f"delta elements={after[0]-base[0]} textfields={after[1]-base[1]}")
p.terminate()
