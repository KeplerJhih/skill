## 🔐 SSL / TLS 證書（cas 服務）

### 27. 免費 wildcard **不存在** — DV 免費僅單域名

**踩坑點**：直覺以為「阿里雲送免費 DV 證書」涵蓋 wildcard，**錯**。

**事實**：
- 免費 product code: `digicert-free-1-free`（DigiCert Encryption Everywhere DV）
- **僅單域名（1 SAN）**，每年最多 20 張，1 年期
- **wildcard / 多 SAN → 一律付費**（基本 wildcard 約 ¥2000-3000/年）

**CLI 確認可用免費額度**：
```bash
aliyun cas DescribePackageState --region cn-hangzhou
# 返回：
# {
#   "ProductCode": "digicert-free-1-free",  ← 確認帳號有此免費額度
#   "IssuedCount": 0                          ← 已用張數
# }
```

⚠️ **API region 必須是 cn-hangzhou**（或其他大陸 region）— cn-hongkong / ap-northeast-* 跑 cas API 會回 `API.Forbidden`。

### 28. SSL 證書 prod 自動續方案選擇

| 方案 | wildcard | 自動續 | 成本 | 適用 |
|---|---|---|---|---|
| **阿里 SSL 付費 wildcard + ALB cert-id annotation**（prod 首選）| ✅ | ✅ 雲託管 | ¥2-3K/年 | 雲託管最穩、ALB / CDN / WAF 共用 |
| 阿里 SSL 免費單域名 × N 張 | ❌（多張單獨）| ✅ | 免費 | 域名 ≤ 5 個、可接受多 cert-id 管理 |
| cert-manager + LE + Cloudflare DNS-01 | ✅ | ✅ K8s 自動 | 免費 | domain 願意搬 CF 託管 |
| cert-manager + LE + alidns webhook | ✅ | ✅ K8s 自動 | 免費 | domain 在阿里 DNS、可接受第三方 webhook |
| certbot 手動 DNS-01 | ✅ | ❌ 90 天手動 | 免費 | UAT 階段、人少能盯到期 |

**建議**：
- UAT：certbot 手動 OK（短期、人會盯）
- prod：付費 wildcard + 阿里 SSL 自動部署到 ALB（無 K8s 介入、續證後 controller 自動 reload）

### 29. Aliyun ALB Ingress 對 TLS 兩種 mode

ALB Ingress Controller 支援兩種 cert 方式，**不互斥可二擇一**：

**A. K8s Secret（標準 K8s pattern）**：
```yaml
spec:
  tls:
    - hosts: ["*.example.com"]
      secretName: my-wildcard-tls   # K8s Secret type=kubernetes.io/tls
```
適用：certbot / cert-manager / 手動上傳

**B. 阿里 SSL 服務 cert-id（雲託管）**：
```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/cert-id: "1234567-cn-hangzhou"
spec:
  # 不寫 spec.tls
```
適用：阿里 SSL 自動續流程、續證後 controller 自動 reload 無需 K8s 介入。

多 cert-id（多 wildcard / 多 domain）：
```yaml
alb.ingress.kubernetes.io/cert-id: "1234-cn-hangzhou,5678-cn-hangzhou"
```
ALB SNI 自動匹配。

**設計教訓**：chart template 內用 if-else 兼容兩種 mode，env 換 values 即可切換：
```yaml
metadata:
  annotations:
    {{- if .Values.tls.certId }}
    alb.ingress.kubernetes.io/cert-id: {{ .Values.tls.certId | quote }}
    {{- end }}
spec:
  {{- if .Values.tls.secretName }}
  tls:
    - hosts: {{ .Values.tls.hosts | toYaml | nindent 8 }}
      secretName: {{ .Values.tls.secretName }}
  {{- end }}
```

⚠️ **cert-id 模式還有一個必踩坑 — 見 #31（缺 listen-ports → 全 503）。**

---

### 31. ALB cert-id 模式缺 `listen-ports` annotation → 443 上 0 條規則、全 host 503（reconcile 還顯示成功）

**現象**（2026-06-10 prod 首次上線實踩）：

- 所有 host HTTPS 一律 **503**，但 HTTP→HTTPS 308 redirect 正常、cert 正確掛上（openssl 看得到 `*.aquawon.com`）
- pod / Service / Endpoints 全部正常，集群內直打後端 200
- `kubectl describe ingress` events：`SuccessfullyReconciled` ✅（**完全沒有錯誤**，極難察覺）

