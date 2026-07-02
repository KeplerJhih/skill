## 🚀 ACK (Container Service for Kubernetes)

### 4. 首次建 NodePool 缺 SLR

**現象**：
```
Code: MissingAuth.AliyunOOSLifecycleHook4CSRole
Message: please complete the AliyunOOSLifecycleHook4CSRole ramrole authorization at
https://ram.console.alibabacloud.com/role/authorize?...
```

**原因**：ACK NodePool 自動擴縮容靠 OOS（運維編排）服務，**第一次用** 需明確授權服務角色。

**修復**：點錯誤訊息給的連結（**用主帳號**）→ 一鍵授權。整個阿里雲帳號**做一次就好**。

通用連結（可放筆記裡）：
```
https://ram.console.alibabacloud.com/role/authorize?request=%7B%22Services%22%3A%5B%7B%22Roles%22%3A%5B%7B%22RoleName%22%3A%22AliyunOOSLifecycleHook4CSRole%22%2C%22TemplateId%22%3A%22AliyunOOSLifecycleHook4CSRole%22%7D%5D%2C%22Service%22%3A%22OOS%22%7D%5D%7D
```

---

### 5. AliyunLinux3 image 不支援 cgroup v2

**現象**：
```
Code: InvalidImageId.NotFound
Message: The specified image aliyun_3_x64_20G_alibase_20251215.vhd does not support cgroup v2
```

**原因**：K8s 1.30+ 預設用 cgroup v2，但 `AliyunLinux3` (預設) 的標準鏡像太舊不支援。

**修復**：image_type 改成 `AliyunLinux3ContainerOptimized`：

```hcl
resource "alicloud_cs_kubernetes_node_pool" "main" {
  image_type = "AliyunLinux3ContainerOptimized"  # ← 必須
  ...
}
```

---

### 6. Terway ENI IP 不足

**現象**：
```
Code: InsufficientInstanceIP
Message: insufficient ENI IP address of instance type ecs.xxx.large for terway
```

**原因**：每台 ECS 能掛幾張網卡 (ENI) + 每張網卡能掛幾個次要 IP 是**硬體限制**。terway-eniip 模式下每個 pod 用一個次要 IP，小規格實例直接 IP 耗盡。

**規格參考**（terway-eniip 場景）：

| 規格 | CPU/RAM | ENI x IP/ENI | 適合最多 pod | 評價 |
|------|---------|--------------|-------------|------|
| ecs.u1-c1m4.large | 2c4g | 2 x 2 = 4 | ❌ 跑不起來 |
| ecs.u2a-c1m2.xlarge | 4c8g | 2 x 4 = 8 | ⚠️ 勉強 |
| **ecs.g7a.xlarge** | 4c16g | 3 x 10 = 30 | ✅ 推薦 |
| ecs.c7a.xlarge | 4c8g | **~48**（非 18） | ✅ 省 RAM |
| ecs.g7a.2xlarge | 8c32g | 4 x 20 = 80 | ✅ 大集群 |

> ⚠️ **修正（2026-06-29 實查 `DescribeInstanceTypes`）**：c7a.xlarge POD_CAP **≈48，不是 18**（18 其實是 `u2a-c1m2.xlarge` 的值，上表曾誤植，與本檔下方 #26 實測 48 一致）。c 系列 **2xlarge**（c8i/c9i/c8a/c9a）ENI 4×15、POD_CAP **≈45，與 g 系列 2xlarge 同級** —— 「c 系列 pod cap 低」的舊印象**不成立**。prod 已改用 c9i.2xlarge 單池（見 terraform `CLAUDE.md` NodePool 段 + 踩坑 #13）。

**修復路徑（按推薦度）**：

1. **升大實例**（最簡單）：`.large` → `.xlarge` 以上
2. **開 ENI Trunking**（最省錢）：每 ENI 可掛多個分支 ENI，pod 容量暴增 100+
   - ACK 控制台 → 組件管理 → terway-eniip → 編輯 → `ENITrunking: "true"`
