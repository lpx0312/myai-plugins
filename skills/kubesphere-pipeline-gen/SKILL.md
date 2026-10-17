---
name: kubesphere-pipeline-gen
description: 生成 KubeSphere DevOps (Jenkins) 的 Pipeline YAML（内嵌 Jenkinsfile），用于在 Kubernetes 上构建/部署 Java(Maven)、前端(NPM)、Go、Gradle 项目。当用户提到"生成流水线/pipeline"、"做个 CI/CD"、"把这个服务配上自动构建部署"、"KubeSphere 流水线"、"Jenkinsfile"、"base-xxx-xc"、"推镜像到 harbor 后部署 k8s"、"批量构建几个服务"，或要求编排触发多个子 job 时，必须使用本 skill。覆盖四类流水线：Maven 依赖安装型、完整 CI/CD 型（构建+推镜像+部署K8s）、编排聚合型（并行触发子job）、NPM/Go/Gradle 构建型。
---

# KubeSphere Pipeline 生成器

为 KubeSphere DevOps 平台（Jenkins on Kubernetes）生成标准化的 `kind: Pipeline` YAML 资源，产出物可直接 `kubectl apply -f` 到集群的 DevOps 命名空间生效。

## 产出物形态

一个完整的 YAML 文件，结构如下（YAML 顶层是 KubeSphere CRD，`jenkinsfile:` 字段内嵌整段声明式 Pipeline 脚本）：

```yaml
apiVersion: devops.kubesphere.io/v1alpha3
kind: Pipeline
metadata:
  name: <pipeline-name>
  namespace: <DEVOPS_NAMESPACE>    # ⚠️ 是 DevOps 项目的 namespace，不是业务 namespace（见下方"两个 namespace"说明）
spec:
  type: pipeline                   # ⚠️ type 在 spec 顶层，不在 spec.pipeline 下
  pipeline:
    name: <pipeline-name>
    discarder:
      days_to_keep: "7"
      num_to_keep: "10"
    parameters:
      - name: BRANCH_NAME          # 与 Jenkinsfile 内 parameters 一一对应
        type: string
        default_value: dev-xc
    jenkinsfile: |
      pipeline { ... }             # 完整 Jenkinsfile 嵌入此处
```

### ⚠️ 关键：KubeSphere 有两个不同的 namespace（极易踩坑）

生成 Pipeline YAML 时必须区分，混用会导致 Pipeline 资源 apply 失败或服务部署到错误的地方：

| 用途 | 字段 | 在哪填 | 值（以 Tking UAT 为例） |
|------|------|--------|----------------------|
| **Pipeline 资源住哪**（`kubectl apply` 目标、`metadata.namespace`） | `DEVOPS_NAMESPACE` | YAML `metadata.namespace` + apply 命令的 `-n` | `tking-uat6qh6q`（DevOps 项目 namespace，形如 `<业务namespace><随机后缀>`） |
| **业务服务部署到哪**（CI/CD 型部署目标） | `DEPLOY_NAMESPACE` | deploy.yaml / deploy 命令的 namespace | `tking-uat`（业务 namespace） |
| **Harbor 镜像仓库项目** | `HARBOR_NAMESPACE` | 推镜像路径 | `tking-uat`（通常 == 业务 namespace） |

**为什么不同**：KubeSphere 的「项目」（业务 namespace）和「DevOps 项目」是两个独立资源。建一个 DevOps 项目时，KubeSphere 会自动生成一个带随机后缀的 K8s namespace（如业务 namespace `tking-uat` → DevOps 项目 namespace `tking-uat6qh6q`）。`kind: Pipeline` 这个 CRD 资源住在 **DevOps 项目 namespace** 里，不是业务 namespace。

**怎么拿到 DEVOPS_NAMESPACE**：在 KubeSphere 控制台进入该 DevOps 项目，看详情页的 namespace；或 `kubectl get ns | grep tking` 找带随机后缀的那个。

