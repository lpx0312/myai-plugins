# 标签分类体系

基于实际笔记使用的精准标签体系。

## 核心标签维度（混合维度标签）

```
技术栈              # K8S、Docker、Jenkins、Oracle...
  ↓
组件/模块           # K8S/Pod、Docker/容器命令...
  ↓
场景/操作           # 安装配置、故障排查、命令参考...
  ↓
具体问题/功能       # Pod启动失败、磁盘分区、网络配置...
```

## 使用原则

- ✅ **直接关键词优先**：标签名就是你搜的词
- ✅ **层级不要太深**：2-3 层足够
- ✅ **每个笔记 3-7 个标签**
- ✅ **技术术语用英文**：K8S、Docker、Jenkins
- ⚠️ **标签中不要使用 emoji**
- ⚠️ **status 字段可以用 emoji**

## 常用标签树

### 1. K8S 相关

```yaml
# 技术栈
K8S

# 组件细分
K8S/Pod
K8S/Service
K8S/Ingress
K8S/ConfigMap
K8S/Secret
K8S/Deployment
K8S/kube-proxy
K8S/StatefulSet
K8S/DaemonSet

# 功能维度
K8S/网络配置
K8S/持久化存储
K8S/资源限制
K8S/调度策略
K8S/认证授权
K8S/日志管理
K8S/监控告警

# 存储相关
K8S/存储/PV
K8S/存储/PVC
K8S/存储/NFS
K8S/存储/StorageClass

# 认证相关
K8S/认证/ServiceAccount
K8S/认证/kubeconfig
K8S/认证/RBAC
K8S/认证/Token

# 场景维度
K8S/安装部署
K8S/运维操作
K8S/故障排查
K8S/性能优化
K8S/最佳实践
```

### 2. Docker 相关

```yaml
# 技术栈
Docker

# 组件细分
Docker/容器命令
Docker/镜像制作
Docker/网络配置
Docker/存储卷
Docker/Compose
Dockerfile

# 功能维度
Docker/容器管理
Docker/镜像管理
Docker/资源限制

# 场景维度
Docker/安装配置
Docker/故障排查
Docker/最佳实践
```

### 3. CI-CD 相关

```yaml
# 技术栈
Jenkins
GitLab
Nexus

# Jenkins 组件
Jenkins/Pipeline
Jenkins/节点管理
Jenkins/触发器
Jenkins/流程控制
Jenkins/异常捕获
Jenkins/构建后处理

# GitLab 组件
GitLab/MR
GitLab/CI配置
GitLab/备份恢复
GitLab/容器镜像
GitLab/Webhook

# Nexus 组件
Nexus/NPM仓库
Nexus/PyPI仓库
Nexus/Maven仓库
Nexus/APK仓库
Nexus/定时任务

# CI-CD 通用
CI-CD/流水线配置
CI-CD/制品管理
CI-CD/自动化部署
CI-CD/集成K8S
```

### 4. 数据库相关

```yaml
# 技术栈
Oracle
MySQL
PostgreSQL
Redis
MongoDB

# 通用功能
数据库/备份恢复
数据库/监控告警
数据库/性能优化
数据库/表空间
数据库/主从同步
数据库/连接配置
数据库/用户权限

# Oracle 特有
Oracle/表空间管理
Oracle/监听配置
Oracle/参数配置
Oracle/故障排查

# Redis 特有
Redis/主从复制
Redis/哨兵模式
Redis/集群模式
Redis/持久化
```

### 5. SRE/Linux 相关

```yaml
# 技术栈
Linux

# 功能细分
Linux/磁盘管理
Linux/网络配置
Linux/软件安装
Linux/用户权限
Linux/服务管理
Linux/进程管理
Linux/防火墙

# 技术细分
Linux/LVM
Linux/文件系统/ext4
Linux/文件系统/xfs
Linux/网络/iptables
Linux/网络/firewalld

# SRE 场景
SRE/故障排查
SRE/监控告警
SRE/自动化运维
SRE/性能优化
SRE/安全加固
```

### 6. Java/构建工具

```yaml
# 技术栈
Maven
Gradle
Jenkins

# Maven 相关
Maven/依赖管理
Maven/构建配置
Maven/仓库配置
Maven/多模块
Maven/属性变量
Maven/常用插件

# 场景维度
Maven/编译构建
Maven/配置优化
Maven/故障排查
```

## 场景标签（通用）

```yaml
# 操作场景
安装配置
故障排查
运维操作
命令参考
最佳实践
运维原理
性能优化
监控告警

# 操作类型
备份恢复
升级迁移
部署发布
参数说明
实例教程
链接收集
```

