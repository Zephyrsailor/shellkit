#!/usr/bin/env bash

# gpu-env-check: 一键检测 GPU 运行环境与系统信息
#
# 用法:
#   bash gpu-env-check [选项]
#
# 选项:
#   --gpu-only        仅检测 GPU/AI 框架相关信息
#   --sys-only        仅输出系统信息
#   --no-python       跳过 Python 框架检测 (PyTorch/TensorFlow)
#   --verbose         输出更详细的原始命令结果（若可用）
#   -h, --help        显示帮助
#
# 说明:
#   - 脚本尽量自解释，无破坏性操作；缺少工具时会优雅降级。
#   - Linux/macOS 通用。Windows 建议用 WSL 运行。
#   - Python 检测会尝试调用 python3，若无则自动跳过。

set -euo pipefail
IFS=$'\n\t'

# 引入通用函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

run_quiet() { "$@" 2>/dev/null || return 1; }

VERBOSE=false
GPU_ONLY=false
SYS_ONLY=false
NO_PY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --gpu-only) GPU_ONLY=true ; shift ;;
    --sys-only) SYS_ONLY=true ; shift ;;
    --no-python) NO_PY=true ; shift ;;
    --verbose) VERBOSE=true ; shift ;;
    -h|--help)
      sed -n '1,50p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      err "未知参数: $1"; exit 2
      ;;
  esac
done

# ---- 基础信息 ----
OS="$(uname -s 2>/dev/null || echo unknown)"
KERNEL="$(uname -r 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
HOST="$(hostname 2>/dev/null || echo unknown)"

os_pretty_name() {
  case "$OS" in
    Linux)
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${PRETTY_NAME:-Linux}"
      else
        echo "Linux"
      fi
      ;;
    Darwin)
      if has_cmd sw_vers; then
        echo "$(sw_vers -productName) $(sw_vers -productVersion)"
      else
        echo "macOS"
      fi
      ;;
    *) echo "$OS" ;;
  esac
}

serial_number() {
  case "$OS" in
    Linux)
      if [ -r /sys/class/dmi/id/product_serial ]; then
        cat /sys/class/dmi/id/product_serial | tr -d '\n'
      elif has_cmd dmidecode; then
        dmidecode -s system-serial-number 2>/dev/null | head -n1 | tr -d '\n'
      elif [ -r /sys/class/dmi/id/product_uuid ]; then
        cat /sys/class/dmi/id/product_uuid | tr -d '\n'
      else
        echo "不可用(可能需要root或设备不支持)"
      fi
      ;;
    Darwin)
      # 优先使用 system_profiler，其次 ioreg
      if has_cmd system_profiler; then
        system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial/ {print $2; exit}'
      elif has_cmd ioreg; then
        ioreg -l | awk -F'"' '/IOPlatformSerialNumber/ {print $4; exit}'
      else
        echo "不可用"
      fi
      ;;
    *) echo "未知" ;;
  esac
}

cpu_info() {
  case "$OS" in
    Linux)
      if has_cmd lscpu; then
        lscpu | awk -F': *' '/Model name|Architecture|^CPU\(s\)/ {gsub(/^ +| +$/,"",$2); printf "  - %s: %s\n", $1, $2}'
      else
        model=$(awk -F': *' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo unknown)
        cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo unknown)
        kv "CPU" "$model"
        kv "Cores" "$cores"
      fi
      ;;
    Darwin)
      brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
      if [ -z "${brand:-}" ] && has_cmd system_profiler; then
        brand=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/^ *Chip/ {print $2; exit}')
      fi
      if [ -z "${brand:-}" ]; then brand=$(sysctl -n hw.model 2>/dev/null || echo unknown); fi
      cores=$(sysctl -n hw.ncpu 2>/dev/null || echo unknown)
      kv "CPU" "$brand"
      kv "Cores" "$cores"
      ;;
    *) kv "CPU" "未知" ;;
  esac
}

mem_info() {
  case "$OS" in
    Linux)
      if has_cmd free; then
        total=$(free -h | awk '/Mem:/ {print $2}')
        used=$(free -h | awk '/Mem:/ {print $3}')
        kv "内存(总/已用)" "$total / $used"
      else
        total=$(awk '/MemTotal/ {printf "%.1f GiB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo unknown)
        kv "内存总量" "$total"
      fi
      ;;
    Darwin)
      mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
      if [ "${mem_bytes:-0}" -gt 0 ] 2>/dev/null; then
        total=$((${mem_bytes}/1024/1024/1024))
        kv "内存总量" "${total} GiB"
      else
        if has_cmd system_profiler; then
          sp_mem=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/^ *Memory/ {print $2; exit}')
          if [ -n "${sp_mem:-}" ]; then
            kv "内存总量" "$sp_mem"
          else
            if has_cmd vm_stat; then
              est=$(vm_stat | awk '/page size of/ {gsub(/[^0-9]/, "", $8); ps=$8} /^Pages/ {gsub(/\./, "", $3); total+= $3} END { if (ps>0) printf "%d", int(total*ps/1024/1024/1024) }')
              [ -n "${est:-}" ] && kv "内存总量(估算)" "${est} GiB" || kv "内存总量" "未知"
            else
              kv "内存总量" "未知"
            fi
          fi
        else
          kv "内存总量" "未知"
        fi
      fi
      ;;
  esac
}

