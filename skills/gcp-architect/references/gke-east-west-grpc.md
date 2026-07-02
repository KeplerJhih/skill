# GKE 東西向 gRPC 負載均衡 — 架構選型指南

解決問題：gRPC（HTTP/2 長連線）在 K8s 的 L4 Service 負載均衡下黏死單一 Pod，
擴容後新 Pod 吃不到流量（gRPC DNS resolver 只在連線斷時重新解析）。
Dataplane V2（eBPF）仍是 L4，不解此問題。

## 四條路比較

| # | 方案 | 收斂速度 | 代碼改動 | 基建改動 | 額外成本 | 附加能力 |
|---|------|---------|---------|---------|---------|---------|
| A | server 端 `MaxConnectionAge`（+ headless `dns:///` round_robin） | 連線輪轉週期（可設 30s~5m） | server 各 +2 行（或讀 env） | 無 | 重連開銷（可忽略） | 無 |
| B | K8s API resolver（kuberesolver，watch EndpointSlice） | 秒級 | 改 dial scheme + 引依賴 | RBAC（watch endpoints） | 無 | 無 |
| C | Cloud Service Mesh **proxyless xDS**（`xds:///`） | 秒級 | **必改**：xds import + scheme + bootstrap | Mesh/GRPCRoute/BackendService + NEG + autoneg + IAM | TD 端點計費 | 流量治理（部分） |
| D | Cloud Service Mesh **sidecar**（Envoy，managed） | 秒級（per-request 分流） | **零** | fleet 註冊 + CSM 啟用 + namespace label + Service 轉 ClusterIP | ~$0.50/Pod/月 + sidecar 資源（~0.1 vCPU/128Mi/Pod） | 金絲雀、流量切分、mTLS、拓撲、跨叢集 |

## 決策準則

1. **只要解黏死、接受分鐘級收斂** → A（最小變更；uat / 小規模首選）
2. **要秒級收斂 + 不想改代碼** → D（sidecar managed CSM；包網/突發擴縮場景首選，
   HPA 擴出的 Pod 立即進流量）
3. **要秒級 + 不想付 sidecar 資源費 + 能改代碼** → C（proxyless）—
   但營運複雜度高一級（bootstrap、NEG/autoneg、xDS 排錯），無流量治理需求時不划算
4. A 與 C/D **不互斥**：MaxConnectionAge 是 gRPC server 衛生慣例，mesh 過渡期還是現成保底

## 關鍵原理（決定方案邊界的事實）

- **proxyless 為何必改代碼**：「無代理」= 把 Envoy 的職責編譯進 binary。
  grpc 庫要 blank import xds 套件註冊 resolver、dial target 換 `xds:///`、
  Pod 注入 td-grpc-bootstrap init container + `GRPC_XDS_BOOTSTRAP` env。任何雲都一樣（阿里雲 ASM proxyless 同理）。
- **sidecar 為何零代碼**：iptables 透明攔截 + Envoy 在 HTTP/2 stream（每個 RPC）層級分流 —
  app 連 sidecar 的單一長連線內，每個 RPC 都被獨立分配到不同後端。
- **sidecar 模式的前提**：client 必須 dial **ClusterIP**（headless 直連 Pod IP 會繞過分流）；
  mesh 外的跨 ns 呼叫者所依賴的 Service 要保留 headless 給 client-side LB。
- **MaxConnectionAge 無法部署層注入**：grpc-go 沒有對應內建 env var，只能代碼設定
  （建議模式：代碼讀 env、預設關閉，CM 控值 — uat/prod 可不同）。

## GKE 應用層 HA 安排模式（配套）

| 機制 | 目的 | 要點 |
|------|------|------|
| PDB `minAvailable: 1` | 防節點升級/縮併一次驅逐全部副本 | minAvailable **必須 < replicas**；單副本 workload 不配（會卡死升級） |
| HPA（CPU-only） | 突發流量自動擴容 | Go 服務勿用 memory metric（heap 不歸還 → 釘死高位）；chart 須在 HPA 開啟時不渲染 replicas |
| topologySpread（zone, soft） | 單 zone 故障容忍 | `whenUnsatisfiable: ScheduleAnyway` 避免 Autopilot 容量不足卡排程 |
| Regional cluster + Cloud SQL REGIONAL | 控制平面 / DB HA | GKE Autopilot 預設 regional |
| ⚠️ 資料層 | 自架單 VM（Redis/ES/Kafka）是 app 層 HA 蓋不住的單點 | 真 HA 需管理版或 VM 複寫，獨立開案 |
| ⚠️ 單副本 worker | K8s 重啟縫隙秒~分鐘級 | 真 HA 需 leader election（代碼層） |

## 成本模型（2026-06 核價）

- CSM standalone：**$0.0006945/client/小時 ≈ $0.50/Pod/月**（含遙測 dashboard、Mesh CA 免費）
- sidecar 資源：Autopilot 按 Pod 計費，每 sidecar 約 0.1~0.25 vCPU + 128Mi
- 範例：18 服務 × 1~3 副本 ≈ $9~27/月 CSM 費 + sidecar 資源費 — 對比省下的營運/代碼成本通常划算

## 落地踩坑

實作層的坑（startup race、clusterIP immutable、mTLS STRICT、Envoy warming 誤判等）
統一收錄在 **`gcp-pitfalls`** skill — 落地前先讀。
