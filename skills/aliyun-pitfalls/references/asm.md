## 🕸 ASM（服務網格）

### 33. ASM API server 對子帳號不開放 core 資源 → helm 部署必失敗，一律 template|apply

**現象**（2026-06-12 prod 實踩）：
```
Error: query: failed to query with labels: secrets is forbidden:
User "219753278489491833-1781236998" cannot list resource "secrets"
in API group "" in the namespace "aqua"
```

**兩層根因**：
1. **新 ASM 實例預設只有主帳號有 RBAC** — 子帳號要顯式授權（TF：`alicloud_service_mesh_user_permission`，role `istio-admin`；授權操作詳見 `aliyun-iam` skill）
2. **授了 istio-admin 也沒用**：ASM 給子帳號的 istio-admin **只開放 Istio CRD + Namespace，core 資源（secrets/configmaps）一律拒絕** — 而 helm 必須在目標 NS 寫 Secret 存 release 記錄 → helm 對 ASM API server 永遠過不去

**修法**：ASM 部署一律 `helm template ... | KUBECONFIG=<asm> kubectl apply -f -`（渲染照舊、放棄 release 管理）。uninstall 改 `kubectl delete <istio-crd> --all -n <ns>`，**不要刪 Namespace 物件**（ASM 會 sync NS 到 ACK，風險不可控）。

**快速驗證**：
```bash
KUBECONFIG=<asm> kubectl auth whoami    # 身分 = <RAM UserId>-<憑證序號>
KUBECONFIG=<asm> kubectl auth can-i create destinationrules.networking.istio.io -n aqua  # 應 yes
KUBECONFIG=<asm> kubectl auth can-i list secrets -n aqua    # 永遠 no（設計如此，不是授權壞了）
```

### 34. mesh 刪除前必須先解綁 cluster — `ErrorPermitted.ClustersNotEmpty`

**現象**：`terraform apply`（destroy mesh）報：
```
Code: ErrorPermitted.ClustersNotEmpty
Message: the clusters should be removed from it before the mesh instance is deleted
```

provider 的 delete 不會自動解綁。**純 TF 兩段式**：
1. module 呼叫處暫改 `cluster_ids = []` → `terraform apply`（in-place 解綁，順帶清掉 ACK 上 istio-system 的同步組件）
2. tfvars `enabled = false` → apply destroy；成功後把 `cluster_ids` 改回 `[module.ack.cluster_id]` 保持代碼正確

**連帶順序**：destroy 前先刪 `IstioGateway` CRD 讓 ASM 回收 ingress SLB（否則可能殘留計費）；mesh 拆掉後，CLI 動態綁的 API server EIP **不會自動釋放**（不在 TF），記得回收或轉用。

### 35. ASM API server 公網訪問 — 別走 TF flag、EIP 綁定後憑證要等重簽

- TF 的 `api_server_public_eip` / `pilot_public_eip` 是 **force-new**（改了整個 mesh 重建）→ 公網訪問一律 CLI 動態綁：
  ```bash
  aliyun servicemesh ModifyApiServerEipResource --ServiceMeshId <id> \
    --Operation BindEip --ApiServerEipId <eip-id>   # 可指定既有閒置 EIP 回收再利用；參數名不是 EipId
  ```
- 綁定後 kubectl 立即連會報 `x509: certificate is valid for ..., not <EIP>` — API server 憑證 SAN 重簽約需 30 秒~數分鐘，**等就好，不用重綁**。
- kubeconfig 取得：`aliyun servicemesh DescribeServiceMeshKubeconfig --ServiceMeshId <id> --PrivateIpAddress false`

### 36. Istio/ASM 對 headless Service 是 passthrough — gRPC LB 必須配套改 ClusterIP

光裝 mesh + 注入 sidecar **解不了** gRPC 黏 pod：headless（`clusterIP: None`）在 Envoy 是 ORIGINAL_DST 直通，不做 per-request LB。配套規則：

1. backend Service 改普通 ClusterIP — `clusterIP` 是 **immutable**：先 `kubectl delete svc` 再 apply 重建（瞬斷數秒，兩條指令連著跑）
2. **「無 sidecar + ClusterIP」是禁止態**（kube-proxy per-connection 黏死單 pod，比 headless 更糟）— 注入與 ClusterIP 必須成對開關、成對回滾
3. 純前端（nginx SPA）pod 加 `sidecar.istio.io/inject: "false"` label 排除注入（pod label 優先於 NS label），省記憶體
4. 與 ALB 入口並存：PERMISSIVE mTLS（預設）下 ALB→pod 明文照收；**禁止 STRICT**（會打斷 ALB 路徑）
5. **分流驗證法**（不需 istioctl）：
   ```bash
   kubectl exec <client-pod> -c istio-proxy -- pilot-agent request GET clusters \
     | grep 'outbound|<port>||<svc>'   # 看 EDS endpoints 數 + 每 endpoint rq_total 分布
   ```
   無流量時起臨時 curl pod（會自動注入）打 N 發再讀計數；**測試流量必須從 app 容器發** — istio-proxy 容器自身流量（uid 1337）不被攔截，從那裡 curl 會繞過 Envoy 得到假結果。

> 無 mesh 環境的替代解：gRPC server 設 `MaxConnectionAge`（Go keepalive 參數）強制定期斷線重連，配 headless + client-side LB 做粗粒度再平衡。

### 37. ASM sidecar 的 emptyDir 讓 Cluster Autoscaler 永遠不縮「跑業務的節點」

**現象**：開 ASM 注入 sidecar 後，節點數只增不減 —— 業務量極低（CPU 實際用 1-2%）卻一直維持十幾台，autoscaler 不縮容。

**根因（兩層疊加）**：
1. **CA 看 request 不看 usage**：節點被 CPU **request** 排到 ≥ `utilization_threshold`（prod 0.6）就不是縮容候選，跟實際用量無關。request 灌太高 → 帳面一直「滿」。
2. **sidecar emptyDir + `skip_nodes_with_local_storage=true`**：istio-proxy 注入 `istio-envoy`/`istio-data`/`workload-certs` 等 **emptyDir** volume；ACK 託管 CA 開著 `--skip-nodes-with-local-storage=true`，把「有 emptyDir 的 pod」所在節點一律跳過。**只要 pod 被注入 sidecar，它的節點 CA 就永不縮** → 開 mesh ≈ 對跑業務的節點關掉自動縮容。

**驗證（CA 自己會講）**：
```bash
kubectl -n kube-system logs -l app=cluster-autoscaler --tail=500 \
 | grep -iE "local storage|not suitable|No candidates"
# 會看到：node X cannot be removed: pod with local storage present: <業務pod>
# 其餘高 util 節點則是：not suitable for removal - utilization too big (0.7x)
```

**修法（針對性、最安全）**：給注入 sidecar 的 workload pod 加 annotation
`cluster-autoscaler.kubernetes.io/safe-to-evict: "true"`（加在專案 Helm chart 的 backend deployment template）。
- **安全前提**：實查該 NS **無 app 級 emptyDir**（只剩 sidecar 的，純 ephemeral，驅逐重排後重生無損）。
- 替代解：autoscaler config `skip_nodes_with_local_storage=false`（全域、較鈍，連 kube-system addon 節點也放行）。
- ⚠️ sidecar fix **不解決第 1 層**：request 灌太高仍會讓節點 ≥ 門檻而不縮 —— 真要縮得一起修 CPU request。

> 關聯：terraform `CLAUDE.md` 踩坑 #13（g7a→c 系列 + 雙 pool→單池遷移合輯）；drain 帶 sidecar 節點要加 `--delete-emptydir-data`。

---
