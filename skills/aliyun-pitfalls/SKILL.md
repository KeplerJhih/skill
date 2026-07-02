---
name: aliyun-pitfalls
description: >-
  阿里雲踩坑紀錄與排錯指南。當使用者在阿里雲 (Aliyun / Alibaba Cloud) 上遇到問題，
  或提到「阿里雲」、「aliyun」、「alicloud」、「ACK」、「ACR」、「OSS」、「Terway」、
  「EIP」、「NAT Gateway」、「實名認證」、「Enterprise_Economy」、「cgroup v2」、
  「ENI IP 不足」、「InsufficientInstanceIP」、「insufficient_scope」、
  「AliyunOOSLifecycleHook4CSRole」、「acr-configuration」、「免密拉鏡像」、
  「cn-beijing 漂移」、「hashicorp/alicloud」、「provider 漂移」、
  「實名 NO_REAL_REGISTER_AUTHENTICATION」、「ACK NodePool 建不起來」、
  「ACR EE 拉不到鏡像」、「Order.NoRealNameAuthentication」、
  「SSL 證書」、「免費 wildcard」、「digicert-free」、「cert-id annotation」、
  「ALB Ingress」、「cas」、「cert-manager」、「DescribePackageState」、「TLS 自動續」、
  「ASM」、「服務網格」、「service mesh」、「ClustersNotEmpty」、「istio-admin」、
  「helm 部署到 ASM 失敗」、「secrets is forbidden」、「ModifyApiServerEipResource」、
  「istio-injection」、「sidecar 注入」、「gRPC 黏住同一個 pod」、「gRPC 負載不均」、
  「headless 改 ClusterIP」、「DescribeServiceMeshKubeconfig」、「mesh 刪不掉」
  等阿里雲特有問題或錯誤碼時，
  立刻觸發此 skill。本 skill 累積實戰經驗，配合 terraform skill 的 aliyun-patterns.md
  與 aliyun-iam skill（RAM / RBAC 授權操作）使用。
version: 1.0.0
---

# Aliyun Pitfalls — 阿里雲踩坑全紀錄

> 本文件來自實戰經驗，每一項都是「**真的踩過坑、花時間 debug 才解的**」。寫成這份是為了下次有人（或自己）遇到時能 5 分鐘內定位。

## 使用原則

1. **遇到報錯時先 grep 錯誤碼**：`Code: XXXX` 對照「📚 坑位索引」定位主題檔，只 Read 相關的 references
2. **任何「奇怪的行為」先檢查 region**：阿里雲 provider 預設漂移到 `cn-beijing` 很常見
3. **付費資源 (ACR EE / ECS / SLB) 通常子帳號不能釋放**：要主帳號

---


## 📚 坑位索引（先查表，再 Read 對應檔）

完整內容依主題拆在 `references/`，**依報錯關鍵字 / 服務名先對照下表**，只讀相關的檔：

| 主題 | 檔案 | 收錄內容 |
|------|------|---------|
| 📍 區域與計費 | `references/region-billing.md` | 實名認證差異（大陸 vs 國際）、Enterprise_Economy |
| 🔌 Provider 與認證 | `references/provider-auth.md` | #1-3：hashicorp/alicloud 漂移救援、OSS backend AK、RAM 權限不足 |
| 🚀 ACK 容器服務 | `references/ack.md` | #4-10, 25-26：NodePool SLR/庫存/廢棄欄位、cgroup v2、Terway ENI IP、autoscaling 轉換、instance_types fallback |
| 📦 ACR 鏡像倉庫 | `references/acr.md` | #11-15：EE 免密拉鏡像、TF 建刪限制、tags/校驗器/公網 ACL |
| 🌐 網路 | `references/network.md` | #16-19：EIP 帶寬、NAT force delete、vSwitch 被 endpoint 占用、CMS 殘留 SG |
| 🖥 ECS 實例 | `references/ecs.md` | #30：image data source 抓最新 → 重裝系統盤慘案 |
| 🪣 State / OSS Backend | `references/state-backend.md` | #20：OSS region endpoint |
| ⚙️ Terraform 設計 | `references/terraform-design.md` | #21-22：for_each 未知 keys、import ACR EE 三件套 |
| 🔐 SSL / TLS 證書 | `references/ssl-tls.md` | #27-29, 31-32：digicert-free 額度、prod 自動續、ALB Ingress 兩種 TLS mode、cert-id 503 雷、VPC endpoint 上限 |
| 🕸 ASM 服務網格 | `references/asm.md` | #33-37：子帳號 core 資源不開放、mesh 刪除順序、公網訪問、headless passthrough、sidecar 擋縮容 |
| 💸 費用控制 | `references/cost.md` | #23-24：擴縮容省錢但有固定費、ACR EE 月費 |

> 找不到對應主題時，先看檔尾「排錯流程 SOP」；跨 Terraform 模板問題配合 `terraform` skill 的 `references/aliyun-patterns.md`。

## 🛠 排錯流程 (SOP)

當阿里雲 TF 出問題，照這個順序檢查：

```
1. 看錯誤碼 → 查「📚 坑位索引」→ Read 對應 references 檔
2. 看 endpoint HostId → 是不是 region 跑錯
3. terraform providers → 看是不是 hashicorp/alicloud 殘留
4. terraform state list → 看 state 內容
5. aliyun configure list → 看當前 profile 對不對
6. 必要時 terraform state replace-provider + 重 init
```

---

## 與其他 skill 的關聯

- **`terraform/references/aliyun-patterns.md`** — 完整模板代碼，搭配本文件食用
- **`aliyun-iam`** skill — RAM / ASM RBAC / ACK 授權操作面（#3 / #33 的授權步驟詳解在那邊）
- **`k8s`** skill — K8s 通用層面（kubectl、Helm、CNI 概念）
- **`devops`** skill — Docker / CI/CD 相關

## 預期未來補充的章節

- ALB Ingress Controller 其餘踩坑（health check 調優 / sticky session；cert-id × listen-ports 已收錄 #31）
- SLS 日誌服務整合
- RDS for MySQL TF 配置
- ESSD vs cloud_essd_entry vs cloud_efficiency 選擇
- Spot Instance NodePool 配置與被搶占處理

