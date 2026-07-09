# Terraform Module Conventions

## Directory Structure

### Root Project Layout

```
infra/
├── environments/           # Per-environment configurations
│   ├── dev/
│   │   ├── main.tf         # Module calls with dev-specific params
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   └── ...
│   └── prod/
│       └── ...
├── modules/                # Reusable modules
│   ├── networking/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── compute/
│   ├── database/
│   ├── storage/
│   ├── dns/
│   └── cdn/
└── .gitignore
```

### Module Internal Structure

Every module directory must contain:

```
modules/{module-name}/
├── main.tf          # Resource definitions
├── variables.tf     # Input variables with descriptions and types
├── outputs.tf       # Output values
└── README.md        # Usage examples (optional but recommended)
```

For complex modules, split resources by concern:

```
modules/networking/
├── main.tf          # VPC resource
├── subnets.tf       # Subnet resources
├── nat.tf           # NAT Gateway resources
├── routes.tf        # Route table resources
├── variables.tf
└── outputs.tf
```

---

## Naming Conventions

### Resource Naming

Pattern: `{project}-{env}-{purpose}`

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}
```

### Variable Naming

- Use `snake_case` for all variable names
- Prefix with resource context when ambiguous: `vpc_cidr`, `db_instance_class`
- Boolean variables: prefix with `enable_` or `is_`: `enable_nat_gateway`, `is_public`

### Output Naming

- Use `snake_case`
- Prefix with module context: `vpc_id`, `subnet_ids`, `db_endpoint`
- List outputs use plural: `public_subnet_ids`, `security_group_ids`

### Terraform Resource Names (Labels)

Use short, descriptive labels — not the full naming pattern:

```hcl
# Good
resource "aws_subnet" "public" { ... }
resource "aws_subnet" "private" { ... }

# Bad
resource "aws_subnet" "my_project_dev_public_subnet" { ... }
```

The full name goes in the `Name` tag, not the resource label.

---

## Module Composition

### Root Module Pattern

Environment root modules should be thin — just module calls and wiring:

```hcl
# environments/dev/main.tf

module "networking" {
  source = "../../modules/networking"

  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}

module "security_groups" {
  source = "../../modules/security-groups"

  project         = var.project
  environment     = var.environment
  vpc_id          = module.networking.vpc_id
  security_groups = var.security_groups
}

module "compute" {
  source = "../../modules/compute"

  project     = var.project
  environment = var.environment
  instances   = local.resolved_instances  # includes per-instance security_group_ids
}

module "database" {
  source = "../../modules/database"

  project           = var.project
  environment       = var.environment
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.private_subnet_ids
  security_group_id = module.security_groups.security_group_ids["db"]
}
```

### Common Variables

Every environment should define these base variables:

```hcl
# variables.tf
variable "project" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "region" {
  description = "Cloud provider region"
  type        = string
}
```

### Standard Tags

Apply to all resources via a `locals` block:

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

Use `merge()` to combine with resource-specific tags:

```hcl
tags = merge(local.common_tags, {
  Name = "${local.name_prefix}-web-server"
  Role = "web"
})
```

---

## .gitignore Template

```gitignore
# Terraform
*.tfstate
*.tfstate.*
*.tfplan
.terraform/
.terraform.lock.hcl
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Sensitive variable files
*.auto.tfvars
terraform.tfvars

# OS
.DS_Store
```

> Note: Decide per-project whether `terraform.tfvars` should be committed. If it contains only non-sensitive values (region, instance size), it can be committed. If it contains secrets, gitignore it.

---

## State Management

### Local Backend (Default)

```hcl
# backend.tf
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

### Future Migration to Remote

When the project scales, migrate to S3 or GCS backend:

```hcl
# AWS S3
terraform {
  backend "s3" {
    bucket         = "{project}-terraform-state"
    key            = "{env}/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "{project}-terraform-lock"
  }
}
```

```hcl
# GCP GCS
terraform {
  backend "gcs" {
    bucket = "{project}-terraform-state"
    prefix = "{env}"
  }
}
```

Migration command:

```bash
terraform init -migrate-state
```

---

## Safe Module Splitting (`moved` Blocks)

When refactoring a monolithic module into smaller, focused modules on **live infrastructure**, use `moved` blocks (Terraform 1.1+) to relocate resources in state without destroy/recreate.

### When to Split

A module should be split when it:
- Manages unrelated resource types (e.g., storage + IAM + registry in one module)
- Has grown beyond ~5 distinct resource groups
- Contains resources with different lifecycle or ownership

### Moved Block Syntax

