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
PACKAGE_VERSION="$(tr -d '\r\n' < "$HERE/VERSION")"
APP_STAMP_DIR="$HOME/.local/state/cua-driver-fork"
APP_KEY="$(printf '%s' "$APP" | shasum -a 256 | awk '{print substr($1,1,16)}')"
APP_STAMP="$APP_STAMP_DIR/$APP_KEY.install-stamp"
APP_CHANGED=0
APP_BACKUP=""
STAMP_BACKUP=""

echo "1/6 app bundle"
mkdir -p "$APP/Contents/MacOS"
if [ -f "$APP_BIN" ]; then
  appv="$("$APP_BIN" --version 2>/dev/null | head -1 || true)"
  app_hash="$(shasum -a 256 "$APP_BIN" | awk '{print $1}')"
  stamp_version=""
  stamp_hash=""
  if [ -f "$APP_STAMP" ]; then
    IFS=' ' read -r stamp_version stamp_hash < "$APP_STAMP" || true
  fi
  if [ "$FORCE" = "1" ]; then
    APP_BACKUP="$APP_BIN.bak-$(date +%s)-$$"
    cp -p "$APP_BIN" "$APP_BACKUP"
    if [ -f "$APP_STAMP" ]; then
      STAMP_BACKUP="$APP_STAMP.bak-$(date +%s)-$$"
      cp -p "$APP_STAMP" "$STAMP_BACKUP"
    fi
    install -m 755 "$HERE/bin/cua-driver" "$APP_BIN"
    APP_CHANGED=1
    echo "  reemplazando $appv por paquete $PACKAGE_VERSION (backup .bak)"
  elif [ "$stamp_version" = "$PACKAGE_VERSION" ] \
    && [ "$stamp_hash" = "$app_hash" ] && [ -f "$APP/Contents/Info.plist" ]; then
    if ! codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
      echo "  ERROR: la firma de $APP no verifica; usá --force para reemplazar y volver a firmar" >&2
      exit 1
    fi
    echo "  ya instalada la revisión $PACKAGE_VERSION; firma y hash verificados; no se toca"
  else
    echo "  ERROR: no puedo verificar que $APP_BIN corresponda al paquete $PACKAGE_VERSION" >&2
    echo "  versión ejecutable: ${appv:-desconocida}; revisión registrada: ${stamp_version:-ninguna}" >&2
    echo "  Usá --force para instalar esta revisión (hace backup)." >&2
    exit 1
  fi
else
  install -m 755 "$HERE/bin/cua-driver" "$APP_BIN"
  APP_CHANGED=1
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
  APP_CHANGED=1
fi
if [ "$APP_CHANGED" = "1" ]; then
  if ! codesign --force --deep --sign - "$APP" >/dev/null 2>&1 \
    || ! codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    echo "  ERROR: no pude firmar/verificar $APP" >&2
    if [ -n "$APP_BACKUP" ]; then
      cp -p "$APP_BACKUP" "$APP_BIN"
      codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
    fi
    if [ -n "$STAMP_BACKUP" ]; then cp -p "$STAMP_BACKUP" "$APP_STAMP"; fi
    exit 1
  fi
  mkdir -p "$APP_STAMP_DIR"
  installed_hash="$(shasum -a 256 "$APP_BIN" | awk '{print $1}')"
  stamp_tmp="$APP_STAMP.tmp.$$"
  printf '%s %s\n' "$PACKAGE_VERSION" "$installed_hash" > "$stamp_tmp"
  chmod 600 "$stamp_tmp"
  mv "$stamp_tmp" "$APP_STAMP"
  echo "  instalada y firmada (revisión $PACKAGE_VERSION)"
fi

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
for s in 1password; do
  if [ -e "$SKILLS/$s" ]; then
    echo "  skill $s ya existe; no se toca"
  else
    cp -R "$HERE/skills/$s" "$SKILLS/"
  fi
done
echo "  Cua Driver usa la skill unificada cua-driver del repo Sintelia."
echo "  Tras integrarla en origin/main: sync-skill-links --desde-repo cua-driver"

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
