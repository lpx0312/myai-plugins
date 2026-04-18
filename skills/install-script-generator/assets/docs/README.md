---
created: 2026-03-12
updated: 2026-03-12T12:30
tags:
  - nerdctl
  - containerd
  - Docker
  - 容器管理
  - 安装配置
  - 自动化安装
  - 脚本工具
category: 运维/容器
difficulty: 初级
importance: 中
status: ✅ 已验证
sources:
  - https://github.com/containerd/nerdctl
  - https://containerd.io/
---
# nerdctl 自动安装脚本使用说明

## 概述

`install_nerdctl.sh` 是一个自动化的 nerdctl 安装脚本，完全参考 Node.js 安装脚本设计，支持多种 nerdctl 版本和架构，能够从内网镜像或 GitHub 下载并安装 nerdctl 容器管理工具。

**脚本地址：** `http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh`

---

## 支持的配置

### nerdctl 版本

| 版本系列 | 完整版本示例 | 状态 | 说明 |
|---------|-------------|------|------|
| `0.x` | 0.23.0, 0.22.2 | 早期版本 | 功能有限 |
| `1.x` | 1.7.7, 1.6.2 | 稳定版本 | Docker 兼容命令 |
| `2.x` | 2.2.1, 2.0.0 | 最新版本 | 增强功能 |

**推荐版本：** 2.2.1（最新稳定版）

### 系统架构

| 架构标识 | 说明 | 系统类型 |
|---------|------|---------|
| `x64` | Intel/AMD 64位 | x86_64 服务器 |
| `arm64` | ARM 64位 | ARM 服务器/嵌入式 |

---

## 处理流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        脚本执行流程                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   1. 参数解析    │
                    │  getopt 解析    │
                    └────────┬────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   2. 网络检测    │
                    │ 检测内网/外网    │
                    │ (可跳过)         │
                    └────────┬────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   3. 架构检测    │
                    │ 自动检测系统架构  │
                    │ (可跳过)         │
                    └────────┬────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   4. URL 构建    │
                    │ 根据版本/架构/   │
                    │ 网络构建下载URL  │
                    └────────┬────────┘
                              │
                              ▼
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
    ┌─────────────────┐             ┌─────────────────┐
    │ 安装目录已存在？  │             │ 安装包已存在？    │
    └────────┬────────┘             └────────┬────────┘
             │                               │
         是  │                           是  │
             ▼                               ▼
    ┌─────────────────┐             ┌─────────────────┐
    │   跳过安装       │             │   跳过下载       │
    └────────┬────────┘             └────────┬────────┘
             │                               │
             └───────────────┬───────────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │  5. 下载文件     │
                   │ wget/curl 下载  │
                   │ tar.gz 包        │
                   └────────┬────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │  6. 解压安装     │
                   │ tar -xzf 解压   │
                   │ --strip-1 去目录│
                   └────────┬────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │  7. 创建软连接   │
                   │ /usr/local/     │
                   │ nerdctl -> ver  │
                   └────────┬────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │  8. 注册系统命令 │
                   │ /usr/bin/       │
                   │ nerdctl 软连接  │
                   └────────┬────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │  9. 设置权限     │
                   │ chmod +x 执行   │
                   │ 权限             │
                   └────────┬────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │ 10. 安装补全    │
                   │ bash 补全文件   │
                   │ (可选)          │
                   └────────┬────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │ 11. 验证安装    │
                   │ nerdctl version │
                   │ 确认安装成功     │
                   └────────┬────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │ 12. 清理安装包  │
                   │ 删除 tar.gz     │
                   │ (可选保留)       │
                   └────────┬────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │     完成         │
                   └─────────────────┘
```

---

## 命令行参数

| 参数 | 长参数 | 说明 | 默认值 |
|------|--------|------|--------|
| `-v` | `--version` | nerdctl 版本 (例如: 2.2.1, 2.0.0) | **必需** |
| `-a` | `--arch` | 系统架构 (x64, arm64) | 自动检测 |
| `-n` | `--network` | 网络类型 (in, out) | 自动检测 |
| `-u` | `--url` | 直接指定下载 URL（优先级最高） | - |
| `-d` | `--dir` | 安装目录 | `/usr/local` |
| `-` | `--download-dir` | 下载目录 | `/tmp` |
| `-` | `--keep-package` | 保留安装包 | 删除 |
| `-` | `--debug` | 启用调试模式 | 关闭 |
| `-h` | `--help` | 显示帮助信息 | - |

---

## 使用方法

### 本地执行

```bash
# 下载脚本
curl -o install_nerdctl.sh http://mirrors.lpx.com/scripts/nerdctl/install_nerdctl.sh

