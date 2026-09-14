# ArgoCD Notifications — 踩坑與範本

設定 ArgoCD Notifications（部署成功 / 失敗 / rollback 通知到 Discord、Slack 或任意 webhook）時的非直覺行為與實測範本。
行為以 argo-cd 與 notifications-engine 原始碼為準（`pkg/controller/state.go`、`util/notification/expression/repo/repo.go`、
`pkg/apis/application/v1alpha1/types.go`、`server/application/application.go`），版本差異時以叢集實際版本的原始碼 / 文件為準。

---

## 0. 心智模型：全局「怎麼送」+ 訂閱「誰要送」

```
git commit → ArgoCD sync → trigger 條件成立 → 比對訂閱 → template 渲染 → service 發送（讀 secret 取 URL / token）
```

| 塊 | 位置（ArgoCD 安裝的 namespace） | 範圍 |
|---|---|---|
| Secret | `argocd-notifications-secret` | 全局 |
| `service.<type>.<name>` | `argocd-notifications-cm` | 全局 — 送到哪 |
| `template.<name>` | `argocd-notifications-cm` | 全局 — 訊息內容 |
| `trigger.<name>` | `argocd-notifications-cm` | 全局 — 何時送 |
| **訂閱** | Application / AppProject annotation，或 cm 的 `subscriptions` | 見 §2 |

改 cm / secret 後不需重啟 notifications controller。

---

## 1. Secret 引用：`$key` 與 `$name:key` 規則不同

| Secret 放法 | 需要 label？ | cm 內寫法 |
|---|---|---|
| 內建 `argocd-notifications-secret` 裡的 key | 不需要（controller 預設讀它） | `$<key>`，例 `url: $discord-webhook` |
| 自建 Secret | 必須在 ArgoCD namespace 且帶 `app.kubernetes.io/part-of: argocd` | `$<secret-name>:<key>` |

使用者描述「webhook 放在 secret X」時，先 `kubectl -n argocd describe secret` 確認 X 是 **Secret 名** 還是 **key 名**，
再決定寫法 — 誤判會導致要求使用者去加不必要的 label。

---

## 2. 訂閱只認 Application / AppProject，不認 Deployment

ArgoCD 只讀 Application / AppProject 上的訂閱 annotation；寫在 Deployment、Service 等被管理資源上的 label / annotation **一律無效**。

| 範圍 | 寫在哪 | 寫法 |
|---|---|---|
| 單一 Application | Application annotation | `notifications.argoproj.io/subscribe.<trigger>.<service>: "<recipient>"` |
| AppProject 下全部 app | AppProject annotation | 同上 |
| 全部 Application | cm `subscriptions` | 見下 |
| 帶特定 label 的 Application | cm `subscriptions` + `selector` | `selector` 比對的是 **Application 的 label** |

webhook 類 service 沒有收件人：annotation 值給 `""`；`subscriptions` 的 recipients 直接寫 webhook 名稱。

```yaml
data:
  subscriptions: |
    - recipients:
        - discord                 # = service.webhook.discord 的名稱
      # selector: notify=discord  # 選配：只套用到帶此 label 的 Application
      triggers:
        - on-deployed
```

- Application 本身由 git 管理（app-of-apps）時，叢集內 `kubectl annotate` / `label` 會被 sync 蓋回 — 改 git 內的 Application manifest。
- 全局 `subscriptions` 與 per-app annotation 擇一為主，混用會讓「為何某 app 有 / 沒通知」難以追查。

---

## 3. `oncePer` 選錯欄位 → rollback 通知錯版或不通知

| 欄位 | types.go 註解 | 實際意義 |
|---|---|---|
| `app.status.sync.revision` | the revision the comparison has been performed to | git target 的最新 commit（比對目標） |
| `app.status.operationState.syncResult.revision` | the revision this sync operation was performed to | **實際部署的版本** |

用 `sync.revision` 當 `oncePer` 或顯示在訊息中，ArgoCD rollback 後它仍指向 git 最新版：

- 最新版已通知過 → rollback 被去重，不發
- 最新版是壞版且未曾 Healthy（從未通知）→ 發出「✅ 成功」，revision 卻顯示**壞版**

官方 catalog 的 `on-deployed` / `on-sync-failed` / `on-health-degraded` 皆使用 `app.status.operationState?.syncResult?.revision`。

