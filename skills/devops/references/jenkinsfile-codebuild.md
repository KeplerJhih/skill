# Jenkinsfile + AWS CodeBuild 範本

工具箱預設 CI/CD 架構：**Jenkins（調度） + AWS CodeBuild（建置） + Discord Webhook（通知）**。

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
                                      └── Docker push → Image Registry
                                              │
                                              ├── GCP Artifact Registry
                                              ├── Aliyun ACR
                                              └── AWS ECR / 其他
                                          詳見 references/registry/
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
def devtargetName = "{local-k8s-host}"     // 地端主機名

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
    'main': '{org}-{product}-frontend-{name}'

    // --- 多服務範例（後端）---
    // 'adminservice':      '{org}-{product}-backend-go-adminservice',
    // 'gameservice':       '{org}-{product}-backend-go-gameservice',
    // 'backendgateway':    '{org}-{product}-backend-go-backendgateway',
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
    // '${Team2Frontend}?thread_id={thread-id}',
]

// ============================================================
// 以下為共用邏輯，不需修改
// ============================================================

@groovy.transform.Field
def discordMessageIds = [:]

// 本次 run 啟動的 CodeBuild 追蹤表（buildType → [buildId, projectName, status...]）
// 提為 @Field 讓 post{aborted} 能精準停掉「本次 run」啟動的 build（不誤傷併行 pipeline）
@groovy.transform.Field
def codeBuildTracker = [:]

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
        // 以下值依專案 / 組織實際情況填入，**勿沿用範例值**
        AWS_REGION         = '<aws-region>'                  // 例：ap-northeast-3
        AWS_CREDENTIALS_ID = '<jenkins-aws-credential-id>'   // Jenkins 內 AWS credentials 的 ID
        AWS_ACCOUNT_ID     = '<aws-account-id>'              // 12 位數 AWS account
        AI_ANALYZER_TOKEN  = credentials('<ai-analyzer-token-credential-id>')
        AI_ANALYZER_URL    = '<ai-analyzer-url>'             // 若無 AI Analyzer 服務，可整段刪除
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
                    withCredentials([usernamePassword(credentialsId: '<jenkins-gitlab-credential-id>', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                        sh """
                            git config --global credential.helper store
                            echo "https://\${GIT_USERNAME}:\${GIT_PASSWORD}@<gitlab-host>" > ~/.git-credentials
                            git tag -d dev || true
                            git push origin :refs/tags/dev || true
                        """
                        sh """
                            git tag dev
                            git push origin refs/tags/dev
                        """
                    }
                    updateDiscordStatus("✅ dev tag 已更新至 ${env.GIT_COMMIT.take(8)}")
                }
            }
        }

        // dev tag → Ansible 部署地端
        //
        // ⚠️ Ansible playbook 內若有 `kubectl rollout restart` 步驟，請注意：
        //   K8s rollout restart 的 annotation timestamp 精度只到秒，
        //   1 秒內重複觸發會 fail：
        //     error: failed to create patch ... if restart has already been triggered
        //     within the past second, please wait before attempting to trigger another
        //   並發兩個 build（如 *-feat push 同時推 dev tag）會同時抵達 rollout 階段。
        //   修法：playbook 內對 rollout restart 加 sleep 2 或 retry。
        stage('Deploy dev tag') {
            when { tag 'dev' }
            steps {
                script {
                    updateDiscordStatus("⏳ 正在部署到地端...")
                    ansiblePlaybook(
                        playbook: '<ansible-playbook-path>',   // 例：/data/exec/jenkins/prj/<org>/<product>/local/<name>.yml
                        inventory: '<ansible-inventory-path>', // 例：/data/exec/jenkins/inventory.ini
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

        // master 進版 → 自動打 *-prod tag（immutable-test-tag「已測證明」模式）
        //
        // 安全閘：只有「恰好是測過的 commit」（HEAD 或 HEAD^2 帶 *-test-<hash> immutable tag）
        // 才自動發版；未經 beta 測試流程的 commit 進 master 只 Discord 警示、不產 prod image。
        //
        // ⚠️ 生效需兩輪：master build 讀的是 master 上的 Jenkinsfile —— 本 stage 首次
        // 隨 beta→master 進版時，該輪跑的仍是舊檔，不會自動打 prod tag；下一輪才生效。
        stage('Auto Tag for *-prod') {
            when { branch 'master' }
            steps {
                script {
                    // master 進版兩種形態都支援：fast-forward（查 HEAD 本身）與 merge commit（查 HEAD^2 = 被合入的 beta head）
                    def version = null
                    def testedProof = null

                    withCredentials([usernamePassword(credentialsId: '<jenkins-gitlab-credential-id>', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                        sh """
                            git config --global credential.helper store
                            echo "https://\${GIT_USERNAME}:\${GIT_PASSWORD}@<gitlab-host>" > ~/.git-credentials
                        """

                        for (ref in ['HEAD', 'HEAD^2']) {
                            def short8 = sh(script: "git rev-parse --short=8 --verify --quiet ${ref} || true", returnStdout: true).trim()
                            if (!short8) continue

                            def tagLine = sh(script: "git ls-remote --tags origin 'refs/tags/*-test-${short8}' | head -1", returnStdout: true).trim()
                            if (tagLine) {
                                def testTag = tagLine.split('refs/tags/')[1].trim()
                                version = testTag.replaceAll("-test-${short8}\$", '')
                                testedProof = "${testTag} (${ref})"
                                break
                            }
                        }
                    }

                    if (version) {
                        echo "偵測到已測試版本進 master: ${testedProof}，版本號: ${version}"
                        updateDiscordStatus("⏳ 正在創建 Tag: ${version}-prod ...")
                        createAndPushTag(version, 'prod')
                        def immutableTag = createImmutableTag(version, 'prod')
                        updateDiscordStatus("✅ 已創建 Tag: ${version}-prod\n🏷️ Image Tag: ${immutableTag}")
                    } else {
                        echo "master HEAD / HEAD^2 均無 immutable *-test tag（未經 beta 測試流程），跳過自動 prod tag"
                        updateDiscordStatus("⚠️ 本次進版找不到已測試證明（*-test-<hash> tag），跳過自動 prod tag；請先走 beta 流程或手動打 *-prod")
                    }
                }
            }
        }

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
        // aborted 精準停止：只停「本次 run」啟動的 buildId（codeBuildTracker @Field）。
        // ❌ 不要掃全 project 的 in-progress build —— 會誤傷併行 pipeline 正在跑的 build。
        // 不先查狀態：stop-build 對 QUEUED / IN_PROGRESS 都有效，對已 terminal 的會報錯 → || true 吞掉。
        aborted {
            script {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: "${AWS_CREDENTIALS_ID}",
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    def tracked = codeBuildTracker.findAll { bt, info -> info.buildId }
                    if (tracked.isEmpty()) {
                        echo "本次 run 無已啟動的 CodeBuild（可能在觸發前就中止），略過"
                    } else {
                        tracked.each { bt, info ->
                            echo "停止 ${info.projectName} 的 build：${info.buildId}"
                            sh "aws codebuild stop-build --id ${info.buildId} --region ${AWS_REGION} || true"
                        }
                    }
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
    // 取 8 碼，與 createImmutableTag / buildspec 的 git rev-parse --short=8 對齊
    // （長度不一致 → Discord 顯示的 tag 與 registry 實際 push 的 tag 不同 → 照貼進 Helm 會 ImagePullBackOff）
    def shortHash = env.GIT_COMMIT?.take(8) ?: 'unknown'
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

    // 一鍵複製內容（貼進 Helm values / 部署配置用，無空格）：
    // 單 project（前端 repo）給「project:tag」；多 project（backend 全服務共用同一 image tag）
    // 給「repo:tag」——repo 名與訊息標題同源（prjName + JOB_NAME 第一段 = multibranch folder 名）
    def copyText = (results.size() == 1)
        ? results.collect { bt, r -> "${r.projectName}:${imageTag}" }.join('\n')
        : "${prjName}-${env.JOB_NAME.tokenize('/')[0]}:${imageTag}"

    def triggerInfo = getTriggerInfo()
    // ⚠️ stripIndent 踩雷：它剝的是「全部行的最小縮排」。多行插值（如 ${detailLines.join('\n')}）
    // 第 2 行起是頂格插入 → 最小縮排 = 0 → 整段一格都不剝。一般文字 Discord 會忽略行首空格
    // 看不出異狀，但 ``` code block 內空格會原樣保留、Copy 按鈕連空格一起複製。
    // → 一鍵複製 code block 必須放在 stripIndent() 之後頂格串接，不可寫進縮排模板內。
    //   （單服務 repo 插值只有 1 行不會踩到；多服務 repo 一上多行就露餡）
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
    　• `latest`
    　• `${tagName}`
    　• `${imageTag}`
    """.stripIndent() + "\n📋 **一鍵複製**\n```\n${copyText}\n```"
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

// ----------------------------------------------------------------------
// Tag 創建 — 雙保險：無條件清 local 殘留 + 查 remote 是否已存在
//
// 踩雷紀錄：原本只查 `git tag -l` 查 local，但 Jenkins SCM 用 `--no-tags`
// fetch，理論上 local 永遠空 — 但實務上 workspace 可能繼承自舊 repo
// 或前次手動測試，local 仍有殘留 tag，導致 `git tag X` 直接 fail：
//   fatal: tag 'X' already exists
// 修法：每次創 tag 前都 `git tag -d X || true` 清 local；用 ls-remote 查 remote
// ----------------------------------------------------------------------

def createImmutableTag(version, env) {
    // 固定 8 碼 —— 與 buildspec 的 IMAGE_TAG hash、Discord 最終回報的 take(8) 三處對齊
    // （git 預設 short 長度隨 repo 物件數浮動，不固定會造成 tag 長度漂移）
    def shortHash = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
    def immutableTag = "${version}-${env}-${shortHash}"
    withCredentials([usernamePassword(credentialsId: '<jenkins-gitlab-credential-id>', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
        sh """
            git config --global credential.helper store
            echo "https://\${GIT_USERNAME}:\${GIT_PASSWORD}@<gitlab-host>" > ~/.git-credentials
        """

        // immutable tag 若 remote 已存在 = 同 commit 重跑，直接跳過
        def existsRemote = sh(
            script: "git ls-remote --tags origin refs/tags/${immutableTag}",
            returnStdout: true
        ).trim()
        if (existsRemote) {
            echo "不可變標籤 ${immutableTag} 已存在於遠端（同 commit 重跑），跳過創建"
            return immutableTag
        }

        // 清 local 殘留（workspace 可能繼承自舊 repo 或前次手動測試）
        sh "git tag -d ${immutableTag} || true"
        sh "git tag ${immutableTag}"
        sh "git push origin refs/tags/${immutableTag}"
    }
    return immutableTag
}

def createAndPushTag(version, tagType) {
    def tagName = "${version}-${tagType}"
    withCredentials([usernamePassword(credentialsId: '<jenkins-gitlab-credential-id>', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
        sh """
            git config --global credential.helper store
            echo "https://\${GIT_USERNAME}:\${GIT_PASSWORD}@<gitlab-host>" > ~/.git-credentials
        """

        // 1. 無條件先清 local 殘留
        sh "git tag -d ${tagName} || true"

        // 2. 查 remote（不查 local — Jenkins SCM --no-tags fetch 後 local 不可靠）
        def tagExistsRemote = sh(
            script: "git ls-remote --tags origin refs/tags/${tagName}",
            returnStdout: true
        ).trim()
        if (tagExistsRemote) {
            echo "標籤 ${tagName} 在遠端已存在，先刪除遠端舊標籤"
            sh "git push origin :refs/tags/${tagName} || true"
        }

        sh "git tag ${tagName}"
        sh "git push origin refs/tags/${tagName}"
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
    codeBuildTracker.clear()
    def buildTracker = codeBuildTracker   // 指向 @Field 共享表，post{aborted} 可讀
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

路徑：
- 單服務：`{service-dir}/.devops/codebuild/buildspec.yml`
- 多服務（多個微服務共用同一個 repo）：`{service-dir}/.devops/codebuild/buildspec-{service}.yml`

### 通用骨架

所有 registry 共用以下結構。**Registry 相關段落（標 `<<<REGISTRY>>>`）依目標 registry 載入對應 reference 取得具體內容**：

```yaml
version: 0.2

env:
  secrets-manager:
    # <<<REGISTRY>>> registry 認證憑證
    # 依目標 registry 載入對應 reference 取得正確的 secret key 結構：
    #   - GCP Artifact Registry → references/registry/gcp-artifact-registry.md
    #   - Aliyun ACR             → references/registry/aliyun-acr.md
    #   - AWS ECR                → 待補

  variables:
    # <<<REGISTRY>>> registry endpoint / namespace / repo 變數
    # 依目標 registry 載入對應 reference 取得 endpoint 命名規則

    # 共通變數
    SERVICE_NAME: "{service}"   # 對應 Makefile target build-{service}
    TAG_NAME: ""                # 空值，pre_build 階段動態生成
    IMAGE_TAG: ""               # 空值，由 TAG_NAME + commit hash 自動產生

phases:
  pre_build:
    commands:
      # <<<REGISTRY>>> docker login（依 registry 不同，登入指令不同）

      # 共通：取得版本號（TAG_NAME）
      # 優先用 version.json，沒有則用 git short hash
      - |
        if [ -z "$TAG_NAME" ]; then
          if [ -f "version.json" ]; then
            export TAG_NAME=$(cat version.json | jq -r '.version')
          else
            export TAG_NAME=$(git rev-parse --short=5 HEAD)
          fi
        fi

      # 共通：產生 IMAGE_TAG = TAG_NAME + commit short hash
      # 固定 8 碼 — 與 Jenkinsfile createImmutableTag / Discord 回報三處對齊（預設 short 長度會浮動）
      - |
        COMMIT_HASH=$(git rev-parse --short=8 HEAD)
        export IMAGE_TAG="${TAG_NAME}-${COMMIT_HASH}"
        echo "IMAGE_TAG: $IMAGE_TAG"

  build:
    commands:
      # 共通：透過 Makefile build（REPO 完整路徑由 registry 變數組合而成）
      - make build-${SERVICE_NAME} REPO=<<<REGISTRY-FULL-REPO-PATH>>>

      # <<<REGISTRY>>> docker tag + docker push（endpoint 依 registry 不同）
      # Tag 策略統一：latest / TAG_NAME / IMAGE_TAG 三個 tag 都推

  post_build:
    commands:
      - echo "所有任務完成"
```

### 三個 Tag 策略（所有 registry 共用）

CodeBuild 推送 3 個 tag：

| Tag | 用途 | 範例 |
|-----|------|------|
| `latest` | 永遠指向最新建置 | `latest` |
| `TAG_NAME` | 對應 Git tag | `1.0.0-test` |
| `IMAGE_TAG` | TAG_NAME + commit hash（唯一不可變） | `1.0.0-test-a1b2c3d4` |

### Registry 具體實作

依目標 registry 載入對應 reference 取得完整可用範本（含 secrets-manager 結構、login 指令、endpoint 格式、tag/push 片段）：

| Registry | Reference 檔案 | 適用情境 |
|----------|---------------|---------|
| GCP Artifact Registry | `references/registry/gcp-artifact-registry.md` | GKE 部署或跨雲 |
| Aliyun ACR | `references/registry/aliyun-acr.md` | Aliyun ACK 部署 |
| AWS ECR | （待補） | AWS EKS / ECS 部署 |

> **跨雲注意**：AWS CodeBuild push 到非 AWS 的 registry（如 → Aliyun ACR / GCP AR）一律走 public endpoint，VPC 內網 endpoint 僅在同雲環境可達。詳見 `references/registry/README.md`。

### 前端服務（帶 VITE Secrets）

前端 buildspec 在通用骨架的 `secrets-manager` 區段額外注入 `VITE_*` 變數，並於 `make build-${SERVICE_NAME}` 指令傳入：

```yaml
env:
  secrets-manager:
    # <<<REGISTRY>>> 認證憑證（依 registry 載入對應 reference）

    # 前端額外 secrets
    MASTER_SECRET: <secret-name>:MASTER_SECRET
    KEY_SALT: <secret-name>:KEY_SALT
    VITE_API_URL: <secret-name>:VITE_API_URL
    # ... 其他 VITE_* 變數

phases:
  build:
    commands:
      - >-
        make build-${SERVICE_NAME}
        REPO=<<<REGISTRY-FULL-REPO-PATH>>>
        MASTER_SECRET="$MASTER_SECRET"
        KEY_SALT="$KEY_SALT"
        VITE_API_URL="$VITE_API_URL"
      # docker tag + push 同後端骨架（依 registry reference 寫具體 endpoint）
```

---

## 新增專案 Checklist

1. **建立 Jenkinsfile**：複製範本，修改頂部配置區的變數
2. **選擇 Image Registry**：依部署目標雲決定（GCP AR / Aliyun ACR / AWS ECR），載入對應 `references/registry/<registry>.md`
3. **建立 buildspec.yml**：放在 `{service-dir}/.devops/codebuild/buildspec.yml`
   - 後端多服務：每個服務一個 `buildspec-{service}.yml`
   - 前端單服務：一個 `buildspec.yml`
4. **AWS CodeBuild**：在 Console 建立 CodeBuild 專案，命名格式依組織慣例（如 `{org}-{product}-{layer}-{name}`）
5. **Jenkins**：設定 Multibranch Pipeline 指向 Git repo
6. **AWS Secrets Manager**：
   - Registry 認證 secret：依 `references/registry/<registry>.md` 的格式建立
   - 前端專案：額外建立 secret 存放 `VITE_*` 等建置期環境變數

---

## Tag 命名規則

| Tag 格式 | 觸發動作 | 範例 |
|----------|---------|------|
| `dev` | Ansible 部署到地端 | `dev` |
| `{version}-test` | CodeBuild → 測試環境 | `1.0.0-test` |
| `{version}-prod` | CodeBuild → 正式環境 | `1.0.0-prod` |
| `{version}-hotfix` | CodeBuild → 正式環境（熱修復） | `1.0.0-hotfix` |
| `{version}-{env}-{hash}` | Immutable tag（自動產生，跳過 pipeline） | `1.0.0-test-a1b2c3d4` |

## Image Tag 規則

CodeBuild 推送 3 個 tag 到目標 Image Registry：

| Tag | 用途 | 範例 |
|-----|------|------|
| `latest` | 永遠指向最新建置 | `latest` |
| `TAG_NAME` | 對應 Git tag | `1.0.0-test` |
| `IMAGE_TAG` | TAG_NAME + commit hash（唯一且不可變） | `1.0.0-test-a1b2c3d4` |
