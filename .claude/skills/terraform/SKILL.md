---
name: terraform
description: >-
  This skill should be used when the user asks to "deploy to AWS", "deploy to GCP",
  "create Terraform config", "write .tf files", "terraform plan", "terraform apply",
  "tf plan", "tf apply", "tf init", "tf import", "tf state",
  "provision infrastructure", "create VPC", "set up ECS", "set up Cloud Run",
  "review Terraform security", "refactor Terraform modules", "add a new cloud resource",
  "set up load balancer", "configure DNS", "create S3 bucket", "set up RDS",
  "deploy to BytePlus", or mentions Terraform, tf, tofu, OpenTofu, HCL,
  tfvars, tfstate, .tf files, IaC, infrastructure-as-code,
  or cloud resource provisioning on AWS/GCP/BytePlus.
version: 0.3.0
---

# Terraform Infrastructure Skill

Provision, manage, and review infrastructure-as-code using Terraform across AWS, GCP, and BytePlus.

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
// Add to .claude/settings.json → mcpServers
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
- **State Safety** — Local backend by default. Never commit `.tfstate` files. Use `.gitignore` to exclude `*.tfstate`, `*.tfstate.backup`, `.terraform/`.
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
infra/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   ├── providers.tf
│   │   └── backend.tf
│   └── prod/
│       └── ... (same structure)
├── modules/
│   ├── networking/
│   ├── compute/
│   ├── database/
│   └── storage/
└── .gitignore
```

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
cd infra/environments/{env}

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

### BytePlus

BytePlus uses a community/custom Terraform provider. When working with BytePlus:
- Check provider availability at the Terraform Registry
- Follow the same module structure as AWS/GCP
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
- **改 variables 必須同步 tfvars** — 每次新增 variable 欄位，必須同步更新 `terraform.tfvars` 明確賦值，即使有 default。確保 tfvars 是完整的配置文件。

### Three-Layer Separation（三層分離原則）

三層分離是 Terraform 配置的基本架構，但**值該放哪一層是設計決策，不是硬性規則**。

| 層級 | 檔案 | 職責 | 範例 |
|------|------|------|------|
| **Schema** | `variables.tf` | 宣告變數的名稱、型別、描述、預設值、驗證規則 | `variable "instances" { type = map(object({...})) }` |
| **Logic** | `main.tf` | 使用 `var.*` 組裝 module、建立 resource、計算 locals | `module "compute" { instances = local.resolved }` |
| **Values** | `terraform.tfvars` | 賦值：環境特定的實際參數 | `instances = { app = { instance_type = "t4g.small" } }` |

#### 值該放 tfvars 還是 main.tf？

HashiCorp 官方的判斷標準（[來源](https://developer.hashicorp.com/terraform/tutorials/configuration-language/variables)）：

> *"In any configuration, there may be some values that you want to let users configure with variables and others you wish to hard-code."*
>
> *"When writing Terraform configuration for a specific project, you may choose to hard-code attributes if you do not want to let users configure them."*

**核心問題：「這個值會因環境而變嗎？」**

| 類別 | 放哪裡 | 範例 |
|------|--------|------|
| 會因環境而變的規格 | **tfvars** | `machine_type`, `tier`, `disk_size`, `region` |
| 環境相關 + 敏感值 | **tfvars** | IP 白名單、`project_id`、IAM members |
| 架構決策、固定命名 | **main.tf 硬編碼可接受** | VPC 名稱、固定 tag、port 號 |
| 衍生/計算值 | **locals** | name prefix、subnet ID 解析 |

> **Directory-per-environment 情境**：若採用 `environments/{env}/` 結構，每個環境有獨立的 `main.tf` 和 `terraform.tfvars`。此時值放 main.tf 或 tfvars 的差異縮小，因為切環境時兩個檔案都是各自獨立的。但建議團隊內統一慣例（如「規格類一律放 tfvars」），讓新人容易找到值在哪裡。

#### tfvars 在 directory-per-env 下的額外價值

即使每個環境有獨立的 main.tf，tfvars 在以下場景仍有獨特作用：

| 場景 | 說明 |
|------|------|
| 同環境多組配置切換 | `terraform apply -var-file=loadtest.tfvars` vs 正常配置 |
| 敏感值不進 git | tfvars 加入 `.gitignore`，main.tf 留在版控 |
| CI/CD 動態注入 | 用 `TF_VAR_*` 環境變數或 `-var-file` 注入 |

#### 原則

- `terraform.tfvars` 只做賦值，不包含邏輯
- 敏感值（密碼、key）不放 `terraform.tfvars`，改用 `TF_VAR_*` 環境變數或 secrets manager
- 多環境切換：用 `dev.tfvars` / `prod.tfvars` + `-var-file=prod.tfvars` 指定
- `locals` 適度使用 — 官方提醒 *"they can make configuration harder to read because they obscure where values originate"*（[來源](https://developer.hashicorp.com/terraform/language/values/locals)），主要用於重複值和複雜表達式，不要過度抽象

### `for_each` + `map(object)` 多資源模式

當一個 module 需要管理**多個同類但不同規格的資源**（例如多台 EC2、多個 bucket），使用 `for_each` + `map(object)` 而非重複呼叫 module：

```hcl
# variables.tf — 用 map(object) 定義，optional() 提供合理預設值
variable "instances" {
  type = map(object({
    instance_type      = string
    instance_name      = string
    subnet_id          = string
    root_volume_size   = optional(number, 30)
    associate_eip      = optional(bool, true)
    security_group_ids = list(string)          # 由外部 SG module 提供
  }))
}

# main.tf — compute 只管 EC2，SG 由獨立 module 管理
resource "aws_instance" "main" {
  for_each               = var.instances
  instance_type          = each.value.instance_type
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = each.value.security_group_ids  # per-instance SG
  ...
}

resource "aws_eip" "main" {
  for_each = { for k, v in var.instances : k => v if v.associate_eip }
  instance = aws_instance.main[each.key].id
  ...
}

# outputs.tf — 輸出 map，key 對應邏輯名稱
output "instance_ids" {
  value = { for k, v in aws_instance.main : k => v.id }
}
```

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

## Additional Resources

### Reference Files

For detailed patterns and checklists, consult:
- **`references/module-conventions.md`** — Module structure, naming, and composition patterns
- **`references/aws-patterns.md`** — AWS resource templates (VPC, ECS, RDS, S3, ALB, etc.)
- **`references/gcp-patterns.md`** — GCP resource templates (VPC, Cloud Run, Cloud SQL, etc.)
- **`references/security-checklist.md`** — Security audit checklist for Terraform configurations

### Scripts

- **`scripts/tf-init-module.sh`** — Scaffold a new Terraform module directory with standard files