Place `moved` blocks in the **environment root** `main.tf` (not inside modules):

```hcl
# Simple resource move
moved {
  from = module.services.google_storage_bucket.main
  to   = module.storage.google_storage_bucket.main
}

# for_each item → standalone resource
moved {
  from = module.services.google_project_service.apis["compute.googleapis.com"]
  to   = google_project_service.compute_api
}

# Nested module move
moved {
  from = module.infra.module.old.aws_s3_bucket.data
  to   = module.infra.module.new.aws_s3_bucket.data
}
```

### Splitting Workflow

```
1. Create new modules with the target resources
2. Replace old module call with new module calls in environment root
3. Add moved blocks for every existing resource (state list helps)
4. terraform init -upgrade
5. terraform plan → verify: only "moved" + new "create", ZERO "destroy"
6. terraform apply
7. terraform plan → confirm "No changes"
8. Remove moved blocks + delete old module directory
```

### Common Pitfalls

| Issue | Cause | Fix |
|-------|-------|-----|
| Resource shows destroy + create | Missing `moved` block | Add the mapping |
| `from` address not found in state | Typo or wrong `for_each` key | Run `terraform state list` to verify exact address |
| Moved block conflicts | Two blocks point to same `from` or `to` | Ensure 1:1 mapping |
| Outputs reference old module | Environment `outputs.tf` not updated | Update all `module.old.*` references |

### Lifecycle

`moved` blocks are **one-time migration aids**. After a successful `apply` + verified clean `plan`, remove them to keep configuration clean.

---

## for_each Module Design

When a module manages **multiple 同類但不同規格的資源**，使用 `for_each` + `map(object)` 搭配 `optional()` 預設值。

> **跨雲通用**：以下原則適用於所有 cloud provider。範例以 AWS 為主（`aws_instance`、`aws_eip`），GCP 等價範例請見 `gcp-patterns.md` § "GCE Multi-Instance (for_each)"。

### 設計原則

1. **SG 獨立 module，compute 只管 compute**
   - Security Group **必須**拆成獨立 module（`modules/security-groups/`），不放在 compute 內
   - 每台 instance 透過 `security_group_keys` 指定 SG 角色，environment 層 resolve 為 SG ID
   - IAM Role 等其他共享資源：不加 `for_each`，只建一份
   - 個別資源（Instance、EIP、Disk）：加 `for_each`，每個 map entry 建一份
   - 判斷依據：該資源的生命週期是否與單一 instance 綁定

2. **`optional()` 減少呼叫端負擔**（Terraform 1.3+）
   ```hcl
   variable "instances" {
     type = map(object({
       instance_type    = string                      # 必填
       instance_name    = string                      # 必填
       subnet_id        = string                      # 必填
       root_volume_size = optional(number, 20)        # 選填，預設 20
       associate_eip    = optional(bool, true)         # 選填，預設 true
       ami_architecture = optional(string, "arm64")   # 選填，預設 arm64
     }))
   }
   ```
   呼叫端只需提供必填欄位，其餘自動填入預設值。

3. **條件式 `for_each` 過濾**
   ```hcl
   # 只有 associate_eip = true 的 instance 才建 EIP
   resource "aws_eip" "main" {
     for_each = { for k, v in var.instances : k => v if v.associate_eip }
     instance = aws_instance.main[each.key].id
   }
   ```

4. **Data source 去重**
   ```hcl
   # 多台機器可能用不同架構的 AMI，用 toset 去重避免重複查詢
   locals {
     architectures = toset([for inst in var.instances : inst.ami_architecture])
   }
   data "aws_ami" "amazon_linux" {
     for_each = local.architectures
     ...
   }
   # 使用時：data.aws_ami.amazon_linux[each.value.ami_architecture].id
   ```

5. **Outputs 回傳 map**
   ```hcl
   output "instance_ids" {
     value = { for k, v in aws_instance.main : k => v.id }
   }
   ```
   呼叫端用 `module.compute.instance_ids["app"]` 取值。

### Environment 層參數解析模式

Environment 的 `terraform.tfvars` 應使用**人類友善的 key**（如 `subnet_key = "a"`），而非寫死 resource ID。在 `main.tf` 的 `locals` 中解析：

