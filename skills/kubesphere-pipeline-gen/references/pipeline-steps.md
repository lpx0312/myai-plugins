# Jenkinsfile 构建 Stage 模板

本文件列出所有标准 stage 的 Groovy 模板及变量说明。按 pipeline 类型（见 `pipeline-types.md`）选 stage，按顺序拼入 `stages { }` 块。

## 目录
1. [拉取代码](#1-拉取代码)
2. [代码构建](#2-代码构建)
3. [拉取配置](#3-拉取配置)
4. [制作并推送镜像](#4-制作并推送镜像)
5. [部署到 K8s](#5-部署到-k8s)
6. [编排聚合型 build/parallel](#6-编排聚合型-build--parallel)
7. [参数与环境变量合并规则](#7-参数与环境变量合并规则)

---

## 1. 拉取代码

所有构建型 pipeline 都需要。把业务代码库检出到 workspace。

| 变量 | 来源 | 说明 |
|------|------|------|
| `{{GIT_REPO}}` | 询问用户 | Git 仓库地址，如 `http://10.18.134.21:32080/Dragon/xxx.git` |
| `{{GIT_CREDENTIALS_ID}}` | 全局配置 | Jenkins 凭据 ID，如 `gitlab-afc` |
| `{{BRANCH_DEFAULT}}` | 询问用户 | 默认分支，如 `dev-xc` |

```groovy
stage('拉取代码') {
  steps {
    git(url: '{{GIT_REPO}}', credentialsId: '{{GIT_CREDENTIALS_ID}}', branch: '$BRANCH_NAME', changelog: true, poll: false)
  }
}
```

**顶部需声明参数：**
```groovy
parameters {
  string(name: 'BRANCH_NAME', defaultValue: '{{BRANCH_DEFAULT}}', description: '')
}
```

---

## 2. 代码构建

所有构建型 pipeline 都需要。按项目类型选命令，命令统一用变量 `{{BUILD_CMD}}` 占位，避免硬编码。

| 构建类型 | container | 命令示例 | 说明 |
|----------|-----------|----------|------|
| Maven 依赖安装（**根目录型**） | `maven` | `mvn clean install -Dmaven.test.skip=true` | 公共模块（masa-common 等），pom 在仓库根，全量构建，**不 cd** |
| Maven 依赖安装（**父 pom 型**） | `maven` | `mvn clean install -Dmaven.test.skip=true -N -f pom.xml` | 聚合父 pom/BOM（packaging=pom），`-N` 只装父 pom 跳过子模块 |
| Maven 依赖安装（**子目录型**） | `maven` | `cd <repo>-service-api && mvn clean install -Dmaven.test.skip=true` | `<repo>-service` 仓库，pom 在子目录，要 cd（见下方技巧） |
| Maven 打包（CI/CD 型） | `maven` | `mvn clean package -Dmaven.test.skip=true` | 仅编译打包当前项目，出 jar 给镜像构建 |
| NPM 打包 | `node` | `npm install && npm run build` | 前端项目 |
| Go 构建 | `go` | `go build ./...` | Go 项目 |
| Gradle 构建 | `gradle` | `./gradlew clean build -x test` | Gradle 项目 |

> 因为 `defaultContainer` 已设为构建容器，stage 内无需再写 `container(...)`，直接 `sh`。

```groovy
stage('编译构建') {
  steps {
    sh '{{BUILD_CMD}}'
  }
}
```

### ⚠️ 关键决策：Maven 安装型先确认 pom 位置（选错必构建失败）

**使用前必须先问用户：pom 在仓库根目录，还是在子目录？是普通父 pom 还是聚合父 pom/BOM？** 这是 Maven 安装型的第一决策点，直接决定构建命令：

| pom 位置 | 适用仓库 | 构建命令 | pipeline 名 |
|---------|---------|---------|------------|
| **仓库根目录**（全量） | `masa-common`、`tking-interfaceplatform-core` 等公共模块 | 直接 `mvn clean install`（**不 cd**，全量构建子模块） | `base-<repo>-xc`（无 `-api`） |
| **仓库根目录**（父 pom/BOM） | 聚合父 pom 项目（`packaging=pom`，定义版本管理），下游只需父 pom | `mvn clean install -N -f pom.xml`（`-N` 只装父 pom） | `base-<repo>-pom-xc`（带 `-pom`） |
| **子目录**（monorepo） | `xxx-service` 仓库，pom 在 `xxx-service-api` 子目录 | `cd <repo>-service-api && mvn clean install` | `base-<repo>-service-api-xc` |

> **根目录全量 vs 父 pom 型**：两者 pom 都在根目录，但构建范围不同。全量型把子模块 jar 也装到 m2（下游要 import 子模块代码）；父 pom 型用 `-N` 只装父 pom（下游只要 BOM/版本管理）。误选会导致下游依赖缺失或白白构建无用子模块。

**根目录型（全量）**最简单，直接：
```groovy
sh 'mvn clean install -Dmaven.test.skip=true'
```

**父 pom 型**加 `-N -f pom.xml`：
```groovy
sh 'mvn clean install -Dmaven.test.skip=true -N -f pom.xml'
```

**子目录型**用 `JOB_BASE_NAME` 反推目录名。只有当 pom 在子目录、且 pipeline 名遵循 `base-<子目录名>-xc` 命名规范时才用此技巧：

```groovy
// 例：pipeline 名 base-afc-fico-service-api-xc
// ${JOB_BASE_NAME#base-} → afc-fico-service-api-xc
// ${DIR%-xc} → afc-fico-service-api  （% 是最短后缀匹配，只剥 -xc）
// 最终 cd 进 afc-fico-service-api 子目录构建
sh 'DIR=${JOB_BASE_NAME#base-}; DIR=${DIR%-xc}; cd "$DIR" && mvn clean install -Dmaven.test.skip=true'
```

> ⚠️ `${DIR%-xc}` 用的是 `%`（最短后缀匹配）不是 `%%`（最长匹配）。若子目录名本身含 `-xc` 会误剥，此时改用显式目录名 `cd '<目录名>'`。

> ⚠️ **子目录大小写与 pipeline 名不符时，不能用推导技巧**。例：`tking-pkgconvert-service` 仓库的 api 子目录是 `tking-pkgConvert-service-api`（C 大写），而 pipeline 名 `base-tking-pkgconvert-service-api-xc` 全小写，推导会得到错误目录。这类必须显式写：
> ```groovy
> sh 'cd tking-pkgConvert-service-api && mvn clean install -Dmaven.test.skip=true'
> ```

---

## 3. 拉取配置

> ⚠️ **仅完整 CI/CD 型需要**。纯 Maven 安装型 / 纯镜像构建型跳过本节。

### 背景

老项目代码库里不含 `Dockerfile` 和 `deploy.yaml`，改造业务库成本高，所以单独建**配置库**存放这些文件，目录结构为：

```
<配置库>/
├── <SERVICE_CONFIG_PATH>/
│   ├── Dockerfile
│   └── deploy.yaml
```

### 规则

- 配置库分支**必须**与代码库分支一致，统一用 `$BRANCH_NAME`（避免配置和代码版本错配）
- `config_repo` 是固定的检出目录名，stage 内直接引用
- 第 3 阶段只把 `Dockerfile` 拷到当前目录（podman build 的 context 在 `.`），**deploy.yaml 留在 config_repo 不动**，由第 5 阶段直接读

| 变量 | 来源 | 说明 |
|------|------|------|
| `{{CONFIG_GIT_REPO}}` | 全局配置 | 配置库 Git 地址，如 `http://10.18.134.21:32080/devops/tking-config.git` |
| `{{GIT_CREDENTIALS_ID}}` | 全局配置 | 配置库凭据 ID（通常与代码库相同） |
| `{{SERVICE_CONFIG_PATH}}` | 询问用户 | 服务在配置库中的目录名，如 `masa-gateway` |

```groovy
stage('拉取配置') {
  steps {
    checkout([$class: 'GitSCM',
      branches: [[name: '$BRANCH_NAME']],
      userRemoteConfigs: [[credentialsId: '{{GIT_CREDENTIALS_ID}}', url: '{{CONFIG_GIT_REPO}}']],
      extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'config_repo']]
    ])
    // 只拷 Dockerfile 到当前目录；deploy.yaml 留在 config_repo 由第 5 阶段直接读
    sh '''
      rm -f Dockerfile
      cp -arf config_repo/${SERVICE_CONFIG_PATH}/Dockerfile Dockerfile
    '''
  }
}
```

**顶部需声明参数：**
```groovy
parameters {
  string(name: 'SERVICE_CONFIG_PATH', defaultValue: '{{SERVICE_CONFIG_PATH}}', description: '')
}
```

---

## 4. 制作并推送镜像

> ⚠️ **仅完整 CI/CD 型需要**。纯依赖安装型跳过。

| 变量 | 来源 | 说明 |
|------|------|------|
| `{{IMAGE_CREDENTIALS_ID}}` | 全局配置 | Harbor 镜像仓库认证凭据 ID，如 `harbor-local` |
| `{{REGISTRY}}` | 全局配置 | 镜像仓库地址，如 `dockerhub.kubekey.local` |
| `{{HARBOR_NAMESPACE}}` | 全局配置 | Harbor 项目/命名空间，如 `tking-uat` |
| `{{IMAGR_NAME}}` | 询问用户 | 镜像名，**默认与 `SERVICE_CONFIG_PATH` 一致** |
| `TAG_NAME` | 固定规则 | `build_${env.BUILD_NUMBER}`，以 Jenkins 构建编号为 tag，无需修改 |

```groovy
stage('制作并推送镜像') {
  steps {
    withCredentials([usernamePassword(credentialsId: '{{IMAGE_CREDENTIALS_ID}}', passwordVariable: 'HARBOR_PASSWD', usernameVariable: 'HARBOR_USER')]) {
      sh '''
        echo "$HARBOR_PASSWD" | podman login $REGISTRY -u "$HARBOR_USER" --tls-verify=false --password-stdin
        podman build --tls-verify=false -f Dockerfile -t $REGISTRY/$HARBOR_NAMESPACE/$IMAGR_NAME:$TAG_NAME .
        podman push --tls-verify=false $REGISTRY/$HARBOR_NAMESPACE/$IMAGR_NAME:$TAG_NAME
      '''
    }
  }
}
```

**顶部需声明参数：**
```groovy
parameters {
  string(name: 'REGISTRY', defaultValue: '{{REGISTRY}}', description: '')
  string(name: 'HARBOR_NAMESPACE', defaultValue: '{{HARBOR_NAMESPACE}}', description: '')
  string(name: 'IMAGR_NAME', defaultValue: '{{IMAGR_NAME}}', description: '')
}
```

**顶部需声明 environment（与第 5 阶段共用同一个块）：**
```groovy
environment {
  TAG_NAME = "build_${env.BUILD_NUMBER}"
}
```

---

## 5. 部署到 K8s

> ⚠️ **仅完整 CI/CD 型需要**。

| 变量 | 来源 | 说明 |
|------|------|------|
| `{{K8S_CREDENTIALS_ID}}` | 全局配置 | K8s 集群 kubeconfig 凭据 ID，如 `k8s` |
| `{{DEPLOY_NAMESPACE}}` | 全局配置 | K8s 部署命名空间，**必须等于 `HARBOR_NAMESPACE`** |
| `{{DEPLOY_NAME}}` | 询问用户 | Deployment 资源名，**默认与 `SERVICE_CONFIG_PATH` 一致** |
| `{{DEPLOY_CONTAINER_NAME}}` | 询问用户 | 容器名，**默认与 `SERVICE_CONFIG_PATH` 一致** |
| `{{SERVICE_CONFIG_PATH}}` | 询问用户 | 与第 3 阶段共用，Jenkinsfile 只声明一次 |
| `TAG_NAME` | 固定规则 | 与第 4 阶段共用同一个 environment 块 |

```groovy
stage('部署到 k8s 集群') {
  steps {
    withCredentials([kubeconfigContent(credentialsId: '{{K8S_CREDENTIALS_ID}}', variable: 'KUBECONFIG_CONFIG')]) {
      sh '''
        mkdir -p ~/.kube/
        echo "$KUBECONFIG_CONFIG" > ~/.kube/config
        envsubst < config_repo/${SERVICE_CONFIG_PATH}/deploy.yaml | kubectl apply -f -
      '''
    }
  }
}
```

> `deploy.yaml` 里通常含 `${REGISTRY}` `${HARBOR_NAMESPACE}` `${IMAGR_NAME}` `${TAG_NAME}` 等占位符，`envsubst` 会在 apply 前把它们替换成 Jenkins 环境变量值。这就是为什么这些参数必须既能被 Jenkinsfile 用、又能透传到 deploy.yaml。

**顶部需声明参数：**
```groovy
parameters {
  string(name: 'DEPLOY_NAMESPACE', defaultValue: '{{DEPLOY_NAMESPACE}}', description: '')
  string(name: 'DEPLOY_NAME', defaultValue: '{{DEPLOY_NAME}}', description: '')
  string(name: 'DEPLOY_CONTAINER_NAME', defaultValue: '{{DEPLOY_CONTAINER_NAME}}', description: '')
}
```

---

## 6. 编排聚合型 build / parallel

> ⚠️ **仅编排聚合型需要**。这类 pipeline 不构建代码，只触发其他 pipeline（子 job）。

### 单个触发

```groovy
stage('xxx') {
  agent none
  steps {
    build(quietPeriod: 0, wait: true, propagate: true, job: '<子pipeline名>')
  }
}
```

- `propagate: true`：子 job 失败则当前 job 也失败
- `wait: true`：等子 job 跑完再继续

### 并行触发多个（一组同时跑）

```groovy
stage('并行构建一组') {
  parallel {
    stage('服务A') {
      agent none
      steps {
        build(quietPeriod: 0, wait: true, propagate: true, job: 'base-xxx-service-api-xc')
      }
    }
    stage('服务B') {
      agent none
      steps {
        build(quietPeriod: 0, wait: true, propagate: true, job: 'base-yyy-service-api-xc')
      }
    }
  }
}
```

### 串行 + 并行混合

用多个顶层 `stage`，不同 stage 之间串行；同层互不依赖的多个 job 放进同一个 stage 的 `parallel { }`：

```groovy
stages {
  // 最底层依赖：单独串行，不要包 parallel
  stage('default-1') {
    agent none
    steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-pkgconvert-service-api-xc') }
  }
  // 中间层（仍被后续依赖）：继续单独串行
  stage('default-2') {
    agent none
    steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-thing-interfaceplatform-service-api-xc') }
  }
  // 同层并行
  stage('default-3') { parallel { ... 多个 build ... } }
  stage('default-4') { parallel { ... 多个 build ... } }
}
```

> ⚠️ **不要把最底层依赖塞进 `parallel`**。例：`pkgconvert` 被几乎所有服务依赖，必须单独占第一批；若与其他服务并行，失败时难定位，且其他服务可能抢跑装到半成品。分批以项目 `*.repo` / 用户依赖说明为准。

> **编排聚合型的 Agent 是顶层 `agent none`**（不需要 kubernetes Pod 模板，因为它自己不跑构建，只是个调度器）。`build()` step 在 Jenkins master 的 flyweight 线程上执行，不依赖工作节点 executor，所以顶层和每个 stage 内都用 `agent none`，完全不占用任何工作节点。

**这类 pipeline 通常没有 parameters**（子 job 名硬编码），但可以加 `BRANCH_NAME` 参数透传给子 job —— 取决于子 job 是否接受参数化构建。简单起见，默认不传参。

---

## 7. 参数与环境变量合并规则

### parameters 合并（去重）

每个 stage 声明自己需要的参数。拼装时把所有 stage 的 `parameters` 收集起来，**同名参数只保留一条**。典型冲突点：

- `SERVICE_CONFIG_PATH`：第 3、5 阶段都用 → 只声明一次
- `TAG_NAME` 不放 parameters（用 environment）

**合并示例**（选了「拉代码」+「构建」+「推镜像」+「部署」）：

```groovy
parameters {
  string(name: 'BRANCH_NAME', defaultValue: '{{BRANCH_DEFAULT}}', description: '')
  string(name: 'SERVICE_CONFIG_PATH', defaultValue: '{{SERVICE_CONFIG_PATH}}', description: '')
  string(name: 'REGISTRY', defaultValue: '{{REGISTRY}}', description: '')
  string(name: 'HARBOR_NAMESPACE', defaultValue: '{{HARBOR_NAMESPACE}}', description: '')
  string(name: 'IMAGR_NAME', defaultValue: '{{IMAGR_NAME}}', description: '')
  string(name: 'DEPLOY_NAMESPACE', defaultValue: '{{DEPLOY_NAMESPACE}}', description: '')
  string(name: 'DEPLOY_NAME', defaultValue: '{{DEPLOY_NAME}}', description: '')
  string(name: 'DEPLOY_CONTAINER_NAME', defaultValue: '{{DEPLOY_CONTAINER_NAME}}', description: '')
}
```

### environment 合并

`TAG_NAME` 这类派生值放 `environment { }`（与 `stages` 同级，只一个块）：

```groovy
environment {
  TAG_NAME = "build_${env.BUILD_NUMBER}"
}
```

### 声明顺序（Jenkinsfile 顶层结构）

```groovy
pipeline {
  agent { kubernetes { ... } }     // 或 agent none（聚合型，不分配 executor）
  environment { TAG_NAME = ... }   // 仅 CI/CD 型
  stages {
    stage('拉取代码') { ... }
    stage('编译构建') { ... }
    // ...其他 stage
  }
  parameters { ... }               // 合并去重后的参数
}
```
