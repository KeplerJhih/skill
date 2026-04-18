# Jenkinsfile + AWS CodeBuild 範本

本專案 CI/CD 架構：**Jenkins（調度） + AWS CodeBuild（建置） + Discord Webhook（通知）**。

Tag-based 部署：打 `*-test`、`*-prod`、`*-hotfix` tag 觸發對應環境的 CodeBuild。

---

## 架構概覽

```
Git Push / Tag
     │
     ▼
  Jenkins (Multibranch Pipeline)
     │
     ├── *-feat 分支 commit → 自動移動 dev tag
     ├── dev tag 推送       → Ansible 部署到地端
     ├── beta 分支 merge    → 自動打 *-test tag + immutable tag
     ├── uat 分支 merge     → 自動打 *-uat tag + immutable tag
     └── *-test/prod/hotfix tag → 觸發 AWS CodeBuild
                                      │
                                      ▼
                                  CodeBuild (buildspec.yml)
                                      │
                                      ├── Docker build (make build-xxx)
                                      ├── Docker tag (latest, TAG_NAME, IMAGE_TAG)
                                      └── Docker push → GCP Artifact Registry
```

---

## Jenkinsfile 範本

新增專案時，只需修改 **頂部配置區** 的 5 個變數，其餘結構不動。

```groovy
// ============================================================
// 🔧 配置區 — 新增專案時只改這裡
// ============================================================
def prjName = "{project-name}"            // 專案名稱（Ansible 用）
def targetName = "{project-testserver}"    // 測試服主機名
def devtargetName = "xg-localK8sServer"   // 地端主機名

// Discord 通知頻道（Jenkins 憑證變數）
@groovy.transform.Field
def discordWebhookUrls = [
    '${Team1Frontend}',       // 取消註解以啟用
    // '${Team1Backend}',
    '${Team2Frontend}',
    // '${Team2Backend}'
]

// CodeBuild 服務對照表
// key = 顯示名稱（Discord 通知用）
// value = AWS CodeBuild 專案名稱
@groovy.transform.Field
def CODEBUILD_SERVICES = [
    // --- 單服務範例（前端）---
    'main': 'gaming-{product}-frontend-{name}'

    // --- 多服務範例（後端）---
    // 'adminservice':      'gaming-rgs-backend-go-adminservice',
    // 'gameservice':       'gaming-rgs-backend-go-gameservice',
    // 'backendgateway':    'gaming-rgs-backend-go-backendgateway',
]

// 各環境共用同一組服務（如需覆寫可單獨設定）
@groovy.transform.Field
def CODEBUILD_CONFIGS = [
    test:   CODEBUILD_SERVICES,
    prod:   CODEBUILD_SERVICES,
    hotfix: CODEBUILD_SERVICES
]

// 子群組額外通知（可帶 thread_id）
@groovy.transform.Field
def discordGroupWebhookUrls = [
    // '${Team2Frontend}?thread_id=1232522440295321641',
]

// ============================================================
// 以下為共用邏輯，不需修改
// ============================================================

@groovy.transform.Field
def discordMessageIds = [:]

def currentDirectory
@groovy.transform.Field
def gitAuthorName = 'N/A'
@groovy.transform.Field
def gitCommitMessage = 'N/A'
@groovy.transform.Field
def lastDiscordDescription = ''

pipeline {
    agent any

    environment {
        AWS_REGION         = 'ap-northeast-3'
        AWS_CREDENTIALS_ID = '545426309786(aws-codebuild)'
        AWS_ACCOUNT_ID     = '545426309786'
        AI_ANALYZER_TOKEN  = credentials('ai-analyzer-token')
        AI_ANALYZER_URL    = 'https://ai-analyzer.nb-dev.pro/analyze'
    }

    stages {
        // Immutable Tag 偵測：跳過 pipeline
        stage('Check immutable tag') {
            when {
                expression {
                    return env.TAG_NAME && env.TAG_NAME.matches('.*-(test|prod|uat|hotfix)-[a-f0-9]{7,}')
                }
            }
            steps {
                script {
                    currentBuild.result = 'NOT_BUILT'
                    echo "Immutable tag ${env.TAG_NAME} 偵測到，跳過 pipeline"
                    error("skip")
                }
            }
        }

        // 取得 Git 資訊
        stage('getInfo') {
            steps {
                script {
                    currentDirectory = sh(script: 'pwd', returnStdout: true).trim()
                    dir("${currentDirectory}") {
                        gitAuthorName = sh(script: "git show -s --format='%an' ${env.GIT_COMMIT}", returnStdout: true).trim()
                        gitCommitMessage = sh(script: "git show -s --format='%s' ${env.GIT_COMMIT}", returnStdout: true).trim()
                    }
                    if (fileExists('version.json')) {
                        def versionFile = readFile('version.json')
                        def versionJson = new groovy.json.JsonSlurper().parseText(versionFile)
                        version = versionJson.version.toString()
                        versionJson = null
                    } else {
                        version = null
                    }
                }
            }
        }

        // Discord 初始通知
        stage('notify') {
            steps {
                script {
                    def triggerInfo = getTriggerInfo()
                    def description = """
                    **📦 ${env.JOB_NAME}**
                    ${triggerInfo}
                    👤 **推送人**: ${gitAuthorName}
                    💬 ${gitCommitMessage}
                    🕐 ${BUILD_TIMESTAMP}

                    ⏳ **處理中...**
                    """.stripIndent()

                    for(url in discordWebhookUrls) {
                        def payload = [embeds: [[title: "${env.JOB_NAME}", description: description, color: 16776960]]]
                        discordMessageIds[url] = sendDiscordMessage(url, payload)
                    }
                }
            }
        }

        // *-feat 分支自動移動 dev tag
        stage('Auto Tag dev') {
            when { branch pattern: '.*-feat', comparator: 'REGEXP' }
            steps {
                script {
                    updateDiscordStatus("⏳ 正在將 dev tag 移至最新...")
                    withCredentials([usernamePassword(credentialsId: 'xg-gitlab-Selfhosting', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                        sh """
                            git config --global credential.helper store
                            echo "https://\${GIT_USERNAME}:\${GIT_PASSWORD}@gitlab.xgstudio.co" > ~/.git-credentials
                            git tag -d dev || true
                            git push origin :refs/tags/dev || true
                        """
                        sh """
                            git tag dev
                            git push origin refs/tags/dev
                        """
                    }
                    updateDiscordStatus("✅ dev tag 已更新至 ${env.GIT_COMMIT.take(7)}")
                }
            }
        }

        // dev tag → Ansible 部署地端
        stage('Deploy dev tag') {
            when { tag 'dev' }
            steps {
                script {
                    updateDiscordStatus("⏳ 正在部署到地端...")
                    ansiblePlaybook(
                        playbook: '/data/exec/jenkins/prj/xg_gaming/{product}/local/{name}.yml',
                        inventory: '/data/exec/jenkins/inventory.ini',
                        extraVars: [project_name: prjName, target_hosts: devtargetName]
                    )
                    updateDiscordStatus("✅ 地端部署完成")
                }
            }
        }

        // beta 合併 → 自動打 *-test tag
        stage('Auto Tag for *-test') {
            when { branch 'beta' }
            steps {
                script {
                    def mergedBranch = sh(
                        script: """git log -1 --merges --format='%s' ${env.GIT_COMMIT} | grep -oP '(?<=Merge branch .)[^\\x27\"]*-feat' || true""",
                        returnStdout: true
                    ).trim()
                    if (!mergedBranch) {
                        mergedBranch = sh(script: """git log --merges -1 --format='%s' | grep -oP '(?<=Merge branch .)[^\\x27\"]*-feat' || true""", returnStdout: true).trim()
                    }
                    if (mergedBranch) {
                        def featVersion = mergedBranch.replaceAll('-feat$', '')
                        updateDiscordStatus("⏳ 正在創建 Tag: ${featVersion}-test ...")
                        createAndPushTag(featVersion, 'test')
                        def immutableTag = createImmutableTag(featVersion, 'test')
                        updateDiscordStatus("✅ 已創建 Tag: ${featVersion}-test\n🏷️ Image Tag: ${immutableTag}")
                    } else {
                        updateDiscordStatus("ℹ️ 未偵測到 feat 分支合併，跳過自動 tag")
                    }
                }
            }
        }

        // uat 合併 → 自動打 *-uat tag（選用，結構同 *-test）
        // stage('Auto Tag for *-uat') { ... }

        // Tag 觸發 CodeBuild
        stage('AWS CodeBuild for tag') {
            when {
                expression {
                    if (!env.TAG_NAME) return false
                    return CODEBUILD_CONFIGS.keySet().any { type -> env.TAG_NAME.endsWith("-${type}") }
                }
            }
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDENTIALS_ID}",
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    script {
                        def tagName = env.BRANCH_NAME
                        def tagType = getTagType(tagName)
                        def configs = CODEBUILD_CONFIGS[tagType]
                        if (!configs || configs.isEmpty()) { error "未找到 ${tagType} 類型的 CodeBuild 配置" }

                        def results = executeCodeBuildsInParallel(configs, tagName, discordWebhookUrls)
                        updateDiscordWithFinalResults(discordWebhookUrls, results, tagName)

                        def hasFailures = results.any { buildType, result -> !result || !result.success }
                        if (hasFailures) {
                            def failedBuilds = results.findAll { buildType, result -> !result || !result.success }.keySet().join(', ')
                            error "CodeBuild 構建失敗: ${failedBuilds}"
                        }
                    }
                }
            }
        }
    }

    post {
        success { script { updateDiscordFinal(3447003, "🟢 構建成功") } }
        failure { script { updateDiscordFinal(15158332, "🔴 構建失敗"); sendAiAnalyzer(["alerts1", "alerts2"]) } }
        aborted {
            script {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDENTIALS_ID}",
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    def projectNames = CODEBUILD_CONFIGS.collectMany { type, configs -> configs.values() }.unique()
                    for (projectName in projectNames) { stopCodeBuildProject(projectName) }
                }
                updateDiscordFinal(16744256, "🛑 構建已中止")
            }
        }
    }
}

// ============================================================
// 共用函數（所有 Jenkinsfile 一致）
// ============================================================

def getTriggerInfo() {
    return env.TAG_NAME ? "🏷️ **Tag**: ${env.TAG_NAME}" : "🔀 **Branch**: ${env.BRANCH_NAME}"
}

def sendDiscordMessage(webhookUrl, payload) {
    def jsonPayload = groovy.json.JsonOutput.toJson(payload)
    def msgId = sh(script: "curl -s -X POST -H 'Content-Type: application/json' -d '${jsonPayload}' ${webhookUrl}?wait=true | jq -r '.id // empty'", returnStdout: true).trim()
    if (msgId) { return msgId }
    echo "警告: 無法取得 Discord message_id"
    return null
}

def updateDiscordMessage(webhookUrl, messageId, payload) {
    if (!messageId) { sendDiscordMessage(webhookUrl, payload); return }
    def jsonPayload = groovy.json.JsonOutput.toJson(payload)
    sh(script: "curl -s -X PATCH -H 'Content-Type: application/json' -d '${jsonPayload}' ${webhookUrl}/messages/${messageId} || true", returnStdout: false)
}

def updateDiscordStatus(statusText) {
    def triggerInfo = getTriggerInfo()
    def description = """
    **📦 ${env.JOB_NAME}**
    ${triggerInfo}
    👤 **推送人**: ${gitAuthorName}
    💬 ${gitCommitMessage}
    🕐 ${BUILD_TIMESTAMP}

    ${statusText}
    """.stripIndent()
    lastDiscordDescription = description

    for(url in discordWebhookUrls) {
        def msgId = discordMessageIds[url]
        def payload = [embeds: [[title: "${env.JOB_NAME}", description: description, color: 16776960]]]
        updateDiscordMessage(url, msgId, payload)
    }
}

def updateDiscordCodeBuildProgress(webhookUrls, buildTracker, tagName, attempt, maxAttempts) {
    def statusEmoji = ['IN_PROGRESS': '⏳', 'SUCCEEDED': '✅', 'FAILED': '🔴', 'STOPPED': '🛑', 'TIMED_OUT': '⏰', 'START_FAILED': '❌']
    def lines = []
    buildTracker.each { buildType, info -> lines.add("${statusEmoji[info.status] ?: '❓'} **${buildType}** — ${info.status}") }
    def finishedCount = buildTracker.count { bt, info -> info.status != 'IN_PROGRESS' }
    def totalCount = buildTracker.size()

    def triggerInfo = getTriggerInfo()
    def description = """
    **📦 ${env.JOB_NAME}**
    ${triggerInfo}
    👤 **推送人**: ${gitAuthorName}
    💬 ${gitCommitMessage}
    🕐 ${BUILD_TIMESTAMP}

    **🚀 CodeBuild 進度 (${finishedCount}/${totalCount})** — 檢查 ${attempt}/${maxAttempts}

    ${lines.join('\n')}
    """.stripIndent()
    lastDiscordDescription = description

    for(url in webhookUrls) {
        def msgId = discordMessageIds[url]
        updateDiscordMessage(url, msgId, [embeds: [[title: "${env.JOB_NAME}", description: description, color: 16776960]]])
    }
}

def updateDiscordWithFinalResults(webhookUrls, results, tagName) {
    def detailLines = []
    def failureCount = 0
    def shortHash = env.GIT_COMMIT?.take(7) ?: 'unknown'
    def imageTag = "${tagName}-${shortHash}"

    results.each { buildType, result ->
        if (result && result.success) {
            detailLines.add("✅ **${buildType}** — 成功")
        } else {
            failureCount++
            def statusText = result?.status ?: 'UNKNOWN'
            def line = "🔴 **${buildType}** — ${statusText}"
            if (result?.buildId) {
                line += "\n　　[CodeBuild 控制台](${buildAwsConsoleUrl(result.buildId, result.projectName)})"
            }
            if (result?.logs && result.logs != 'None' && result.logs.trim()) {
                line += "\n　　[CloudWatch 日志](${result.logs})"
            }
            detailLines.add(line)
        }
    }

    def overallSuccess = (failureCount == 0)
    def color = overallSuccess ? 3447003 : 15158332
    def resultEmoji = overallSuccess ? "🎉" : "⚠️"
    def resultText = overallSuccess ? "所有構建完成" : "${failureCount} 個構建失敗"

    def triggerInfo = getTriggerInfo()
    def description = """
    **📦 ${env.JOB_NAME}**
    ${triggerInfo}
    👤 **推送人**: ${gitAuthorName}
    💬 ${gitCommitMessage}
    🕐 ${BUILD_TIMESTAMP}

    **📊 CodeBuild 結果 (${results.size() - failureCount}/${results.size()} 成功)**

    ${detailLines.join('\n')}

    ${resultEmoji} **${resultText}**

    🏷️ **Pushed Tags**
    　• `${tagName}`
    　• `${imageTag}`
    """.stripIndent()
    lastDiscordDescription = description

    for(url in webhookUrls) {
        def msgId = discordMessageIds[url]
        updateDiscordMessage(url, msgId, [embeds: [[title: "${env.JOB_NAME}", description: description, color: color]]])
    }
}

def updateDiscordFinal(color, statusText) {
    def description
    if (lastDiscordDescription) {
        description = lastDiscordDescription.trim() + "\n\n${statusText}"
    } else {
        def triggerInfo = getTriggerInfo()
        description = """
        **📦 ${env.JOB_NAME}**
        ${triggerInfo}
        👤 **推送人**: ${gitAuthorName ?: 'N/A'}
        💬 ${gitCommitMessage ?: 'N/A'}
        🕐 ${BUILD_TIMESTAMP}

        ${statusText}
        """.stripIndent()
    }
    for(url in discordWebhookUrls) {
        def msgId = discordMessageIds[url]
        def payload = [embeds: [[title: "${env.JOB_NAME}", description: description, color: color]]]
        msgId ? updateDiscordMessage(url, msgId, payload) : sendDiscordMessage(url, payload)
    }
    for(url in discordGroupWebhookUrls) {
        sendDiscordMessage(url, [embeds: [[title: "${env.JOB_NAME}", description: description, color: color]]])
    }
}

def createImmutableTag(version, env) {
    def shortHash = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
    def immutableTag = "${version}-${env}-${shortHash}"
    withCredentials([usernamePassword(credentialsId: 'xg-gitlab-Selfhosting', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
        sh """
            git config --global credential.helper store
            echo "https://\${GIT_USERNAME}:\${GIT_PASSWORD}@gitlab.xgstudio.co" > ~/.git-credentials
            git tag ${immutableTag}
            git push origin refs/tags/${immutableTag}
        """
    }
    return immutableTag
}

def createAndPushTag(version, tagType) {
    def tagName = "${version}-${tagType}"
    withCredentials([usernamePassword(credentialsId: 'xg-gitlab-Selfhosting', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
        def tagExists = sh(script: "git tag -l '${tagName}'", returnStdout: true).trim()
        if (tagExists) {
            sh "git tag -d ${tagName} || true"
            sh """
                git config --global credential.helper store
                echo "https://\${GIT_USERNAME}:\${GIT_PASSWORD}@gitlab.xgstudio.co" > ~/.git-credentials
                git push origin :refs/tags/${tagName} || true
            """
        }
        sh "git tag ${tagName}"
        sh """
            git config --global credential.helper store
            echo "https://\${GIT_USERNAME}:\${GIT_PASSWORD}@gitlab.xgstudio.co" > ~/.git-credentials
            git push origin refs/tags/${tagName}
        """
    }
}

def getTagType(tagName) {
    for (type in CODEBUILD_CONFIGS.keySet()) {
        if (tagName.endsWith("-${type}")) return type
    }
    error "無法識別的 Tag 類型: ${tagName}"
}

def buildAwsConsoleUrl(buildId, projectName) {
    def encodedBuildId = java.net.URLEncoder.encode(buildId, "UTF-8")
    return "https://${AWS_REGION}.console.aws.amazon.com/codesuite/codebuild/${AWS_ACCOUNT_ID}/projects/${projectName}/build/${encodedBuildId}/?region=${AWS_REGION}"
}

def startCodeBuild(projectName, tagName, buildType) {
    try {
        def buildOutput = sh(script: """
            aws codebuild start-build \
            --project-name ${projectName} --region ${AWS_REGION} --source-version ${tagName} \
            --environment-variables-override \
                name=BRANCH_NAME,value=${tagName},type=PLAINTEXT \
                name=TAG_NAME,value=${tagName},type=PLAINTEXT \
                name=IMAGE_TAG,value=${tagName},type=PLAINTEXT \
            --output json
        """, returnStdout: true).trim()
        def buildId = sh(script: "echo '${buildOutput}' | jq -r '.build.id'", returnStdout: true).trim()
        return buildId?.trim() ? buildId : null
    } catch (Exception e) {
        echo "${buildType} CodeBuild 啟動失敗: ${e.message}"
        return null
    }
}

def queryBuildStatus(buildId) {
    return sh(script: "aws codebuild batch-get-builds --ids ${buildId} --region ${AWS_REGION} --query 'builds[0].buildStatus' --output text", returnStdout: true).trim()
}

def queryBuildLogs(buildId) {
    return sh(script: "aws codebuild batch-get-builds --ids ${buildId} --region ${AWS_REGION} --query 'builds[0].logs.cloudWatchLogs.deepLink' --output text", returnStdout: true).trim()
}

def executeCodeBuildsInParallel(configs, tagName, webhookUrls) {
    def buildTracker = [:]
    configs.each { buildType, projectName ->
        def buildId = startCodeBuild(projectName, tagName, buildType)
        buildTracker[buildType] = [buildId: buildId, projectName: projectName, status: buildId ? 'IN_PROGRESS' : 'START_FAILED', logs: null, success: false]
    }
    updateDiscordCodeBuildProgress(webhookUrls, buildTracker, tagName, 0, 30)

    def maxAttempts = 30
    def attempt = 0
    def terminalStatuses = ['SUCCEEDED', 'FAILED', 'STOPPED', 'FAULT', 'TIMED_OUT', 'START_FAILED']
    while (attempt < maxAttempts) {
        if (buildTracker.every { bt, info -> terminalStatuses.contains(info.status) }) break
        sleep 60
        attempt++
        buildTracker.each { buildType, info ->
            if (!terminalStatuses.contains(info.status) && info.buildId) { info.status = queryBuildStatus(info.buildId) }
        }
        updateDiscordCodeBuildProgress(webhookUrls, buildTracker, tagName, attempt, maxAttempts)
    }

    def results = [:]
    buildTracker.each { buildType, info ->
        if (info.buildId) { info.logs = queryBuildLogs(info.buildId) }
        info.success = (info.status == 'SUCCEEDED')
        results[buildType] = info
    }
    return results
}

def stopCodeBuildProject(projectName) {
    try {
        def buildsInProgress = sh(script: "aws codebuild list-builds-for-project --project-name ${projectName} --region ${AWS_REGION} --query 'ids' --output text", returnStdout: true).trim()
        if (buildsInProgress && buildsInProgress != 'None') {
            for (buildId in buildsInProgress.split(/\s+/)) {
                def status = queryBuildStatus(buildId)
                if (status == 'IN_PROGRESS') {
                    sh "aws codebuild stop-build --id ${buildId} --region ${AWS_REGION}"
                }
            }
        }
    } catch (Exception e) {
        echo "停止 ${projectName} 構建時出錯: ${e.message}"
    }
}

def sendAiAnalyzer(channelList = null) {
    try {
        def logLines = currentBuild.rawBuild.getLog(500)
        def body = [job_name: env.JOB_NAME, build_number: env.BUILD_NUMBER as Integer, build_url: env.BUILD_URL, log: logLines.join('\n')]
        if (channelList) { body.discord_channels = channelList }
        httpRequest(url: "${AI_ANALYZER_URL}", httpMode: 'POST', contentType: 'APPLICATION_JSON',
            customHeaders: [[name: 'Authorization', value: "Bearer ${AI_ANALYZER_TOKEN}"]],
            requestBody: groovy.json.JsonOutput.toJson(body))
    } catch (Exception e) {
        echo "AI Log Analyzer 呼叫失敗: ${e.message}"
    }
}
```

