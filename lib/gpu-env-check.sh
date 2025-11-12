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
#   --py <python>     指定用于检测 PyTorch/TF 的 Python 解释器
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
PY_EXEC_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --gpu-only) GPU_ONLY=true ; shift ;;
    --sys-only) SYS_ONLY=true ; shift ;;
    --no-python) NO_PY=true ; shift ;;
    --verbose) VERBOSE=true ; shift ;;
    --py) PY_EXEC_OVERRIDE="${2:-}"; shift 2 ;;
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
      sn=""
      if [ -r /sys/class/dmi/id/product_serial ]; then
        sn=$(tr -d '\n' < /sys/class/dmi/id/product_serial)
      fi
      if [ -z "$sn" ] && [ -r /sys/firmware/devicetree/base/serial-number ]; then
        sn=$(tr -d '\0\n' < /sys/firmware/devicetree/base/serial-number)
      fi
      if [ -z "$sn" ] && [ -r /proc/device-tree/serial-number ]; then
        sn=$(tr -d '\0\n' < /proc/device-tree/serial-number)
      fi
      if [ -z "$sn" ] && awk -F': ' '/Serial/ {print $2; found=1} END{exit !found}' /proc/cpuinfo >/dev/null 2>&1; then
        sn=$(awk -F': *' '/Serial/ {print $2; exit}' /proc/cpuinfo | tr -d '\n')
      fi
      if [ -z "$sn" ] && has_cmd dmidecode; then
        # 非 root 尝试直接读取（某些系统允许）
        out=$(dmidecode -s system-serial-number 2>/dev/null | head -n1 || true)
        sn="${out//$'\r\n'/}"
        if [ -z "$sn" ]; then
          # 尝试使用 sudo -n（无密码不提示）；失败则在交互终端尝试 sudo 提示输入
          if out=$(sudo -n dmidecode -s system-serial-number 2>/dev/null | head -n1); then
            sn="${out//$'\r\n'/}"
          else
            if [ -t 1 ]; then
              if out=$(sudo dmidecode -s system-serial-number 2>/dev/null | head -n1); then
                sn="${out//$'\r\n'/}"
              fi
            fi
          fi
        fi
      fi
      echo "$sn"
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
        lscpu | awk -F': *' '/Model name|Architecture|^CPU\(s\):/ {gsub(/^ +| +$/,"",$2); printf "  - %s: %s\n", $1, $2}'
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
      # 使用 /proc/meminfo 计算，避免本地化差异
      if [ -r /proc/meminfo ]; then
        mem_total_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
        mem_avail_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
        if [ -n "${mem_total_kb:-}" ] && [ -n "${mem_avail_kb:-}" ]; then
          used_kb=$((mem_total_kb - mem_avail_kb))
          total_gi=$(awk -v kb="$mem_total_kb" 'BEGIN{printf "%.1f GiB", kb/1024/1024}')
          used_gi=$(awk -v kb="$used_kb" 'BEGIN{printf "%.1f GiB", kb/1024/1024}')
          kv "内存(总/已用)" "$total_gi / $used_gi"
        else
          total=$(awk '/MemTotal/ {printf "%.1f GiB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo unknown)
          kv "内存总量" "$total"
        fi
      else
        if has_cmd free; then
          total=$(free -h | awk 'NR==2{print $2}')
          used=$(free -h | awk 'NR==2{print $3}')
          kv "内存(总/已用)" "$total / $used"
        else
          kv "内存总量" "未知"
        fi
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
        lsblk -d -o NAME,SIZE,MODEL | sed '1d' | grep -v '^loop' | sed 's/^/  - 物理盘: /'
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
    if out=$(nvidia-smi --query-gpu=index,name,memory.total,memory.used,uuid,compute_cap --format=csv,noheader 2>/dev/null); then
      IFS=$'\n' read -r -d '' -a arr < <(printf '%s\0' "$out") || true
      for line in "${arr[@]:-}"; do
        idx=$(echo "$line" | awk -F', *' '{print $1}')
        name=$(echo "$line" | awk -F', *' '{print $2}')
        memt=$(echo "$line" | awk -F', *' '{print $3}')
        memu=$(echo "$line" | awk -F', *' '{print $4}')
        uuid=$(echo "$line" | awk -F', *' '{print $5}')
        cc=$(echo "$line" | awk -F', *' '{print $6}')
        # 计算空闲（如果可用）
        memf=""
        if [ -n "${memt}" ] && [ -n "${memu}" ] && [[ ! "$memt" =~ N/A ]] && [[ ! "$memu" =~ N/A ]]; then
          # 去单位 MiB
          t=$(echo "$memt" | sed 's/[^0-9]//g')
          u=$(echo "$memu" | sed 's/[^0-9]//g')
          if [ -n "$t" ] && [ -n "$u" ]; then
            f=$((t-u))
            memf="${f} MiB"
          fi
        fi
        # 若显存为 N/A，用 -q/-x 方式兜底（优先 FB memory usage 块）
        if [ -z "$memt" ] || [[ "$memt" =~ N/A ]]; then
          q=$(nvidia-smi -q -i "$idx" -d MEMORY 2>/dev/null)
          fb=$(echo "$q" | awk 'BEGIN{IGNORECASE=1} /FB .*memory usage/ {f=1; next} f && NF==0 {exit} f {print}')
          if [ -z "$fb" ]; then
            fb=$(echo "$q" | awk 'BEGIN{IGNORECASE=1} /Memory Usage/ {f=1; next} f && NF==0 {exit} f {print}')
          fi
          if [ -n "$fb" ]; then
            # 优先 Total/Used/Free
            [ -z "$memt" ] && memt=$(echo "$fb" | awk -F': *' 'BEGIN{IGNORECASE=1} /Total/ {print $2; exit}')
            u2=$(echo "$fb" | awk -F': *' 'BEGIN{IGNORECASE=1} /Used/ {print $2; exit}')
            [ -z "$memf" ] && memf=$(echo "$fb" | awk -F': *' 'BEGIN{IGNORECASE=1} /Free/ {print $2; exit}')
            if [ -z "$memf" ] && [ -n "$memt" ] && [ -n "$u2" ]; then
              t=$(echo "$memt" | sed 's/[^0-9]//g')
              u=$(echo "$u2" | sed 's/[^0-9]//g')
              if [ -n "$t" ] && [ -n "$u" ]; then memf="$((t-u)) MiB"; fi
            fi
          fi
          # 再尝试 XML 输出（更稳定的字段名）
          if { [ -z "$memt" ] || [ -z "$memf" ]; } && nvidia-smi -q -x -i "$idx" >/dev/null 2>&1; then
            xml=$(nvidia-smi -q -x -i "$idx" 2>/dev/null)
            if [ -z "$memt" ]; then
              memt=$(echo "$xml" | awk -F'[<>]' '/<fb_memory_usage>/{f=1;next} f&&$2=="total" {print $3; exit} f&&$2=="fb_memory_usage"{f=0}')
            fi
            if [ -z "$memf" ]; then
              memf=$(echo "$xml" | awk -F'[<>]' '/<fb_memory_usage>/{f=1;next} f&&$2=="free" {print $3; exit} f&&$2=="fb_memory_usage"{f=0}')
            fi
          fi
          # 再兜底，用概要表格解析（不可靠，但总比空好）
          if [ -z "$memt" ] || [ -z "$memf" ]; then
            sum=$(nvidia-smi 2>/dev/null | sed -n 's/.*Default: *\([0-9]*\)MiB .*Used: *\([0-9]*\)MiB.*/\1 \2/p' | head -n1)
            if [ -n "$sum" ]; then
              t=$(echo "$sum" | awk '{print $1}')
              u=$(echo "$sum" | awk '{print $2}')
              memt="${t} MiB"; memf="$((t-u)) MiB"
            fi
          fi
        fi
        kv "GPU#$idx" "$name | 显存: ${memt:-N/A}，总空闲: ${memf:-N/A} | CC: ${cc:-N/A} | $uuid"
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
    # 兼容不同输出格式
    ver=$(nvcc --version 2>/dev/null | awk '/release/{for(i=1;i<=NF;i++) if($i ~ /release/) rel=$(i+1); } END{gsub(",","",rel); print rel}')
    [ -z "$ver" ] && ver=$(nvcc --version 2>/dev/null | awk -F'V' '/release/{print $2}')
    kv "NVCC" "已安装, 版本: ${ver:-未知}"
  else
    warn "未检测到 nvcc (CUDA Toolkit)"
  fi

  # CUDA_HOME 及 version.txt
  # CUDA Toolkit 版本（优先 version.txt/json，回退 NVCC 解析）
  cuda_toolkit_ver=""
  cuda_home="${CUDA_HOME:-}"
  if [ -z "$cuda_home" ]; then
    if [ -d /usr/local/cuda ]; then cuda_home=/usr/local/cuda; fi
    # 扫描 /usr/local/cuda-* 选择存在版本文件的路径
    for d in /usr/local/cuda-*; do
      [ -d "$d" ] || continue
      if [ -f "$d/version.txt" ] || [ -f "$d/version.json" ]; then
        cuda_home="$d"
      fi
    done
  fi
  if [ -n "$cuda_home" ]; then
    if [ -f "$cuda_home/version.txt" ]; then
      cudatxt=$(tr -d '\n' < "$cuda_home/version.txt")
      cuda_toolkit_ver=$(echo "$cudatxt" | sed -n 's/.*CUDA[^0-9]*\([0-9][0-9\.]*\).*/\1/p')
    fi
    if [ -z "$cuda_toolkit_ver" ] && [ -f "$cuda_home/version.json" ]; then
      cuda_toolkit_ver=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9.][0-9.]*\)".*/\1/p' "$cuda_home/version.json" | head -n1)
    fi
  fi
  if [ -z "$cuda_toolkit_ver" ] && [ -n "$ver" ]; then
    cuda_toolkit_ver=$(echo "$ver" | sed -n 's/\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
  fi
  [ -n "$cuda_toolkit_ver" ] && kv "CUDA" "$cuda_toolkit_ver"

  # 也尝试从 nvidia-smi 顶部提取 CUDA 版本（驱动报告的 runtime 版本）
  if has_cmd nvidia-smi; then
    smi_cuda=$(nvidia-smi 2>/dev/null | grep -m1 -o 'CUDA Version: [0-9.]*' | awk '{print $3}' || true)
    [ -n "$smi_cuda" ] && kv "CUDA(RT)" "$smi_cuda"
  fi

  # cuDNN 检测 (Linux/mac)
  cudnn_ver=""
  for d in \
    "$cuda_home/include" \
    /usr/include /usr/local/cuda/include /opt/cuda/include /usr/local/cuda-*/include \
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

  section "Python 与 AI 框架"

  # 选择 Python 解释器
  py_exec=""
  if [ -n "$PY_EXEC_OVERRIDE" ] && command -v "$PY_EXEC_OVERRIDE" >/dev/null 2>&1; then
    py_exec="$PY_EXEC_OVERRIDE"
  elif has_cmd python3; then
    py_exec="python3"
  elif [ -n "${CONDA_PREFIX:-}" ] && [ -x "$CONDA_PREFIX/bin/python" ]; then
    py_exec="$CONDA_PREFIX/bin/python"
  elif has_cmd python; then
    py_exec="python"
  fi

  if [ -z "$py_exec" ]; then
    kv "Python" "未检测到 (可用 --py 指定解释器)"
    kv "PyTorch" "跳过"
    kv "TensorFlow" "跳过"
    return
  fi

  kv "Python" "$("$py_exec" -V 2>&1)"

  timeout_cmd=""
  if has_cmd timeout; then timeout_cmd="timeout 15s"; fi

  # PyTorch（含编译CUDA版本信息）
  $timeout_cmd "$py_exec" - <<'PY' 2>/dev/null || true
import json, sys
try:
    import torch
    v=torch.__version__
    cuda=torch.cuda.is_available()
    tc=getattr(torch.version, 'cuda', None)
    devs=[torch.cuda.get_device_name(i) for i in range(torch.cuda.device_count())] if cuda else []
    print(f"  - PyTorch: {v} | TorchCUDA: {tc or 'none'} | CUDA可用: {cuda} | GPUs: {', '.join(devs) if devs else '0'}")
except Exception as e:
    print("  - PyTorch: 未安装或导入失败")
PY

  # TensorFlow
  $timeout_cmd "$py_exec" - <<'PY' 2>/dev/null || true
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
  sn="$(serial_number)"
  if [ -n "$sn" ]; then
    kv "序列号" "$sn"
  else
    kv "序列号" "不可用(可能需要root或硬件不暴露)"
  fi
  # 机器ID作为补充标识
  if [ -f /etc/machine-id ]; then kv "机器ID" "$(tr -d '\n' < /etc/machine-id)"; fi
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