disk_info() {
  kv "根分区(总/已用)" "$(df -h / | awk 'NR==2{print $2" / "$3" ("$5")"}')"
  case "$OS" in
    Linux)
      if has_cmd lsblk; then
        lsblk -d -o NAME,SIZE,MODEL | sed '1d;s/^/  - 物理盘: /'
      fi
      ;;
    Darwin)
      if has_cmd diskutil; then
        dim "(物理盘概览)"
        if diskutil list >/dev/null 2>&1; then
          diskutil list | awk '/^\//{print "  - 物理盘:",$0}' || true
        fi
      fi
      ;;
  esac
}

uptime_info() {
  if has_cmd uptime; then
    up=$(uptime | awk -F'up ' 'NF>1{split($2,a,/,/);print a[1]; next} {print ""}')
    if [ -n "$up" ]; then
      kv "开机时长" "$up"
    fi
  fi
}

nvidia_info() {
  if ! has_cmd nvidia-smi; then return 1; fi

  section "NVIDIA 驱动与 GPU"
  if $VERBOSE; then
    nvidia-smi || true
  else
    if out=$(nvidia-smi --query-driver_version --format=csv,noheader 2>/dev/null); then
      kv "驱动版本" "$out"
    fi
    if out=$(nvidia-smi --query-gpu=name,memory.total,memory.free,uuid,compute_cap --format=csv,noheader 2>/dev/null); then
      IFS=$'\n' read -r -d '' -a arr < <(printf '%s\0' "$out") || true
      idx=0
      for line in "${arr[@]:-}"; do
        idx=$((idx+1))
        name=$(echo "$line" | awk -F', *' '{print $1}')
        memt=$(echo "$line" | awk -F', *' '{print $2}')
        memf=$(echo "$line" | awk -F', *' '{print $3}')
        uuid=$(echo "$line" | awk -F', *' '{print $4}')
        cc=$(echo "$line" | awk -F', *' '{print $5}')
        kv "GPU#$idx" "$name | 显存: $memt，总空闲: $memf | CC: $cc | $uuid"
      done
    else
      nvidia-smi -L || true
    fi
  fi
  return 0
}

amd_info() {
  if has_cmd rocm-smi; then
    section "AMD ROCm 与 GPU"
    if $VERBOSE; then
      rocm-smi || true
    else
      rocm-smi --showproductname --showbus --showfw --showmeminfo vram 2>/dev/null || rocm-smi || true
    fi
    return 0
  fi
  return 1
}

opencl_info() {
  if has_cmd clinfo; then
    section "OpenCL 设备"
    if $VERBOSE; then
      clinfo || true
    else
      clinfo | awk '/Number of platforms/ {print "  - 平台数:",$NF} /Device Type/ {print "  - 设备:",$0}' | sed 's/^/  /' || true
    fi
    return 0
  fi
  return 1
}

mac_gpu_info() {
  if [ "$OS" = "Darwin" ] && has_cmd system_profiler; then
    section "macOS 显卡"
    system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model|VRAM/ {gsub(/^ +/ ,"  - ", $0); print $0}'
    return 0
  fi
  return 1
}

lspci_gpu_fallback() {
  if [ "$OS" = Linux ] && has_cmd lspci; then
    section "显卡(PCI)概览"
    lspci | grep -i -E 'vga|3d|nvidia|amd|ati' | sed 's/^/  - /'
    return 0
  fi
  return 1
}

