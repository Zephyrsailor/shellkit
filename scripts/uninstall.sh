#!/usr/bin/env bash
set -euo pipefail

# Uninstall ShellKit.
# - Removes launcher `sk` from BIN_DIR (default: ~/.local/bin)
# - Optionally removes SK_HOME directory (default: ~/.shellkit)
# - Cleans PATH entries added by installer in common shell rc files
#
# Usage:
#   bash scripts/uninstall.sh [--home <dir>] [--bin <dir>] [--keep-home] [--dry-run]

HOME_DIR_DEFAULT="$HOME/.shellkit"
BIN_DIR_DEFAULT="$HOME/.local/bin"

SK_HOME="${SK_HOME:-$HOME_DIR_DEFAULT}"
BIN_DIR="${BIN_DIR:-$BIN_DIR_DEFAULT}"
KEEP_HOME=false
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home) SK_HOME="$2"; shift 2;;
    --bin)  BIN_DIR="$2"; shift 2;;
    --keep-home) KEEP_HOME=true; shift;;
    --dry-run) DRY_RUN=true; shift;;
    -h|--help)
      cat <<EOF
Usage: bash scripts/uninstall.sh [--home <dir>] [--bin <dir>] [--keep-home] [--dry-run]
Defaults: --home $HOME_DIR_DEFAULT  --bin $BIN_DIR_DEFAULT
EOF
      exit 0;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

say() { printf '%s\n' "$*"; }

remove_launcher() {
  local launcher="$BIN_DIR/sk"
  if [ -e "$launcher" ]; then
    if $DRY_RUN; then
      say "[DRY] rm -f $launcher"
    else
      rm -f "$launcher" && say "[OK] Removed launcher: $launcher" || true
    fi
  fi
}

remove_path_marks() {
  local file="$1"
  [ -f "$file" ] || return 0
  if grep -q "^# >>> ShellKit PATH >>>" "$file" 2>/dev/null; then
    if $DRY_RUN; then
      say "[DRY] clean PATH markers in $file"
    else
      awk 'BEGIN{b=0} /^# >>> ShellKit PATH >>>/ {b=1; next} /^# <<< ShellKit PATH <<</ {b=0; next} { if(!b) print }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
      say "[OK] Cleaned PATH markers in: $file"
    fi
  fi
}

remove_rc_paths() {
  remove_path_marks "$HOME/.bashrc"
  remove_path_marks "$HOME/.profile"
  remove_path_marks "$HOME/.zshrc"
}

remove_home() {
  if $KEEP_HOME; then return 0; fi
  if [ -d "$SK_HOME" ]; then
    # sanity check to avoid deleting arbitrary folders
    if [ -f "$SK_HOME/main.sh" ] && [ -d "$SK_HOME/lib" ]; then
      if $DRY_RUN; then
        say "[DRY] rm -rf $SK_HOME"
      else
        rm -rf "$SK_HOME"
        say "[OK] Removed SK_HOME: $SK_HOME"
      fi
    else
      say "[WARN] Skip removing SK_HOME (unexpected layout): $SK_HOME"
    fi
  fi
}

remove_launcher
remove_rc_paths
remove_home

say "Uninstall complete. Open a new terminal or 'source' your rc if PATH was changed."