# 添加执行权限
chmod +x install_nerdctl.sh

# 基本用法：安装指定版本
sudo ./install_nerdctl.sh -v 2.2.1

# 安装指定版本和架构
sudo ./install_nerdctl.sh -v 2.2.1 -a x64

# 指定内网环境安装（跳过网络检测）
sudo ./install_nerdctl.sh -v 2.2.1 -n in

# 指定外网环境安装（跳过网络检测）
sudo ./install_nerdctl.sh -v 2.2.1 -n out

# 使用自定义 URL 安装（优先级最高）
sudo ./install_nerdctl.sh -u https://github.com/containerd/nerdctl/releases/download/v2.2.1/nerdctl-2.2.1-linux-amd64.tar.gz

# 安装到指定目录并保留安装包
sudo ./install_nerdctl.sh -v 2.2.1 -d /opt/nerdctl --keep-package

# 启用调试模式
sudo ./install_nerdctl.sh -v 2.2.1 --debug
```

### 远程调用（推荐）

#### 基本用法

```bash
# 安装 nerdctl 2.2.1（自动检测架构和网络）
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1

# 安装 nerdctl 2.2.1（arm64 架构）
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 -a arm64

# 指定内网环境安装（跳过网络检测）
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 -n in

# 指定外网环境安装（跳过网络检测）
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 -n out

# 安装到指定目录
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 -d /opt/nerdctl

# 使用自定义 URL 安装
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -u https://github.com/containerd/nerdctl/releases/download/v2.2.1/nerdctl-2.2.1-linux-amd64.tar.gz

# 保留安装包
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 --keep-package

# 指定下载目录
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 --download-dir /data/tmp

# 启用调试模式
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 --debug
```

---

## 快速参考表

### 内网环境常用命令

```bash
# nerdctl 2.2.1 (最新稳定版)
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 -n in

# nerdctl 2.0.0
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.0.0 -n in

# nerdctl 1.7.7
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 1.7.7 -n in
```

### 外网环境常用命令

```bash
# 从 GitHub 下载
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 -n out

# 或直接使用 -g 等效于 -n out
curl -sSL http://192.168.0.180:8082/scripts/runtime/nerdctl/install_nerdctl.sh | sudo bash -s -- -v 2.2.1 -n out
```

### 安装后操作

```bash
# 验证安装
nerdctl version

# 查看帮助
nerdctl --help

# 列出容器
nerdctl ps

# 列出镜像
nerdctl images

# 运行容器
nerdctl run -d --name nginx nginx:alpine

# 查看容器日志
nerdctl logs nginx
```

---

## 安装目录结构

```
/usr/local/
├── nerdctl -> /usr/local/nerdctl-2.2.1        # 软连接，指向当前使用的版本
├── nerdctl-2.2.1/                              # 实际安装目录
│   ├── nerdctl                                 # 主程序
│   └── extras/
│       └── complete/
│           └── bash-completion                 # bash 补全文件
└── ...

/usr/bin/
└── nerdctl -> /usr/local/nerdctl-2.2.1/nerdctl  # 系统命令软连接

/usr/share/bash-completion/completions/
└── nerdctl                                      # bash 补全（可选）
```

---

## 网络检测逻辑

脚本会按以下顺序检测网络环境：

1. **用户指定网络类型** - 如果使用 `-n` 参数指定，跳过自动检测
2. **DNS 配置检测** - 检查 `/etc/resolv.conf` 中是否包含 `192.168.0.180`
3. **网关连通性检测** - ping `192.168.0.1`
4. **环境变量检测** - 检查 `$INTRANET_MIRROR` 环境变量
5. **镜像连通性检测** - 尝试连接 `http://mirrors.lpx.com/test`
6. **IP 地址检测** - 检查网卡 IP 是否包含 `192.168.0.`

根据检测结果：
- **内网** → 使用 `http://192.168.0.180:8082/soft/runtime/nerdctl/`
- **外网** → 使用 `https://github.com/containerd/nerdctl/releases/download/`

---

## 系统要求

### 最低系统要求

