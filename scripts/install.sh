#!/usr/bin/env bash
set -euo pipefail

# Install ShellKit: copies this repo to SK_HOME (default: ~/.shellkit)
# and installs a small `sk` launcher into BIN_DIR (default: ~/.local/bin).
#
# Usage:
#   bash scripts/install.sh [--home <dir>] [--bin <dir>] [--force]
#
# Examples:
#   bash scripts/install.sh                      # installs to ~/.shellkit and ~/.local/bin/sk
#   bash scripts/install.sh --home ~/apps/shellkit --bin ~/bin

HOME_DIR_DEFAULT="$HOME/.shellkit"
BIN_DIR_DEFAULT="$HOME/.local/bin"

SK_HOME="${SK_HOME:-$HOME_DIR_DEFAULT}"
BIN_DIR="${BIN_DIR:-$BIN_DIR_DEFAULT}"
FORCE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home)
      SK_HOME="$2"; shift 2;;
    --bin)
      BIN_DIR="$2"; shift 2;;
    --force)
      FORCE=true; shift;;
    -h|--help)
      cat <<EOF
Usage: bash scripts/install.sh [--home <dir>] [--bin <dir>] [--force]
Defaults: --home $HOME_DIR_DEFAULT  --bin $BIN_DIR_DEFAULT
EOF
      exit 0;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

mkdir -p "$SK_HOME"

# Copy repo contents into SK_HOME, unless SK_HOME is current repo path
SRC_DIR=$(pwd -P)
DEST_DIR=$(cd "$SK_HOME" 2>/dev/null && pwd -P)

if [ "$SRC_DIR" != "$DEST_DIR" ]; then
  # On macOS/Linux, this tar pipe preserves hidden files without needing rsync
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

echo "[OK] Installed ShellKit to: $SK_HOME"
echo "[OK] Installed launcher: $LAUNCHER"

# PATH hint
case ":$PATH:" in
  *:"$BIN_DIR":*) :;;
  *) echo "[HINT] Add to PATH: export PATH=\"$BIN_DIR:\$PATH\"";;
esac

echo "Try: sk gpu  or  sk sys"