---

## 4. 已通知紀錄不會隨條件轉 false 而清除

`state.go`：state key = `<oncePer 值>:<trigger>:<condition>:<service>:<recipient>`；條件轉 false 時
`if result.OncePer != "" { return false }` → **設了 oncePer 的紀錄不刪**，每個 Application 保留最多 100 筆
（`notifiedHistoryMaxSize`，超過從最舊刪），存在 Application 的 annotation `notified.notifications.argoproj.io`。

後果：rollback 回「曾經通知過的舊 revision」→ 不再通知，即使 `oncePer` 已改用 `syncResult.revision`。

| 需求 | `oncePer` | 代價 |
|---|---|---|
| 每個 commit 只通知一次（catalog 預設） | `app.status.operationState?.syncResult?.revision` | rollback 回舊版不通知 |
| **每次 sync 完成都通知**（含 rollback） | `app.status.operationState.finishedAt` | 同版手動 re-sync、selfHeal 修正也會通知 |

- 修改 `oncePer` 表達式後，現有 Synced + Healthy 的 app 會各補發一次（新 key 不在紀錄內）— 屬正常，事先告知使用者。
- 重置某 app 的去重紀錄：`kubectl -n argocd annotate application <app> notified.notifications.argoproj.io-`
  （之後當下成立的條件會再發一次）。

---

## 5. Rollback 方式決定有沒有通知

| 方式 | 通知 | 備註 |
|---|---|---|
| `git revert` 後 push | ✅ | 新 SHA，等同一次新部署；GitOps 下的建議做法 |
| ArgoCD Rollback（UI / `argocd app rollback`） | 取決於 §3 / §4 的 `oncePer` | auto-sync 開啟時被 server 拒絕：`rollback cannot be initiated when auto-sync is enabled`；rollback 後 app 通常呈 OutOfSync，事後需恢復 auto-sync |
| `kubectl rollout undo` / `kubectl set image` | ❌ | 繞過 ArgoCD，無 sync operation；開 selfHeal 會被改回 git 狀態 |

審查部署腳本時，若資源已由 ArgoCD 管理，指出 `kubectl set image` / `rollout undo` 與 GitOps 衝突。

---

## 6. 部署失敗預設是靜默的

只設 `on-deployed` 時，ImagePullBackOff / CrashLoop 等情況 sync 仍為 Succeeded 但 health 不會 Healthy → **沒有任何通知**。
補上失敗類 trigger（條件取自官方 catalog）：

- `on-sync-failed`：`app.status.operationState != nil and app.status.operationState.phase in ['Error', 'Failed']`
- `on-health-degraded`：`app.status.health.status == 'Degraded'`

Deployment 卡住時要超過 `progressDeadlineSeconds`（預設 600 秒）才會變 Degraded，失敗通知約 10 分鐘後才到。

---

## 7. Template：commit 訊息、作者、觸發者

| 資訊 | 取法 | 注意 |
|---|---|---|
| commit 訊息 / 作者 | `call .repo.GetCommitMetadata <sha>` → `.Message` `.Author` `.Date` `.Tags` | 經 repo-server 查詢；失敗時函式 panic → 該則通知送不出，看 controller log |
| 觸發者 | `.app.status.operationState.operation.initiatedBy.username` | auto-sync 時為空、`.automated` 為 true → 用 `default "auto-sync"` 補 |
| 推送人（pusher） | **拿不到** | git 不記錄 pusher；只有 Git 平台 push event 知道，需要時改在 CI 發通知 |

- template 已載入 sprig（`sprig.TxtFuncMap()`）。**以 `toJson` 產生 JSON 字串** — 手寫 `"{{ .Message }}"` 遇到引號 / 換行會產生壞 JSON（Discord 回 400）。
- Go template 對不存在的巢狀欄位繼續取值會渲染失敗：失敗類 template 不要碰 `operationState` / `syncResult`（degraded 時可能不存在），改用 `.app.status.sync.revision`。
- ArgoCD rollback 時「作者」是舊 commit 的作者、「觸發者」是按 rollback 的帳號 — 兩欄並列才看得出是誰回滾。
- Discord `content` 上限 2000 字 → 對 commit 訊息 `trunc`。Slack incoming webhook 把 `content` 換成 `text`。

---

