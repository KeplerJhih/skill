## 📦 ACR (Container Registry)

### 11. ACR EE 免密拉鏡像必填配置

**現象**：
```
pull access denied, repository does not exist or may require authorization:
server message: insufficient_scope: authorization failed
```

**原因**：ACR **企業版** 與個人版設計不同：
- 個人版：插件自動發現，免設定
- **企業版**：因為一個帳號可有多個 EE 實例，插件不會自動猜，**必須**在 `kube-system/acr-configuration` ConfigMap 顯式列出 `instanceId`

**修復**：
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
    - instanceId: "cri-xxxxxxxx"        # ← 必填
      regionId: "ap-northeast-1"
      domains: "acr-xxx-registry-vpc.<region>.cr.aliyuncs.com,acr-xxx-registry.<region>.cr.aliyuncs.com"
```

> 注意：新版 `managed-aliyun-acr-credential-helper` 完全跑在阿里雲 control plane 側，集群裡看不到 pod。但 ConfigMap 一樣要建在 `kube-system`。

---

### 12. ACR EE TF 創建 / 刪除限制

**創建**：`alicloud_cr_ee_instance` 對 `PayAsYouGo` 支援不完整。常見對策：
1. 先在控制台手動建 → `terraform import` 接管（推薦）
2. 改 `payment_type = "Subscription"`

**刪除**：ACR EE 是付費資源，**TF destroy 不會釋放**。必須：
- 主帳號到控制台 → 實例管理 → 釋放實例
- 或 BSS API（需要 `AliyunBSSFullAccess`）

---

### 13. ACR EE 不支援 tags

**現象**：
```
Error: Unsupported argument
An argument named "tags" is not expected here.
```

**修復**：把 `alicloud_cr_ee_instance` 內的 `tags = {...}` 全移除。要分組改用 `resource_group_id`。

---

### 14. ACR EE `instance_type` 校驗器太舊

**現象**：
```
Error: expected instance_type to be one of [Basic Standard Advanced], got Enterprise_Economy
[NOTE] set env variable TF_SKIP_RESOURCE_SCHEMA_VALIDATION to true can skip the error
```

**原因**：阿里雲控制台已改用新名（`Enterprise_Economy / Enterprise_Basic / Enterprise_Advanced`），但 TF provider 校驗器還只認 legacy 名。

**修復**：
1. tfvars 寫 legacy 名：`acr_instance_type = "Basic"`（語義等同 Enterprise_Economy）
2. import 既有實例的話，加 `lifecycle.ignore_changes = [instance_type, payment_type, period]`

---

### 15. ACR EE 公網 ACL 容易報 INSTANCE_ACCESS_ACL_ENTRY_INVALID

**現象**：
```
Code: INSTANCE_ACCESS_ACL_ENTRY_INVALID
Message: Instance access acl entry is invalid.
```

**根因**：實例層級的「公網訪問」沒先啟用，直接套 ACL policy 會被拒。

**修復**：**直接不要用** `alicloud_cr_endpoint_acl_policy "internet"`，UAT/Prod 只用 VPC 內網拉鏡像就好，省事又安全。要開公網時再到控制台手動設。

---