3. **切 IPVlan 模式**：pod 共享 node IP，無 IP 限制（但 CNI 行為改變，謹慎）
4. **加入多個 fallback instance type**：
   ```hcl
   instance_types = ["ecs.g7a.xlarge", "ecs.c7a.xlarge", "ecs.g9i.xlarge"]
   ```

**避免使用**：
- ❌ `t6 / e / t5 / u1-c1m4` 系列 — ENI 容量不足
- ⚠️ `u1 / u2 / u2a` 系列 — 經濟款，xlarge 才勉強

---

### 7. NodePool instance type 沒庫存

**現象**：
```
Code: RecommendEmpty.InstanceTypeNoStock
Message: The instanceTypes are out of usage
```

**修復**：給多個 fallback：
```hcl
instance_types = [
  "ecs.g7a.xlarge",
  "ecs.c7a.xlarge",
  "ecs.g9i.xlarge",
]
```

阿里雲會挑第一個有庫存的建。

**怎麼查當前有什麼可用**：
```bash
aliyun ecs DescribeAvailableResource \
  --RegionId ap-northeast-1 --ZoneId ap-northeast-1b \
  --DestinationResource InstanceType --InstanceChargeType PostPaid \
  --Cores 4 --Memory 16
```

---

### 8. `load_balancer_spec` 廢棄

**現象**：
```
Warning: "load_balancer_spec": [DEPRECATED] Field 'load_balancer_spec' has been deprecated
from provider version 1.232.0. The spec will not take effect because the charge of the
load balancer has been changed to PayByCLCU
```

**修復**：直接從 `alicloud_cs_managed_kubernetes` 移除 `load_balancer_spec` 參數。SLB 改 LCU（容量單位）計費，TF 不用管。

---

### 9. `worker_vswitch_ids` 廢棄

**現象**：
```
Warning: "worker_vswitch_ids": [DEPRECATED] from provider version 1.241.0.
Please use 'vswitch_ids' to managed control plane vswtiches
```

**修復**：`worker_vswitch_ids` → `vswitch_ids`（用於 control plane）。NodePool 內的 `vswitch_ids` 仍叫 `vswitch_ids` 沒變。

---

### 10. `version` 是 Terraform module 保留字

**現象**：
```
Error: Variables not allowed
on main.tf line 68, in module "ack":
  version = var.ack_version
Variables may not be used here.
```

**原因**：Terraform 的 `module { }` block 中，`version` 是給 registry module 用的保留字段，**不能拿來傳變數**。

**修復**：rename 變數，例如 `kubernetes_version`：
```hcl
# modules/ack/variables.tf
variable "kubernetes_version" {  # 不要叫 "version"
  type = string
}

# environments/prod/main.tf
module "ack" {
  ...
  kubernetes_version = var.ack_version  # ✅
}
```

---

### 25. NodePool `enable_autoscaling = true → false` 轉換被 API 拒絕

**現象**：
```
Error: ... InvalidDesiredSizeOrCount.NotNull
Code: 400
Message: Desired size is not allowed for autoscaling-enabled nodepool
```

當你把 tfvars 中某個 pool 從：
```hcl
enable_autoscaling = true
min_size           = 1
max_size           = 3
```
改成：
```hcl
enable_autoscaling = false
desired_size       = 1
```
跑 `terraform apply` → ACK API 拒絕。

**原因**：

Aliyun ACK API **不支援在一個 PUT call 內同時「關 autoscaling」+「設 desired_size」**。terraform provider 把這兩件事打包成單一 update 送過去，API 看到請求時自己後台 state 仍是「autoscaling enabled」→ 「enabled 的 pool 不能直接設 desired_size」→ 拒絕。

這是 terraform alicloud provider 對「autoscaling true→false 轉換」沒處理好。

**修復（推薦）**：**不要真的關 autoscaling**，改用 `min_size = max_size = 1` 鎖死：

```hcl
default = {
  enable_autoscaling = true
  min_size           = 1
  max_size           = 1  # ← 鎖死 1 台
  scaling_type       = "cpu"
}
```

效果：
- autoscaler 跑著、評估著、但不能 add（已 max）也不能 remove（已 min）
- 永遠 1 台
- 之後想開回彈性 → 直接改 `max_size = 3` apply（true→true 不會撞陷阱）

