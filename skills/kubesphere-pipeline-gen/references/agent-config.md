# Agent Pod 配置参考

KubeSphere DevOps Pipeline 的 Agent 是一个 K8s Pod，构建在 Pod 里的容器中执行。本文档规定镜像、资源、缓存、settings.xml 的选择规则。

> 编排聚合型 pipeline 用顶层 `agent none`（纯调度器，不分配 executor），不需要 Pod 模板，跳过整篇文档。

---

## 1. 构建镜像选择

镜像前缀统一为 `dockerhub.kubekey.local/kubesphere`，按构建类型选 tag。

> **默认规则**：用户没明确说 JDK 版本时，Maven 默认走 **JDK 11**（团队主流版本）。只有用户明确要求 JDK17/21 或项目 `pom.xml` 指定了高版本 JDK 时才换。Node 默认 18，Go 默认 1.22.5。

| 构建类型 | 镜像 Tag | container 名 |
|----------|----------|-------------|
| Maven + JDK 11（默认） | `builder-maven:v4.1.3-jdk11-podman` | `maven` |
| Maven + JDK 17 | `builder-maven:v4.1.3-jdk17-podman` | `maven` |
| Maven + JDK 21 | `builder-maven:v4.1.3-jdk21-podman` | `maven` |
| Node.js 12 | `builder-node:v4.1.3-node12-podman` | `node` |
| Node.js 14 | `builder-node:v4.1.3-node14-podman` | `node` |
| Node.js 16 | `builder-node:v4.1.3-node16-podman` | `node` |
| Node.js 18 | `builder-node:v4.1.3-node18-podman` | `node` |
| Node.js 20 | `builder-node:v4.1.3-node20-podman` | `node` |
| Node.js 22 | `builder-node:v4.1.3-node22-podman` | `node` |
| Go 1.22.5 | `builder-go:v4.1.3-go1.22.5-podman` | `go` |
| Gradle + JDK 8 | `builder-gradle:v4.1.3-jdk8-podman` | `gradle` |

`defaultContainer` 设为对应 container 名（如 `'maven'`），这样 stage 里不显式写 `container(...)` 时默认进这个容器。

---

## 2. 资源限制

按构建类型给推荐值。这些值是团队实测后的平衡点：太低 OOM、太高浪费集群资源。

| 构建类型 | requests (cpu/memory) | limits (cpu/memory) | ephemeral-storage |
|----------|----------------------|---------------------|-------------------|
| Maven    | 2000m / 4Gi | 4000m / 6Gi | request 1Gi, limit 10Gi |
| NPM      | 1500m / 2Gi | 4000m / 4Gi | request 1Gi, limit 10Gi |
| Gradle   | 2000m / 4Gi | 4000m / 6Gi | request 1Gi, limit 10Gi |
| Go       | 1000m / 2Gi | 2000m / 4Gi | request 1Gi, limit 10Gi |

`jnlp` sidecar（Jenkins agent 连接器）固定：requests 1000m/512Mi，limits 3000m/512Mi。

---

## 3. 构建缓存

构建缓存能避免每次都重新下依赖（Maven `.m2`、NPM `.npm` 等），大幅缩短构建时间。

> **namespace 提醒**：本节创建缓存 PVC 的命令用的是 `kubesphere-devops-worker`，这是 **Jenkins Agent Pod 运行的全局 namespace**（KubeSphere DevOps 固定值），**不是** Pipeline CRD 资源住的 `DEVOPS_NAMESPACE`（如 `tking-uat6qh6q`），也**不是**业务 `DEPLOY_NAMESPACE`。三个 namespace 各管各的：Pipeline 资源住 DevOps 项目 namespace，Agent Pod 和它挂的 PVC/ConfigMap 住 `kubesphere-devops-worker`，业务服务住业务 namespace。

