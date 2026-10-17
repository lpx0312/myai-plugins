// ============================================================
// 示例：完整 CI/CD 型 pipeline（masa-gateway-uat）
// 用途：构建 → 推镜像 → 部署 K8s，端到端交付。
// 对应类型见 references/pipeline-types.md §2
// 注意：本示例已应用 deploy.yaml 路径统一修正（config_repo/...）
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

  environment {
    TAG_NAME = "build_${env.BUILD_NUMBER}"
  }

  stages {
    stage('拉取代码') {
      steps {
        git(url: 'http://10.18.134.21:32080/Dragon/masa-system.git', credentialsId: 'gitlab-afc', branch: '$BRANCH_NAME', changelog: true, poll: false)
      }
    }

    stage('编译构建') {
      steps {
        sh 'cd masa-gateway && mvn clean package -Dmaven.test.skip=true'
      }
    }

    stage('拉取配置') {
      steps {
        checkout([$class: 'GitSCM',
          branches: [[name: '$BRANCH_NAME']],
          userRemoteConfigs: [[credentialsId: 'gitlab-afc', url: 'http://10.18.134.21:32080/devops/tking-config.git']],
          extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'config_repo']]
        ])
        // 只拷 Dockerfile 到当前目录（podman build context 在 .）；deploy.yaml 留在 config_repo 由部署阶段直接读
        sh '''
          rm -f Dockerfile
          cp -arf config_repo/${SERVICE_CONFIG_PATH}/Dockerfile Dockerfile
        '''
      }
    }

    stage('制作并推送镜像') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'harbor-local', passwordVariable: 'HARBOR_PASSWD', usernameVariable: 'HARBOR_USER')]) {
          sh '''
            echo "$HARBOR_PASSWD" | podman login $REGISTRY -u "$HARBOR_USER" --tls-verify=false --password-stdin
            podman build --tls-verify=false -f Dockerfile -t $REGISTRY/$HARBOR_NAMESPACE/$IMAGR_NAME:$TAG_NAME .
            podman push --tls-verify=false $REGISTRY/$HARBOR_NAMESPACE/$IMAGR_NAME:$TAG_NAME
          '''
        }
      }
    }

    stage('部署到 k8s 集群') {
      steps {
        withCredentials([kubeconfigContent(credentialsId: 'k8s', variable: 'KUBECONFIG_CONFIG')]) {
          sh '''
            mkdir -p ~/.kube/
            echo "$KUBECONFIG_CONFIG" > ~/.kube/config
            envsubst < config_repo/${SERVICE_CONFIG_PATH}/deploy.yaml | kubectl apply -f -
          '''
        }
      }
    }
  }

  parameters {
    string(name: 'BRANCH_NAME', defaultValue: 'dev-xc', description: '')
    string(name: 'REGISTRY', defaultValue: 'dockerhub.kubekey.local', description: '')
    string(name: 'HARBOR_NAMESPACE', defaultValue: 'tking-uat', description: '')
    string(name: 'IMAGR_NAME', defaultValue: 'masa-gateway', description: '')
    string(name: 'DEPLOY_NAMESPACE', defaultValue: 'tking-uat', description: '')
    string(name: 'DEPLOY_NAME', defaultValue: 'masa-gateway', description: '')
    string(name: 'DEPLOY_CONTAINER_NAME', defaultValue: 'masa-gateway', description: '')
    string(name: 'SERVICE_CONFIG_PATH', defaultValue: 'masa-gateway', description: '')
  }
}