```hcl
# environments/prod/variables.tf — 呼叫端 schema
variable "instances" {
  type = map(object({
    subnet_key       = string                        # "a" or "b"
    subnet_type      = optional(string, "public")    # "public" or "private"
    instance_type    = string
    instance_name    = string
    root_volume_size = optional(number, 20)
    associate_eip    = optional(bool, true)
  }))
}

# environments/prod/main.tf — 解析為 module 需要的 subnet_id
locals {
  resolved_instances = {
    for k, v in var.instances : k => {
      subnet_id        = v.subnet_type == "public" ? module.networking.public_subnet_ids[v.subnet_key] : module.networking.private_subnet_ids[v.subnet_key]
      instance_type    = v.instance_type
      instance_name    = v.instance_name
      root_volume_size = v.root_volume_size
      associate_eip    = v.associate_eip
    }
  }
}

module "compute" {
  source    = "../../modules/compute"
  instances = local.resolved_instances
  ...
}
```

**好處**：
- `terraform.tfvars` 不依賴其他 resource 的 ID，更直觀、更容易維護
- Module 接收的是標準 `subnet_id`，保持通用性
- 解析邏輯集中在 environment 層的 `locals`，不汙染 module

---

## Variable Value Placement Guide

在 directory-per-environment 結構中，每個環境有獨立的 `main.tf` + `terraform.tfvars`。以下指南幫助團隊統一決策。

### 分類原則

問自己：**「如果要加一個新環境，這個值會不會變？」**

```
會變 → terraform.tfvars（透過 var.* 引用）
不會變 → main.tf 硬編碼或 locals 均可
不確定 → 放 tfvars（多一個變數的成本遠低於日後重構）
```

### 分類對照表

| 值的類型 | 建議位置 | 範例 |
|---------|---------|------|
| 專案/環境識別 | tfvars | `project_id`, `region`, `zone` |
| 資源規格（CPU、記憶體、磁碟） | tfvars | `machine_type`, `cloud_sql_tier`, `disk_size` |
| 網路拓撲（CIDR、子網） | tfvars | `subnets = { "subnet-vm" = { cidr = "10.10.2.0/24" } }` |
| IP 白名單、IAM 成員 | tfvars | `ssh_allow_source_ranges`, `iap_members` |
| 域名、憑證 | tfvars | `certificate_domains = { "app" = { domain = "example.com" } }` |
| 資源開關（備份、刪除保護） | tfvars | `backup_enabled`, `deletion_protection` |
| 架構命名慣例 | tfvars 或 main.tf 均可 | `vpc_name = "vpc-gaming"` |
| 固定的架構開關 | main.tf | `enable_private_service_access = true` |
| 固定的標籤/tag | main.tf | `iap_ssh_target_tags = ["allow-iap-ssh"]` |
| Module 間的接線 | main.tf | `network_id = module.networking.vpc_id` |
| 衍生值 | locals | `name_prefix = "${var.project}-${var.env}"` |

### tfvars 在 directory-per-env 下的額外價值

即使每個環境有獨立的 main.tf，tfvars 在以下場景仍有獨特作用：

| 場景 | 說明 |
|------|------|
| 同環境多組配置切換 | `terraform apply -var-file=loadtest.tfvars` vs 正常配置 |
| 敏感值不進 git | tfvars 加入 `.gitignore`，main.tf 留在版控 |
| CI/CD 動態注入 | 用 `TF_VAR_*` 環境變數或 `-var-file` 注入 |

### 實際案例：compute instances 的 subnet 引用

`terraform.tfvars` 不能引用其他 resource 的輸出（如 `module.networking.subnet_ids`）。解法是在 tfvars 用人類友善的 key，在 main.tf 的 `locals` 或 `for` 表達式中解析：

```hcl
# terraform.tfvars — 用 subnet_key 而非 subnet_id
compute_instances = {
  "app-vm" = {
    machine_type = "e2-standard-4"
    subnet_key   = "subnet-vm"       # 人類友善的 key
    tags         = ["allow-http"]
  }
}

# main.tf — for 表達式解析為實際 subnet_id
module "compute" {
  source = "../../modules/compute"
  instances = {
    for name, inst in var.compute_instances : name => {
      machine_type = inst.machine_type
      subnet_id    = module.networking.subnet_ids[inst.subnet_key]
      tags         = inst.tags
    }
  }
}
```

### 官方來源

- [Input Variables](https://developer.hashicorp.com/terraform/language/values/variables) — tfvars 的定義與用法
- [Variables Tutorial](https://developer.hashicorp.com/terraform/tutorials/configuration-language/variables) — 何時用 variable 何時硬編碼
- [Local Values](https://developer.hashicorp.com/terraform/language/values/locals) — locals 的適用場景與注意事項
- [Standard Module Structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure) — 模組檔案結構

---

## Module Versioning

For registry modules, pin exact versions:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"
  # ...
}
```

For local modules, use relative paths:

```hcl
module "networking" {
  source = "../../modules/networking"
}
```
