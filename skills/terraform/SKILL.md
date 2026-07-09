---
name: terraform
description: >-
  This skill should be used when the user asks to "deploy to AWS", "deploy to GCP",
  "deploy to Aliyun", "deploy to 阿里雲", "create Terraform config", "write .tf files",
  "terraform plan", "terraform apply", "tf plan", "tf apply", "tf init", "tf import",
  "tf state", "provision infrastructure", "create VPC", "set up ECS", "set up Cloud Run",
  "set up ACK", "create ACR", "review Terraform security", "refactor Terraform modules",
  "add a new cloud resource", "set up load balancer", "configure DNS",
  "create S3 bucket", "set up RDS", "deploy to BytePlus", "set up Atlantis",
  "atlantis plan", "atlantis apply", "configure atlantis.yaml", "atlantis webhook",
  or mentions Terraform, tf, tofu, OpenTofu, HCL, tfvars, tfstate, .tf files, IaC,
  infrastructure-as-code, Atlantis, or cloud resource provisioning on AWS/GCP/Aliyun/BytePlus.
version: 0.5.0
---

# Terraform Infrastructure Skill

Provision, manage, and review infrastructure-as-code using Terraform across AWS, GCP, Aliyun (阿里雲), and BytePlus.

## MCP Tool Detection (MANDATORY on Skill Load)

When this skill is activated, **immediately detect** available MCP tools before starting any work:

### Detection Steps

1. **Check Terraform MCP** — Search for deferred tools matching `mcp__terraform` or `mcp.*terraform`:
   - Use `ToolSearch` with query `terraform` to check availability
   - If found → report available tools and use them for registry lookups, provider docs, module search
   - If not found → report status and suggest setup (see below)

2. **Check gcloud MCP** — Search for `mcp__gcloud`:
   - If found → can use `gcloud` commands via MCP (useful for SA key generation, resource verification)
   - If not found → fall back to local `gcloud` CLI via Bash

3. **Check AWS CLI** — Run `aws --version` via Bash:
   - If found → can use `aws` commands for IAM key generation, S3 operations, resource verification
   - If not found → report and suggest `brew install awscli` or `pip install awscli`

4. **Report to user**:

```
🔍 Terraform 工具偵測結果：
- Terraform Registry MCP: ✅ 可用 / ❌ 未安裝
- gcloud MCP:             ✅ 可用 / ❌ 未安裝
- 本地 terraform CLI:     ✅ 可用 / ❌ 未安裝 (terraform version)
- 本地 gcloud CLI:        ✅ 可用 / ❌ 未安裝 (gcloud version)
- 本地 aws CLI:           ✅ 可用 / ❌ 未安裝 (aws --version)
```

### MCP Setup Instructions (when not available)

If Terraform MCP is not detected, provide these setup options:

**Option 1: Terraform Registry MCP** (provider/module docs lookup)
```json
// Add to 專案根目錄 .mcp.json → mcpServers
"terraform-mcp": {
  "command": "npx",
  "args": ["-y", "terraform-mcp-server"]
}
```

**Option 2: Terraform Best Practices MCP** (cost, lint, security guidance)
```json
"terraform-best-practices-mcp": {
  "command": "npx",
  "args": ["-y", "@downatthebottomofthemolehole/terraform-best-practices-mcp-server"]
}
```

**Option 3: gcloud MCP** (GCP resource operations via gcloud CLI)
```json
"gcloud-mcp": {
  "command": "npx",
  "args": ["-y", "@google-cloud/gcloud-mcp"]
}
```

### MCP Usage Strategy

| Task | Preferred Tool | Fallback |
|------|---------------|----------|
| Look up provider/resource docs | Terraform Registry MCP | `references/*.md` patterns |
| Search for Terraform modules | Terraform Registry MCP | Manual registry search |
| Run `terraform plan/apply` | Local CLI via Bash | — |
| Run `gcloud` commands (SA keys, etc.) | gcloud MCP | Local `gcloud` CLI via Bash |
| Run `aws` commands (IAM keys, S3, etc.) | Local `aws` CLI via Bash | — |
| Security/cost review | Best Practices MCP | `references/security-checklist.md` |
| Write/edit `.tf` files | Edit/Write tools | — |

