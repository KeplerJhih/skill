# Aliyun Terraform Patterns

阿里雲 (Aliyun / Alibaba Cloud) 常用資源範本。本文件假設**國際版帳號**（ap-northeast-1 / ap-southeast-1 等），大陸區 (cn-*) 需額外的中國實名認證。

> ⚠️ **務必同時參考** [`aliyun-pitfalls`](../../aliyun-pitfalls/SKILL.md) skill — 列出 provider 漂移、ENI IP 不足、各種一次性 RAM 授權等坑。

---

## Provider 設定

```hcl
# providers.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"   # 必須用 aliyun/alicloud，不可用 legacy hashicorp/alicloud
      version = "~> 1.220"
    }
  }
}

provider "alicloud" {
  region  = var.region
  profile = "default"   # 讀取 ~/.aliyun/config.json（與 aliyun CLI 共用）
}
```

**關鍵**：
- 每個 module 都要顯式宣告 `required_providers`（建一個 `versions.tf`），否則 lock 檔可能殘留 legacy provider 引用
- `profile = "default"` 配合 `aliyun configure`，免去 ALICLOUD_ACCESS_KEY/SECRET 環境變數

### 子 module 必加的 versions.tf

```hcl
# modules/<any>/versions.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.220"
    }
  }
}
```

---

## OSS Backend（state 存阿里雲）

```hcl
# backend.tf
terraform {
  backend "oss" {
    bucket  = "<project>-tfstate-<region-short>"
    prefix  = "<env>"             # uat / prod / staging
    key     = "terraform.tfstate"
    region  = "ap-northeast-1"
    encrypt = true                # SSE-OSS 加密
    profile = "default"           # 跟 provider 共用 ~/.aliyun/config.json
  }
}
```

**Bootstrap 流程**：
```bash
# 1. 建 bucket（注意要用 region endpoint）
aliyun oss mb oss://<project>-tfstate-<region-short> --region <region> --acl private

# 2. 開 versioning（state 安全保險）
aliyun oss bucket-versioning --method put \
  oss://<project>-tfstate-<region-short> Enabled \
  --endpoint oss-<region>.aliyuncs.com

# 3. 啟用 backend
terraform init -migrate-state    # 從 local 遷移到 OSS
```

---

## VPC + vSwitch（多 AZ）

```hcl
# modules/vpc/main.tf
resource "alicloud_vpc" "main" {
  vpc_name   = var.vpc_name
  cidr_block = var.vpc_cidr      # 例：192.168.0.0/16

  tags = merge(var.tags, { Name = var.vpc_name })
}

resource "alicloud_vswitch" "main" {
  for_each = var.vswitches      # map(object({ zone_id, cidr }))

  vpc_id       = alicloud_vpc.main.id
  zone_id      = each.value.zone_id
  cidr_block   = each.value.cidr
  vswitch_name = "${var.project}-${var.environment}-vsw-${each.key}"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-vsw-${each.key}"
    Zone = each.value.zone_id
  })
}
```

`var.vswitches` 範例（tfvars）：
```hcl
vswitches = {
  b = { zone_id = "ap-northeast-1b", cidr = "192.168.0.0/24" }
  c = { zone_id = "ap-northeast-1c", cidr = "192.168.1.0/24" }
}
```

**vSwitch 大小考量**：
- /24 = 251 個可用 IP（足夠中小型集群）
- terway-eniip 下，Pod 從 worker vSwitch 同段拿 secondary IP
- 預計超過 200 個 pod，建 /22 或新建額外 vSwitch
- 真正的瓶頸通常是 **ECS 實例的 ENI 容量**，不是 vSwitch CIDR

---

## NAT Gateway + EIP（統一出站）

```hcl
# modules/nat/main.tf
resource "alicloud_nat_gateway" "main" {
  vpc_id           = var.vpc_id
  vswitch_id       = var.vswitch_id
  nat_gateway_name = var.nat_name
  nat_type         = "Enhanced"   # 推薦：Enhanced 不 Normal
  payment_type     = "PayAsYouGo"
}

resource "alicloud_eip_address" "main" {
  address_name         = "${var.nat_name}-eip"
  bandwidth            = var.eip_bandwidth         # 100~200 Mbps
  internet_charge_type = "PayByTraffic"            # 按流量計費（彈性帶寬）
  payment_type         = "PayAsYouGo"
}

resource "alicloud_eip_association" "main" {
  allocation_id = alicloud_eip_address.main.id
  instance_id   = alicloud_nat_gateway.main.id
  instance_type = "Nat"
}

# 每個 vSwitch CIDR 一條 SNAT entry → 統一走 NAT 出網
resource "alicloud_snat_entry" "main" {
  for_each = var.snat_source_cidrs    # map(string)

  snat_table_id   = alicloud_nat_gateway.main.snat_table_ids
  source_cidr     = each.value
  snat_ip         = alicloud_eip_address.main.ip_address
  snat_entry_name = "${var.nat_name}-snat-${each.key}"
  depends_on      = [alicloud_eip_association.main]
}
```

