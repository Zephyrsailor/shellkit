#!/usr/bin/env bash

# 通用输出与工具函数。需由 bash 脚本通过:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# 引入。

if [ -t 1 ]; then COLOR=true; else COLOR=false; fi

bold() { $COLOR && printf "\033[1m%s\033[0m\n" "$1" || printf "%s\n" "$1"; }
dim()  { $COLOR && printf "\033[2m%s\033[0m\n" "$1" || printf "%s\n" "$1"; }
ok()   { $COLOR && printf "\033[32m✔\033[0m %s\n" "$1" || printf "[OK] %s\n" "$1"; }
warn() { $COLOR && printf "\033[33m⚠\033[0m %s\n" "$1" || printf "[WARN] %s\n" "$1"; }
err()  { $COLOR && printf "\033[31m✖\033[0m %s\n" "$1" || printf "[ERR] %s\n" "$1"; }

kv() { printf "  - %s: %s\n" "$1" "${2:-}"; }
section() { echo; bold "== $1 =="; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

