#!/bin/bash
# Instalador de Cua AX-only (macOS arm64). No pisa una instalación existente
# sin --force.
# Uso: ./scripts/install.sh [--force]
#   APP=/ruta CuaDriverFork.app   BIN_DIR=~/.local/bin   SKIP_SMOKE=1
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-$HOME/Applications/CuaDriverFork.app}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
POLICY="$HOME/.cua-driver/ax-only.yaml"
SKILLS="$HOME/.agents/skills"
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "arg desconocido: $arg" >&2; exit 2 ;;
  esac
done

APP_BIN="$APP/Contents/MacOS/cua-driver"

echo "1/6 app bundle"
mkdir -p "$APP/Contents/MacOS"
if [ -f "$APP_BIN" ]; then
  pkgv="$("$HERE/bin/cua-driver" --version 2>/dev/null | head -1 || true)"
  appv="$("$APP_BIN" --version 2>/dev/null | head -1 || true)"
  if [ -n "$pkgv" ] && [ "$pkgv" = "$appv" ]; then
    echo "  ya instalada ($appv); no se toca"
  elif [ "$FORCE" = "1" ]; then
    cp "$APP_BIN" "$APP_BIN.bak-$(date +%s)"
    install -m 755 "$HERE/bin/cua-driver" "$APP_BIN"
    echo "  reemplazada (backup .bak)"
  else
    echo "  ERROR: ya existe otra versión en $APP_BIN" >&2
    echo "  No la piso. Usá --force (hace backup) o APP=<otra ruta>." >&2
    exit 1
  fi
else
  install -m 755 "$HERE/bin/cua-driver" "$APP_BIN"
fi
if [ ! -f "$APP/Contents/Info.plist" ]; then
  cat > "$APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CuaDriverFork</string>
  <key>CFBundleIdentifier</key><string>com.jero.cuafork</string>
  <key>CFBundleVersion</key><string>0.38.0</string>
  <key>CFBundleShortVersionString</key><string>0.38.0</string>
  <key>CFBundleExecutable</key><string>cua-driver</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PL
fi
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "2/6 política"
mkdir -p "$(dirname "$POLICY")"
if [ -f "$POLICY" ]; then
  if cmp -s "$HERE/policy/ax-only.yaml" "$POLICY"; then
    echo "  ya existe (idéntica); no se toca"
  elif [ "$FORCE" = "1" ]; then
    cp "$POLICY" "$POLICY.bak-$(date +%s)"
    install -m 644 "$HERE/policy/ax-only.yaml" "$POLICY"
    echo "  reemplazada (backup .bak)"
  else
    echo "  existe una política distinta; se CONSERVA (usá --force para reemplazarla)"
  fi
else
  install -m 644 "$HERE/policy/ax-only.yaml" "$POLICY"
fi

echo "3/6 utilidades"
mkdir -p "$BIN_DIR"
install -m 755 "$HERE/bin/op-inject.py" "$BIN_DIR/op-inject.py"
if [ ! -e "$BIN_DIR/op" ]; then
  install -m 755 "$HERE/bin/op-shim" "$BIN_DIR/op"
  echo "  shim op instalado"
else
  echo "  ya existe $BIN_DIR/op; no lo toco"
fi

echo "4/6 skills"
mkdir -p "$SKILLS"
for s in cua-ax-only 1password; do
  if [ -e "$SKILLS/$s" ]; then
    echo "  skill $s ya existe; no se toca"
  else
    cp -R "$HERE/skills/$s" "$SKILLS/"
  fi
done
for d in "$HOME/.claude/skills" "$HOME/.claude-b/skills" "$HOME/.codex/skills" \
         "$HOME/.config/opencode/skills" "$HOME/.gemini/skills" \
         "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity-cli/skills"; do
  [ -d "$d" ] && ln -sfn "$SKILLS/cua-ax-only" "$d/cua-ax-only"
done

echo "5/6 permisos (TCC)"
echo "  Concedé Accesibilidad y Grabación de pantalla a CuaDriverFork.app"
echo "  (o al host que use --direct) y reiniciá la app/sesión."

echo "6/6 smoke"
if [ "${SKIP_SMOKE:-0}" = "1" ]; then
  echo "  omitido"
elif APP="$APP" "$HERE/tests/smoke.sh"; then
  echo "  OK"
else
  echo "  smoke falló (probable TCC pendiente). Concedé permisos y reintentá."
fi

cat <<EOF

Listo. Cableá el host (patrón):
  command: $APP/Contents/MacOS/cua-driver
  args:    ["mcp","--direct"]
  env:     CUA_DRIVER_AX_ONLY=1
           CUA_DRIVER_POLICY_FILE=$POLICY

Ejemplos en examples/. Para 1Password: op-inject.py (ver skills/1password).
EOF
