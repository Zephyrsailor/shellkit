ShellKit 脚本套件

ShellKit 是一套以“简单直观、开箱即用”为目标的 Bash 脚本集合，聚焦常见机器排查与环境检测任务。当前包含 GPU 环境检测与系统信息两类能力，后续可按需扩展更多子命令。

- 入口：`main.sh`
- 兼容：Linux、macOS（Windows 建议在 WSL 中运行）

快速开始

- 安装：`bash scripts/install.sh`（默认安装到 `~/.shellkit`，生成 `~/.local/bin/sk`）
- 使用：`sk gpu` 或 `sk sys`
- 更新：`bash scripts/update.sh`
- 卸载：`bash scripts/uninstall.sh`（支持 --keep-home 保留安装目录）
- 也可直接运行：`bash main.sh gpu`

可用命令

- `gpu`（GPU 环境）
  - NVIDIA：`nvidia-smi` 驱动版本、GPU 型号/显存、计算能力
  - AMD：`rocm-smi` 设备摘要
  - OpenCL：`clinfo` 简要信息（若安装）
  - CUDA：`nvcc` 版本、`CUDA_HOME`、cuDNN 版本/线索
  - Python 框架：PyTorch、TensorFlow 版本与是否识别到 GPU
- `sys`（系统信息）
  - 操作系统名称、内核（uname）、架构、主机名、开机时长
  - CPU 型号/核心数
  - 内存总量/已用
  - 磁盘：根分区使用、物理盘概览
  - 序列号（尽力获取；Linux 可能需要 root 或硬件支持）

常用选项

- 跳过 Python 框架检测：`bash main.sh gpu --no-python`
- 查看更详细原始输出：`bash main.sh gpu --verbose`
- 查看帮助：`bash main.sh help` 或 `bash lib/gpu-env-check.sh -h`

设计原则

- 简单直观：一条命令拿到关键信息
- 层次清晰：统一 `section/kv/ok/warn/err` 输出风格
- 易于扩展：新增检查以函数或新脚本附加，入口统一分发
- 安全稳健：无破坏性操作，工具缺失时优雅降级

目录结构

- `main.sh`：统一入口与子命令分发
- `lib/gpu-env-check.sh`：GPU 环境与系统信息检测脚本
- `lib/common.sh`：通用输出与工具函数
- `contrib/shellkit.sh`：便捷函数（提供 `sk` 作为 main.sh 的简写）

在当前终端生效（可选）

- 将函数加入你的 shell 配置（zsh 示例）：
  - `echo 'source $(pwd)/contrib/shellkit.sh' >> ~/.zshrc && source ~/.zshrc`
- 之后可直接使用：`sk gpu`、`sk sys`

扩展方式

- 新增命令：在仓库根新增脚本，按需 `source lib/common.sh`，并在 `main.sh` 中注册子命令
- 新的检查项：在脚本中新增 `xxx_info()`/`xxx_env()` 函数，并在主流程中调用

兼容性说明

- 缺少相关命令时会自动降级并提示（如 `nvidia-smi`、`nvcc`、Python 框架等）
- cuDNN 版本通过头文件 `cudnn_version.h` 或 `ldconfig` 线索推断，路径非标准时可能无法准确识别
- Python 检测可在存在 `timeout` 命令时设置 15 秒超时

欢迎根据需要调整脚本输出或收集项，保持简单直观是本脚本的首要目标。