---

## Buildspec.yml 範本

路徑：`{service-dir}/.devops/codebuild/buildspec.yml`

### 後端服務（Go）

```yaml
version: 0.2

env:
  secrets-manager:
    GCP_SA_KEY: gcp_gaming_artifact:GCP_SA_KEY

  variables:
    GCP_REGION: "asia-southeast1"
    GCP_PROJECT_ID: "january01-487003"
    GCP_REPO_NAME: "gaming/{product}-backend-go-{service}"  # ← 改這裡
    SERVICE_NAME: "{service}"                                 # ← 對應 Makefile target
    XG_ENV: "master"
    TAG_NAME: ""
    IMAGE_TAG: ""

phases:
  pre_build:
    commands:
      - echo "$GCP_SA_KEY" | docker login -u _json_key --password-stdin https://${GCP_REGION}-docker.pkg.dev
      - |
        if [ -z "$TAG_NAME" ]; then
          if [ -f "version.json" ]; then
            export TAG_NAME=$(cat version.json | jq -r '.version')
          else
            export TAG_NAME=$(git rev-parse --short=5 HEAD)
          fi
        fi
      - |
        COMMIT_HASH=$(git rev-parse --short HEAD)
        export IMAGE_TAG="${TAG_NAME}-${COMMIT_HASH}"
        echo "IMAGE_TAG: $IMAGE_TAG"
      - echo "=== 運行參數 ==="
      - 'echo "GCP_REPO_NAME: $GCP_REPO_NAME"'
      - 'echo "TAG_NAME: $TAG_NAME"'
      - 'echo "IMAGE_TAG: $IMAGE_TAG"'

  build:
    commands:
      - make build-${SERVICE_NAME} REPO=${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME
      - docker tag ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:latest ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:$TAG_NAME
      - docker tag ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:latest ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:$IMAGE_TAG
      - docker push ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:latest
      - docker push ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:$TAG_NAME
      - docker push ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:$IMAGE_TAG

  post_build:
    commands:
      - echo "所有任務完成"
```

