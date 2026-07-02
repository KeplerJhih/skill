---
description: 架構圖 ↔ Terraform ↔ 雲端三方對齊同步 workflow
argument-hint: [圖檔或同步方向]
---

# Command: /infra-sync (Infrastructure Sync Workflow)

此指令用於**同步架構圖、Terraform 代碼與雲端實際狀態**。你的角色是 **Infrastructure Sync Engineer**：解讀架構圖中的基礎設施元件，比對雲端現況，產出或更新 Terraform 配置。

**核心原則：圖 ↔ 代碼 ↔ 雲，三方對齊。方案確認、批准後動。** 嚴禁在未獲得用戶明確確認 (`Yes`/`Y`/`y`) 前進行任何 Terraform 檔案修改。

---

## 工具鏈 (Toolchain)

- **Terraform Skill**：載入 `terraform` skill 取得 HCL 撰寫規範與 module patterns
- **GCP Architect Skill**：涉及 GCP 架構決策時，載入 `gcp-architect` skill
- **Draw.io 檔案**：使用 Read 工具解析 `.drawio` XML，提取基礎設施元件
- **gcloud-mcp（優先）**：使用 `gcloud-mcp` MCP server 查詢 GCP 雲端資源。此為**首選**雲端查詢方式，比 Bash + gcloud CLI 更安全（MCP 工具有明確的權限邊界）。若 gcloud-mcp 不可用，fallback 至 Bash + `gcloud` CLI。
- **雲端狀態查詢優先順序**：
  1. `gcloud-mcp` MCP 工具（首選，結構化輸出、權限可控）
  2. Bash + `gcloud` CLI（備選，需用戶授權）
  3. Bash + `aws` CLI（AWS 環境時使用）
- **檔案操作**：Read / Grep / Glob / Edit / Write 操作 `.tf` 檔案

---

## 產出存放位置

```text
<project-root>/
├── devops/
│   ├── draw.io/                # 架構圖（輸入來源）
│   │   └── architecture.drawio
│   └── terraform/              # Terraform 配置（輸出目標）
│       ├── environments/
│       │   ├── dev/
│       │   └── prod/
│       └── modules/
│           ├── networking/
│           ├── compute/
│           ├── database/
│           └── ...
```

---

## 觸發邏輯 (Trigger & Behavior)

### 情境 A：用戶未提供具體需求 (Empty Input)

**判定標準**：用戶僅輸入 `/infra-sync`，後面沒有描述。

**你的行動**：

1. 掃描 `devops/draw.io/` 目錄，列出可用的 `.drawio` 檔案及其頁面
2. 掃描 `devops/terraform/` 目錄，列出現有 Terraform 配置
3. 展示選單：

> **Infrastructure Sync**
>
> **請選擇同步模式：**
>
> 1. **圖 → 代碼 (Diagram to Terraform)** — 從 `.drawio` 架構圖提取元件，生成 Terraform 配置
> 2. **雲 → 代碼 (Cloud to Terraform)** — 查詢雲端現有資源，比對並更新 Terraform 配置
> 3. **全同步 (Full Sync)** — 雲端狀態 + 架構圖 → 比對差異 → 對齊 Terraform
> 4. **差異報告 (Drift Report)** — 僅比對三方差異，不修改任何檔案
>
> **可用架構圖**：[列出檔案與頁面]
> **現有 Terraform**：[列出目錄結構]
>
> *請選擇模式，並指定要操作的架構圖檔案/頁面。*

---

### 情境 B：用戶已提供需求 (With Input)

**判定標準**：用戶輸入 `/infra-sync [需求描述]`，或由情境 A 延續而來。

**你的行動**：

1. 若用戶輸入包含 `.drawio` 檔案路徑，先進入**頁面選擇流程**
2. 再依需求判斷模式，進入對應流程

---

## 頁面選擇流程 (Page Selection)

當用戶指定了 `.drawio` 檔案時（無論哪種模式），**必須先執行此流程**：

1. **讀取 `.drawio` XML**：使用 Read 工具讀取檔案
2. **解析所有 `<diagram>` 節點**：提取每個頁面的 `name` 屬性與 `id`
3. **快速掃描每頁內容**：統計各頁面的節點數量，識別主要元件關鍵字（如 VPC、GKE、DB 等）
4. **展示頁面清單**，讓用戶選擇：

> ### 偵測到的頁面
>
> **檔案**：`devops/draw.io/architecture.drawio`
>
> | # | 頁面名稱 | 節點數 | 主要元件 |
> |---|---------|-------|---------|
> | 1 | 暫存設計 | 25 | VPC, Subnet x3, GKE x3, Cloud NAT, MySQL |
> | 2 | 網路拓撲 | 12 | VPC, Firewall Rules, VPN |
> | 3 | CI/CD | 8 | Cloud Build, Artifact Registry |
> | 4 | ... | ... | ... |
>
> **請選擇要同步的頁面（可多選，用逗號分隔，如 `1,3`）：**