**定位過程（CLI 三步看穿）**：
```bash
# 1. 443 listener 規則數 = 0（80 上只有 redirect 規則）
aliyun alb ListRules --region <r> --MaxResults 100   # 按 ListenerId 分組數規則

# 2. 業務 server group 一個都沒建（只有 kube-system-fake-svc-80/443 兩個佔位）
aliyun alb ListServerGroups --region <r> --MaxResults 100   # 看 VpcId 歸屬

# 3. 確認 default action 落到 fake-svc → 503
aliyun alb GetListenerAttribute --region <r> --ListenerId lsn-xxx
```

**根因**：

ALB Ingress Controller 決定「要不要把 Ingress 規則綁上 HTTPS listener」的依據是 **`spec.tls` 的存在**：

| TLS mode | `spec.tls` | controller 行為 |
|---|---|---|
| K8s Secret（UAT）| ✅ 有 | 自動綁 443，規則正常 → **所以 UAT 永遠踩不到** |
| cert-id annotation（prod）| ❌ 沒有 | **只處理 80**；443 listener 建了、cert 掛了，但 0 條轉發規則、0 個 server group |

配 `ssl-redirect: "true"` 後 80 全變 redirect → 流量被推去一個空的 443 → 全 503。

**修復**：cert-id 模式**必須**同時帶 `listen-ports` 明示 HTTPS：

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/cert-id: {{ .Values.tls.certId | quote }}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80},{"HTTPS": 443}]'   # ← 缺這行全 503
```

修完 server group / 443 規則約 1 分鐘內全部自動建出。

**排錯教訓**：
1. 「reconcile 成功 + 全 503」≠ 後端問題 — 先數 **443 listener 的規則數** 與 **server group 的 VpcId 歸屬**
2. 同帳號多 cluster 時 server group 名字會撞名（`aqua-frontend-main-80` UAT/prod 各一份）— **一定要看 VpcId** 再下結論
3. controller 卡在錯誤殘留狀態時，砍掉重建 Ingress（uninstall routes release 再裝）**救不了配置性缺失** — 缺 annotation 就是缺

---

### 32. ACR EE 經濟版 VPC endpoint 上限 = 1 個 VPC（多 env 必撞）

**現象**（prod VPC 想綁 ACR 內網 endpoint 時）：
```
Code: INSTANCE_ACCESS_VPC_LIMIT_EXCEED
Message: Instance vpc access endpoint count exceeds the limit.
```
同時 prod cluster 拉鏡像報：
```
dial tcp: lookup acr-xxx-registry-vpc.<region>.cr.aliyuncs.com on 100.100.2.136:53: no such host
```
（VPC endpoint 域名靠 PrivateZone 按 VPC 解析 — 沒綁的 VPC 直接 DNS 查無此名）

**根因**：ACR EE **經濟版（Enterprise_Economy）VPC 內網 endpoint 只能綁 1 個 VPC**。UAT 占掉名額後，prod VPC 無法再綁。

**解法二擇一**：
1. **升級 ACR 版本**（標準版以上可綁多 VPC）→ console 升級 + 綁定 → 回來 `terraform import` 收斂：
   ```bash
   terraform import 'module.acr.alicloud_cr_vpc_endpoint_linked_vpc.main["prod"]' \
     'cri-xxx:vpc-xxx:vsw-xxx:Registry'   # ⚠️ ID 是 4 段，最後一段 module_name=Registry
   ```
2. 該 env 改走**公網 endpoint** pull（`acr-xxx-registry.<region>.cr.aliyuncs.com`，走 NAT 流量費；credential-helper 的 `domains` 有列公網域名即可直接用）

**連帶提醒**：新 cluster 的 `kube-system/acr-configuration` 是 addon 預設**空殼**（`acr-registry-info` 整段被註解、`watch-namespace: default`、`acr-api-version: 2018-12-01`）— 不同步成 #11 的正確內容（instanceId + `watch-namespace: all` + `v1`），憑證 secret 永遠不會出現在業務 NS。**每開一個新 cluster 都要做一次**，然後 `rollout restart deployment aliyun-acr-credential-helper -n kube-system`。

---