**緊急修復（已踩坑要回到正軌）**：

如果不小心已經改了 tfvars 且卡住，先用 aliyun CLI 把 ACK 那邊強制關 autoscaling，再 apply 對齊：

```bash
# 強制關掉，讓 cloud state 跟 tfvars 一致
aliyun cs PUT /clusters/<cluster_id>/nodepools/<np_id> \
  --header "Content-Type=application/json" \
  --body '{"auto_scaling":{"enable":false}}'

# 等 30s 後
terraform apply
```

然後**改用上面的 trick**（min=max=1）回到 autoscaling=true 路線，永遠不要再做這個轉換。

**設計教訓**：把「鎖死 N 台」當成 autoscaling 的特例（min=max=N），不要當成「關掉 autoscaling」的功能。Aliyun 的 autoscaling toggle 不是 idempotent friendly。

---

### 26. `instance_types` fallback 順序 + AZ 庫存差異 → autoscaler 隨機抓到低 ENI 機型

**現象**：

幾個新 pod 排不上、`kubectl describe pod` 看到：

```
0/3 nodes are available: 1 Too many pods, 2 Insufficient cpu.
NotTriggerScaleUp: pod didn't trigger scale-up
                   (it wouldn't fit if a new node is added):
                   1 can't increase node group size
```

明明已 `max_size=3`，autoscaler 卻不擴容；觀察 node 規格：

```
node                          INSTANCE_TYPE         ZONE   POD_CAP
192.168.0.247                 ecs.c7a.xlarge        1b     48 ✅
192.168.0.110                 ecs.c7a.xlarge        1b     48 ✅
192.168.1.6                   ecs.u2a-c1m2.xlarge   1c     18 ❌
```

`u2a` 那台 pod cap 只有 c7a 的 3 分之 1。

**根因**：

`ack_node_pools.default.instance_types` 是 **fallback list**，autoscaler 在目標 AZ 按列表順序試，**取第一個可用的**。當 tfvars 寫：

```hcl
instance_types = [
  "ecs.u2a-c1m2.xlarge", # ← 第一個！經濟款
  "ecs.c9a.xlarge",
  "ecs.c7a.xlarge",
  "ecs.c9i.xlarge"
]
```

zone-b 庫存豐富時抓 c7a，zone-c 庫存緊張時 fallback 到 u2a → 拿到 **POD_CAP=18** 的 node，新 pod 全卡 Pending。

且 ENI Trunking 已開（`enable_eni_trunking: true`）也救不了 u2a — Trunking 給 c7a 是 ×3 跳到 48，給 u2a 只有 18（u 系列 vCPU 弱 → ENI 限制低）。

**修法**：

```hcl
instance_types = [
  "ecs.c7a.xlarge",  # 4c8g, AMD Zen3 ✅ 首選
  "ecs.c9a.xlarge",  # 4c8g, AMD Zen4
  "ecs.c9i.xlarge",  # 4c8g, Intel
  # ⚠️ 不放 u2a / u1 系列：便宜 ~30% 但 POD_CAP 只有 ~18
  #   差價對 UAT 不值得，prod 完全不能放
]
```

修完 + 砍掉舊 u2a node：

```bash
kubectl drain <u2a-node> --ignore-daemonsets --delete-emptydir-data --force
kubectl delete node <u2a-node>
# autoscaler 偵測 desired_size 不足 → 補新 node（這次按新 instance_types 抓 c7a）
```

**設計教訓**：

1. **`instance_types` 不要按「便宜」排** — 同一規格內，**ENI 容量差很大**，autoscaler 在不同 AZ 抓哪個是隨機的
2. **u / e / t 系列在 K8s 場景儘量不用** — 經濟款設計給 web server / dev 環境，ENI 配額被閹割
3. **避免「混合規格」陷阱**：節點規格不一致時，「為什麼這 node 排不上」之類 debug 會浪費好幾小時
4. **新 node 起來先驗證 POD_CAP**：`kubectl get nodes -o custom-columns=NAME:.metadata.name,POD_CAP:.status.allocatable.pods`，48 才及格

---
