#!/usr/bin/python3
"""Smoke probe: policy/fork invariants without touching the user's GUI."""
import json
import os
import selectors
import subprocess
import sys
import time

C = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else
                       "~/Applications/CuaDriverFork.app/Contents/MacOS/cua-driver")
POLICY = os.path.expanduser("~/.cua-driver/ax-only.yaml")
EXPECT_COUNT = os.environ.get("EXPECT_COUNT")

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
    return bool(res.get("isError")), text


fail = []


def check(ok, label):
    print(("PASS " if ok else "FAIL ") + label)
    if not ok:
        fail.append(label)


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2024-11-05", "capabilities": {},
    "clientInfo": {"name": "smoke", "version": "1"}}})
check(bool(wait(1)), "initialize")

send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
r = wait(2) or {}
names = sorted(t["name"] for t in (r.get("result") or {}).get("tools", []))
if EXPECT_COUNT is not None:
    check(len(names) == int(EXPECT_COUNT), f"tools/list = {len(names)} (esperado {EXPECT_COUNT})")
else:
    check(len(names) >= 40, f"tools/list contiene un inventario plausible ({len(names)} tools)")
check("run_script" not in names, "run_script oculta")
check("drag" in names, "drag condicionado a background")
check("double_click" in names, "double_click condicionado a background")
check(not (set(names) & {"focus", "paste", "invoke_menu", "move_cursor"}),
      "el catálogo no publica aliases ausentes de este binario")
check("press_key" in names, "press_key visible")
check("scroll" in names, "scroll visible")
check("browser_prepare" in names, "browser_prepare visible behind background constraint")

err, text = call(3, "press_key", {})
check(err and "policy" in text.lower(), "press_key sin args -> política")

err, text = call(4, "click", {"pid": 1, "x": 5, "y": 5})
check(err and ("policy" in text.lower() or "ax_only" in text.lower()), "click x,y -> denegado")

err, text = call(5, "run_script", {"script": "return 1"})
check(err, "run_script -> denegado")

for i, name, args in [
    (6, "hotkey", {"pid": 1, "window_id": 1, "scope": "window",
                     "delivery_mode": "foreground", "keys": ["cmd", "v"]}),
    (7, "drag", {"pid": 1, "window_id": 1, "delivery_mode": "foreground"}),
    (8, "run_steps", {"delivery_mode": "background", "foreground_fallback": True,
                        "steps": []}),
    (9, "browser_prepare", {"delivery_mode": "foreground"}),
]:
    err, text = call(i, name, args)
    check(err and ("policy" in text.lower() or "denied" in text.lower()),
          f"{name} -> política rechaza antes de actuar")

p.terminate()
try:
    p.wait(timeout=5)
except subprocess.TimeoutExpired:
    p.kill()
    p.wait()
if fail:
    print(f"\n{len(fail)} fallo(s)")
    sys.exit(1)
print("\nsmoke OK")
