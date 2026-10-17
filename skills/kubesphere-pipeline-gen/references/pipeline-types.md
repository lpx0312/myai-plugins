# Pipeline 类型速查

确定类型后，本文件给出该类型需要的 stage 清单、参数清单、Agent 形态、参考示例。SKILL.md 第一步的决策树指向这里。

## 速查总表

| 类型 | stages | 顶部 parameters | environment | Agent | 参考示例 |
|------|--------|----------------|-------------|-------|---------|
| **Maven 安装型**（子目录型/根目录型/父 pom 型三变体，见 §1） | 拉代码 + 构建 | `BRANCH_NAME` | 无 | kubernetes Pod | `examples/maven-install.groovy`（子目录）/ `maven-install-root.groovy`（根目录）/ `maven-install-pom.groovy`（父pom） |
| **完整 CI/CD 型** | 拉代码 + 构建 + 拉配置 + 推镜像 + 部署 | 全套 8 个 | `TAG_NAME` | kubernetes Pod | `examples/full-cicd.groovy` |
| **编排聚合型** | N 个 `build()` / `parallel` | 无（或仅 `BRANCH_NAME` 透传） | 无 | `none`（顶层，不分配 executor） | `examples/aggregator.groovy` |
| **NPM/Go/Gradle 构建型** | 拉代码 + 构建（+可选推镜像/部署） | `BRANCH_NAME` + 构建相关 | 同 CI/CD（若部署） | kubernetes Pod | 改 Maven 示例的镜像/命令 |

---

## 1. Maven 安装型

**用途**：把某个服务的 API/公共模块 `mvn install` 到本地仓库（`.m2`）或私服，供下游服务引用。**不部署**。

**stage 清单**：
1. 拉取代码
2. 编译构建（`mvn clean install`）

**参数**：仅 `BRANCH_NAME`

**Agent**：Maven Pod（JDK11 默认），挂 `.m2` 缓存 + settings.xml

> 本类型按 **pom 在仓库里的位置 + 构建范围** 分三个变体。stage 结构、Agent Pod、参数完全相同，**唯一区别是构建命令**（要不要 cd 子目录、要不要 `-N` 只装父 pom）——选错会导致构建失败。先确认 pom 位置和构建范围再决定走哪个变体。

### 变体 A：子目录型（默认）

| 项 | 值 |
|----|----|
| 适用 | `<repo>-service` 仓库（monorepo），pom 在 `<repo>-service-api` 子目录 |
| 典型 | `base-afc-fico-service-api-xc`、`base-tking-interfacegroup-service-api-xc` |
| pipeline 名 | `base-<repo>-service-api-xc` |
| 构建命令 | `cd <repo>-service-api && mvn clean install`（用 `JOB_BASE_NAME` 自动推目录名） |
| 参考示例 | `examples/maven-install.groovy` |

构建命令靠 pipeline 名反推子目录（见 `pipeline-steps.md` §2 的「进子目录构建技巧」）：
```groovy
sh 'DIR=${JOB_BASE_NAME#base-}; DIR=${DIR%-xc}; cd "$DIR" && mvn clean install -Dmaven.test.skip=true'
```

> ⚠️ **pkgconvert 子目录大小写例外**：`tking-pkgconvert-service` 仓库的 api 子目录名是 **`tking-pkgConvert-service-api`**（C 大写），和 pipeline 名 `base-tking-pkgconvert-service-api-xc`（全小写）不一致。此时 `JOB_BASE_NAME` 推导会得到错误的全小写目录名，**必须改用显式 cd**：
> ```groovy
> sh 'cd tking-pkgConvert-service-api && mvn clean install -Dmaven.test.skip=true'
> ```
> 凡是子目录实际大小写与 pipeline 名不符的，都不能用推导技巧，改用显式目录名。

### 变体 B：根目录型

| 项 | 值 |
|----|----|
| 适用 | 公共依赖模块，pom 直接在仓库根目录 |
| 典型 | `base-tking-interfaceplatform-core-xc`；**masa-common 特殊**：名为 `masa-common-install-xc`（无 base- 前缀，因为它是所有 service 的公共依赖） |
| pipeline 名 | `base-<repo>-xc`（**没有 `-api`**，因为是公共模块不是某服务的 API 子模块）；masa-common 例外为 `masa-common-install-xc` |
| 构建命令 | `mvn clean install -Dmaven.test.skip=true`（**直接构建，不 cd**） |
| 参考示例 | `examples/maven-install-root.groovy` |