## 8. 完整範本（Discord webhook，已實測 sync / rollback / 失敗通知）

前置：`argocd-notifications-secret` 內有 key `discord-webhook`，值為完整 webhook URL（建立時勿用不帶 `-n` 的 `echo`，結尾換行會讓 URL 失效）。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.webhook.discord: |
    url: $discord-webhook
    headers:
      - name: Content-Type
        value: application/json

  template.app-deployed-discord: |
    webhook:
      discord:
        method: POST
        body: |
          {{- $rev := .app.status.operationState.syncResult.revision -}}
          {{- $c := call .repo.GetCommitMetadata $rev -}}
          {{- $by := default "auto-sync" .app.status.operationState.operation.initiatedBy.username -}}
          {{- $msg := printf "✅ %s 部署成功\nsync: %s\ncommit: %s\n作者: %s\n觸發: %s\n訊息: %s" .app.metadata.name .app.status.sync.status (trunc 7 $rev) $c.Author $by (trim $c.Message | trunc 1500) -}}
          {"content": {{ toJson $msg }} }

  template.app-failed-discord: |
    webhook:
      discord:
        method: POST
        body: |
          {{- $rev := .app.status.sync.revision -}}
          {{- $c := call .repo.GetCommitMetadata $rev -}}
          {{- $msg := printf "❌ %s 部署異常\nhealth: %s\nsync: %s\ncommit: %s\n作者: %s\n訊息: %s" .app.metadata.name .app.status.health.status .app.status.sync.status (trunc 7 $rev) $c.Author (trim $c.Message | trunc 1500) -}}
          {"content": {{ toJson $msg }} }

  trigger.on-deployed: |
    - when: app.status.operationState != nil and app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'
      oncePer: app.status.operationState.finishedAt
      send: [app-deployed-discord]

  trigger.on-sync-failed: |
    - when: app.status.operationState != nil and app.status.operationState.phase in ['Error', 'Failed']
      oncePer: app.status.operationState?.syncResult?.revision
      send: [app-failed-discord]

  trigger.on-health-degraded: |
    - when: app.status.health.status == 'Degraded'
      oncePer: app.status.operationState?.syncResult?.revision
      send: [app-failed-discord]

  subscriptions: |
    - recipients:
        - discord
      triggers:
        - on-deployed
        - on-sync-failed
        - on-health-degraded
```

- 以 GitOps 管理此 cm 時，從叢集匯出後移除 `resourceVersion` / `uid` / `creationTimestamp` 再入 git；Secret 不入 git。
- 引導使用者在 `kubectl edit`（vim）貼上多行 YAML 前先 `:set paste`，避免自動縮排破壞區塊結構。

---

## 9. 驗證與排錯

CLI 的 `--argocd-repo-server` 預設 `argocd-repo-server:8081`，只在叢集內可解析 → 本機執行時 `GetCommitMetadata` 會失敗。
在 notifications controller pod 內執行：

```bash
# 只評估 trigger 條件並印出結果，不發送
kubectl -n argocd exec deploy/argocd-notifications-controller -- \
  /usr/local/bin/argocd admin notifications trigger run on-deployed <app>

# 渲染 template 到 stdout（未指定 --recipient 時預設 console:stdout，不發送）
kubectl -n argocd exec deploy/argocd-notifications-controller -- \
  /usr/local/bin/argocd admin notifications template notify app-deployed-discord <app>
```

| 症狀 | 優先檢查 |
|---|---|
| 完全沒發送 | `trigger run` 條件是否成立；訂閱是否涵蓋該 app（§2）；是否被去重（§4，看 `notified.notifications.argoproj.io`） |
| log 有 template 渲染錯誤 | 貼上時縮排跑掉；取了不存在的巢狀欄位（§7） |
| log 有 commit metadata 錯誤 | repo-server 取不到該 SHA（repo 權限、SHA 不屬於 app source repo） |
| Discord 回 400 | JSON 壞掉（未用 `toJson`）；`content` 超過 2000 字 |
| Discord 回 401 / 404 | webhook URL 錯誤或結尾多了換行；secret key 名與 cm 的 `$key` 不一致 |
| rollback 沒通知 | auto-sync 開著無法 ArgoCD rollback；`oncePer` 去重（§3 / §4）；用了 `kubectl rollout undo`（§5） |