> 注意：`DEVOPS_NAMESPACE` 的随机后缀每个集群/每个实例都不同，**不要硬编码到 skill 或通用示例里**，必须从 `.pipeline/base.yaml` 读真实值。

## 第一步：判断 pipeline 类型（关键决策）

用户的只言片语决定了走哪条路。按下表对号入座，类型不同，stage 组合、参数、Agent 配置都不同：

| 用户怎么说 | 类型 | 典型特征 |
|-----------|------|---------|
| "装到本地仓库供别的项目用" / "install 到 m2" / "base-xxx-api" / "common" / "core 公共模块" | **Maven 安装型** | 只拉代码 + `mvn install`，不部署。按 pom 位置/构建范围分三变体（见下） |
| "构建+部署" / "推镜像" / "更新服务" / "发到 k8s" | **完整 CI/CD 型** | 构建→拉配置→推镜像→部署，全流程 |
| "一次构建好几个" / "批量" / "先 A 再并行 B C D" / 触发其他 job | **编排聚合型** | 不构建，只 `build(job: 'xxx')` 串/并行触发子 pipeline |
| 前端 / Go / Gradle 项目 | **NPM/Go/Gradle 构建型** | 与 Maven 型结构相同，仅 Agent 镜像和构建命令不同 |

**Maven 安装型的第二决策点 —— pom 在哪 + 构建范围？**（选错构建命令必失败）：

| 用户怎么说 / 仓库特征 | 变体 | 构建命令 | pipeline 名 |
|----------------------|------|---------|------------|
| `xxx-service` 仓库（monorepo）/ "base-xxx-service-api" | **子目录型** | `cd <repo>-service-api && mvn install` | `base-<repo>-service-api-xc` |
| `masa-common` / `xxx-core` / 公共依赖模块 / "pom 在根目录，全量构建" | **根目录型** | 直接 `mvn install`（不 cd，全量） | `base-<repo>-xc`（无 `-api`） |
| 聚合父 pom / BOM / "packaging=pom" / "只装父 pom" / "base-xxx-pom" | **父 pom 型** | `mvn install -N -f pom.xml`（只装父 pom） | `base-<repo>-pom-xc`（带 `-pom`） |

> 判断不了 pom 位置或构建范围时，**直接问用户**："pom 在仓库根目录还是子目录？是全量构建还是只装父 pom？" 不要猜。

**类型判断不准时直接问用户**："这个 pipeline 是只装依赖、还是要构建镜像部署、还是用来编排触发别的 job？" 不要猜。

类型确定后，读 `references/pipeline-types.md` 拿到该类型需要的 stage 清单和参数清单。

## 第二步：收集全局信息（项目级，只问一次）

同一项目+环境下，namespace、各类凭据 ID、镜像仓库地址、配置库地址等是**全局共享**的。这些信息集中存到一份 `.pipeline/base.yaml`，后续同项目的 pipeline 直接复用，不必重复问。

**懒加载流程**：生成 pipeline 前先检查项目根下的 `.pipeline/base.yaml`：
- **不存在** → 向用户收集下面的全局信息，自动创建 `.pipeline/` 目录并写入 `base.yaml`（模板见 `references/base-config.md`），再继续生成
- **已存在** → 直接读取复用，只问单条 pipeline 的差异信息

全局信息清单：
- **DevOps 项目命名空间 `{{DEVOPS_NAMESPACE}}`**（如 `tking-uat6qh6q`）—— Pipeline CRD 资源住这里，是 `metadata.namespace` 和 `kubectl apply -n` 的目标。**不是业务 namespace！**
- **业务命名空间 `{{DEPLOY_NAMESPACE}}`**（如 `tking-uat`）—— 业务服务部署的目标 namespace
- 代码库 Git 凭据 ID `{{GIT_CREDENTIALS_ID}}`
- 镜像仓库地址 `{{REGISTRY}}`、命名空间 `{{HARBOR_NAMESPACE}}`、凭据 ID `{{IMAGE_CREDENTIALS_ID}}`
- 配置库地址 `{{CONFIG_GIT_REPO}}`
- K8s 集群 kubeconfig 凭据 ID `{{K8S_CREDENTIALS_ID}}`
- 构建缓存 PVC 的 StorageClass `{{BUILD_CACHE_SC}}`

