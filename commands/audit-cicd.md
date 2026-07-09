---
description: 通用 CI/CD 對齊檢查 — 以代碼為錨，跨層驗證 service 命名與存在性一致
argument-hint: [專案路徑或範圍]
---

# Command: /audit-cicd

通用 CI/CD 對齊檢查 — discovery-first，不綁定任何專案技術棧 / 路徑 / 雲端。
以 **代碼入口（source entrypoint / BC 目錄 / binary 自宣告名）為單一真理來源（canonical）**，
build pivot（Makefile 等）只是「第一個下游消費者」，**不是真理本身**。
驗證方向永遠是 `code → build pivot → CI spec → CI orchestrator → cloud project → deploy`，
跨層偵測 service 在 container / CI / deployment / cloud / runtime 各層的存在性與命名一致性。

> ⚠️ **核心鐵律（血淚換來）**：發現任何層命名分歧時，**canonical 一律以代碼為準**，
> 把所有下游（含雲端 project / Helm）對齊到代碼名 —— **絕不**反向把代碼改去遷就某個下游的孤兒名。
> 「雲端現在叫什麼」「Makefile 現在寫什麼」都可能是上次重構沒收乾淨的殘留，不能拿來當錨。

---

## 觸發語法

```
/audit-cicd                          # 預設：純檔案層級 audit（無雲端依賴）
/audit-cicd --deep                   # 加上雲端 cli + K8s runtime 比對
/audit-cicd --fix                    # 輸出 patch 計畫（不執行；可搭配 /doit 落地）
/audit-cicd --service=<glob>         # 只查特定服務（e.g. --service=*worker）
```

## 角色定義

你是 CI/CD consistency auditor。任務是**讀取與報告**，**絕不**自動改檔或動雲端（除 `--fix` 模式且使用者明確確認）。

---

## Phase 0 — 安全網（MANDATORY）

1. 載入 `karpathy-guidelines` skill（防過度設計）
2. 確認當前 working directory；若不在 git 倉內、提示使用者確認 audit 目標
3. 純讀取模式：本命令 ≠ /doit，不修改任何檔案

---

## Phase 1 — Discovery（無寫死路徑）

> 衝突 / 多選 / 偵測不到 → **列給使用者選**，不自動猜測。

### 1.1 Build Pivot（下游第一站，**非**真理來源）

> build pivot 是「code 之後的第一個消費者」，audit 時要驗的是「它有沒有忠實反映代碼」，
> 而不是把它當基準。真正的 canonical 在 Phase 2 從代碼推導。

依下表偵測，**全部列出找到的**：

| 信號 | 解讀 |
|------|------|
| `Makefile` 含 `build-*` / `image-*` / `docker-*` target | Make-driven |
| `package.json` 的 `scripts` 含 `docker` / `build:*` | Node / pnpm workspaces |
| `justfile` / `Taskfile.yml` | Task runner |
| `BUILD` / `BUILD.bazel` / `WORKSPACE` | Bazel |
| `nx.json` / `turbo.json` | Nx / Turbo monorepo |
| `pyproject.toml` + 多個 Dockerfile | Python monorepo |
| `Cargo.toml` workspace | Rust workspace |

偵測指令：
```bash
ls -1 Makefile package.json justfile Taskfile.yml BUILD.bazel WORKSPACE nx.json turbo.json pyproject.toml Cargo.toml 2>/dev/null
```

### 1.2 Reflection Layers

| 層 | 偵測信號 |
|----|---------|
| **Container definitions** | `find . -name 'Dockerfile*' -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.git/*'` 加上 `find . -name 'dockerfile-*' -type f` 涵蓋非標準命名 |
| **CI orchestrator** | `Jenkinsfile` / `.github/workflows/*.yml` / `.gitlab-ci.yml` / `.circleci/config.yml` / `azure-pipelines.yml` / `bitbucket-pipelines.yml` |
| **Per-service CI spec** | `.devops/codebuild/buildspec-*.yml` / `cloudbuild*.yaml` / GitHub Actions matrix / GitLab `parallel:matrix` |
| **Deployment manifest** | `Chart.yaml` + `values*.yaml`（Helm）/ `kustomization.yaml`（Kustomize）/ 純 `k8s/*.yaml` / `compose.yaml` / `serverless.yml` / `app.yaml`（App Engine）|