> ⚠️ **根目录型绝不能 cd 子目录**：pom 就在根目录，`cd` 进任何子目录都会找不到 pom 而构建失败。

### 变体 C：父 pom 型（-N）

| 项 | 值 |
|----|----|
| 适用 | 聚合父 pom / BOM 项目（`packaging=pom`，定义 `dependencyManagement`/版本），下游只需父 pom 的版本管理 |
| 典型 | `base-tking-pkgconvert-pom-xc`、`base-<agg>-pom-xc`（命名常带 `-pom` 后缀） |
| pipeline 名 | `base-<repo>-pom-xc`（**带 `-pom`**，和根目录型的 `-xc` 区分） |
| 构建命令 | `mvn clean install -Dmaven.test.skip=true -N -f pom.xml`（`-N` non-recursive 只装父 pom，跳过 `<modules>` 子模块） |
| 参考示例 | `examples/maven-install-pom.groovy` |

> **与根目录型的区别**：根目录型是全量构建（把所有子模块也装到 m2）；父 pom 型用 `-N` 只装父 pom。**适用场景不同，不要混用**：
> - 下游需要父 pom **里的具体子模块 jar**（要 import/use 子模块代码）→ 根目录型
> - 下游只需要父 pom **的版本管理/BOM**（`dependencyManagement` 声明依赖版本）→ 父 pom 型
>
> 误用父 pom 型装聚合项目会漏装子模块，下游引用时报"找不到子模块 artifact"；误用根目录型装 BOM 会白白构建一堆不需要的子模块、还可能因子模块自身依赖问题失败。

**示例骨架**（三变体通用，构建命令处按变体替换）：
```groovy
pipeline {
  agent { kubernetes { defaultContainer 'maven'; yaml '''...Maven Pod...''' } }
  stages {
    stage('拉取代码') { steps { git(...) } }
    // stage('编译构建') { steps { sh 'DIR=${JOB_BASE_NAME#base-}; ...; cd "$DIR" && mvn clean install ...' } }  // 子目录型
    // stage('编译构建') { steps { sh 'mvn clean install -Dmaven.test.skip=true' } }                            // 根目录型(全量)
    stage('编译构建') { steps { sh 'mvn clean install -Dmaven.test.skip=true -N -f pom.xml' } }                  // 父 pom 型(只父pom)
  }
  parameters {
    string(name: 'BRANCH_NAME', defaultValue: 'dev-xc', description: '')
  }
}
```

---

## 2. 完整 CI/CD 型

**用途**：从源码构建出镜像，推到 Harbor，再部署到 K8s。端到端交付。

**典型场景**：`masa-gateway-uat`、`xxx-service-uat` 这类业务服务部署。

**stage 清单**：
1. 拉取代码
2. 编译构建（`mvn clean package` 打出 jar/war）
3. 拉取配置（从配置库取 Dockerfile + deploy.yaml）
4. 制作并推送镜像（podman build + push）
5. 部署到 K8s（kubectl apply）

**参数（全套 8 个）**：
```
BRANCH_NAME, REGISTRY, HARBOR_NAMESPACE, IMAGR_NAME,
DEPLOY_NAMESPACE, DEPLOY_NAME, DEPLOY_CONTAINER_NAME, SERVICE_CONFIG_PATH
```

**environment**：`TAG_NAME = "build_${env.BUILD_NUMBER}"`

**Agent**：Maven Pod，需要 `docker-sock` 挂载（podman 用）、`.m2` 缓存、settings.xml

**关键约束**：
- `DEPLOY_NAMESPACE` == `HARBOR_NAMESPACE`
- `IMAGR_NAME` / `SERVICE_CONFIG_PATH` / `DEPLOY_NAME` / `DEPLOY_CONTAINER_NAME` 默认四合一
- 配置库分支 == 代码库分支（`$BRANCH_NAME`）
- deploy.yaml 路径统一 `config_repo/${SERVICE_CONFIG_PATH}/deploy.yaml`

**完整结构**：见 `examples/full-cicd.groovy`（Jenkinsfile 形态）和 `examples/full-cicd.yaml`（端到端 `kind: Pipeline` YAML 形态，最终交付物标杆）。