> **默认规则**：如果 `.pipeline/base.yaml`（见 `base-config.md`）里已经填了对应类型的 `XXX_CACHE_PVC` 字段（如 `MAVEN_CACHE_PVC: tking-uat-maven-cache-pvc`），**默认开启缓存**，不必再问用户。只有当 `base.yaml` 里没有该字段、或用户明确说"不要缓存"时才跳过。

- ✅ **启用**（默认）→ 按下方挂载 PVC
- ❌ **不启用** → 跳过本节，Pod 里不加 cache volume 和 volumeMount

### 3.1 缓存挂载路径

| 构建类型 | 容器内缓存路径 |
|----------|---------------|
| Maven    | `/root/.m2`   |
| NPM      | `/root/.npm`  |
| Gradle   | `/root/.gradle` |
| Go       | `/root/go/pkg/mod` |

PVC 名称由用户命名，习惯 `<namespace>-<type>-cache-pvc`，如 `tking-uat-maven-cache-pvc`。

### 3.2 Pod 中的挂载写法（仅启用时）

**volumes：**
```yaml
- { name: maven-cache, persistentVolumeClaim: { claimName: tking-uat-maven-cache-pvc } }
```

**对应 container volumeMounts：**
```yaml
- { name: maven-cache, mountPath: /root/.m2 }
```

### 3.3 PVC 不存在时创建

先确认目标 PVC 是否已存在：
```bash
kubectl get pvc <CACHE_PVC> -n kubesphere-devops-worker
```
不存在再创建：
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: tking-uat-maven-cache-pvc
  namespace: kubesphere-devops-worker
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: <BUILD_CACHE_SC>
  resources:
    requests:
      storage: 5Gi
```
```bash
kubectl apply -f tking-uat-maven-cache-pvc.yaml
```

> `BUILD_CACHE_SC` 在 `.pipeline/base.yaml` 里确认（如 `local-path`、`nfs-client`）。

---

## 4. Maven / Gradle 的 settings.xml

私有 Maven 仓库（Nexus）需要认证，靠挂载自定义 `settings.xml` 实现。**仅 Maven / Gradle 需要**，NPM/Go 跳过本节。

### 4.1 两步询问

**第一步**：要不要挂自定义 settings.xml？
- ✅ 自定义（私有仓库认证）→ 继续
- ❌ 用 Pod 内置默认 → 跳过本节

**第二步**：挂载的 ConfigMap key 是什么？
- 常见 key：`MavenSetting`（平台默认）、`TkingMavenUatSetting`（Tking UAT 环境）
- 得到 key 后按 4.3 验证是否存在，不存在按 4.4 创建

### 4.2 Pod 中的挂载写法（仅自定义时）

**volumeMounts：**
```yaml
- { name: maven-config, mountPath: /opt/apache-maven/conf/settings.xml, subPath: settings.xml }
```

**volumes：**
```yaml
- name: maven-config
  configMap:
    name: ks-devops-agent
    items: [{ key: TkingMavenUatSetting, path: settings.xml }]
```

### 4.3 验证 key 是否存在

```bash
kubectl get cm ks-devops-agent -n kubesphere-devops-worker -o jsonpath='{.data}' | jq -r 'keys[]'
```
- key 已存在 → 直接用
- key 不存在 → 按 4.4 创建

### 4.4 向 ConfigMap 添加新 key（仅 key 不存在时）

Tking UAT 环境的标准 settings.xml（含真实 Nexus 凭据）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">
  <servers>
    <server>
      <id>snapshots</id>
      <username>mvnpush</username>
      <password>mvnpush123!</password>
    </server>
  </servers>
  <mirrors>
    <mirror>
      <id>AFC-DRAGON-MAVEN</id>
      <mirrorOf>*</mirrorOf>
      <name>AFC-DRAGON-MAVEN</name>
      <url>http://10.18.134.7:33005/repository/AFC-DRAGON-MAVEN/</url>
    </mirror>
  </mirrors>
</settings>
```