| 组件 | 要求 |
|------|------|
| 操作系统 | Linux (CentOS 7+, Rocky Linux 8+, Ubuntu 18.04+, Debian 10+) |
| 架构 | x86_64/amd64 或 aarch64/arm64 |
| 依赖 | `wget` 或 `curl` |
| 权限 | root 或 sudo |

### 检查系统架构

```bash
# 查看系统架构
uname -m

# 输出示例：
# x86_64    -> x64
# aarch64   -> arm64
```

### 安装依赖

```bash
# CentOS/Rocky Linux/AlmaLinux
sudo yum install -y wget curl

# Ubuntu/Debian
sudo apt install -y wget curl
```

---

## 注意事项

1. **需要 root 权限** - 脚本会写入 `/usr/local`、`/usr/bin` 等系统目录
2. **URL 优先级最高** - 使用 `-u/--url` 参数时，`-v`、`-a` 参数将被忽略
3. **架构自动检测** - 如不指定 `-a`，脚本会通过 `uname -m` 自动检测
4. **版本格式** - 版本号必须为 `x.y.z` 格式（如 2.2.1）
5. **containerd 依赖** - nerdctl 需要 containerd 作为后端，使用前请确保已安装

---

## 故障排查

### 常见问题

#### 1. 权限不足

**错误信息：**
```
ln: failed to create symbolic link '/usr/bin/nerdctl': Permission denied
```

**解决方案：**
```bash
# 使用 sudo 执行
sudo ./install_nerdctl.sh -v 2.2.1

# 或使用 root 用户
su -
./install_nerdctl.sh -v 2.2.1
```

#### 2. 缺少依赖

**错误信息：**
```
系统未安装 wget 或 curl，无法下载
```

**解决方案：**
```bash
# CentOS/Rocky Linux
sudo yum install -y wget curl

# Ubuntu/Debian
sudo apt install -y wget curl
```

#### 3. 网络连接失败

**解决方案：**
```bash
# 检查网络连通性
ping 192.168.0.180
curl -I http://192.168.0.180:8082/soft/runtime/nerdctl/

# 手动指定网络类型
sudo ./install_nerdctl.sh -v 2.2.1 -n in

# 使用自定义 URL
sudo ./install_nerdctl.sh -u https://github.com/containerd/nerdctl/releases/download/v2.2.1/nerdctl-2.2.1-linux-amd64.tar.gz
```

#### 4. 版本号格式错误

**错误信息：**
```
无效的版本号格式: 2
版本号格式应为: x.y.z (例如: 2.2.1, 2.0.0, 1.7.7)
```

**解决方案：**
```bash
# 使用完整的版本号
sudo ./install_nerdctl.sh -v 2.2.1  # 正确
sudo ./install_nerdctl.sh -v 2      # 错误
```

### 调试技巧

```bash
# 启用调试模式查看详细信息
sudo ./install_nerdctl.sh -v 2.2.1 --debug

# 检查网络连通性
ping 192.168.0.180
curl -I http://192.168.0.180:8082/soft/runtime/nerdctl/

# 检查软连接
ls -la /usr/local/nerdctl
ls -la /usr/bin/nerdctl

# 查看安装目录
ls -la /usr/local/nerdctl-2.2.1/

# 检查 nerdctl 二进制文件
file /usr/local/nerdctl-2.2.1/nerdctl
```

---

## 版本管理

### 查看已安装版本

```bash
# 查看当前版本
nerdctl version

# 查看所有已安装的 nerdctl 版本
ls -la /usr/local/ | grep nerdctl
```

### 切换版本

```bash
# 删除当前软连接
sudo rm -f /usr/local/nerdctl

# 创建新的软连接指向目标版本
sudo ln -s /usr/local/nerdctl-2.0.0 /usr/local/nerdctl

# 更新系统命令软连接
sudo rm -f /usr/bin/nerdctl
sudo ln -s /usr/local/nerdctl/nerdctl /usr/bin/nerdctl

# 验证版本
nerdctl version
```

### 卸载 nerdctl

```bash
# 删除安装目录
sudo rm -rf /usr/local/nerdctl-2.2.1

# 删除软连接
sudo rm -f /usr/local/nerdctl
sudo rm -f /usr/bin/nerdctl

# 删除 bash 补全（可选）
sudo rm -f /usr/share/bash-completion/completions/nerdctl
```

---

## 高级用法

### 指定安装目录

