# Command: /deploy (遠端部署)

此指令用於連線遠端伺服器執行標準化部署流程。支援 SSH / AWS SSM / gcloud SSH 三種連線方式。

**⚠️ 核心原則：確認先行，嚴禁未經確認直接執行部署。**

---

## 使用者需求

$ARGUMENTS

---

## 前置準備 — 必須首先執行

載入 deploy skill：

```
Skill("deploy-remote")
```

---

## 觸發邏輯

### 情境 A：使用者未提供參數

**判定標準**：使用者僅輸入 `/deploy`，後面沒有描述。

**你的行動**：

詢問使用者：

> **遠端部署助手**
>
> 請提供以下資訊：
>
> 1. **專案名稱**（必填）— 如 `141`、`money`
> 2. **服務類型** — `backend` / `frontend` / `node` / `all`（預設 all）
> 3. **環境** — `dev` / `uat` / `prod`（預設 dev）
> 4. **連線方式** — `ssh` / `ssm` / `gcloud`
> 5. **連線目標** — SSH: `user@host`、SSM: `instance-id`、gcloud: `instance-name --zone=xxx`
>
> *範例：`/deploy 141 backend dev ssh root@1.2.3.4`*

---

### 情境 B：使用者已提供參數

**判定標準**：使用者輸入 `/deploy [參數]`。

**參數解析規則**：

```
/deploy {project}                              → 全服務部署，需詢問其餘資訊
/deploy {project} {service}                    → 需詢問環境與連線資訊
/deploy {project} {service} {env} {method} {target}  → 完整參數，直接執行
```

| 位置 | 參數 | 範例 |
|------|------|------|
| 1 | 專案名 | `141` |
| 2 | 服務類型 | `backend` / `frontend` / `node` / `all` |
| 3 | 環境 | `dev` / `uat` / `prod` |
| 4 | 連線方式 | `ssh` / `ssm` / `gcloud` |
| 5+ | 連線目標 | `root@1.2.3.4`、`i-0abc123`、`my-vm --zone=asia-east1-b` |

**你的行動**：

1. 解析已提供的參數
2. 若有缺漏，僅詢問缺少的部分
3. 依照 deploy skill 的流程執行：
   - 顯示部署摘要
   - 等待確認
   - 執行部署
   - 回報結果

---

## 連線方式快速參考

### SSH

```bash
ssh {user}@{host} "{commands}"
```

### AWS SSM

優先使用 MCP 工具 `mcp__aws-api__call_aws`，若不可用則降級為 AWS CLI：

```bash
aws ssm send-command --instance-ids "{id}" --document-name "AWS-RunShellScript" \
  --parameters 'commands=["{commands}"]'
```

### gcloud SSH

```bash
gcloud compute ssh {instance} --zone={zone} --command="{commands}"
```

---

## 執行流程

1. **載入 Skill** → `Skill("deploy-remote")`
2. **收集參數** → 解析 `$ARGUMENTS` + 互動補全
3. **顯示摘要** → 部署目標、服務、環境、連線方式
4. **等待確認** → 使用者明確同意後才執行
5. **執行部署** → git pull + devops_xxx.sh
6. **回報結果** → 成功/失敗狀態