### 1.3 Cloud Provider

| 信號 | 解讀 |
|------|------|
| `*-docker.pkg.dev` URL | GCP Artifact Registry |
| `*.dkr.ecr.*.amazonaws.com` / 含 `buildspec.yml` / `aws codebuild` | AWS |
| `ghcr.io` / `.github/workflows` 內含 docker build | GitHub Container Registry |
| `*.azurecr.io` | Azure |
| `registry.cn-*.aliyuncs.com` / 含 `acr` | 阿里雲 ACR |

### 1.4 偵測輸出格式

對使用者展示：
```
🔎 Discovery 結果

Build pivot:          Makefile（build-* targets × N）
Container defs:       ./.devops/dockerfile/  （camelCase 命名 × N）
CI orchestrator:      Jenkinsfile  (+ .github/workflows/*.yml 各 1)
Per-service CI spec:  .devops/codebuild/buildspec-*.yml × N
Deployment manifest:  ../../devops/k8s/.../values-*.yaml （Helm chart）
Cloud provider:       AWS CodeBuild + GCP Artifact Registry
K8s context:          <current kubeconfig context>

⚠️ 偵測到多個 CI orchestrator（Jenkinsfile + GHA），請問哪個是主要的？
```

衝突解決：
- 多個 build pivot → 用 AskUserQuestion 列出，請選擇
- 多個 CI orchestrator → 同上
- 任何層偵測不到 → 詢問或標 N/A，繼續

---

## Phase 2 — Canonical Service Identity（**以代碼為錨**）

> ❌ **不要**從 build pivot 抽 canonical（那是上次踩的坑：Makefile 名可能是孤兒）。
> ✅ canonical 一律從**代碼實體**推導，build pivot 之後才當「下游」逐一比對。

### 2.1 從代碼推 canonical（真理來源）

依語言 / 框架，找出每個 deployable 的**代碼實體**，這才是 service 真名的依據：

| 信號 | 抽法（例） |
|------|-----------|
| 入口目錄 | `ls cmd/*/ cmd/service/*/ cmd/worker/*/`、`apps/*/`、`services/*/` |
| Domain / BC 目錄 | `ls boundedContext/ domain/ internal/` —— 對照入口是否仍存在對應 BC |
| binary 自宣告名 | grep 入口檔的 `ServiceName` / `app.name` / log prefix（如 `log.Printf("[site]...")`、`ServiceName: "siteService"`） |
| 註冊的 RPC / handler | grep `Register*Server` / route prefix，確認這個 binary 實際是哪個服務 |

**輸出**：每個 service 一行「代碼實體 → 推導出的 canonical 名」，並標準化大小寫（記錄正規化規則）。

### 2.2 偵測「不完整重構」殘留（git 歷史，必跑）

當代碼名與某個下游層名**不一致**時，**先別急著判斷誰對**，跑 git 歷史定位：

```bash
# 看分歧檔何時被改 / 改成什麼，找出「重構只改了一半」的證據
git log --oneline --all -- <分歧的檔案路徑>
git log -p --all -S '<舊名>' -- <相關目錄>     # 舊名在哪次 commit 被引入 / 移除
```

典型訊號：某次 commit message 寫「rename / 合併 / 移除 X」，但只動了部分 repo / 層
→ 沒被改到的層（常見：雲端 project、Helm values、跨 repo 的部署設定）就是**孤兒**。
**孤兒一律對齊回代碼 canonical，不是反過來。**

### 2.3 確認 pattern

接著問使用者：
> 從代碼推得 N 個 service: [...]，canonical 命名 pattern = `<...>`。
> build pivot / 雲端如有不一致，預設**以代碼為準對齊**，確認方向？

---

## Phase 3 — Layer Diff（檔案層，必跑）

> ⚠️ **本 phase 只驗「存在性 + 命名」**，不驗 wiring。
> 「A 引用 B、B 真的對得上 A 想要的事嗎」屬於 callgraph 驗證，**必須繼續做 Phase 3.5**，不能只交這張表收工。

對 Phase 2 的 inventory × Phase 1.2 的每個 layer，產出矩陣：