> **Rule**: MCP tools enhance but do not replace the core workflow. All `.tf` file editing, `terraform plan`, and `terraform apply` still go through local CLI. MCP is for **information retrieval and validation**.

---

## Cloud Pitfalls Skill Detection (MANDATORY on Skill Load)

偵測當前專案的 cloud provider 後，**自動載入對應雲的踩坑 / 架構 skill**（依偵測結果決定，**不寫死單一雲** — 同一台機器這個 repo 是 Aliyun、下一個可能是 AWS/GCP）。

### Detection Steps

1. **偵測 provider**（依序，取到即停）：
   - `grep -rhE 'source\s*=' **/versions.tf providers.tf` 看 `required_providers` 的 source
   - 已 init 的話 `terraform providers`
   - 退而求其次看 tfvars 的 region 命名：`cn-*` → alicloud（注意 `ap-*` 在 AWS 與阿里雲國際區皆存在，不可單靠它判定）；`us-east-1` 等 → aws；`*-central1` / `asia-*` → gcp

2. **依偵測結果載入對應 skill**（用 `Skill` 工具，可多個）：

   | provider source | 載入 skill |
   |---|---|
   | `aliyun/alicloud` | `aliyun-pitfalls` |
   | `hashicorp/aws` | `aws-architect` |
   | `hashicorp/google` / `google-beta` | `gcp-architect` |
   | 多 provider 並存 | 全部對應 skill 都載 |

3. **偵測不到**（全新專案、無 `.tf`）→ 先問使用者目標雲，**不臆測**。

> **Rule**: 此步與上方 MCP Detection 同為 skill 載入時的 mandatory 動作。Aliyun 場景**務必**載 `aliyun-pitfalls`（28+ 條實戰踩坑：provider 漂移、Terway ENI IP 不足、ACR EE 免密、cgroup v2、autoscaling 轉換陷阱、CAS wildcard… 第一次部署 ACK/ACR/EIP 不讀必踩）。

---

## Core Principles

> **🚨 CRITICAL: `terraform apply` / `terraform destroy` 禁止自行執行**
>
> **未經用戶明確允許（`Yes`/`Y`/明確授權），一律禁止執行 `terraform apply` 和 `terraform destroy`。**
> 這是不可違反的硬性規則。`plan` 可以自由執行，但 `apply` / `destroy` 必須：
> 1. 先執行 `terraform plan` 並展示完整結果
> 2. 明確告知用戶將要 create / change / destroy 的資源數量
> 3. **等待用戶回覆確認後才可執行**
> 4. 若 plan 顯示任何 **destroy**，必須額外高亮警告

- **Module-First** — Encapsulate every logical resource group into a reusable module. Avoid inline resource sprawl in root modules.
- **Provider Agnostic Where Possible** — Abstract cloud-specific details into modules; root configurations should read like a deployment manifest.
- **Least Privilege** — IAM roles, service accounts, and security groups grant only what is needed. No wildcards (`*`) in production policies.
- **State Safety** — Never commit `.tfstate` files. Use `.gitignore` to exclude `*.tfstate`, `*.tfstate.backup`, `.terraform/`. When using Atlantis or any CI/CD, **must use remote backend** (GCS/S3) — local backend will lose state on every run.
- **Immutable Inputs** — All configurable values flow through `variables.tf`. No hardcoded IDs, regions, or credentials in resource blocks.
- **Plan Before Apply** — Always run `terraform plan` and present the output for user review. **Never run `apply` without explicit user approval.**

---

## Workflow

### Step 1: Understand Requirements

Before writing any `.tf` files, clarify:

1. **MCP detection** — Run the MCP detection (see § "MCP Tool Detection") and report results
2. **Target cloud** — AWS, GCP, BytePlus, or multi-cloud
3. **Resources needed** — Compute, networking, storage, database, DNS, CDN, etc.
4. **Environment strategy** — Single env, or dev/staging/prod separation
5. **Existing state** — Scan for existing `*.tf` files, `.terraform/`, `terraform.tfstate`