---

## 3. 编排聚合型

**用途**：自己不构建，只按依赖顺序串行/并行触发一堆子 pipeline（通常是上面两类）。用于"一键构建全部 base 依赖"这种场景。

**典型场景**：`tking-api-install-all-xc`、`tking-pom-install-all-xc`。

**分批原则**（生成前先读项目的 `*.repo` / 用户给出的依赖说明，不要猜）：
1. **最底层依赖单独串行** —— 例：`base-tking-pkgconvert-service-api-xc` 被几乎所有服务依赖，必须单独占第一批，不可与其他服务 `parallel`
2. **被后续多批依赖的中间层也单独串行** —— 例：`base-thing-interfaceplatform-service-api-xc` 依赖 pkgconvert，又被第三批依赖 → 单独第二批
3. **同层互不依赖 → 同一 `parallel { }` 批内并行**
4. **批间串行**：下一批等上一批全部成功（`wait: true, propagate: true`）

**参数**：通常**无参数**（子 job 名硬编码）。可选加 `BRANCH_NAME` 透传，但 KubeSphere 的 `build` step 默认不传参时子 job 用自己的默认参数，简单可靠。

**Agent**：顶层 `agent none`（纯调度器，不跑构建，不分配 executor，`build()` 在 Jenkins master flyweight 线程执行）。每个 stage 内也 `agent none`。

**结构示例**（对齐 `tking-api-install-all-xc`）：
```groovy
pipeline {
  agent none
  stages {
    // 第一批：最底层，单独串行
    stage('default-1') {
      agent none
      steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-pkgconvert-service-api-xc') }
    }
    // 第二批：中间层，单独串行
    stage('default-2') {
      agent none
      steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-thing-interfaceplatform-service-api-xc') }
    }
    // 第三批：同层并行
    stage('default-3') {
      parallel {
        stage('服务A') { agent none; steps { build(..., job: 'base-aaa-api-xc') } }
        stage('服务B') { agent none; steps { build(..., job: 'base-bbb-api-xc') } }
      }
    }
    // 第四批：依赖第三批，并行
    stage('default-4') {
      parallel {
        stage('服务C') { agent none; steps { build(..., job: 'base-ccc-api-xc') } }
      }
    }
  }
}
```

**完整结构**：见 `examples/aggregator.groovy`（与 `tking-uat.repo` 批次一致）。

---

## 4. NPM / Go / Gradle 构建型

**用途**：非 Maven 项目的构建（前端、Go 服务、Gradle 项目）。结构上和 Maven 安装型 / CI/CD 型一样，只是 Agent 镜像、构建命令、缓存路径不同。

### NPM 型（前端）

| 项 | 值 |
|----|----|
| Agent 镜像 | `builder-node:v4.1.3-node<N>-podman`（N=12/14/16/18/20/22） |
| container 名 | `node` |
| 资源 | requests 1500m/2Gi, limits 4000m/4Gi |
| 缓存路径 | `/root/.npm` |
| 构建命令 | `npm install && npm run build` |
| settings.xml | 不需要 |

如果前端也要镜像化部署，加 stage 3/4/5（拉配置/推镜像/部署），和 Maven CI/CD 型的后半段完全一样。

### Go 型

| 项 | 值 |
|----|----|
| Agent 镜像 | `builder-go:v4.1.3-go1.22.5-podman` |
| container 名 | `go` |
| 资源 | requests 1000m/2Gi, limits 2000m/4Gi |
| 缓存路径 | `/root/go/pkg/mod` |
| 构建命令 | `go build -o app ./...` 或项目特定命令 |

### Gradle 型

| 项 | 值 |
|----|----|
| Agent 镜像 | `builder-gradle:v4.1.3-jdk8-podman` |
| container 名 | `gradle` |
| 资源 | requests 2000m/4Gi, limits 4000m/6Gi |
| 缓存路径 | `/root/.gradle` |
| 构建命令 | `./gradlew clean build -x test` |
| settings.xml | 可选（挂 Gradle 的 init.gradle 或 settings.gradle，规则同 Maven） |

> 这三类目前没有真实跑通的样例，生成时以 Maven 示例为骨架，替换镜像、container 名、命令、缓存路径即可。生成后建议让用户先手动跑一次验证。
