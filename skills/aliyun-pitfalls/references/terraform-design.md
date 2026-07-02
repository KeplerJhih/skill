## ⚙️ Terraform 設計層面

### 21. `for_each` 拒絕未知 keys（import 時常見）

**現象**：
```
Error: Invalid for_each argument
var.snat_source_cidrs is a map of string, known only after apply
```

**根因**：for_each 的 map keys 必須在 plan 時可決定。如果傳入的是 `module.xxx.computed_output`，TF 會拒絕。

**修復**：改傳「**靜態變數**」而非 module 輸出：
```hcl
# ❌ 錯
snat_source_cidrs = module.vpc.vswitch_cidrs

# ✅ 對
snat_source_cidrs = { for k, v in var.vswitches : k => v.cidr }
```

特別在 `terraform import` 時容易撞到。**臨時對策**：
1. 把 problematic block 暫設 `= {}`
2. 完成 import
3. 還原 block

### 22. import 既有 ACR EE 三件套

```bash
terraform import module.acr.alicloud_cr_ee_instance.main cri-xxx
terraform import 'module.acr.alicloud_cr_ee_namespace.main["ns"]' 'cri-xxx:ns'
terraform import 'module.acr.alicloud_cr_ee_repo.main["repo"]' 'cri-xxx:ns:repo'
```

注意 ID 分隔符是 `:`。

---
