---
name: gcp-pitfalls
description: >-
  GCP / GKE 踩坑紀錄與排錯指南（實戰累積）。當使用者在 GCP / GKE 上遇到問題，或提到
  「GKE」、「Autopilot」、「gRPC 負載均衡」、「gRPC 黏死」、「流量不均」、「卡在同一個 pod」、
  「scale up 後新 pod 沒流量」、「擴容沒收斂」、「長連線不重連」、「MaxConnectionAge」、「GOAWAY」、
  「dns:///」、「round_robin」、「headless service」、「clusterIP: None」、
  「Cloud Service Mesh」、「CSM」、「ASM」、「managed service mesh」、「Traffic Director」、
  「istio-injection」、「istio.io/rev」、「sidecar」、「Envoy」、「sidecar 注入」、
  「holdApplicationUntilProxyStarts」、「pod 一直 restart」、「啟動競態」、「2/2 Ready」、
  「field is immutable」、「clusterIP 不可變」、「helm upgrade 失敗 immutable」、
  「fleet」、「gkehub」、「servicemesh feature」、「MANAGEMENT_AUTOMATIC」、「fleet 註冊」、
  「PeerAuthentication」、「mTLS STRICT」、「健康檢查全紅」、「outboundTrafficPolicy」、
  「REGISTRY_ONLY」、「連不到 mesh 外」、「pilot-agent」、「GET clusters 是空的」、
  「Envoy 配置沒下發」、「EDS endpoint」、「Dataplane V2」、「eBPF 負載均衡」、
  「HPA 不生效」、「replicas 被重設」、「HPA memory」、「副本降不下來」、
  「PDB 卡住」、「節點升級卡住」、「無法驅逐」、「eviction blocked」、
  「terraform plan 有奇怪的 change」、「ssh-keys metadata 漂移」、「gcloud ssh 殘留」、
  「GKE Gateway CDN」、「kubectl exec 結果不一致」等 GCP / GKE 特有問題時，立刻觸發此 skill。
  與 gcp-architect（架構選型）、gcp-iam（權限授予）、terraform / k8s skill 互補。
version: 0.1.0
---

# GCP Pitfalls — GKE / Mesh / gRPC 實戰踩坑錄

實戰累積的 GCP 特有坑。每條含「症狀 → 原因 → 解法」。排錯時先掃本檔再動手。

## P1. gRPC 東西向流量黏死單一 Pod（GKE 通病）

**症狀**：gRPC 服務多副本，但流量全打到一個 Pod；scale up 後新 Pod 流量為 0。

**原因**：gRPC 是 HTTP/2 長連線，K8s Service（kube-proxy / Dataplane V2）只做 **L4 連線級**
負載均衡 — 連線建立時選一次 backend，之後所有 RPC 多路復用在同一條連線上。
**Dataplane V2（eBPF）也是 L4，不解此問題。**
更隱蔽的是：gRPC 的 DNS resolver **只在連線斷時重新解析**，所以擴容（連線沒斷）對既有
client 完全隱形 — 縮容/滾動更新會自癒，唯獨擴容不會。

**解法**（按成本遞增）：
1. **headless Service（`clusterIP: None`）+ client `dns:///` + `round_robin`** — 基本盤，先有 per-連線分散
2. **server 端 `MaxConnectionAge` + `MaxConnectionAgeGrace`**（grpc-go `keepalive.ServerParameters`）—
   定期發 GOAWAY 優雅輪轉，client 重連時重新解析 → 擴容最慢 N 分鐘收斂。
   注意：這是 `grpc.NewServer()` 建構參數，**grpc-go 沒有內建 env var**，必須代碼支援（可做成代碼讀 env、部署控值）
3. **Managed Cloud Service Mesh sidecar** — Envoy per-request 分流，秒級收斂、零代碼（見 P2）
4. proxyless xDS（`xds:///`）— 同樣秒級但**必須改代碼**（xds resolver 要編譯進 binary + bootstrap 注入），無 sidecar 成本

決策細節見 `gcp-architect` skill 的 `references/gke-east-west-grpc.md`。

## P2. headless Service 讓 sidecar mesh 失效

**症狀**：上了 mesh（sidecar 都注入了）但 gRPC 流量還是黏死。

**原因**：headless Service 下 client 解析到 **Pod IP 直連**，Envoy 尊重原始目的地、
不做 per-request 分流 — mesh 形同虛設。

**解法**：mesh 內的 gRPC Service 必須用**普通 ClusterIP**（client 連 VIP 單一邏輯位址，
Envoy 攔截後 per-request 選 backend）。例外：被 **mesh 外** 呼叫者跨 namespace 調用的服務
要保留 headless（caller 靠 client-side LB）。

## P3. `clusterIP` 欄位不可變（headless ↔ ClusterIP 切換）

**症狀**：helm upgrade 報 `Service "x" is invalid: spec.clusterIP: Invalid value: "": field is immutable`。

**原因**：K8s API Server 硬限制，`spec.clusterIP` 建立後不可改（None → VIP 也算改）。

**解法**：`kubectl delete svc` 後重建（helm upgrade 會重建）。窗口影響極小：既有連線是
Pod IP ↔ Pod IP 不受影響，只有刪除~重建間的新 DNS 解析失敗幾秒。未上線環境可整包
`helm uninstall` + install 最乾淨。注意 chart 模板若用條件式渲染 `clusterIP: None`，
切換時**所有**受影響 Service 都要先刪，否則 helm 對沒刪的會報 immutable 擋掉整次 upgrade。

## P4. Sidecar 啟動競態 — app 比 Envoy 先起來

**症狀**：注入 sidecar 後每個 Pod 啟動時 RESTARTS 1~3 次，app log 顯示連 DB / gRPC 失敗後退出。

