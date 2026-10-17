// ============================================================
// 示例：Maven 安装型 pipeline（base-afc-fico-service-api-xc）
// 用途：拉代码 + mvn install 到本地仓库，供下游服务引用。不部署。
// 对应类型见 references/pipeline-types.md §1
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
        git(url: 'http://10.18.134.21:32080/Dragon/afc-fico-service.git', credentialsId: 'gitlab-afc', branch: '$BRANCH_NAME', changelog: true, poll: false)
      }
    }

    stage('编译构建') {
      steps {
        // JOB_BASE_NAME = base-afc-fico-service-api-xc
        // ${JOB_BASE_NAME#base-} 剥掉 "base-" 前缀 → afc-fico-service-api-xc
        // ${DIR%-xc} 剥掉 "-xc" 后缀（% 是最短后缀匹配）→ afc-fico-service-api
        // 所以进的是 afc-fico-service-api 子目录构建（仓库内是 monorepo，pom 在该子目录下）
        // ⚠️ 仅当 pom 不在仓库根、且 pipeline 名遵循 base-<子目录名>-xc 规范时才用这个技巧；
        //    pom 在仓库根时直接用 sh 'mvn clean install -Dmaven.test.skip=true'，不要 cd。
        sh 'DIR=${JOB_BASE_NAME#base-}; DIR=${DIR%-xc}; cd "$DIR" && mvn clean install -Dmaven.test.skip=true'
      }
    }
  }

  parameters {
    string(name: 'BRANCH_NAME', defaultValue: 'dev-xc', description: '')
  }
}
