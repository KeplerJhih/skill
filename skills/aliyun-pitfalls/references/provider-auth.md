## 🔌 Provider 與認證

### 1. Provider 漂移到 cn-beijing

**現象**：tfvars 寫 `ap-northeast-1`，但 apply 後資源跑到 `cn-beijing`。

**原因**：lock 檔同時鎖了 `aliyun/alicloud` **跟** legacy `hashicorp/alicloud`。某些 resource 走舊版 provider，舊版的預設 region fallback 是 cn-beijing。

**確認**：
```bash
terraform providers
# 若看到：
# Providers required by state:
#     provider[registry.terraform.io/hashicorp/alicloud]   ← 中招！
```

**修復**：
```bash
# 1. State 內的 provider reference 替換
terraform state replace-provider hashicorp/alicloud aliyun/alicloud

# 2. 清掉 lock + cache
rm -rf .terraform .terraform.lock.hcl

# 3. 確保每個 module 都有 versions.tf 顯式宣告
cat > modules/<m>/versions.tf <<'EOF'
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.220"
    }
  }
}
EOF

# 4. 重新 init
terraform init -upgrade
```

**預防**：所有 module 必加 `versions.tf`；root 的 `providers.tf` 也要明確宣告 `aliyun/alicloud`。

---

### 2. 認證問題 — OSS backend 拿不到 AK

**現象**：
```
Error: Failed to get existing workspaces: oss: service returned error:
StatusCode=400, ErrorCode=InvalidArgument,
ErrorMessage="Authorization header is invalid."
```

**原因**：OSS backend **獨立於 provider**，需自己讀認證。`ALICLOUD_PROFILE` 環境變數有時無效。

**修復**：在 `backend.tf` 顯式設 `profile`：
```hcl
terraform {
  backend "oss" {
    bucket  = "..."
    region  = "ap-northeast-1"
    profile = "default"   # ← 加這行
  }
}
```

Provider 也要：
```hcl
provider "alicloud" {
  region  = var.region
  profile = "default"   # ← 加這行
}
```

設好後**不用任何環境變數**，直接跑 `terraform plan` 就會用 `aliyun configure` 的認證。

---

### 3. 子帳號 (RAM User) 權限不足

**現象**：CLI/TF 操作部分 API 報 `NoPermission`。

**最低權限套餐**（給 RAM 子帳號跑 TF 用）：
- `AliyunVPCFullAccess` — VPC / vSwitch / EIP / NAT
- `AliyunCSFullAccess` — ACK 集群
- `AliyunContainerRegistryFullAccess` — ACR
- `AliyunRAMFullAccess` — ACK 建 worker role 需要
- `AliyunOSSFullAccess` — state bucket
- `AliyunECSFullAccess` — 節點
- `AliyunSLBFullAccess` — API SLB

**不會給子帳號的**：
- `AliyunBSSFullAccess`（計費）— 釋放 ACR EE 等付費資源需要，通常只主帳號有
- 服務角色 (SLR) 授權 — 必須主帳號點連結

---
