// ============================================================
// 示例：Maven 安装型（父 pom 型）pipeline（base-<agg>-pom-xc）
// 用途：只 mvn install 父 pom 到本地仓库，供下游项目的 dependencyManagement 引用。不构建子模块。
// 对应类型见 references/pipeline-types.md §1 的「父 pom 型（-N）」
//
// 与根目录型（maven-install-root.groovy）的唯一区别：
//   构建命令加 -N -f pom.xml（non-recursive，只装父 pom，跳过子模块）。
// 典型适用：聚合父 pom / BOM 项目（packaging=pom，定义 dependencyManagement/version），
//   下游只需父 pom 的版本管理，不需要也不应构建其聚合的具体子模块。
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
        git(url: 'http://10.18.134.21:32080/Dragon/<agg-pom-repo>.git', credentialsId: 'gitlab-afc', branch: '$BRANCH_NAME', changelog: true, poll: false)
      }
    }

    stage('编译构建') {
      steps {
        // -N non-recursive: 只装父 pom,跳过 <modules> 里的子模块
        // -f pom.xml: 显式指定根 pom(packaging=pom)
        // 典型: 聚合父 pom / BOM,下游只需父 pom 的 dependencyManagement/version
        sh 'mvn clean install -Dmaven.test.skip=true -N -f pom.xml'
      }
    }
  }

  parameters {
    string(name: 'BRANCH_NAME', defaultValue: 'dev-xc', description: '')
  }
}
