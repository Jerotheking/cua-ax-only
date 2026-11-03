#!/bin/bash
# Rebuild the AX-only fork from upstream + our patch series, deploy, sign, test.
# Usage:
#   ./update.sh --help
#   ./update.sh --dry-run            # clone+build only, no deploy
#   REF=main ./update.sh             # deploy
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REF="${REF:-main}"
APP="${APP:-$HOME/Applications/CuaDriverFork.app}"
DRY=0

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --dry-run) DRY=1 ;;
    *) echo "arg desconocido: $arg (usá --help)" >&2; exit 2 ;;
  esac
done

WORK="$(mktemp -d)"
PATCHES=("$HERE"/patches/*.patch)

echo "== upstream $REF -> $WORK"
git clone --depth 1 --filter=blob:none --sparse --branch "$REF" \
  https://github.com/trycua/cua "$WORK/cua"
cd "$WORK/cua"
git sparse-checkout set libs/cua-driver/rust libs/cua libs/images

for p in "${PATCHES[@]}"; do
  echo "== patch $(basename "$p")"
  if ! git apply --check "$p"; then
    echo "ERROR: el parche no aplica limpio sobre $REF." >&2
    echo "Rebasealo: git clone, aplicá a mano, regenerá el patch y reintentá." >&2
    exit 1
  fi
  git apply "$p"
done

cd libs/cua-driver/rust
echo "== build"
cargo build -p cua-driver --release

BIN="$WORK/cua/libs/cua-driver/rust/target/release/cua-driver"
"$BIN" --version >/dev/null 2>&1 || true
if [ "$DRY" = "1" ]; then
  echo "DRY: binario en $BIN"
  exit 0
fi

echo "== deploy atómico a $APP"
mkdir -p "$APP/Contents/MacOS"
BACKUP="$(mktemp)"
cp "$APP/Contents/MacOS/cua-driver" "$BACKUP" 2>/dev/null || true
cp "$BIN" "$APP/Contents/MacOS/cua-driver"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

if ! "$HERE/tests/smoke.sh"; then
  echo "ERROR: smoke falló; restaurando binario anterior" >&2
  if [ -s "$BACKUP" ]; then
    cp "$BACKUP" "$APP/Contents/MacOS/cua-driver"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  fi
  exit 1
fi
echo "OK: fork actualizado y verificado"
