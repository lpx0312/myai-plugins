# 项目级 base.yaml 配置模板

同一项目（如 Tking）的同一个环境（如 UAT）下，所有 pipeline 共享一组全局信息：命名空间、各类凭据 ID、镜像仓库、配置库等。把这些信息集中存到一份 `base.yaml` 里，后续同项目的 pipeline 直接复用，避免重复询问、也避免不同 pipeline 之间填错值。

## 目录约定（重要）

本 skill 在项目根下使用两个固定目录：

```
<项目根>/
├── .pipeline/
│   └── base.yaml        # 全局配置（本文件），不会被 kubectl apply
└── output/              # 生成的 pipeline yaml 产物都放这里
    └── base-xxx-xc.yaml
```

- **`.pipeline/base.yaml`** — 全局配置清单，给人/agent 看的参考，**不会被 kubectl apply**，格式自由（用 YAML 便于人读）。以 `.` 开头表示这是 skill 的工作区配置，不混入业务代码。
- **`output/`** — 所有生成的 `kind: Pipeline` YAML 产物都写到这里，方便统一 `kubectl apply -f output/` 或批量管理。

> 这两个目录都**不需要提前手动创建** —— skill 在首次生成时会自动创建。

## 创建时机（懒加载）

**第一次**为某项目生成 pipeline 时，检查 `.pipeline/base.yaml` 是否存在：

- **不存在** → 向用户收集下表全局字段，创建 `.pipeline/` 目录并写入 `.pipeline/base.yaml`，再继续生成 pipeline
- **已存在** → 直接读取复用，只问单条 pipeline 的差异信息（`GIT_REPO`、`IMAGR_NAME`、pipeline 名等）

不要让用户手动初始化 —— 在用户第一次说"生成 xxx 流水线"时顺带把 `base.yaml` 建好，是无摩擦的。

## 模板（以 Tking UAT 为例，已填真实值）

```yaml
# ============================================================
# 项目级全局配置 - Tking / UAT 环境
# 同项目下所有 pipeline 复用这些值，生成时直接引用，不重复询问
# ============================================================

project: tking
env: uat

# --- 命名空间（⚠️ KubeSphere 有两个不同的 namespace，见下方说明）---
# DEVOPS_NAMESPACE：Pipeline CRD 资源住的 namespace，即 kubectl apply -n 的目标。
#   KubeSphere 建 DevOps 项目时会自动生成带随机后缀的 namespace（业务 namespace + 随机串）。
#   这个值每个集群都不同，必须从控制台或 kubectl get ns 查到真实值填入。
DEVOPS_NAMESPACE: tking-uat6qh6q      # DevOps 项目 namespace（形如 <业务namespace><随机后缀>）
# 业务 namespace：服务真正部署的地方，也是 Harbor 项目名
DEPLOY_NAMESPACE: tking-uat           # 业务部署 namespace（必须 == HARBOR_NAMESPACE）
HARBOR_NAMESPACE: tking-uat           # Harbor 镜像仓库项目名

# --- Git 凭据 ---
GIT_CREDENTIALS_ID: gitlab-afc        # 代码库 + 配置库共用的 Jenkins 凭据 ID

# --- 代码库 GitLab ---
# GIT_REPO 每条 pipeline 不同，不放这里，逐个询问
GITLAB_BASE: http://10.18.134.21:32080

# --- 配置库（存放 Dockerfile / deploy.yaml）---
CONFIG_GIT_REPO: http://10.18.134.21:32080/devops/tking-config.git

# --- 镜像仓库 Harbor ---
REGISTRY: dockerhub.kubekey.local
IMAGE_CREDENTIALS_ID: harbor-local    # Harbor 推拉镜像凭据 ID

# --- K8s 集群 ---
K8S_CREDENTIALS_ID: k8s               # kubeconfig 凭据 ID（部署用）

# --- 构建缓存 ---
BUILD_CACHE_SC: local-path            # 缓存 PVC 的 StorageClass
# 各构建类型的缓存 PVC（命名约定：<namespace>-<type>-cache-pvc）
MAVEN_CACHE_PVC: tking-uat-maven-cache-pvc
NPM_CACHE_PVC: tking-uat-npm-cache-pvc     # 启用前端缓存时用
GO_CACHE_PVC: tking-uat-go-cache-pvc       # 启用 Go 缓存时用

# --- Maven settings.xml ---
MAVEN_SETTINGS_KEY: TkingMavenUatSetting   # ks-devops-agent ConfigMap 里的 key
```

## 字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| `DEVOPS_NAMESPACE` | ✅ | **Pipeline CRD 资源住的 namespace**，即 `metadata.namespace` 和 `kubectl apply -n` 的目标。**不是业务 namespace！** KubeSphere DevOps 项目的 namespace 形如 `<业务namespace><随机后缀>`（如 `tking-uat6qh6q`），从控制台或 `kubectl get ns` 查真实值 |
| `DEPLOY_NAMESPACE` | ✅ | 业务服务部署的 namespace（业务 namespace）。**必须 == `HARBOR_NAMESPACE`** |
| `HARBOR_NAMESPACE` | ✅ | Harbor 镜像推到的项目名 |
| `GIT_CREDENTIALS_ID` | ✅ | Jenkins 里 GitLab 凭据的 ID |
| `CONFIG_GIT_REPO` | CI/CD 型必填 | 配置库地址（完整 URL） |
| `REGISTRY` | CI/CD 型必填 | Harbor 地址 |
| `IMAGE_CREDENTIALS_ID` | CI/CD 型必填 | Harbor 推镜像凭据 ID |
| `K8S_CREDENTIALS_ID` | CI/CD 型必填 | 部署用 kubeconfig 凭据 ID |
| `BUILD_CACHE_SC` | 用缓存时填 | 缓存 PVC 的 StorageClass |
| `XXX_CACHE_PVC` | 用缓存时填 | 各类型缓存 PVC 名 |
| `MAVEN_SETTINGS_KEY` | Maven 自定义 settings 时填 | ConfigMap key 名 |

## 不同环境的差异

切到新环境（如 prod）时，通常变化的字段：
- `DEVOPS_NAMESPACE`（prod 的 DevOps 项目 namespace，随机后缀不同，需重新查）
- `DEPLOY_NAMESPACE` / `HARBOR_NAMESPACE`（如 `tking-prod`）
- `MAVEN_SETTINGS_KEY`（如 `TkingMavenProdSetting`，指向 prod 私服）
- `K8S_CREDENTIALS_ID`（prod 集群凭据）
- `GIT_CREDENTIALS_ID` / `IMAGE_CREDENTIALS_ID` 通常不变（同一套 Jenkins）

建议每个环境一份 `.pipeline/base-<env>.yaml`（如 `base-prod.yaml`），生成时让用户指定用哪份；或用一份 `base.yaml` + 环境覆盖段。