写入 ConfigMap：
```bash
# 1. 备份
kubectl get cm ks-devops-agent -n kubesphere-devops-worker -o yaml > ks-devops-agent.backup.yaml

# 2. 追加新 key（替换 <MAVEN_SETTINGS_KEY> 为实际 key，如 TkingMavenUatSetting）
kubectl create cm ks-devops-agent -n kubesphere-devops-worker \
  --from-file=<MAVEN_SETTINGS_KEY>=settings.xml \
  --dry-run=client -o yaml \
  | kubectl patch cm ks-devops-agent -n kubesphere-devops-worker --type merge --patch-file /dev/stdin

# 3. 验证
kubectl get cm ks-devops-agent -n kubesphere-devops-worker -o jsonpath='{.data.<MAVEN_SETTINGS_KEY>}' | head -5

# 4. 重启 Agent 使挂载生效
kubectl rollout restart -n kubesphere-devops-worker deployment ks-devops-agent
```

---

## 5. 完整 Agent Pod 模板（Maven + 缓存 + settings）

组装后的标准 Pod YAML（嵌入 Jenkinsfile 的 `yaml '''...'''` 内）。注意整体缩进：在 Jenkinsfile 里要再右移若干空格保持块标量对齐。

```yaml
apiVersion: v1
kind: Pod
spec:
  activeDeadlineSeconds: 21600
  securityContext:
    fsGroup: 1000
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - { key: node-role.kubernetes.io/worker, operator: In, values: [ci] }
  tolerations:
  - { key: node.kubernetes.io/ci, operator: Exists, effect: NoSchedule }
  - { key: node.kubernetes.io/ci, operator: Exists, effect: PreferNoSchedule }
  containers:
  - name: maven
    image: dockerhub.kubekey.local/kubesphere/builder-maven:v4.1.3-jdk11-podman
    imagePullPolicy: IfNotPresent
    command: [cat]
    tty: true
    workingDir: /home/jenkins/agent
    securityContext:
      privileged: true
    resources:
      requests: { cpu: 2000m, memory: 4Gi, ephemeral-storage: 1Gi }
      limits:   { cpu: 4000m, memory: 6Gi, ephemeral-storage: 10Gi }
    volumeMounts:
    - { name: docker-sock, mountPath: /var/run/docker.sock }
    - { name: sonar-cache, mountPath: /root/.sonar/cache }
    - { name: workspace, mountPath: /home/jenkins/agent }
    - { name: maven-cache, mountPath: /root/.m2 }
    - { name: maven-config, mountPath: /opt/apache-maven/conf/settings.xml, subPath: settings.xml }
  - name: jnlp
    image: dockerhub.kubekey.local/jenkins/inbound-agent:4.10-2
    imagePullPolicy: IfNotPresent
    resources:
      requests: { cpu: 1000m, memory: 512Mi }
      limits:   { cpu: 3000m, memory: 512Mi }
    volumeMounts:
    - { name: workspace, mountPath: /home/jenkins/agent }
  volumes:
  - { name: docker-sock, hostPath: { path: /var/run/docker.sock } }
  - { name: sonar-cache, hostPath: { path: /var/data/jenkins_sonar_cache } }
  - { name: workspace, emptyDir: {} }
  - { name: maven-cache, persistentVolumeClaim: { claimName: tking-uat-maven-cache-pvc } }
  - name: maven-config
    configMap:
      name: ks-devops-agent
      items: [{ key: TkingMavenUatSetting, path: settings.xml }]
```

> `docker-sock` 挂载是给 podman 构建/推镜像用的（完整 CI/CD 型需要）；`sonar-cache` 是 SonarQube 扫描缓存。**为统一 Pod 模板、减少差异化，所有 Maven 型（含纯安装型）一律保留 docker-sock + sonar-cache**，避免不同 pipeline 的 Pod 模板分叉、维护成本上升。