**EIP 計費三選一**：
| Mode | 計費 | 適用 |
|------|------|------|
| **PayByTraffic** | 按 GB 出網收費，帶寬上限免費 | 流量不固定（推薦） |
| **PayByBandwidth** | 按帶寬大小收，流量免費 | 流量穩定且高 |
| **共享帶寬包 CBWP** | 多 EIP 共享帶寬池 | 多 EIP 削峰填谷 |

PayByTraffic 單 EIP 帶寬上限 **200 Mbps**，超過要用 CBWP。

**重要**：snat_source_cidrs 在 root main.tf 傳入時，**避免用 module.vpc.vswitch_cidrs 的 computed 輸出**（for_each 會卡住），改成靜態：
```hcl
snat_source_cidrs = { for k, v in var.vswitches : k => v.cidr }
```

---

## ACR EE (Container Registry Enterprise Edition)

```hcl
# modules/acr/main.tf
resource "alicloud_cr_ee_instance" "main" {
  instance_name  = var.instance_name
  instance_type  = var.instance_type    # 用 legacy 名: Basic / Standard / Advanced
                                        # 雖然控制台顯示 Enterprise_Economy 等新名，
                                        # 但 TF provider 校驗器只認 legacy 名
  payment_type   = var.payment_type     # Subscription / PayAsYouGo
  period         = var.payment_type == "Subscription" ? var.period : null
  renewal_status = var.payment_type == "Subscription" ? "ManualRenewal" : null

  # ⚠️ 此資源不支援 tags
  lifecycle {
    # 既有實例 import 後，provider 校驗會撞 Enterprise_Economy ≠ Basic
    ignore_changes = [instance_type, payment_type, period]
  }
}

# Namespace（auto_create = true 讓 docker push 自動建 repo）
resource "alicloud_cr_ee_namespace" "main" {
  for_each = var.namespaces

  instance_id        = alicloud_cr_ee_instance.main.id
  name               = each.key
  auto_create        = each.value.auto_create
  default_visibility = each.value.default_visibility   # PRIVATE / PUBLIC
}

# VPC 內網訪問入口（讓 ACK 從內網拉鏡像，免走公網）
resource "alicloud_cr_vpc_endpoint_linked_vpc" "main" {
  for_each = var.linked_vpc

  instance_id = alicloud_cr_ee_instance.main.id
  vpc_id      = each.value.vpc_id
  vswitch_id  = each.value.vswitch_id
  module_name = "Registry"
}
```

**重要設計選擇**：
- **不要在 TF 管 repo**：repos 隨 `docker push` 自動建，TF 只管 namespace（更簡潔、開發者友善）
- **PayAsYouGo 創建限制**：provider 對 PayAsYouGo 創建支援不完整，多半要先在控制台建好，再 `terraform import`
- **不要 alicloud_cr_endpoint_acl_policy "internet"**：除非實例層級的「公網訪問」已啟用，不然會報 `INSTANCE_ACCESS_ACL_ENTRY_INVALID`

### Import 既有 ACR EE

```bash
terraform import module.acr.alicloud_cr_ee_instance.main cri-xxxxxxxx
terraform import 'module.acr.alicloud_cr_ee_namespace.main["myns"]' 'cri-xxxxxxxx:myns'
terraform import 'module.acr.alicloud_cr_ee_repo.main["myrepo"]' 'cri-xxxxxxxx:myns:myrepo'
```

import 前需暫時清空所有 for_each 依賴 module.vpc 輸出的 block（如 linked_vpc），不然 TF 會抱怨 unknown for_each keys。

---

## ACK Pro Managed + NodePool