```bash
# Check local CLI availability
terraform version 2>/dev/null && echo "✅ terraform CLI available" || echo "❌ terraform CLI not found"
gcloud version 2>/dev/null | head -1 && echo "✅ gcloud CLI available" || echo "❌ gcloud CLI not found"
aws --version 2>/dev/null && echo "✅ aws CLI available" || echo "❌ aws CLI not found"

# Scan for existing Terraform files
find {project-dir} -name "*.tf" -o -name "*.tfvars" -o -name ".terraform" 2>/dev/null
```

Present findings (including MCP status) and confirm scope with the user before proceeding.

### Step 2: Initialize Project Structure

For new Terraform projects, follow the standard module layout defined in `references/module-conventions.md`.

Typical root structure:

```
terraform/                      # Git repo root
├── .gitignore                  # Exclude .terraform/, *.tfstate, repos.yaml
├── atlantis.yaml               # Atlantis project config (進 git)
├── repos.example.yaml          # Server-side config 範例 (進 git)
├── modules/
│   ├── gcs-bucket/
│   ├── networking/
│   ├── compute/
│   └── database/
└── env/
    ├── dev/
    │   ├── main.tf             # Module calls
    │   ├── variables.tf
    │   ├── outputs.tf
    │   ├── providers.tf        # Provider + remote backend
    │   └── terraform.tfvars
    ├── staging/
    │   └── ... (same structure)
    └── prod/
        └── ... (same structure)
```

> When using Atlantis, `repos.yaml` (actual server-side config) stays **outside** the repo on the Atlantis server, excluded via `.gitignore`. Only `repos.example.yaml` is committed as a template.

Use `scripts/tf-init-module.sh` to scaffold module directories quickly.

### Step 3: Write Terraform Configuration

#### Provider Configuration

Separate provider config into `providers.tf`. Pin provider versions:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

#### Resource Naming Convention

All resources follow: `{project}-{env}-{service}-{resource}`

```hcl
resource "aws_s3_bucket" "assets" {
  bucket = "${var.project}-${var.environment}-assets"
}
```

#### Variable Definitions

Every variable must include `description` and `type`. Sensitive values must be marked:

```hcl
variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}
```

#### Output Definitions

Export values needed by other modules or for user reference:

```hcl
output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.networking.vpc_id
}
```

### Step 4: Validate and Plan

Run validation before planning:

```bash
cd env/{env}    # 依 Step 2 結構；專案採 environments/ 命名則對應調整

# Format check
terraform fmt -check -recursive

# Validate syntax
terraform validate

# Generate execution plan
terraform plan -out=tfplan
```

Present the plan output to the user. Highlight:
- Resources to be **created** (green)
- Resources to be **changed** (yellow)
- Resources to be **destroyed** (red) — **必須額外高亮警告**

Summarize the plan result clearly:
```
📋 Plan 結果：X to add, Y to change, Z to destroy
```

**⛔ 此處必須停下來等待用戶確認。禁止自行執行 apply。**

### Step 5: Apply (REQUIRES EXPLICIT USER APPROVAL)

> **🚨 此步驟僅在用戶明確回覆 `Yes`/`Y`/同意 後才可執行。**
> **如果用戶沒有明確授權，即使上下文暗示要 apply，也必須先詢問。**

Only after user confirmation:

```bash
terraform apply tfplan
```

If the plan contains **any destroy actions**, remind the user before applying:
```
⚠️ 注意：此次 apply 將 destroy X 個資源。確認執行？(Y/N)
```

After apply, present the outputs and any important resource identifiers.

The same rule applies to `terraform destroy` — **never execute without explicit confirmation**.

### Step 6: Security Review

When reviewing existing Terraform code, consult `references/security-checklist.md` and check:

1. No hardcoded credentials or secrets
2. Security groups / firewall rules are restrictive
3. Encryption at rest and in transit enabled
4. IAM follows least privilege
5. Public access is intentional and documented
6. State file is excluded from version control

### Step 7: Refactoring Existing Infrastructure

When restructuring modules on **live infrastructure**, follow this workflow to avoid destroying existing resources.