| Service | Container | CI Spec | CI Orch | Deploy |
|---------|:---:|:---:|:---:|:---:|
| <name1> | ✅ | ✅ | ✅ | ✅ |
| <name2> | ✅ | ❌ | ✅ | ⚠️ orphan |

標記規則：
- ✅ 存在且命名與 inventory 對齊
- ❌ 缺漏（pivot 有，此層沒有）
- ⚠️ orphan（此層有，pivot 沒有 → 可能廢棄遺孤）
- 🟠 命名不一致（存在但名稱與 inventory pattern 不符）

---

## Phase 3.5 — Chain Trace（callgraph 端到端追蹤，必跑）

> Phase 3 的綠燈代表「五層各自都有檔案」，但**不代表它們串得起來**。
> 本 phase 要對 Phase 2 inventory 的**每一個 service**、順著 callgraph 把「引用 → 被引用」的箭頭追到底，逐個 edge 驗 wiring。

### 3.5.1 推導 Edges（依 Phase 1 偵測結果動態組合）

抽象 callgraph（**錨在最左的「代碼」，由左往右驗下游是否忠實對齊**）：

```
[CANONICAL]                                                          下游 ───────────────►
Source entrypoint / BC ──► Build pivot target ──► Per-service CI spec ──► CI orchestrator ──► Cloud project
   (code = 真理)              (Makefile 等)          (buildspec 等)         (Jenkinsfile 等)    (CodeBuild 等)
        │                                                  │
        └──► Containerfile                                  └──► Registry push path ◄──── Deployment pull path (Helm)
```

> **範例驗證鏈**（Jenkins + CodeBuild + Make + Helm 棧，以代碼為出發）：
> `code (cmd/service/<x>, boundedContext/<x>, ServiceName) → Makefile build-<x> → buildspec-<x> / SERVICE_NAME → Jenkinsfile CODEBUILD_SERVICES → AWS CodeBuild project → Helm values apps key`
> 每一段都問「下游有沒有忠實反映代碼名」，**任一段不符 → 該段是待修的下游，不是改代碼的理由**。

依偵測到的技術棧，把抽象 edge 對應到具體欄位（例）：

| 抽象 edge | Jenkins+CodeBuild+Make+Helm 範例 | GHA+Docker build+Compose 範例 |
|---------|--------------------------------|------------------------------|
| Orch → CI spec | `Jenkinsfile` 內 `CODEBUILD_SERVICES[svc]` 對應 codebuild project，需有 `buildspec-<svc>.yml` | GHA `jobs.<id>.uses` 對應的 workflow / action 路徑存在 |
| CI spec → build target | buildspec 內 `make build-${SERVICE_NAME}` 對應 Makefile 有 `build-<X>` target | workflow `run: pnpm build:<X>` 對應 `package.json scripts["build:X"]` |
| Build target → containerfile | Makefile `-f ./.devops/dockerfile-<X>` 實檔存在 | `docker build -f Dockerfile.<X>` 實檔存在 |
| Build target → entrypoint | Makefile build 來源（如 `cmd/<svc>/main.go`）實檔存在 | `package.json` 對應 entry 存在 |
| CI spec → registry | buildspec `GCP_REPO_NAME` / `ECR_REPO` 字面值 | workflow `env.IMAGE_NAME` 字面值 |
| Deploy → registry | Helm template 算出來的 image path（含 `_helpers.tpl` 的 prefix/printf！） | compose `image:` 字面值 |
| **Registry equality** | 上兩列字面相等？ | 同上 |

> ⚠️ **Helm 陷阱**：image path 不能只看 `image:` 那行，必須讀 `_helpers.tpl` / template 內所有的 `printf` / prefix / suffix。第一輪曾因漏看 `printf "backend-go-%s" $name` 誤報 🔴。

### 3.5.2 Per-service Checkpoint Table

對每個 service 跑 N 個 checkpoint（依 edge 數動態），用 ✅ / ❌(原因)：

