#!/usr/bin/env bash

# main.sh: 统一入口
# 用法:
#   bash main.sh <子命令> [参数]
#
# ShellKit 统一入口（脚本套件）。
# 子命令:
#   gpu       GPU 运行环境检测（支持 --no-python / --verbose）
#   sys       系统信息
#   help      显示帮助

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

is_sourced() {
  if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return 0
  fi
  if [ -n "${ZSH_EVAL_CONTEXT:-}" ]; then
    case $ZSH_EVAL_CONTEXT in
      *:file) return 0 ;;
    esac
  fi
  return 1
}

usage() {
  cat <<'EOF'
用法: bash main.sh <子命令> [参数]

子命令:
  gpu [--no-python|--verbose]
  sys
  help

示例:
  bash main.sh gpu
  bash main.sh sys
EOF
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  gpu)
    exec bash "$SCRIPT_DIR/lib/gpu-env-check.sh" "$@"
    ;;
  sys)
    exec bash "$SCRIPT_DIR/lib/gpu-env-check.sh" --sys-only
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "未知子命令: $cmd" >&2
    usage
    exit 2
    ;;
esac
