// ============================================================
// 示例：Maven 安装型（根目录变体）pipeline（masa-common-install-xc）
// 用途：拉代码 + mvn install 到本地仓库，供下游服务引用。不部署。
// 对应类型见 references/pipeline-types.md §1 的「根目录型」
//
// 与 maven-install.groovy（子目录型）的唯一区别：
//   pom 在仓库根目录，构建命令直接 mvn clean install，**不 cd 子目录**。
// 典型适用：masa-common、tking-interfaceplatform-core 这类公共依赖模块。
//
// ⚠️ 命名例外：masa-common 是所有 service 的公共依赖，pipeline 名特殊，为
//    `masa-common-install-xc`（**无 base- 前缀**），和普通根目录型的 `base-<repo>-xc` 不同。
//    其他根目录型公共模块仍用 base- 前缀。
// ============================================================

pipeline {
  agent {
    kubernetes {
      defaultContainer 'maven'
      yaml '''
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
'''
    }
  }

  stages {
    stage('拉取代码') {
      steps {
        git(url: 'http://10.18.134.21:32080/Dragon/masa-common.git', credentialsId: 'gitlab-afc', branch: '$BRANCH_NAME', changelog: true, poll: false)
      }
    }

    stage('编译构建') {
      steps {
        // pom 在仓库根目录，直接 mvn install，**不要 cd 子目录**（cd 会找不到 pom 导致构建失败）
        sh 'mvn clean install -Dmaven.test.skip=true'
      }
    }
  }

  parameters {
    string(name: 'BRANCH_NAME', defaultValue: 'dev-xc', description: '')
  }
}