**原因**：iptables 在 init 階段就把出站流量導向 Envoy，但 K8s 預設**同時**啟動所有容器 —
app 第一波連線打到還沒 ready 的 Envoy 上失敗。

**解法**：pod annotation `proxy.istio.io/config: '{"holdApplicationUntilProxyStarts": true}'` —
注入器把 sidecar 排第一 + postStart hook 等 Envoy ready 才放 app 啟動。代價是 Pod 啟動慢 2~5 秒。

## P5. GKE Hub `servicemesh` feature 是 project 單例

**症狀**：第二個環境（同 GCP project）的 Terraform 要啟用 mesh 時，`google_gke_hub_feature` 撞名衝突。

**原因**：`servicemesh` feature 每個 project 只能有一個；多環境共用一個 project 時
（如 share/uat/prod 同 project），只能有一個 Terraform state 持有它。

**解法**：feature 歸屬單一 state（或共用的 share state），各環境只各自管理
`google_gke_hub_membership` + `google_gke_hub_feature_membership`。後續要搬用 `moved` / `import`。

## P6. mesh 兩大殺手設定（動了會出大事）

- **`PeerAuthentication` mTLS `STRICT`**：GCLB（北南向）的健康檢查是明文，STRICT 會讓
  健康檢查全紅、gateway 全下線。**維持預設 PERMISSIVE**，除非北南向已改走 mesh 終結。
- **`meshConfig.outboundTrafficPolicy: REGISTRY_ONLY`**：瞬斷所有 mesh 外目的地
  （自架 MySQL / Redis / ES / Kafka VM、外部 API 全斷）。維持預設 `ALLOW_ANY`（passthrough）。

## P7. `kubectl exec deploy/...` 隨機選 Pod → Envoy 驗證誤判

**症狀**：`pilot-agent request GET clusters` 一下有配置一下沒有；剛擴容後查 Envoy 配置「是空的」。

**原因**：`kubectl exec deploy/x` 每次可能選到不同 Pod；剛擴容的新 Pod，其 Envoy xDS
還在 warming，clusters 列表不完整 — 看起來像「控制平面沒下發」其實只是還沒同步完。

**解法**：驗證時先 pin 住特定 Pod（`kubectl get pods -o jsonpath='{.items[0].metadata.name}'`），
並挑啟動已久的 Pod 查。endpoint 數量 = 副本數即收斂正常。

## P8. HPA 與 Helm 的 replicas 打架

**症狀**：HPA 擴到 5 副本，一次 helm upgrade 後瞬間縮回 2，再慢慢擴回去（抖動）。

**原因**：chart 的 Deployment 無條件渲染 `replicas: N`，每次 upgrade 都把副本數重設，
HPA 再拉回 — 兩個控制器互搶。

**解法**：chart 模板在 `hpa.enabled` 時**不渲染 replicas 欄位**
（`{{- if not (and $app.hpa $app.hpa.enabled) }}replicas: …{{- end }}`）。

## P9. HPA memory metric 把 Go 服務副本釘死在高位

**症狀**：流量退了 HPA 卻不縮容，memory utilization 永遠高於目標。

**原因**：Go runtime 不主動把 heap 歸還 OS，memory 利用率只上不下；HPA 取多 metric 的
**最大值**，memory 永遠觸頂 → 副本縮不下來。

**解法**：Go 服務的 HPA 用 **CPU-only**；memory metric 做成 opt-in、僅在真有記憶體型負載時開。

## P10. PDB + 單副本 = 節點升級卡死

**症狀**：Autopilot 節點升級卡住不動，事件顯示 eviction blocked by PodDisruptionBudget。

**原因**：`replicas: 1` 的 Deployment 配 `minAvailable: 1` 的 PDB → 永遠不允許驅逐。

**解法**：單副本 workload（如 worker）**不配 PDB**，掛了靠 K8s 重啟；要配 PDB 先把副本 ≥2。
同理：副本 2 配 `minAvailable: 2` 也一樣卡死 — minAvailable 必須 < replicas。

## P11. `gcloud compute ssh` 殘留臨時 key → terraform plan 漂移

**症狀**：terraform plan 出現 VM 的 metadata `ssh-keys` 變更（移除一把帶 `expireOn` 的 key），
看起來像有人改了 VM。

**原因**：`gcloud compute ssh` / IAP SSH 每次連線會往 instance metadata 注入帶過期時間的
臨時 key；Terraform 宣告裡沒有它，plan 就想清掉 — 純雜訊，key 早已過期。

**解法**：放著無害（apply 會清掉，in-place 不重啟）。要根治在 instance 資源加
`lifecycle { ignore_changes = [metadata["ssh-keys"]] }`。

## P12. GKE Gateway API 啟用 CDN 只能用 gcloud

**症狀**：想對 GKE Gateway 後端開 Cloud CDN，找不到對應的 K8s CRD 欄位。

**原因**：Gateway API 的 GCPBackendPolicy 不支援 CDN 設定（Ingress 時代的
`BackendConfig.cdn` 不適用於 Gateway）。

**解法**：直接用 `gcloud compute backend-services update <bs> --enable-cdn …` 對
Gateway controller 產生的 backend service 操作（名稱可從 HTTPRoute 對應的 NEG/BS 反查）。
注意 controller 不會回滾此設定，但也不歸 Terraform 管 — 屬於帶外操作，需文件記錄。

## 相關 Skill

- **`gcp-architect`** — 架構選型（東西向 gRPC LB 四條路比較：`references/gke-east-west-grpc.md`）
- **`gcp-iam`** — IAM 授權（含 mesh 相關角色）
- **`k8s`** — 叢集連線規範、manifest 模板
- **`terraform`** — GCP patterns、Autopilot 注意事項