```hcl
# modules/ack/main.tf
resource "alicloud_cs_managed_kubernetes" "main" {
  name                = var.cluster_name
  cluster_spec        = var.cluster_spec       # ack.pro.small / .medium / .large
  version             = var.kubernetes_version # null 用最新
  vswitch_ids         = var.worker_vswitch_ids # ← 新名（舊版叫 worker_vswitch_ids）
  pod_vswitch_ids     = var.pod_vswitch_ids
  service_cidr        = var.service_cidr       # 例：172.16.0.0/16
  proxy_mode          = "ipvs"
  deletion_protection = var.deletion_protection
  timezone            = "Asia/Taipei"

  # ❌ load_balancer_spec 在 1.232+ 廢棄（SLB 改 LCU 計費）

  dynamic "addons" {
    for_each = var.addons
    content {
      name     = addons.value.name
      config   = addons.value.config           # JSON string
      disabled = addons.value.disabled
    }
  }

  lifecycle {
    ignore_changes = [
      version,    # 由 ACK 自動升級控制
      addons,     # addons 漂移由 ACK 控制
    ]
  }
}

resource "alicloud_cs_kubernetes_node_pool" "main" {
  for_each = var.node_pools

  cluster_id     = alicloud_cs_managed_kubernetes.main.id
  node_pool_name = "${var.cluster_name}-${each.key}"
  vswitch_ids    = var.worker_vswitch_ids
  instance_types = each.value.instance_types   # list（fallback 用）

  # 自動擴縮容 vs 固定 size
  desired_size = each.value.enable_autoscaling ? null : each.value.desired_size

  dynamic "scaling_config" {
    for_each = each.value.enable_autoscaling ? [1] : []
    content {
      min_size = each.value.min_size
      max_size = each.value.max_size
      type     = each.value.scaling_type        # cpu / gpu / spot
    }
  }

  # 重要：必須用支援 cgroup v2 的 image（K8s 1.30+）
  image_type            = "AliyunLinux3ContainerOptimized"
  system_disk_category  = "cloud_essd"
  system_disk_size      = 120
  runtime_name          = "containerd"
  install_cloud_monitor = true

  # 可選：node labels / taints（搭配 nodeSelector + toleration 做專屬節點池）
  dynamic "labels" {
    for_each = each.value.labels
    content {
      key   = labels.value.key
      value = labels.value.value
    }
  }
  dynamic "taints" {
    for_each = each.value.taints
    content {
      key    = taints.value.key
      value  = taints.value.value
      effect = taints.value.effect
    }
  }
}

# ⭐ Cluster Autoscaler 全域配置（必加，否則 pool 的 enable_autoscaling=true 沒人實作）
# 沒有這個 resource → node_pool 的 enable_autoscaling 變裝飾用，node 不會自動伸縮
resource "alicloud_cs_autoscaling_config" "main" {
  count = var.autoscaler_config != null ? 1 : 0

  cluster_id = alicloud_cs_managed_kubernetes.main.id

  scale_down_enabled            = var.autoscaler_config.scale_down_enabled            # default true
  utilization_threshold         = var.autoscaler_config.utilization_threshold         # "0.5" — node 使用率 < 此值才縮
  cool_down_duration            = var.autoscaler_config.cool_down_duration            # "10m" — 擴容後冷卻時間
  unneeded_duration             = var.autoscaler_config.unneeded_duration             # "10m" — 持續閒置多久才縮
  scan_interval                 = var.autoscaler_config.scan_interval                 # "30s"
  expander                      = var.autoscaler_config.expander                      # "least-waste"
  skip_nodes_with_system_pods   = var.autoscaler_config.skip_nodes_with_system_pods   # default true（最保守，但會擋住 default pool 縮容）
  skip_nodes_with_local_storage = var.autoscaler_config.skip_nodes_with_local_storage # default true
  daemonset_eviction_for_nodes  = var.autoscaler_config.daemonset_eviction_for_nodes  # default false
  max_graceful_termination_sec  = var.autoscaler_config.max_graceful_termination_sec  # 14400
  scaler_type                   = var.autoscaler_config.scaler_type                   # "cluster-autoscaler"

  depends_on = [alicloud_cs_kubernetes_node_pool.main]
}
```

### Autoscaling 模式選擇（重要 — 避開 API 轉換陷阱）

