#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-$HOME/Applications/CuaDriverFork.app}"
BIN="$APP/Contents/MacOS/cua-driver"

test -x "$BIN" || { echo "FAIL falta $BIN"; exit 1; }
test -f "$HOME/.cua-driver/ax-only.yaml" || { echo "FAIL falta la política"; exit 1; }
echo "PASS binario y política"

"$HERE/tests/probe_tools.py" "$BIN"
"$HERE/tests/ax_smoke.py" "$BIN"

# Doctor global (codex-cu, política, hosts, skill)
if command -v "$HOME/.local/bin/cu-doctor.mjs" >/dev/null 2>&1; then
  "$HOME/.local/bin/cu-doctor.mjs" >/dev/null || { echo "FAIL cu-doctor"; exit 1; }
  echo "PASS cu-doctor"
fi
echo "smoke OK"