### 前端服務（帶 Secrets）

前端 buildspec 額外需要 VITE 環境變數（從 AWS Secrets Manager 注入）：

```yaml
version: 0.2

env:
  secrets-manager:
    GCP_SA_KEY: gcp_gaming_artifact:GCP_SA_KEY
    MASTER_SECRET: gcp_gaming_artifact:MASTER_SECRET
    KEY_SALT: gcp_gaming_artifact:KEY_SALT
    # 前端專屬 secrets（對應 AWS Secrets Manager 的 key）
    VITE_GAME_ID: gcp_gaming_{name}:VITE_GAME_ID
    VITE_SOCKET_URL: gcp_gaming_{name}:VITE_SOCKET_URL
    VITE_API_URL: gcp_gaming_{name}:VITE_API_URL
    # ... 其他 VITE_* 變數

  variables:
    GCP_REGION: "asia-southeast1"
    GCP_PROJECT_ID: "january01-487003"
    GCP_REPO_NAME: "gaming/{product}-frontend-{name}"  # ← 改這裡
    SERVICE_NAME: "prod"
    XG_ENV: "master"
    TAG_NAME: ""
    IMAGE_TAG: ""

phases:
  pre_build:
    commands:
      # 同後端...

  build:
    commands:
      - >-
        make build-${SERVICE_NAME}
        REPO=${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME
        MASTER_SECRET="$MASTER_SECRET"
        KEY_SALT="$KEY_SALT"
        VITE_GAME_ID="$VITE_GAME_ID"
        VITE_SOCKET_URL="$VITE_SOCKET_URL"
        VITE_API_URL="$VITE_API_URL"
      # tag + push 同後端...
```