5. **等待用戶選擇後**，僅對選定的頁面進行後續操作

---

## 模式一：圖 → 代碼 (Diagram to Terraform)

### 階段 0：解析架構圖

1. **確認頁面已選定**：若尚未執行頁面選擇流程，先執行
2. **針對選定頁面提取基礎設施元件**：從 node labels、styles、連線關係中識別：

   | 辨識依據 | 對應類別 | 範例 |
   |---------|---------|------|
   | `vpc` / `network` | 網路 | `cloud vpc` |
   | `subnet` + CIDR | 子網路 | `subnet-singapore 10.0.1.0/24` |
   | `gke` / `kubernetes` / `k8s` | 容器叢集 | GKE node |
   | `vm` / `virtual_machine` shape / 規格標註 | 計算實例 | `redis-server 2c 8g 30g` |
   | `mysql` / `sql` / `db` | 資料庫 | `SAAS MySQL 8c 64ram` |
   | `nat` / `cloud nat` | NAT 閘道 | `Cloud NAT` |
   | `ingress` / `lb` / `load balancer` | 負載均衡 | `k8s ingress neg` |
   | `iap` | 身份感知代理 | `GCP IAP` |
   | `nfs` / `filestore` | 檔案儲存 | `nfs-server` |
   | IP 位址標註 | 靜態 IP | `203.0.113.55` |
   | 連線標籤 | 存取關係 | `統一出站`、`訪問` |

4. **展示解析結果**，讓用戶確認：

> ### 架構圖解析結果
>
> **檔案**：`devops/draw.io/architecture.drawio`
> **頁面**：`[頁面名稱]`
>
> | # | 元件 | 類別 | 規格/備註 | 對應 Terraform Resource |
> |---|------|------|---------|----------------------|
> | 1 | cloud vpc | VPC | — | `google_compute_network` |
> | 2 | subnet-singapore | Subnet | 10.0.1.0/24 | `google_compute_subnetwork` |
> | 3 | ... | ... | ... | ... |
>
> **連線關係**：
> - [元件A] → [元件B]：[關係描述]
> - ...
>
> **未能辨識的節點**（需要你確認）：
> - [列出無法自動對應的節點]
>
> **確認後將進入 Terraform 生成規劃。輸入 `Y` 確認，或修正上方解析結果。**

**等待用戶確認 (`Y`/`Yes`/`y`) 後才繼續。**

### 階段 1：Terraform 規劃

1. **【強制】載入 `terraform` skill**：使用 Skill tool 載入 `terraform` skill，取得 HCL 撰寫規範、module patterns、security checklist。此步驟為強制前置條件，未載入前禁止編輯任何 `.tf` 檔案。涉及 GCP 架構決策時，額外載入 `gcp-architect` skill。
2. **檢查現有 Terraform**：掃描 `devops/terraform/` 是否已有配置
   - **有**：比對差異，產出增量變更方案
   - **無**：產出完整 module 結構方案
3. **產出規劃方案**：

> ### Terraform 生成規劃
>
> **Module 結構**：
> ```
> devops/terraform/
> ├── environments/dev/
> │   ├── main.tf
> │   ├── variables.tf
> │   ├── outputs.tf
> │   ├── providers.tf
> │   └── terraform.tfvars
> └── modules/
>     ├── networking/    # VPC, Subnets, NAT, Firewall
>     ├── compute/       # GKE, VMs
>     └── database/      # Cloud SQL
> ```
>
> **各 Module 內容預覽**：
>
> | Module | Resources | 來源元件 |
> |--------|-----------|---------|
> | networking | `google_compute_network`, `google_compute_subnetwork` x3, `google_compute_router_nat` | vpc, subnet-a/b/c, Cloud NAT |
> | compute | `google_container_cluster`, `google_compute_instance` x3 | GKE, redis-server, hotfix, nfs-server |
> | database | `google_sql_database_instance` | SAAS MySQL |
>
> **確認後將生成 `.tf` 檔案。輸入 `Y` 確認，或提出調整。**

**等待用戶確認 (`Y`/`Yes`/`y`) 後才繼續。**

### 階段 2：生成 Terraform 檔案

1. **【檢查】確認 `terraform` skill 已載入**：若階段 1 未載入，此處必須補載。
2. 依照 `terraform` skill 規範生成 `.tf` 檔案
2. 使用 `references/gcp-patterns.md` 中的 resource patterns
3. 所有可變值透過 `variables.tf` 管理，不 hardcode
4. 從 drawio 中提取的具體數值（IP、CIDR、規格）寫入 `terraform.tfvars`
5. 生成後執行 `terraform fmt` + `terraform validate`（若 terraform CLI 可用）