```
SERVICE        | Orch→Spec | Spec→Make | Spec=Orch? | Mk→Df | DfExists | Helm=Spec?
adminservice   | ✅         | ✅         | ✅          | ✅     | ✅        | ✅
foo-svc        | ✅         | ❌(no target build-foo-svc) | … | … | … | …
bar-worker     | ✅         | ✅         | ❌(SN="barworker"≠"bar-worker") | … | … | …
baz            | ✅         | ✅         | ✅          | ✅     | ❌(file missing) | …
```

### 3.5.3 不可省略的 sanity check

- **Registry 字面相等**：Push path 與 Pull path 必須**完整字串相等**（含 region / project / repo / 前綴）。常見坑：buildspec push 到 `<repo>/<prefix>-X`，Helm 算出 `<repo>/X`（漏掉 prefix）→ 100% ImagePullBackOff。
- **Variable resolution**：Makefile 用 `$(DOCKERFILE_PATH_X)` 等變數時，必須展開後再驗檔案存在，不能只看字面有 `-f`。
- **大小寫**：Pivot target、CI spec 變數、containerfile basename 可能各自大小寫不同（如 buildspec lowercase、dockerfile camelCase），用 string equality 驗時要先正規化或顯式記錄。
- **Tag / commit-hash 計算一致性（多來源，血淚換來）**：同一個 image tag 的 hash 段，往往在**多個獨立位置各算一次**——push 到 registry 的 CI（buildspec `git rev-parse --short`）、orchestrator 推的 audit git tag（Jenkins `createImmutableTag`）、**通知 / 顯示層**（Discord/Slack 用 `env.GIT_COMMIT.take(7)` 之類**完全不同的取法**）、deploy manifest 寫死的 tag。這些只要有一處長度 / 算法不同，就會 tag 不符 → ImagePullBackOff，或「顯示的 tag」與「實際 push 的 tag」不一致（更陰，會誤導人照貼進 deploy）。
  - **不能只 grep 一種 API**。要把**所有**會產出 hash/tag 字串的途徑都搜出來逐一核對：
    ```bash
    grep -rnE 'rev-parse|--short|\.take\(|substring|\[0\.\.|cut -c|head -c|GIT_COMMIT|COMMIT_HASH|IMAGE_TAG' <ci/orchestrator/buildspec/通知腳本>
    ```
  - 逐一確認**長度與來源一致**（如全部 `--short=8` / `.take(8)`），且 **clone 深度不影響**（`git rev-parse --short` 不釘長度時，full clone 與 `gitCloneDepth=1` 淺 clone 會縮出不同長度 → 必須釘死 `--short=N`）。
  - 驗證 deploy 寫死的 tag 時，要對到 **registry 上真實存在的 tag**，不是對到「通知訊息顯示的 tag」（顯示層可能是另一段程式碼算的，會騙人）。

### 3.5.4 失敗示例（必須在報告中以 🔴 列出）

- `Spec→Make: ❌` → CI 會跑出 `make: *** No rule to make target 'build-X'`
- `Helm=Spec: ❌` → 部署時 `ImagePullBackOff` / `ErrImagePull`
- `DfExists: ❌` → docker build 失敗
- `Orch→Spec: ❌` → Jenkins stage skip 或 codebuild project not found

---

## Phase 4 — Naming Audit

1. 推導 dominant pattern（多數派決定）
2. 列出 outlier：哪些服務違反 pattern
3. 提示常見錯誤類型：
   - 大小寫不一致（buildspec 全小寫 vs Dockerfile camelCase 同檔內混用）
   - 連字號殘留（`build-credit-session-reconcile` vs 正規化後的 `build-creditsessionreconcile`）
   - 角色後綴漂移（`publisher` vs 一致的 `worker`）

---

## Phase 5 — Cloud / Runtime Audit（僅 `--deep` 模式）

> ⚠️ 跑 cloud cli 前必須先 `aws sts get-caller-identity` / `gcloud config list` / `kubectl config current-context` 顯示給使用者確認帳號 / context 是否正確，**錯帳號不能繼續**。

依 Phase 1.3 偵測到的 provider，跑對應 cli（純讀取）：

