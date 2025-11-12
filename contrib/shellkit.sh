#!/usr/bin/env bash

# ShellKit helper: source this file in your shell profile to get
# convenient functions that apply in the current shell session.
#
# Usage:
#   echo 'source /ABS/PATH/TO/contrib/shellkit.sh' >> ~/.zshrc   # or ~/.bashrc
#   source ~/.zshrc
#   sk gpu                        # run GPU check
#   sk sys                        # run system info

_shellkit_root() {
  # Resolve repo root from this file location
  local here
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  # contrib/ -> repo root
  (cd "$here/.." && pwd)
}

_SK_ROOT="$(_shellkit_root)"

sk() {
  # pass-through for other subcommands
  bash "$_SK_ROOT/main.sh" "$@"
}
