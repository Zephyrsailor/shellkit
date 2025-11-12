#!/usr/bin/env bash
set -euo pipefail

# Update ShellKit installation by copying from the current repo working dir
# into SK_HOME (default: ~/.shellkit). Reinstalls the `sk` launcher.
#
# Usage:
#   bash scripts/update.sh [--home <dir>] [--bin <dir>]

HOME_DIR_DEFAULT="$HOME/.shellkit"
BIN_DIR_DEFAULT="$HOME/.local/bin"

SK_HOME="${SK_HOME:-$HOME_DIR_DEFAULT}"
BIN_DIR="${BIN_DIR:-$BIN_DIR_DEFAULT}"

while [ $# -gt 0 ]; do
  case "$1" in
    --home) SK_HOME="$2"; shift 2;;
    --bin)  BIN_DIR="$2"; shift 2;;
    -h|--help)
      cat <<EOF
Usage: bash scripts/update.sh [--home <dir>] [--bin <dir>]
Defaults: --home $HOME_DIR_DEFAULT  --bin $BIN_DIR_DEFAULT
EOF
      exit 0;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

mkdir -p "$SK_HOME"
SRC_DIR=$(pwd -P)
DEST_DIR=$(cd "$SK_HOME" 2>/dev/null && pwd -P)

if [ "$SRC_DIR" != "$DEST_DIR" ]; then
  (cd "$SRC_DIR" && tar -cf - .) | (cd "$SK_HOME" && tar -xf -)
fi

mkdir -p "$BIN_DIR"
LAUNCHER="$BIN_DIR/sk"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
SK_HOME="${SK_HOME}"
if [ ! -f "$SK_HOME/main.sh" ]; then
  echo "ShellKit not found in \"$SK_HOME\"" >&2
  exit 1
fi
exec bash "$SK_HOME/main.sh" "$@"
EOF
chmod +x "$LAUNCHER"

echo "[OK] Updated ShellKit at: $SK_HOME"
echo "[OK] Refreshed launcher: $LAUNCHER"
echo "Run: sk help"