**强制约束（解释 why）**：`DEPLOY_NAMESPACE` 必须等于 `HARBOR_NAMESPACE`。原因：镜像推到哪个 Harbor 项目，就该部署到同名的 K8s namespace，否则会出现"推到 A 项目、部署到 B namespace"的错乱，排查时极难定位。

## 第三步：配置 Agent Pod

Agent Pod 决定了在哪个容器里跑构建。按 `references/agent-config.md` 逐步确认：
1. 构建镜像（Maven JDK11/17/21、Node 12-22、Go、Gradle）
2. CPU/内存 requests/limits（按构建类型有推荐值）
3. 是否启用构建缓存（PVC）及缓存 PVC 名称
4. Maven/Gradle 是否挂载自定义 `settings.xml`（ConfigMap key）

> 编排聚合型 pipeline 的 Agent 是顶层 `agent none`（纯调度器，不分配 executor），不需要 Pod 模板，跳过本步。

## 第四步：选 stage 并拼装 Jenkinsfile

根据类型从 `references/pipeline-steps.md` 选 stage 模板，按顺序拼入 `stages { }`。五个标准 stage：

1. **拉取代码**（所有构建型都需要）
2. **代码构建**（所有构建型都需要；命令用变量 `{{MAVEN_BUILD_CMD}}` 等）
3. **拉取配置**（仅完整 CI/CD 型；从独立配置库取 Dockerfile/deploy.yaml）
4. **制作并推送镜像**（仅完整 CI/CD 型；podman build + push）
5. **部署到 K8s**（仅完整 CI/CD 型；kubectl apply）

编排聚合型不用上面五个 stage，而是用 `build(job: 'xxx')` + `parallel { }` 组合，写法见 `references/pipeline-steps.md` 末尾。**分批以项目 `*.repo` / 用户依赖说明为准**：最底层依赖（如 pkgconvert）单独串行，同层才 parallel，不要猜。

### 拼装规则

| 事项 | 规则 |
|------|------|
| **parameters 合并** | 收集所选各 stage 的 `parameters { }`，**同名参数只声明一次**（如多个 stage 都用 `SERVICE_CONFIG_PATH`，Jenkinsfile 顶部只写一条） |
| **environment 合并** | `TAG_NAME` 等用 `environment { }` 块定义在 Jenkinsfile 顶部（与 stages 同级），多个 stage 共用同一个块 |
| **参数顺序** | 按业务逻辑分组：分支 → 镜像仓库 → 镜像名 → 部署目标 → 配置路径 |

## 第五步：嵌入 Pipeline YAML

把拼好的 Jenkinsfile 整体嵌入 YAML 的 `jenkinsfile: |` 字段。同时把 Jenkinsfile 里的每个 `parameters` 条目，**一一映射**到 YAML 顶层的 `spec.pipeline.parameters`：

**YAML 块标量缩进规则**：`jenkinsfile: |` 后的所有内容必须相对该字段统一缩进 **6 个空格**（即 `spec.pipeline.jenkinsfile` 字段在第 4 列，内容从第 6 列开始）。Jenkinsfile 内嵌的 Pod YAML（`yaml '''...'''` 里的部分）再在 Jenkinsfile 自身缩进基础上继续右移，保持 Groovy 字符串内的对齐。直接照抄 `assets/examples/` 里对应示例的缩进即可，不要自己重新算。

```
Jenkinsfile:                                YAML:
string(name: 'BRANCH_NAME',          →      - name: BRANCH_NAME
       defaultValue: 'dev-xc',                type: string
       description: '')                        default_value: dev-xc
```

两边必须严格对应，否则 KubeSphere UI 上参数显示和 Jenkinsfile 取值会不一致。

### 强制约束（解释 why）