```bash
# 安装到自定义目录
sudo ./install_nerdctl.sh -v 2.2.1 -d /opt/nerdctl

# 安装到用户目录（不需要 root 权限）
mkdir -p $HOME/.local
./install_nerdctl.sh -v 2.2.1 -d $HOME/.local

# 手动配置 PATH
echo 'export PATH=$HOME/.local/nerdctl:$PATH' >> ~/.bashrc
source ~/.bashrc
```

### 离线安装

```bash
# 1. 在有网络的机器上下载
wget http://192.168.0.180:8082/soft/runtime/nerdctl/v2.2.1/nerdctl-2.2.1-linux-amd64.tar.gz

# 2. 传输到目标机器

# 3. 使用本地文件安装
sudo mkdir -p /usr/local/nerdctl-2.2.1
sudo tar -xzf nerdctl-2.2.1-linux-amd64.tar.gz -C /usr/local/nerdctl-2.2.1 --strip-components=1
sudo ln -s /usr/local/nerdctl-2.2.1 /usr/local/nerdctl
sudo ln -s /usr/local/nerdctl/nerdctl /usr/bin/nerdctl
sudo chmod +x /usr/local/nerdctl-2.2.1/nerdctl
```

---

## nerdctl 基础用法

### 常用命令对照

| Docker 命令 | nerdctl 命令 | 说明 |
|------------|-------------|------|
| `docker ps` | `nerdctl ps` | 列出运行中的容器 |
| `docker images` | `nerdctl images` | 列出镜像 |
| `docker run` | `nerdctl run` | 运行容器 |
| `docker exec` | `nerdctl exec` | 在容器中执行命令 |
| `docker logs` | `nerdctl logs` | 查看容器日志 |
| `docker stop` | `nerdctl stop` | 停止容器 |
| `docker rm` | `nerdctl rm` | 删除容器 |
| `docker rmi` | `nerdctl rmi` | 删除镜像 |
| `docker pull` | `nerdctl pull` | 拉取镜像 |
| `docker build` | `nerdctl build` | 构建镜像 |

### 快速示例

```bash
# 运行 Nginx
nerdctl run -d --name nginx -p 80:80 nginx:alpine

# 运行 MySQL
nerdctl run -d --name mysql \
  -e MYSQL_ROOT_PASSWORD=password \
  -p 3306:3306 \
  mysql:8

# 查看日志
nerdctl logs -f nginx

# 进入容器
nerdctl exec -it nginx sh

# 停止并删除容器
nerdctl stop nginx
nerdctl rm nginx
```

---

## 相关资源

- **nerdctl GitHub：** https://github.com/containerd/nerdctl
- **nerdctl 文档：** https://github.com/containerd/nerdctl/blob/main/docs/README.md
- **containerd 官网：** https://containerd.io/
- **containerd 文档：** https://containerd.io/docs/
- **Docker 命令参考：** https://docs.docker.com/reference/

---

## 与 containerd 的关系

```
┌─────────────────────────────────────────────────────────────┐
│                    nerdctl 架构                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│   用户      │────▶│  nerdctl    │────▶│   containerd    │
│  (CLI)      │     │  (CLI)      │     │   (容器运行时)   │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                 │
                                                 ▼
                                        ┌─────────────────┐
                                        │   runc/crun     │
                                        │   (OCI 运行时)  │
                                        └─────────────────┘
```

**说明：**
- **nerdctl** 是 Docker CLI 的兼容替代品
- **containerd** 是实际的容器运行时
- **runc/crun** 是底层的 OCI 运行时

**前置要求：**
```bash
# 安装 containerd (如果尚未安装)
# CentOS/Rocky Linux
sudo yum install -y containerd

# Ubuntu/Debian
sudo apt install -y containerd

# 启动 containerd
sudo systemctl enable --now containerd
```

---

## 更新日志

### v1.0.0 (2026-03-12)
- ✅ 初始版本发布
- ✅ 完全参考 Node.js 安装脚本设计
- ✅ 支持 nerdctl 0.0.1 - 2.2.1 所有版本
- ✅ 支持内网/外网自动检测
- ✅ 支持 x64/arm64 架构自动检测
- ✅ 支持自定义安装目录
- ✅ 支持自定义下载目录
- ✅ 支持保留/删除安装包
- ✅ 支持调试模式
- ✅ 支持软连接版本管理
- ✅ 支持自动安装 bash 补全