#### 7a. Audit Current State

```bash
# Inventory all resources in current state
terraform state list

# Inspect a specific resource's attributes
terraform state show <resource_address>
```

Identify which resources need to move and map old → new addresses.

#### 7b. Create New Modules + `moved` Blocks

For each resource being relocated, add a `moved` block in the environment root:

```hcl
moved {
  from = module.old_module.google_storage_bucket.main
  to   = module.new_module.google_storage_bucket.main
}
```

Key rules:
- Resource type and resource name in the new module **can differ** from old — `moved` maps by state address, not schema.
- `for_each` → single resource: `moved { from = module.old.resource.name["key"] to = module.new.resource.name }`
- Nested modules: include the full address path.

#### 7c. Validate Zero-Destroy

```bash
terraform init -upgrade   # Pick up new module sources
terraform plan
```

**Expected output**: existing resources show `has moved to`, new resources show `will be created`. **Zero `destroy` actions.**

If **any destroy appears** → stop, check the moved mapping. Common causes:
- Typo in `from` or `to` address
- `for_each` key mismatch
- Missing a moved block for a resource

#### 7d. Apply and Clean Up

```bash
terraform apply            # Moves state + creates new resources
# Verify: plan shows "No changes"
terraform plan

# Now safe to remove moved blocks — they served their purpose
# Also delete the old module directory if fully replaced
```

> **`moved` blocks are one-time migration aids.** Once `apply` succeeds and state is updated, they can (and should) be removed to keep config clean.

See `references/module-conventions.md` § "Safe Module Splitting" for detailed patterns and examples.

---

## Multi-Cloud Support

### AWS

Primary provider. Consult `references/aws-patterns.md` for common patterns:
- VPC + Subnets + NAT Gateway
- ECS Fargate / EKS
- RDS / Aurora
- S3 + CloudFront
- ALB / NLB
- Route53 DNS

### GCP

Consult `references/gcp-patterns.md` for common patterns:
- VPC Network + Subnets
- Cloud Run / GKE Autopilot
- Cloud SQL
- Cloud Storage + Cloud CDN
- Cloud Load Balancing
- Cloud DNS

> **GKE Autopilot 注意事項**：建立 GKE Autopilot 叢集時，必須在 `addons_config` 中明確啟用
> `http_load_balancing`（`disabled = false`）。缺少此設定會導致 GCE Ingress Controller
> 無法運作、GCLB Ingress 無法綁定 IP。詳見 `references/gcp-patterns.md` 的 GKE Autopilot 區段。

### Aliyun (阿里雲 / Alibaba Cloud)

Consult `references/aliyun-patterns.md` for common patterns:
- VPC + 多 AZ vSwitch
- NAT Gateway + EIP（統一出站，PayByTraffic 彈性帶寬）
- ACR EE（Container Registry Enterprise）+ namespace + VPC endpoint
- ACK Pro Managed（Kubernetes 託管 Pro 版）+ NodePool + Cluster Autoscaler
- OSS backend（state 存阿里雲，含 versioning）

> **🚨 重要**：阿里雲踩坑非常多，**務必同步閱讀 [`aliyun-pitfalls`](../aliyun-pitfalls/SKILL.md) skill**。
> 涵蓋 provider 漂移到 cn-beijing、Terway ENI IP 不足、`AliyunOOSLifecycleHook4CSRole`
> 一次性授權、`AliyunLinux3` 不支援 cgroup v2、ACR EE `instance_type` 校驗器舊名等
> 高頻踩坑點。**第一次部署 ACK 強烈建議先讀這份文件。**

#### Aliyun 特有注意事項

- **Provider 必須用 `aliyun/alicloud`**（不是 legacy `hashicorp/alicloud`），每個 module 加 `versions.tf` 顯式宣告
- **認證走 `profile = "default"`**（共用 `aliyun configure` 的 `~/.aliyun/config.json`）
- **大陸區 (cn-*) 需中國實名認證**，國際區 (ap-*) 不用
- **ACR EE 必須手動建 `acr-configuration` ConfigMap**（不像個人版自動）
- **K8s 1.30+ NodePool 必須用 `AliyunLinux3ContainerOptimized` image**（支援 cgroup v2）