- **`IMAGR_NAME` / `SERVICE_CONFIG_PATH` / `DEPLOY_NAME` / `DEPLOY_CONTAINER_NAME` 默认四合一为同一个服务名**。原因：这四个值在实际中几乎总是同一个东西（镜像名 = 配置库目录名 = Deployment 名 = 容器名），分开声明只会引入拼写错误。只有用户**明确**说"不一致"时才分别填。
- **配置库分支必须等于代码库分支**（都用 `$BRANCH_NAME`）。原因：配置（Dockerfile/deploy.yaml）要和代码版本对齐，否则会用旧配置部署新代码。
- **deploy.yaml 路径统一 `config_repo/${SERVICE_CONFIG_PATH}/deploy.yaml`**。原因：第 3 阶段 checkout 配置库到 `config_repo/` 目录，第 5 阶段直接读这个目录，不再中途拷贝，避免路径漂移。

## 第六步：交付与自检

生成最终 YAML 前，对照 `assets/examples/` 里同类型的示例做 diff 式自检：
- `assets/examples/maven-install.groovy` —— Maven 安装型（**子目录型**）参考（Jenkinsfile 形态）
- `assets/examples/maven-install-root.groovy` —— Maven 安装型（**根目录型**，公共模块）参考
- `assets/examples/maven-install-pom.groovy` —— Maven 安装型（**父 pom 型**，聚合父 pom/BOM）参考
- `assets/examples/full-cicd.groovy` —— 完整 CI/CD 型参考（Jenkinsfile 形态，已含路径修正）
- `assets/examples/full-cicd.yaml` —— 完整 CI/CD 型**端到端 YAML 标杆**（`kind: Pipeline` + 内嵌 jenkinsfile，直接对照最终产物形态）
- `assets/examples/aggregator.groovy` —— 编排聚合型参考

自检清单：
- [ ] YAML 能被 `kubectl apply --dry-run=client -f` 解析（缩进、引号正确）
- [ ] `jenkinsfile:` 字段内 Pod YAML 的缩进层级正确（块标量整体右移）
- [ ] YAML `parameters` 与 Jenkinsfile `parameters` 完全对应、无遗漏
- [ ] 凭据 ID、namespace、registry 等已替换为真实值（本项目保留真实凭据，不做占位符化）
- [ ] 用了缓存的 pipeline，volumeMount 和 volumes 配对正确
- [ ] 完整 CI/CD 型：第 5 阶段读的是 `config_repo/...`，不是 `config/...` 或 `./deploy.yaml`
- [ ] Maven 安装型：构建命令匹配变体（子目录型 cd、根目录型直接 mvn 全量、父 pom 型加 `-N -f pom.xml`），三者不能搞反
- [ ] `metadata.namespace` 填的是 `DEVOPS_NAMESPACE`（带随机后缀的 DevOps 项目 namespace），不是业务 namespace

交付时把最终 YAML 写到项目的 `output/` 目录（不存在则自动创建），文件名 `<pipeline-name>.yaml`，并告知用户 apply 命令：

```bash
kubectl apply -f output/<pipeline-name>.yaml -n <DEVOPS_NAMESPACE>
```

## 何时读哪个 reference

| 想做的事 | 读这个 |
|---------|--------|
| 确定类型后看 stage 清单和参数清单 | `references/pipeline-types.md` |
| 配 Agent Pod（镜像/资源/缓存/settings） | `references/agent-config.md` |
| 拿某个 stage 的具体 Groovy 模板 | `references/pipeline-steps.md` |
| 第一次为某项目落全局配置 | `references/base-config.md` |
| 看完整 pipeline 长什么样 | `assets/examples/` 下对应类型 |

## 沟通方式

这个 skill 服务的用户是运维/开发同学，熟悉 K8s/Jenkins 术语，可以直接用 namespace、PVC、ConfigMap、kubeconfig 这类词，不必解释。但涉及决策点（选哪个镜像、要不要缓存、用哪个 settings key）时，**主动列选项让用户选**，不要默认替用户决定。