Aliyun ACK API **不支援「autoscaling=true → false」的原子轉換**（見 [`aliyun-pitfalls` #25](../../aliyun-pitfalls/SKILL.md)）。轉換時會撞 `InvalidDesiredSizeOrCount.NotNull`。

**推薦做法**：永遠保持 `enable_autoscaling = true`，用 `min_size = max_size = N` 達成「鎖死 N 台」效果：

```hcl
# tfvars
ack_node_pools = {
  # ----- 鎖死 1 台（省錢模式）-----
  default = {
    enable_autoscaling = true
    min_size           = 1
    max_size           = 1            # ← 鎖死，autoscaler 跑著但不能加減
    scaling_type       = "cpu"
    # ...
  }

  # ----- 彈性 1-3 台（業務模式）-----
  # 只改 max_size = 3 就能切換，永遠不轉 enable_autoscaling 值
}
```

**理由**：
- autoscaler 持續評估，但 `min=max` 鎖死區間 → 永遠不會 add（已 max）、不會 remove（已 min）
- 切換成本：改一個數字，pure terraform apply，無 API 陷阱
- 真要關 autoscaling：先用 aliyun CLI 改 ACK state，再 terraform apply 對齊（不推薦）

**`enable_autoscaling = false` 適用情境**：
- pool 從一開始就要固定 size（never autoscaling）
- 不要從 `true` 切到 `false` — 會撞陷阱

### Instance Type 選擇（4c8g/16g 工作節點）

依**穩定性 + ENI 容量**排序（terway-eniip 場景）：

| 系列 | 範例 | 評價 |
|------|------|------|
| **g7a / g9i**（推薦）| ecs.g7a.xlarge | AMD/Intel 通用，ENI 充足 |
| **c7a / c9a** | ecs.c7a.xlarge | Compute 優化，4c8g 較省 |
| u2a | ecs.u2a-c1m2.xlarge | 經濟款，ENI 容量勉強 |
| ⚠️ u1-c1m4 | ecs.u1-c1m4.large | **ENI IP 不足會 fail** |
| ⚠️ t6 / e | - | 突發性能型，K8s 不推薦 |

**ENI IP 不足解決方案**：
1. 升級到 .xlarge 以上
2. 開 ENI Trunking（addon config: `ENITrunking = "true"`）
3. 切 IPVlan 模式（CNI 行為改變，謹慎）

### 必備 Addons

```hcl
addons = [
  { name = "terway-eniip" },                    # CNI（必須）
  { name = "csi-plugin" },                      # 存儲驅動
  { name = "logtail-ds" },                      # SLS 日誌
  { name = "alicloud-monitor-controller" },     # CloudMonitor
  { name = "aliyun-acr-credential-helper" },    # ⭐ ACR EE 免密拉鏡像
  { name = "nginx-ingress-controller", disabled = true },  # 用 ALB 取代
]
```

### 一次性 RAM 授權（apply 前準備）

ACK NodePool 首次建立需要這個 SLR（service-linked role）：
- **AliyunOOSLifecycleHook4CSRole**

點開連結授權一次即可（主帳號）：
```
https://ram.console.alibabacloud.com/role/authorize?request=%7B%22Services%22%3A%5B%7B%22Roles%22%3A%5B%7B%22RoleName%22%3A%22AliyunOOSLifecycleHook4CSRole%22%2C%22TemplateId%22%3A%22AliyunOOSLifecycleHook4CSRole%22%7D%5D%2C%22Service%22%3A%22OOS%22%7D%5D%7D
```

---

## ACK + ACR 免密拉鏡像（K8s 端設定）

TF 建好集群後，**手動建這個 ConfigMap** 才能讓 EE 鏡像免密：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: acr-configuration
  namespace: kube-system
data:
  service-account: "default"
  watch-namespace: "all"
  expiring-threshold: "15m"
  acr-api-version: "v1"
  acr-registry-info: |
    - instanceId: "cri-xxxxxxxx"             # ACR EE 實例 ID
      regionId: "ap-northeast-1"
      domains: "<vpc-domain>,<public-domain>"  # 都列上
```

> 詳見 [`aliyun-pitfalls`](../../aliyun-pitfalls/SKILL.md) 的「ACR EE 免密拉鏡像必填配置」段落。

---

## 完整 root main.tf 範本

```hcl
locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

module "vpc" {
  source      = "../../modules/vpc"
  project     = var.project
  environment = var.environment
  vpc_name    = var.vpc_name
  vpc_cidr    = var.vpc_cidr
  vswitches   = var.vswitches
  tags        = local.common_tags
}

module "nat" {
  source      = "../../modules/nat"
  project     = var.project
  environment = var.environment
  nat_name    = var.nat_name
  vpc_id      = module.vpc.vpc_id
  vswitch_id  = module.vpc.vswitch_ids[var.nat_attached_vswitch_key]
  # ❗ for_each 友善：用 var 不用 module computed output
  snat_source_cidrs = { for k, v in var.vswitches : k => v.cidr }
  eip_bandwidth     = var.eip_bandwidth
  tags              = local.common_tags
}

module "acr" {
  source        = "../../modules/acr"
  project       = var.project
  environment   = var.environment
  instance_name = var.acr_instance_name
  instance_type = var.acr_instance_type   # Basic（legacy）
  payment_type  = var.acr_payment_type
  namespaces    = var.acr_namespaces

  linked_vpc = {
    main = {
      vpc_id     = module.vpc.vpc_id
      vswitch_id = module.vpc.vswitch_ids[var.acr_linked_vswitch_key]
    }
  }
  tags = local.common_tags
}

module "ack" {
  source             = "../../modules/ack"
  project            = var.project
  environment        = var.environment
  cluster_name       = var.ack_cluster_name
  cluster_spec       = var.ack_cluster_spec
  kubernetes_version = var.ack_version   # 注意：不能叫 var.version（保留字）
  vpc_id             = module.vpc.vpc_id
  worker_vswitch_ids = [for k, v in module.vpc.vswitch_ids : v]
  pod_vswitch_ids    = [for k, v in module.vpc.vswitch_ids : v]

  deletion_protection = var.ack_deletion_protection
  node_pools          = var.ack_node_pools
  tags                = local.common_tags

  depends_on = [module.nat]  # 節點要走 NAT 出網拉系統鏡像
}
```

---

## tfvars 完整範例

```hcl
project     = "myproject"
environment = "uat"
region      = "ap-northeast-1"

vpc_name = "vpc_myproject"
vpc_cidr = "192.168.0.0/16"
vswitches = {
  b = { zone_id = "ap-northeast-1b", cidr = "192.168.0.0/24" }
  c = { zone_id = "ap-northeast-1c", cidr = "192.168.1.0/24" }
}

nat_name                 = "nat-myproject"
nat_attached_vswitch_key = "b"
eip_bandwidth            = 200

acr_instance_name      = "acr-myproject"
acr_instance_type      = "Basic"           # 別寫 Enterprise_Economy
acr_payment_type       = "Subscription"    # PayAsYouGo provider 創建支援差
acr_linked_vswitch_key = "b"
acr_namespaces = {
  myproject = { auto_create = true, default_visibility = "PRIVATE" }
}

ack_cluster_name        = "ack-myproject"
ack_cluster_spec        = "ack.pro.small"
ack_version             = null
ack_deletion_protection = true

ack_node_pools = {
  default = {
    instance_types        = ["ecs.g7a.xlarge", "ecs.c7a.xlarge"]
    enable_autoscaling    = true
    min_size              = 1
    max_size              = 4
    scaling_type          = "cpu"
    image_type            = "AliyunLinux3ContainerOptimized"
    system_disk_category  = "cloud_essd"
    system_disk_size      = 120
    install_cloud_monitor = true
    runtime_name          = "containerd"
    labels                = []
    taints                = []
  }
}

tags = {
  Project     = "myproject"
  Environment = "uat"
  ManagedBy   = "terraform"
  Region      = "ap-northeast-1"
}
```

---

## 命名規範

| 資源類型 | 命名範例 | 備註 |
|---------|---------|------|
| VPC | `vpc_{project}` | 用 underscore（阿里雲控制台慣例）|
| vSwitch | `{project}-{env}-vsw-{az}` | dash |
| NAT | `nat-{purpose}-{project}` | |
| EIP | `{nat-name}-eip` | NAT 對應 EIP 一對一 |
| ACR EE | `acr-{project}` | |
| ACR Namespace | `{project}` | 開發者 push 直接用 |
| ACK Cluster | `ack-{project}` 或 `ack-{project}-{env}` | |
| NodePool | `{cluster}-{role}` 例 `ack-myproject-default` | |

---

## 認證與權限速查

| 動作 | 子帳號是否需額外權限 |
|------|---------------------|
| 創 VPC / vSwitch / SG | AliyunVPCFullAccess |
| 創 NAT / EIP | AliyunVPCFullAccess + AliyunEIPFullAccess |
| 創 ACR EE | AliyunBSSFullAccess（計費）|
| 刪 ACR EE（付費）| 通常只有主帳號可釋放 |
| 創 ACK 集群 | AliyunCSFullAccess + AliyunRAMFullAccess（建 worker role）|
| 創 NodePool 首次 | AliyunOOSLifecycleHook4CSRole SLR 一次性授權 |
| Worker → ACR 拉鏡像 | 不用手動，credential-helper + EE 信任自動處理 |
| OSS state bucket | AliyunOSSFullAccess |

子帳號 (RAM User) 跑 TF 時，最少給：
- `AliyunVPCFullAccess`
- `AliyunCSFullAccess`
- `AliyunContainerRegistryFullAccess`
- `AliyunRAMFullAccess`
- `AliyunOSSFullAccess`

---

## 必看：與其他文件的關聯

- **`module-conventions.md`** — for_each、optional() 等模組設計模式
- **`security-checklist.md`** — Security Group / 公網訪問檢查
- **`aliyun-pitfalls/SKILL.md`** — 完整踩坑紀錄（強烈建議搭配讀）