### 階段 3：執行 Terraform（僅在用戶明確要求時）

用戶要求執行 `terraform plan` 或 `terraform apply` 時，**必須先執行雲端現況調查**：

1. **【強制】確認 `terraform` skill 已載入**：若當前對話中尚未載入 `terraform` skill，必須先使用 Skill tool 載入。這確保 plan/apply 前的任何 `.tf` 檔案修改都符合規範。
2. **查詢雲端現有資源**：優先使用 `gcloud-mcp` MCP 工具查詢，fallback 至 `gcloud` CLI。列出與本次操作相關的現有資源
3. **執行 `terraform plan`**：產出變更計畫
4. **分類並標示風險等級**：

> ### Terraform Plan 風險評估
>
> **變更摘要**：
>
> | 風險等級 | 操作 | 資源 | 影響說明 |
> |---------|------|------|---------|
> | 🟢 安全 | **新增** (create) | `google_compute_network.main` | 新建 VPC，不影響現有資源 |
> | 🟡 注意 | **修改** (update in-place) | `google_compute_instance.redis` | 更新 metadata，不重啟 |
> | 🟠 警告 | **替換** (destroy + create) | `google_compute_subnetwork.sg-a` | 子網路將被刪除重建，**所有依賴此子網路的 VM / GKE 節點將中斷** |
> | 🔴 危險 | **刪除** (destroy) | `google_sql_database_instance.main` | **資料庫將被永久刪除，所有資料將遺失** |
>
> **🔴 危險操作詳細說明**（若有）：
>
> - **`google_sql_database_instance.main`**：
>   - 當前狀態：運行中，包含 `[N]` 個資料庫，磁碟使用 `[X] GB`
>   - 刪除後果：所有資料永久遺失，無法復原（除非有備份）
>   - 建議：確認是否已備份，或考慮先設定 `deletion_protection = true`
>
> **🟠 替換操作詳細說明**（若有）：
>
> - **`google_compute_subnetwork.sg-a`**：
>   - 替換原因：CIDR 範圍變更（`10.0.1.0/24` → `10.0.2.0/24`）
>   - 影響範圍：[列出依賴此資源的其他資源]
>   - 預估停機時間：約 `[N]` 分鐘

5. **風險確認規則**：

   - 🟢🟡 操作：展示摘要，等待 `Y` 確認即可執行
   - 🟠 替換操作：**必須列出所有受影響的下游資源**，等待 `Y` 確認
   - 🔴 刪除/摧毀操作：**必須額外要求用戶輸入資源名稱確認**（如 `請輸入 "google_sql_database_instance.main" 確認刪除`），防止誤操作
   - 含有 🔴 操作時：建議用戶先執行 `terraform state rm` 移出管理（而非直接 destroy），或確認備份狀態

6. **嚴禁自動執行 `terraform apply`**：任何情況下都必須先展示 plan 結果與風險評估，獲得明確確認後才執行

---

## 模式二：雲 → 代碼 (Cloud to Terraform)

### 階段 0：查詢雲端狀態

1. **確認雲端平台與權限**：
   - **優先使用 `gcloud-mcp` MCP 工具**：先嘗試透過 MCP 工具查詢（如 `mcp__gcloud-mcp__*`），確認連線與認證正常
   - **Fallback**：若 gcloud-mcp 不可用，嘗試 Bash 執行 `gcloud config list` 確認認證狀態
   - 若兩者皆無權限，提示用戶設定認證

2. **查詢資源清單**（依優先順序選擇工具）：

   **方式 A：gcloud-mcp MCP 工具（首選）**
   使用 `gcloud-mcp` 提供的工具查詢各類 GCP 資源。MCP 工具回傳結構化資料，便於解析與比對。

   **方式 B：Bash + gcloud CLI（備選）**
   ```bash
   gcloud compute networks list --format=json
   gcloud compute instances list --format=json
   gcloud container clusters list --format=json
   gcloud sql instances list --format=json
   ```

3. **展示雲端資源清單**，讓用戶確認哪些需要納入 Terraform 管理

**等待用戶確認 (`Y`/`Yes`/`y`) 後才繼續。**

### 階段 1：比對與規劃

1. 將雲端資源與現有 `.tf` 檔案比對
2. 分類為：
   - **已管理**：Terraform 中已有定義
   - **未管理**：雲端存在但 Terraform 中沒有（需 import 或新建）
   - **已刪除**：Terraform 中有定義但雲端已不存在