### BytePlus

BytePlus uses a community/custom Terraform provider. When working with BytePlus:
- Check provider availability at the Terraform Registry
- Follow the same module structure as AWS/GCP/Aliyun
- Document any provider-specific quirks in comments

---

## File Conventions

| File | Purpose |
|------|---------|
| `main.tf` | Resource definitions and module calls |
| `variables.tf` | Input variable declarations |
| `outputs.tf` | Output value declarations |
| `providers.tf` | Provider and Terraform version constraints |
| `backend.tf` | State backend configuration |
| `locals.tf` | Local values and computed expressions |
| `data.tf` | Data sources (existing resources lookup) |
| `terraform.tfvars` | Variable values (env-specific, gitignored if sensitive) |

---

## Best Practices

- **Tag everything** — All resources must include `Project`, `Environment`, `ManagedBy = "terraform"` tags.
- **Use `terraform fmt`** — Format all files before committing.
- **One module, one concern** — Networking module handles VPC/subnets; compute module handles instances/containers.
- **Version pin modules** — Use exact versions for external modules from the registry.
- **No `terraform destroy` without confirmation** — Always confirm with user, show what will be destroyed.
- **Sensitive outputs** — Mark outputs containing secrets with `sensitive = true`.
- **Use `count` or `for_each`** — Prefer `for_each` with maps for resources that need stable addressing.
- **SG 獨立 module** — Security Group **永遠**拆成獨立 module，不放在 compute/ecs 等 module 內。不同角色 VM 需要不同 SG 組合，從第一天就分離。
- **Per-instance SG 綁定** — 每台 instance 在 tfvars 用 `security_group_keys = ["web"]` 指定 SG 角色，environment 層 resolve 為 SG ID。不要用全域 `security_group_ids` 給所有 instance。
- **用 `name` 不用 `name_prefix`** — `name_prefix` 會產生隨機後綴（如 `money-prod-web-20260413...`），難以辨識。用固定 `name`（如 `money-prod-web-sg`）更清晰。
- **Outputs 要包含 name** — 除了 ID 和 ARN，也輸出 `name`，方便 debug 和確認。
- **root_volume_size 預設 30GB** — Amazon Linux 2023 等常見 AMI snapshot 為 30GB，設 20GB 會報錯。預設值用 30GB 更安全。
- **VM AMI 必須寫死（pin）在 tfvars** — 動態查詢（`data.aws_ami`）會在新 AMI 發佈時導致 `terraform plan` 出現 **force replacement**（destroy + create），造成 instance 資料遺失。正確做法：在 tfvars 的 `ami` 欄位寫死 AMI ID（如 `ami = "ami-0761abe7d296ac155"`）。若用戶新增 VM 或未指定 AMI，**必須先列出該 region + architecture 的可用 AMI 版本（LTS 優先），詢問用戶要使用哪個版本後再寫入 tfvars**，不可自行決定。
- **改 variables 必須同步 tfvars** — 每次新增 variable 欄位，必須同步更新 `terraform.tfvars` 明確賦值，即使有 default。確保 tfvars 是完整的配置文件。
- **共用屬性用環境層 default 變數** — 多台 VM 共用的屬性（如 `key_name`）不要在每台 instance 重複寫，改用環境層級的 `default_*` 變數（如 `default_key_name`），在 `locals.resolved_instances` 用 `coalesce(v.key_name, var.default_key_name)` 合併。個別 instance 仍可覆蓋。這減少 tfvars 重複且確保一致性。

### Three-Layer Separation（三層分離原則）

三層分離是 Terraform 配置的基本架構，但**值該放哪一層是設計決策，不是硬性規則**。

| 層級 | 檔案 | 職責 | 範例 |
|------|------|------|------|
| **Schema** | `variables.tf` | 宣告變數的名稱、型別、描述、預設值、驗證規則 | `variable "instances" { type = map(object({...})) }` |
| **Logic** | `main.tf` | 使用 `var.*` 組裝 module、建立 resource、計算 locals | `module "compute" { instances = local.resolved }` |
| **Values** | `terraform.tfvars` | 賦值：環境特定的實際參數 | `instances = { app = { instance_type = "t4g.small" } }` |