cuda_info() {
  section "CUDA 工具链"
  if has_cmd nvcc; then
    ver=$(nvcc --version | awk -F', | ' '/release/ {for(i=1;i<=NF;i++) if($i ~ /^V?[0-9]/) v=$i; } END{print v}')
    kv "nvcc" "已安装, 版本: ${ver:-未知}"
  else
    warn "未检测到 nvcc (CUDA Toolkit)"
  fi

  # CUDA_HOME 及 version.txt
  cuda_home="${CUDA_HOME:-}"
  if [ -z "$cuda_home" ] && [ -d /usr/local/cuda ]; then cuda_home=/usr/local/cuda; fi
  if [ -n "$cuda_home" ] && [ -f "$cuda_home/version.txt" ]; then
    kv "CUDA_HOME" "$cuda_home"
    kv "version.txt" "$(tr -d '\n' < "$cuda_home/version.txt")"
  elif [ -n "$cuda_home" ]; then
    kv "CUDA_HOME" "$cuda_home"
  fi

  # cuDNN 检测 (Linux/mac)
  cudnn_ver=""
  for d in \
    "$cuda_home/include" \
    /usr/include /usr/local/cuda/include /opt/cuda/include \
    /Library/Frameworks /usr/local/include; do
    h="$d/cudnn_version.h"
    if [ -f "$h" ]; then
      major=$(awk '/CUDNN_MAJOR/ {print $3}' "$h" 2>/dev/null | head -n1)
      minor=$(awk '/CUDNN_MINOR/ {print $3}' "$h" 2>/dev/null | head -n1)
      patch=$(awk '/CUDNN_PATCHLEVEL/ {print $3}' "$h" 2>/dev/null | head -n1)
      if [ -n "${major:-}" ]; then cudnn_ver="$major.$minor.$patch"; break; fi
    fi
  done
  if [ -n "$cudnn_ver" ]; then
    kv "cuDNN" "已检测到版本: $cudnn_ver"
  else
    if has_cmd ldconfig; then
      if ldconfig -p 2>/dev/null | grep -qi cudnn; then kv "cuDNN" "已安装(通过 ldconfig)"; else warn "未检测到 cuDNN"; fi
    else
      warn "未检测到 cuDNN 头文件 (可能未安装或路径非标准)"
    fi
  fi
}

python_info() {
  if [ "$NO_PY" = true ]; then warn "已跳过 Python 框架检测 (--no-python)"; return; fi
  if ! has_cmd python3; then warn "未发现 python3，跳过 PyTorch/TensorFlow 检测"; return; fi

  section "Python 与 AI 框架"
  kv "Python" "$(python3 -V 2>&1)"
  py_exec="python3"
  timeout_cmd=""
  if has_cmd timeout; then timeout_cmd="timeout 15s"; fi

  # PyTorch
  $timeout_cmd $py_exec - <<'PY' 2>/dev/null || true
import json, sys
try:
    import torch
    v=torch.__version__
    cuda=torch.cuda.is_available()
    devs=[torch.cuda.get_device_name(i) for i in range(torch.cuda.device_count())] if cuda else []
    print(f"  - PyTorch: {v} | CUDA可用: {cuda} | GPUs: {', '.join(devs) if devs else '0'}")
except Exception as e:
    print("  - PyTorch: 未安装或导入失败")
PY

  # TensorFlow
  $timeout_cmd $py_exec - <<'PY' 2>/dev/null || true
import os
os.environ['TF_CPP_MIN_LOG_LEVEL']='3'
try:
    import tensorflow as tf
    v=tf.__version__
    gpus=tf.config.list_physical_devices('GPU')
    print(f"  - TensorFlow: {v} | GPUs: {len(gpus)}")
except Exception as e:
    print("  - TensorFlow: 未安装或导入失败")
PY
}

system_info() {
  section "系统信息"
  kv "主机名" "$HOST"
  kv "操作系统" "$(os_pretty_name)"
  kv "内核(uname)" "$(uname -srm)"
  kv "架构" "$ARCH"
  uptime_info
  cpu_info
  mem_info
  disk_info
  kv "序列号" "$(serial_number)"
}

gpu_env() {
  section "GPU 环境总览"
  nv=0; am=0; mc=0; pc=0
  if nvidia_info; then nv=1; ok "检测到 NVIDIA 环境"; fi
  if amd_info; then am=1; ok "检测到 AMD ROCm 环境"; fi
  if mac_gpu_info; then mc=1; fi
  opencl_info || true
  if [ $nv -eq 0 ] && [ $am -eq 0 ] && [ $mc -eq 0 ]; then
    if lspci_gpu_fallback; then pc=1; fi
    if [ $pc -eq 0 ]; then
      warn "未检测到已知 GPU 工具，可能无独显或驱动未安装"
    fi
  fi

  cuda_info
  python_info
}

# ---- 主流程 ----
if [ "$SYS_ONLY" = true ] && [ "$GPU_ONLY" = true ]; then
  err "--sys-only 与 --gpu-only 不能同时使用"; exit 2
fi

bold "GPU/系统一键检测 (gpu-env-check)"
dim  "时间: $(date '+%F %T')"

if [ "$GPU_ONLY" = true ]; then
  gpu_env
elif [ "$SYS_ONLY" = true ]; then
  system_info
else
  gpu_env
  system_info
fi

echo
ok "检测完成"