3. 產出變更方案，等待確認

### 階段 2：更新 Terraform

1. 為未管理的資源生成 `.tf` 定義
2. 提供 `terraform import` 指令（若需要匯入既有 state）
3. 清理已刪除資源的定義

---

## 模式三：全同步 (Full Sync)

結合模式一與模式二：

1. 先執行**頁面選擇流程**（若有指定 `.drawio` 檔案）
2. 執行「模式一 階段 0」：解析選定頁面的架構圖元件
3. 執行「模式二 階段 0」：查詢雲端狀態
3. **三方比對**：

> ### 三方差異報告
>
> | 元件 | 架構圖 | Terraform | 雲端 | 狀態 |
> |------|--------|-----------|------|------|
> | main-vpc | O | O | O | 同步 |
> | subnet-a | O | X | O | 缺 Terraform 定義 |
> | old-vm | X | O | X | 殘留 Terraform 定義 |
> | new-svc | O | X | X | 待建立 |

4. 依差異產出修正方案，等待確認後執行

---

## 模式四：差異報告 (Drift Report)

與模式三相同分析流程，但**僅產出報告，不修改任何檔案**。適合日常巡檢使用。

---

## gcloud-mcp 整合指南

### 工具探索

首次使用時，先透過 `ToolSearch` 搜尋 `gcloud-mcp` 可用工具：
```
ToolSearch query="gcloud-mcp" max_results=20
```

### 使用原則

1. **查詢操作優先用 gcloud-mcp**：所有 read/list/describe/get 類操作，優先使用 gcloud-mcp MCP 工具
2. **結構化輸出**：gcloud-mcp 回傳結構化資料（JSON），直接用於比對與報告，無需手動解析 CLI 文字輸出
3. **Fallback 至 CLI**：若 gcloud-mcp 無法完成特定查詢（如工具未涵蓋的資源類型），fallback 至 `gcloud` CLI
4. **寫入操作仍走 Terraform**：gcloud-mcp 僅用於查詢，所有基礎設施變更必須透過 Terraform 進行
5. **Terraform 執行用 CLI**：`terraform init/plan/apply` 等操作仍使用 Bash + terraform CLI

### 典型查詢場景

| 場景 | 優先使用 | Fallback |
|------|---------|----------|
| 列出 VPC / Subnets / VMs | gcloud-mcp | `gcloud compute ... list` |
| 查看 GKE 叢集詳情 | gcloud-mcp | `gcloud container clusters describe` |
| 查看 Cloud SQL 狀態 | gcloud-mcp | `gcloud sql instances describe` |
| 執行 terraform plan | Bash + terraform CLI | — |
| 執行 terraform apply | Bash + terraform CLI | — |

---

## 重要規則

1. **三階段確認制**：解析確認 → 規劃確認 → 生成確認。任何一階段未獲 `Y`/`Yes`/`y`，嚴禁進入下一階段。
2. **不破壞現有 Terraform**：更新時使用增量方式，不覆蓋現有配置。有衝突時展示差異讓用戶選擇。
3. **Skill 強制載入**：任何涉及 `.tf` 檔案編輯或 `terraform` CLI 執行的階段，必須先使用 Skill tool 載入 `terraform` skill（若當前對話中尚未載入）。涉及 GCP 架構決策時，額外載入 `gcp-architect` skill。純查詢雲端狀態（不修改 .tf）則不需要載入。
4. **安全優先**：生成的 Terraform 必須遵循 `terraform` skill 的 security checklist。不 hardcode credentials，sensitive 變數正確標記。
5. **drawio 元件辨識容錯**：無法自動辨識的節點，列為「未能辨識」讓用戶補充，不自行猜測。
6. **雲端操作謹慎**：查詢命令（list/describe/get）可直接執行；修改命令（create/delete/update）嚴禁在此 command 中執行，所有變更透過 Terraform 進行。
7. **tfvars 不進版控**：提醒用戶將含敏感值的 `.tfvars` 加入 `.gitignore`。
8. **Terraform 執行前必查雲端**：執行 `terraform plan/apply` 前，必須先查詢雲端現有資源，確保理解當前狀態與變更影響。
9. **破壞性操作雙重確認**：任何涉及 destroy / replace 的操作，必須展示風險等級、受影響資源、資料遺失風險，🔴 危險操作需用戶輸入資源名稱二次確認。
10. **嚴禁靜默刪除**：即使 `terraform plan` 顯示 destroy，也不得在未告知用戶的情況下執行 apply。優先建議 `terraform state rm` 移出管理或確認備份。

ARGUMENTS: 同步架構圖、Terraform 代碼與雲端實際狀態。支援四種模式：圖→代碼、雲→代碼、全同步、差異報告
