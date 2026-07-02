## 🖥 ECS / 實例（Instance）

### 30. ECS image 用 data source 抓「最新」→ 阿里雲一發新 image 就想重裝系統盤（資料全毀）

**現象**：

明明沒改任何 tfvars，`terraform plan` 卻冒出（每當阿里雲發布新 OS image 後）：

```
# module.infra_vm[0].alicloud_instance.main will be updated in-place
  ~ image_id = "ubuntu_24_04_x64_20G_alibase_20260506.vhd"
            -> "ubuntu_24_04_x64_20G_alibase_20260522.vhd"

Plan: 0 to add, 1 to change, 0 to destroy.
```

**⚠️「0 to destroy」是假象**：`alicloud_instance` 改 `image_id` = 阿里雲執行 **ReplaceSystemDisk（重裝系統盤）**。Terraform 視角是 in-place（instance id 不變），但**系統盤會被重裝、上面的資料全毀**。對「單一系統盤又承載資料」的 VM（如 infra-vm 跑 mysql/redis/kafka/es 全在系統盤），一 apply 就是災難。判斷準則：**「0 to destroy」只代表沒有 TF 資源被刪，不代表沒有資料損失。**

**根因**：

module 把 image_id 綁在「永遠抓最新」的 data source：

```hcl
data "alicloud_images" "ubuntu" {
  owners      = "system"
  name_regex  = "^ubuntu_24_04_x64_20G_alibase"
  most_recent = true                                   # ← 每次 plan 都回傳當下最新那張
}
resource "alicloud_instance" "main" {
  image_id = data.alicloud_images.ubuntu.images[0].id  # ← images[0] = 最新
}
```

VM 建立時拿到 A 版 → 阿里雲後來發 B 版 → data source 回 B → 跟 state 的 A 不一致 → plan 想「修正」成 B（重裝）。**會反覆發生**，每發一次新 image 冒一次。

**修復（已建好、承載資料的 VM）**：

```hcl
resource "alicloud_instance" "main" {
  image_id = data.alicloud_images.ubuntu.images[0].id
  lifecycle {
    ignore_changes = [image_id]   # 已建的 VM 不因新 image 重裝；真要換 image 重建時再臨時移除
  }
}
```

`ignore_changes` 是 **plan 時就生效**的 meta 參數，加上去那一刻起就不再追新 image（不必 apply 才算數）。

**設計教訓 / 規範（重要）**：

- **VM image 不要預設追最新**。`most_recent = true` + `images[0]` 只適合「first apply 當下取一張」，**不適合長期持有的 VM**。
- **🔴 選 image 要先跟使用者確認**：建立任何 VM 時，image 選擇（追最新 vs pin 特定版本）**一律先問使用者**，不要默默 `most_recent`。承載資料的 stateful VM 必須 pin 或 `ignore_changes=[image_id]`。
- pin 法：`image_id = var.image_id`（tfvars 給定版本字串），或 data source 取得後第一次 apply、之後 `ignore_changes`。
- 同理警惕其他「data source 抓最新」的欄位（最新 K8s 版本、最新規格碼…）都可能造成非預期 drift；prod 一律 pin。

---