| Provider | 指令 | 用途 |
|----------|------|------|
| AWS CodeBuild | `aws codebuild list-projects --region <r>` | 比對 CI orchestrator 引用的 project 是否存在 |
| AWS ECR | `aws ecr describe-repositories --region <r>` | image 倉是否齊備 |
| GCP Artifact Registry | `gcloud artifacts docker images list <repo> --filter=...` | image 是否存在、tag 是否齊備 |
| GCP Cloud Build | `gcloud builds list --filter=...` | 最近建置紀錄 |
| K8s runtime | `kubectl get deployment -n <ns>` | 實際部署 vs 期望部署 |
| Helm release | `helm list -n <ns>` | release 狀態 |

額外 audit：
- **Tag drift**：`values*.yaml` 寫死的 image tag 是否在 registry 中**所有 service 都真實存在**？查的是 **registry 上實際的 tag 列表**（`aws ecr describe-images` / `gcloud artifacts docker tags list` / `aliyun cr` / `crane ls`），**不是** CI 通知訊息顯示的 tag（顯示層常是另一段程式碼算的、長度可能不符 → 會騙人）。常見坑：① value 用 global tag，但部分 service 沒對應 tag；② deploy 寫的 hash 長度（如 7 碼）與 registry 上實際 push 的（如 8 碼）不符 → 兩者皆 ImagePullBackOff。

---

## Phase 6 — 輸出（最終報告）

### 6.1 兩張表（缺一不可）

**Table A — 存在性矩陣**（Phase 3 產物，columns 隨 discovery 動態調整）

**Table B — Chain Trace 矩陣**（Phase 3.5 產物，per-service × per-edge 的 ✅/❌(原因)）

> 只交 Table A 收工 = audit 失格。Table B 才是「會不會壞」的判定依據。

### 6.2 不一致清單（分嚴重度）

```
🔴 高 — 會直接導致 build / deploy 失敗
  - [list]
🟡 中 — 命名 / pattern outlier，不立即壞但長期會混亂
  - [list]
🟢 低 — 純檔案層級小漂移 / 孤兒
  - [list]
```

### 6.3 推薦動作

逐項列出需要做什麼（不執行）：
- 新增 / 刪除 / 改名什麼檔案（cite 路徑 + 行號）
- 雲端要跑什麼 cli（含完整 command + region + account 提示）
- 預估每項的 reversibility（可逆 / 半可逆 / 不可逆）

> ⚠️ **改名 / 對齊方向（MANDATORY，踩過坑）**：每一條「改名」建議都必須先寫明
> 「**canonical = `<代碼推導名>`（出處：cmd/.../BC/ServiceName）**，故 `<下游檔案>` 對齊到它」。
> - **永遠是下游對齊代碼**，不准建議把代碼改去遷就雲端 / Makefile 的孤兒名。
> - 指令若有「改名」但方向不明（往 A 還是往 B），**先用 git 歷史 + 代碼定 canonical，再用一句話跟使用者確認方向**，不得自行腦補後直接動手。
> - 「對齊到較少檔案的那邊」是**成本考量、不是 canonical 判準**；canonical 只由代碼決定，兩者衝突時以代碼為準。

### 6.4 可選：匯出報告

詢問是否寫成 `./audit-cicd-YYYY-MM-DD.md`，方便 share / git commit。

---

## Phase 7 — `--fix` 模式（patch plan only）

僅產出 Markdown 格式的 patch 計畫，**絕不執行**：

```markdown
## Patch Plan — generated by /audit-cicd --fix

### 檔案變更
1. 新增 `<path>` — 內容範例見下
2. 刪除 `<path>` — 因為 [原因]
3. 重命名 `<old>` → `<new>` — 對齊 [pattern]

### Cloud 變更（手動執行 / 經 /doit 落地）
1. `aws codebuild delete-project --name <X>`（destructive，需確認）
2. `aws codebuild create-project --cli-input-json file://...`

### K8s 變更
1. 下次 `helm upgrade` 後手動 `kubectl delete deployment <orphan>` 清理

