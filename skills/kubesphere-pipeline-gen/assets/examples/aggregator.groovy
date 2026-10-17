// ============================================================
// 示例：编排聚合型 pipeline（tking-api-install-all-xc）
// 用途：自己不构建，只按依赖顺序串行/并行触发一批子 pipeline（base-xxx-api-xc）。
// 对应类型见 references/pipeline-types.md §3
// 特点：顶层 agent none（纯调度器，不分配 executor，build() 在 Jenkins master flyweight 线程执行），
//       每个 stage 内也 agent none。这样不占用任何工作节点。
//
// 分批原则（与 tking-uat.repo 对齐）：
//   1) 最底层依赖单独串行，不可与其他服务 parallel
//   2) 同层互不依赖 → 同一 parallel 批
//   3) 下一批 wait + propagate，等上一批全部成功
// ============================================================

pipeline {
  agent none

  stages {
    // 第一批：最底层依赖，单独串行（其他服务都依赖它）
    stage('default-1') {
      agent none
      steps {
        build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-pkgconvert-service-api-xc')
      }
    }

    // 第二批：依赖第一批，且被后续批次依赖 → 单独串行
    stage('default-2') {
      agent none
      steps {
        build(quietPeriod: 0, wait: true, propagate: true, job: 'base-thing-interfaceplatform-service-api-xc')
      }
    }

    // 第三批：互不依赖，并行
    stage('default-3') {
      parallel {
        stage('thirdinterface') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-thirdinterface-service-api-xc') }
        }
        stage('br-decision') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-afc-br-decision-service-api-xc') }
        }
        stage('fico') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-afc-fico-service-api-xc') }
        }
        stage('pboc') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-afc-pboc-service-api-xc') }
        }
        stage('sinoiov') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-afc-sinoiov-service-api-xc') }
        }
        stage('baiwang') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-baiwang-service-api-xc') }
        }
        stage('batch') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-batch-service-api-xc') }
        }
        stage('business') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-business-service-api-xc') }
        }
      }
    }

    // 第四批：依赖第三批产物，并行
    stage('default-4') {
      parallel {
        stage('interfacegroup') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-interfacegroup-service-api-xc') }
        }
        stage('dispatch') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-dispatch-service-api-xc') }
        }
        stage('flow') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-flow-service-api-xc') }
        }
        stage('function') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-function-service-api-xc') }
        }
        stage('hangkong') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-hangkong-service-api-xc') }
        }
        stage('model') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-model-service-api-xc') }
        }
        stage('script') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-script-service-api-xc') }
        }
        stage('iautos') {
          agent none
          steps { build(quietPeriod: 0, wait: true, propagate: true, job: 'base-tking-iautos-service-api-xc') }
        }
      }
    }
  }
}