## 标签组合示例

### K8S ConfigMap 创建
```yaml
tags:
  - K8S                    # 技术栈
  - K8S/ConfigMap          # 组件
  - 安装配置                # 场景
category: 云原生/K8S/ConfigMap
```

### Pod 启动故障排查
```yaml
tags:
  - K8S                    # 技术栈
  - K8S/Pod                # 组件
  - 故障排查                # 场景
  - Pod启动失败             # 具体问题
category: 云原生/K8S/Pod
```

### Docker 命令参考
```yaml
tags:
  - Docker                 # 技术栈
  - Docker/容器命令         # 组件
  - 命令参考                # 场景
  - inspect                # 具体命令
category: 云原生/Docker
```

### Oracle 表空间监控
```yaml
tags:
  - Oracle                 # 技术栈
  - 数据库/表空间           # 功能
  - 监控告警                # 场景
  - 命令参考                # 场景
category: 数据库/Oracle
```

### Jenkins Pipeline 配置
```yaml
tags:
  - Jenkins                # 技术栈
  - Jenkins/Pipeline       # 组件
  - CI-CD/流水线配置        # 场景
  - 触发器                  # 功能
category: CI-CD/Jenkins
```

### Linux 磁盘分区
```yaml
tags:
  - Linux                  # 技术栈
  - 磁盘管理                # 功能
  - 运维操作                # 场景
  - 分区格式化              # 具体操作
category: SRE/Linux/磁盘管理
```

## Category 映射规则

### 简化原则
完整路径 → 简化 category（只保留 2-3 层）

```yaml
# 完整路径
D:\Study\005 - 云原生\03 - K8S\04 - K8S各种资源对象\01 - Pod相关\

# 简化的 category
category: 云原生/K8S/Pod
```

### 规则
- 去掉数字前缀：`005 - 云原生` → `云原生`
- 去掉泛泛词汇：`各种资源对象`、`基本操作`、`常见错误`
- 保留关键路径：技术栈 → 主要组件 → 具体功能

### 常见映射

| 完整路径 | 简化 Category |
|---------|---------------|
| `007 - 中间件/01 - 数据库/01 - Oracle/基本操作/` | `数据库/Oracle` |
| `005 - 云原生/03 - K8S/04 - K8S各种资源对象/01 - Pod相关/` | `云原生/K8S/Pod` |
| `005 - 云原生/01 - Docker/00-docker命令/` | `云原生/Docker` |
| `007 - 中间件/99 - CICD工具链/01 - jenkins/` | `CI-CD/Jenkins` |
| `003 - 程序员/03 - Java/01 - Maven/` | `Java/Maven` |
| `004 - SRE/02-Linux基础/01 - 系统管理/05 - 磁盘管理/` | `SRE/Linux/磁盘管理` |

## 迁移建议

### 从旧格式迁移

#### 去掉顶部 # 标签
```markdown
# ❌ 旧格式
#k8s
#k8s-cm
#configmap

# ✅ 新格式
---
tags:
  - K8S
  - K8S/ConfigMap
  - 安装配置
category: 云原生/K8S/ConfigMap
---
```

#### 标签标准化
```yaml
# ❌ 旧格式（太笼统）
tags:
  - 工具/Kubernetes        # 太正式，不直观
  - 类型/安装配置          # 层级太深

# ✅ 新格式（关键词优先）
tags:
  - K8S                    # 搜 "K8S" 就能找到
  - K8S/ConfigMap          # 搜 "ConfigMap" 就能找到
  - 安装配置                # 搜 "配置" 就能找到
```

### 搜索优化

标签设计优先考虑**搜索场景**：
- 搜技术栈："K8S"、"Docker"、"Jenkins"
- 搜组件名："Pod"、"Service"、"ConfigMap"
- 搜操作："安装"、"配置"、"故障排查"
- 搜问题："启动失败"、"连接超时"、"磁盘满"

标签名直接用搜索关键词，不需要额外的前缀。

## 维护建议

### 定期清理
1. 合并重复标签：`K8S` 和 `k8s` → 统一为 `K8S`
2. 统一命名：`K8s` → `K8S`
3. 删除无用标签：长时间未使用的
4. 删除标签中的 emoji

### 批量更新
使用 Obsidian 搜索替换：
- 搜索 `#k8s`（顶部标签）
- 替换为元数据 `tags: [K8S]`

- 搜索 `tags: [kubernetes]`
- 替换为 `tags: [K8S]`
