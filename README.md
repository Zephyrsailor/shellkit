ShellKit

轻量的 Bash 脚本套件，聚焦“GPU 环境检测”和“系统信息”。支持 Linux 与 macOS（Windows 建议 WSL）。

安装与升级

- 安装：`bash scripts/install.sh`（默认安装到 `~/.shellkit` 并生成 `~/.local/bin/sk`）
- 使用：`sk gpu` 或 `sk sys`
- 升级：`bash scripts/update.sh`
- 卸载：`bash scripts/uninstall.sh`（加 `--keep-home` 可保留安装目录）

不安装也可用

- `bash main.sh gpu`
- `bash main.sh sys`

命令

- `gpu`：NVIDIA/ROCm/OpenCL、CUDA（Toolkit 与 Runtime）、NVCC、cuDNN、PyTorch/TF
  - 选项：`--verbose`、`--py <python>`
- `sys`：操作系统、内核、架构、开机时长、CPU、内存（总/已用）、磁盘、序列号/机器ID

帮助：`sk help` 或 `bash main.sh help`
