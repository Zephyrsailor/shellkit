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
BIN_DIR_ARG=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home) SK_HOME="$2"; shift 2;;
    --bin)  BIN_DIR="$2"; BIN_DIR_ARG=true; shift 2;;
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

# If user didn't specify --bin and BIN_DIR is default, try to pick the first
# writable dir already present in PATH to keep `sk` immediately available.
if [ "$BIN_DIR_ARG" = false ] && [ "$BIN_DIR" = "$BIN_DIR_DEFAULT" ]; then
  IFS=':' read -r -a path_entries <<< "${PATH:-}"
  for p in "${path_entries[@]}"; do
    if [ -n "$p" ] && [ -d "$p" ] && [ -w "$p" ]; then
      BIN_DIR="$p"
      echo "[OK] Using existing PATH dir for launcher: $BIN_DIR"
      break
    fi
  done
fi
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
exec bash "$SK_HOME/main.sh" "\$@"
EOF
chmod +x "$LAUNCHER"

echo "[OK] Updated ShellKit at: $SK_HOME"
echo "[OK] Refreshed launcher: $LAUNCHER"

# Ensure BIN_DIR on PATH (idempotent)
ensure_path_line() {
  local file="$1"; shift || true
  local line="export PATH=\"$BIN_DIR:\$PATH\""
  if [ -f "$file" ]; then
    if grep -q "ShellKit PATH" "$file" 2>/dev/null; then return 0; fi
  fi
  {
    echo "# >>> ShellKit PATH >>>"
    echo "$line"
    echo "# <<< ShellKit PATH <<<"
  } >> "$file"
}

case ":$PATH:" in
  *:"$BIN_DIR":*) onpath=1 ;;
  *) onpath=0 ;;
esac

if [ $onpath -eq 0 ]; then
  shname=$(basename "${SHELL:-}")
  case "$shname" in
    zsh) ensure_path_line "$HOME/.zshrc" ;;
    bash) ensure_path_line "$HOME/.bashrc"; ensure_path_line "$HOME/.profile" ;;
    *) ensure_path_line "$HOME/.profile" ;;
  esac
  echo "[OK] Ensured PATH in your shell rc (open new terminal or source rc)."
  echo "[HINT] Current session: export PATH=\"$BIN_DIR:\$PATH\""
fi

echo "Run: sk help"