#### 值該放 tfvars 還是 main.tf？

**核心問題：「這個值會因環境而變嗎？」**（HashiCorp 官方判準與來源連結見 `references/module-conventions.md` § "Variable Value Placement Guide"）

| 類別 | 放哪裡 | 範例 |
|------|--------|------|
| 會因環境而變的規格 | **tfvars** | `machine_type`, `tier`, `disk_size`, `region` |
| 環境相關 + 敏感值 | **tfvars** | IP 白名單、`project_id`、IAM members |
| 架構決策、固定命名 | **main.tf 硬編碼可接受** | VPC 名稱、固定 tag、port 號 |
| 衍生/計算值 | **locals** | name prefix、subnet ID 解析 |

> Directory-per-environment 取捨與 tfvars 額外價值場景 → `references/module-conventions.md` § "Variable Value Placement Guide"。

#### 原則

- `terraform.tfvars` 只做賦值，不包含邏輯
- 敏感值（密碼、key）不放 `terraform.tfvars`，改用 `TF_VAR_*` 環境變數或 secrets manager
- 多環境切換：用 `dev.tfvars` / `prod.tfvars` + `-var-file=prod.tfvars` 指定
- `locals` 適度使用 — 官方提醒 *"they can make configuration harder to read because they obscure where values originate"*（[來源](https://developer.hashicorp.com/terraform/language/values/locals)），主要用於重複值和複雜表達式，不要過度抽象

### `for_each` + `map(object)` 多資源模式

當一個 module 需要管理**多個同類但不同規格的資源**（例如多台 EC2、多個 bucket），使用 `for_each` + `map(object)` 而非重複呼叫 module（完整 HCL 三件套範例見 `references/module-conventions.md` § "for_each Module Design"）。

**設計原則**：
- **SG 獨立 module**：Security Group **必須**拆成獨立 module（`modules/security-groups/`），不可放在 compute 內。不同角色的 VM 需要不同 SG 組合，綁死在 compute 會導致無法靈活配置
- **Per-instance SG 綁定**：每台 instance 透過 `security_group_keys = ["web"]` 指定要掛哪些 SG，在 environment 層 resolve 為實際 SG ID 後傳入 compute
- **`optional()` 減少輸入**：用 `optional(type, default)` 讓呼叫端只需提供必填欄位（Terraform 1.3+）
- **條件式資源**：用 `{ for k, v in map : k => v if condition }` 過濾，實現部分實例才建立的資源（如 EIP）
- **outputs 回傳 map**：讓呼叫端可用 `module.compute.instance_ids["app"]` 精確取值
- **environment 層參數解析**：在 `locals` 中將使用者友善的 key（如 `subnet_key = "a"`、`security_group_keys = ["web"]`）解析為實際 ID，避免 tfvars 寫死 resource ID

詳細範例見：
- `references/module-conventions.md` § "for_each Module Design"
- `references/aws-patterns.md` § "EC2 Multi-Instance" + "Security Group Module"

---

## Atlantis Integration

When using Atlantis for GitOps-driven Terraform, consult **`references/atlantis-integration.md`** for full details.

Covers: project structure, atlantis.yaml / repos.yaml config, remote backend requirements, webhook notifications, GCP authentication, server startup, state migration, and common issues troubleshooting.

---

## Additional Resources

### Reference Files

For detailed patterns and checklists, consult:
- **`references/module-conventions.md`** — Module structure, naming, and composition patterns
- **`references/aws-patterns.md`** — AWS resource templates (VPC, ECS, RDS, S3, ALB, etc.)
- **`references/gcp-patterns.md`** — GCP resource templates (VPC, Cloud Run, Cloud SQL, etc.)
- **`references/security-checklist.md`** — Security audit checklist for Terraform configurations
- **`references/atlantis-integration.md`** — Atlantis GitOps integration (config, webhooks, auth, troubleshooting)

### Scripts

- **`scripts/tf-init-module.sh`** — Scaffold a new Terraform module directory with standard files