---

## 新增專案 Checklist

1. **建立 Jenkinsfile**：複製範本，修改頂部 5 個配置變數
2. **建立 buildspec.yml**：放在 `{service-dir}/.devops/codebuild/buildspec.yml`
   - 後端多服務：每個服務一個 `buildspec-{service}.yml`
   - 前端單服務：一個 `buildspec.yml`
3. **AWS CodeBuild**：在 Console 建立 CodeBuild 專案，命名格式 `gaming-{product}-{layer}-{name}`
4. **Jenkins**：設定 Multibranch Pipeline 指向 Git repo
5. **AWS Secrets Manager**：前端專案需建立 `gcp_gaming_{name}` secret 存放 VITE 變數

---

## Tag 命名規則

| Tag 格式 | 觸發動作 | 範例 |
|----------|---------|------|
| `dev` | Ansible 部署到地端 | `dev` |
| `{version}-test` | CodeBuild → 測試環境 | `1.0.0-test` |
| `{version}-prod` | CodeBuild → 正式環境 | `1.0.0-prod` |
| `{version}-hotfix` | CodeBuild → 正式環境（熱修復） | `1.0.0-hotfix` |
| `{version}-{env}-{hash}` | Immutable tag（自動產生，跳過 pipeline） | `1.0.0-test-a1b2c3d` |

## Image Tag 規則

CodeBuild 推送 3 個 tag 到 GCP Artifact Registry：

| Tag | 用途 | 範例 |
|-----|------|------|
| `latest` | 永遠指向最新建置 | `latest` |
| `TAG_NAME` | 對應 Git tag | `1.0.0-test` |
| `IMAGE_TAG` | TAG_NAME + commit hash（唯一且不可變） | `1.0.0-test-a1b2c3d` |