### 估計
- 可逆檔案變更：N
- 不可逆雲端動作：M（需明確確認）
```

使用者拿到計畫後可：
- 自己手動執行
- 或用 `/doit <貼上 patch plan>` 走完整 plan → confirm → execute 流程

---

## 禁止事項

- ❌ 寫死任何專案路徑 / cloud / region / project ID
- ❌ 未確認自動執行 `aws ... delete` / `kubectl delete/apply` / `docker push`
- ❌ 對檔案做修改（除 `--fix` 模式且**使用者明確輸入 Y**）
- ❌ 跳過 Phase 1 discovery，直接套用上次 audit 的 layout
- ❌ **只交 Phase 3 存在性矩陣就收工**（必須跑 Phase 3.5 Chain Trace，否則漏掉 wiring 斷鏈）
- ❌ Helm image path 只看 `image:` 那行 → 必須讀 `_helpers.tpl` 與所有 template 的 `printf` / prefix / suffix 後再對字面值
- ❌ **把 build pivot（Makefile）/ 雲端現況當 canonical** → canonical 只由代碼決定（Phase 2）
- ❌ **發現命名分歧就自行決定改名方向** → 必須先 git 歷史 + 代碼定 canonical，方向不明先問使用者
- ❌ **建議把代碼改去對齊下游孤兒名**（永遠下游對齊代碼，不是反過來）

---

## 加分項（best effort）

- 若有 root `CLAUDE.md`：先讀當 context（不取代 discovery，但可降低詢問次數）
- 若是 git repo：用 `git log --since=30d --name-only` 標出最近改動過的 layer（drift 風險高的優先審）
- 若偵測到多個 environment values（uat / staging / prod）：分環境跑 audit（global tag 各環境不同正常）

---

## 與其他 skill / command 的協作

| 既有資源 | 用途 |
|---------|------|
| `karpathy-guidelines` | Phase 0 安全網 |
| `aws` | Phase 5 用，沿用其安全分級規則 |
| `gcp` | Phase 5 用 |
| `k8s` | Phase 5 用 |
| `/doit` | `--fix` 模式產出的 patch plan，可丟給 /doit 走完整落地流程 |

不重複實作 cli 邏輯 — 借用既有 skill。

---

## 範例輸出片段

```
🔎 Discovery 結果（請確認）

Build pivot:          Makefile  (18 build-* targets)
Container defs:       .devops/dockerfile/  (camelCase × 18)
Per-service CI:       .devops/codebuild/buildspec-*.yml × 18
CI orchestrator:      Jenkinsfile (CODEBUILD_SERVICES map × 18)
Deployment:           ../../devops/k8s/<...>/value-uat.yaml (Helm chart, apps × 18)
Cloud:                AWS CodeBuild (ap-northeast-3) + GCP AR (asia-southeast1)
Inventory pattern:    <basename_lowercase_no_hyphens><role_suffix>

繼續 audit? [Y/n] _
```

```
📊 Table A — 存在性矩陣

| Service                    | Container | CI Spec | Jenkins | Deploy | (deep) AWS | (deep) Image |
|----------------------------|:---------:|:-------:|:-------:|:------:|:----------:|:------------:|
| adminservice               | ✅        | ✅      | ✅      | ✅     | ✅         | ✅           |
| ...                        | ...       | ...     | ...     | ...    | ...        | ...          |
| outboxpublisher            | ❌        | ❌      | ❌      | ❌     | ⚠️ orphan  | ⚠️ orphan    |
| outboxworker (new)         | ✅        | ✅      | ✅      | ✅     | ✅         | ❌ no tag    |

📊 Table B — Chain Trace 矩陣（callgraph wiring）

| Service        | Orch→Spec | Spec→Make | SN=Key? | Mk→Df | DfExists | Helm=Spec? |
|----------------|:---------:|:---------:|:-------:|:-----:|:--------:|:----------:|
| adminservice   | ✅        | ✅        | ✅      | ✅    | ✅       | ✅         |
| foo-svc        | ✅        | ❌ no `build-foo-svc` target | … | … | … | …    |
| bar-worker     | ✅        | ✅        | ❌ SN="barworker"≠key | … | … | …          |

🔴 高優先 — value-uat global tag 為 X，但 outboxworker image 無此 tag → 部署會 ImagePullBackOff
🔴 高優先 — foo-svc Jenkins 指 codebuild project 但無對應 Makefile build target → CI 必失敗
🟡 中優先 — AWS CodeBuild project `<org>-...-outboxpublisher` 是孤兒，無 Jenkins 引用
🟢 低優先 — GCP image `<prefix>-outboxpublisher` 是孤兒（無自動 build pipeline）
```
