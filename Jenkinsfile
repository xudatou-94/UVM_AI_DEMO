// =============================================================================
// Jenkinsfile - Jenkins 流水线配置
//
// 流水线阶段：
//   1. Checkout  - 拉取代码
//   2. Setup     - 环境检查
//   3. Compile   - 编译 DUT + Testbench
//   4. Smoke     - smoke 级别快速验证
//   5. Regress   - 全量回归（参数化触发）
//   6. Report    - 生成回归报告与覆盖率
//
// 参数化构建：
//   PROJ       项目名称
//   TAG        回归过滤标签（空=全量）
//   JOBS       并行作业数
//   CODE_COV   是否开启代码覆盖率
//   FUNC_COV   是否开启功能覆盖率
//   SUBMIT     提交方式（local/lsf/sge）
// =============================================================================

pipeline {
    agent any

    // -------------------------------------------------------------------------
    // 参数化构建
    // -------------------------------------------------------------------------
    parameters {
        string(name: 'PROJ',     defaultValue: 'example',
               description: '项目名称（verif/ 下的子目录名）')
        string(name: 'TAG',      defaultValue: '',
               description: '回归过滤标签（空=运行全部激励）')
        string(name: 'JOBS',     defaultValue: '4',
               description: '并行作业数')
        booleanParam(name: 'CODE_COV', defaultValue: false,
               description: '开启代码覆盖率')
        booleanParam(name: 'FUNC_COV', defaultValue: false,
               description: '开启功能覆盖率')
        choice(name: 'SUBMIT',   choices: ['local', 'lsf', 'sge'],
               description: '作业提交方式')
        booleanParam(name: 'FULL_REGRESS', defaultValue: false,
               description: '是否执行全量回归（默认仅 smoke）')
    }

    // -------------------------------------------------------------------------
    // 环境变量
    // -------------------------------------------------------------------------
    environment {
        REPO_ROOT    = "${WORKSPACE}"
        OUTPUT_ROOT  = "${WORKSPACE}/output"
        CODE_COV_ARG = "${params.CODE_COV ? 'CODE_COV=1' : 'CODE_COV=0'}"
        FUNC_COV_ARG = "${params.FUNC_COV ? 'FUNC_COV=1' : 'FUNC_COV=0'}"
        TAG_ARG      = "${params.TAG ? "TAG='${params.TAG}'" : ''}"
    }

    // -------------------------------------------------------------------------
    // 构建选项
    // -------------------------------------------------------------------------
    options {
        timeout(time: 8, unit: 'HOURS')     // 全局超时
        timestamps()                         // 日志加时间戳
        ansiColor('xterm')                   // 彩色日志
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {
        // =====================================================================
        // Stage 1: 代码检出
        // =====================================================================
        stage('Checkout') {
            steps {
                checkout scm
                echo "代码检出完成，WORKSPACE=${WORKSPACE}"
            }
        }

        // =====================================================================
        // Stage 2: 环境检查
        // =====================================================================
        stage('Setup') {
            steps {
                sh '''
                    set +e
                    source scripts/setup.sh || true
                    echo "=== 工具版本检查 ==="
                    which vcs   && vcs -ID 2>&1 | head -2 || echo "WARNING: vcs not found"
                    which verdi && verdi -ID 2>&1 | head -2 || echo "WARNING: verdi not found"
                    which urg   || echo "WARNING: urg not found"
                    python3 --version
                '''
            }
        }

        // =====================================================================
        // Stage 3: 编译
        // =====================================================================
        stage('Compile') {
            steps {
                sh """
                    source scripts/setup.sh || true
                    cd scripts
                    make compile PROJ=${params.PROJ} ${CODE_COV_ARG}
                """
            }
            post {
                failure {
                    echo '编译失败，请查看编译日志'
                    archiveArtifacts artifacts: "output/${params.PROJ}/compile/*.log",
                                     allowEmptyArchive: true
                }
            }
        }

        // =====================================================================
        // Stage 4: Smoke 测试
        // =====================================================================
        stage('Smoke') {
            steps {
                sh """
                    source scripts/setup.sh || true
                    cd scripts
                    make regress PROJ=${params.PROJ} TAG=smoke \
                        JOBS=${params.JOBS} SUBMIT=${params.SUBMIT} \
                        WAVE=0
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: "output/${params.PROJ}/reports/**",
                                     allowEmptyArchive: true
                }
            }
        }

        // =====================================================================
        // Stage 5: 全量回归（参数化控制是否执行）
        // =====================================================================
        stage('Full Regress') {
            when {
                expression { return params.FULL_REGRESS }
            }
            steps {
                sh """
                    source scripts/setup.sh || true
                    cd scripts
                    make regress PROJ=${params.PROJ} \
                        ${TAG_ARG} \
                        JOBS=${params.JOBS} SUBMIT=${params.SUBMIT} \
                        ${CODE_COV_ARG} ${FUNC_COV_ARG} WAVE=0
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: "output/${params.PROJ}/reports/**",
                                     allowEmptyArchive: true
                }
            }
        }

        // =====================================================================
        // Stage 6: 生成报告 & 覆盖率合并
        // =====================================================================
        stage('Report') {
            steps {
                sh """
                    source scripts/setup.sh || true
                    cd scripts
                    make report PROJ=${params.PROJ} || true
                """

                // 覆盖率合并（仅在开启覆盖率时执行）
                script {
                    if (params.CODE_COV || params.FUNC_COV) {
                        sh """
                            source scripts/setup.sh || true
                            cd scripts
                            make merge_cov PROJ=${params.PROJ} || true
                        """
                    }
                }
            }
            post {
                always {
                    // 归档报告
                    archiveArtifacts artifacts: "output/${params.PROJ}/reports/**," +
                                               "output/${params.PROJ}/cov_report/**",
                                     allowEmptyArchive: true
                    // 发布 HTML 报告（需安装 HTML Publisher 插件）
                    publishHTML([
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: "output/${params.PROJ}/reports",
                        reportFiles: '**/report.html',
                        reportName: 'UVM 回归报告'
                    ])
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // 构建后通知（可按需配置邮件/企业微信/Slack 通知）
    // -------------------------------------------------------------------------
    post {
        success {
            echo "流水线执行成功"
            // emailext(to: 'team@example.com', subject: "✅ ${JOB_NAME} #${BUILD_NUMBER} 通过",
            //          body: "回归通过，报告: ${BUILD_URL}")
        }
        failure {
            echo "流水线执行失败"
            // emailext(to: 'team@example.com', subject: "❌ ${JOB_NAME} #${BUILD_NUMBER} 失败",
            //          body: "回归失败，请查看: ${BUILD_URL}")
        }
        always {
            cleanWs(cleanWhenSuccess: false)  // 失败时保留工作空间便于调试
        }
    }
}
