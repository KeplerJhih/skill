# Atlantis Integration Guide

When using [Atlantis](https://www.runatlantis.io/) for GitOps-driven Terraform, follow these guidelines.

---

## Core Concept

```
Developer → MR → Atlantis Plan → Review → Atlantis Apply → Merge MR
```

**Never merge before apply.** Atlantis enforces: plan → apply → merge. This ensures the code in `main` always matches the actual infrastructure state.

---

## Project Structure (with Atlantis)

```
terraform/                      # Git repo root
├── .gitignore                  # Exclude .terraform/, *.tfstate, repos.yaml
├── atlantis.yaml               # Atlantis project config (進 git)
├── repos.example.yaml          # Server-side config 範例 (進 git，給團隊參考)
├── modules/
│   ├── gcs-bucket/
│   ├── networking/
│   └── compute/
└── env/
    ├── dev/
    │   ├── main.tf             # Module calls
    │   ├── variables.tf
    │   ├── outputs.tf
    │   ├── providers.tf        # Provider + remote backend
    │   └── terraform.tfvars
    ├── staging/
    └── prod/
```

**Key files:**

| File | Location | In Git? | Purpose |
|------|----------|:---:|---------|
| `atlantis.yaml` | Repo root | ✅ | 定義 Atlantis 要管理哪些目錄、autoplan 規則 |
| `repos.example.yaml` | Repo root | ✅ | Server-side config 範例，給團隊成員參考 |
| `repos.yaml` | Atlantis server 本地 | ❌ | 實際的 server-side 權限設定（.gitignore 排除） |

---

## Remote Backend (Required)

Atlantis clones a fresh repo for every plan/apply. Local backend **will lose state**. Always use a remote backend.

**GCP (GCS):**
```hcl
backend "gcs" {
  bucket = "{project}-terraform-state"
  prefix = "atlantis/{env}"
}
```

**AWS (S3 + DynamoDB):**
```hcl
backend "s3" {
  bucket         = "{project}-terraform-state"
  key            = "atlantis/{env}/terraform.tfstate"
  region         = "ap-northeast-1"
  dynamodb_table = "{project}-terraform-lock"
}
```

> Create the state bucket **before** running Atlantis. If migrating from local to remote, use `terraform init -migrate-state`.

---

## atlantis.yaml (Repo-Side Config)

Lives in the Git repo root. Defines which directories Atlantis should manage.

**Single environment:**
```yaml
version: 3
projects:
  - name: dev
    dir: env/dev
    workspace: default
    terraform_version: v1.5.7
    autoplan:
      when_modified:
        - "*.tf"
        - "*.tfvars"
        - "../../modules/**/*.tf"    # Trigger on module changes too
      enabled: true
```

**Multi-environment:**
```yaml
version: 3
projects:
  - name: dev
    dir: env/dev
    workspace: default
    autoplan:
      when_modified: ["*.tf", "*.tfvars", "../../modules/**/*.tf"]
      enabled: true
  - name: staging
    dir: env/staging
    workspace: default
    autoplan:
      when_modified: ["*.tf", "*.tfvars", "../../modules/**/*.tf"]
      enabled: true
  - name: prod
    dir: env/prod
    workspace: default
    autoplan:
      when_modified: ["*.tf", "*.tfvars", "../../modules/**/*.tf"]
      enabled: false    # Prod requires manual `atlantis plan -p prod`
```

---

## repos.yaml (Server-Side Config)

Lives on the Atlantis server **outside** the Git repo. Controls permissions.

```yaml
repos:
  - id: "gitlab.example.com/team/infra"
    allow_custom_workflows: true    # Allow repo to define custom workflow steps
    allowed_overrides:
      - workflow                    # Allow repo to select custom workflows
```

### Two-Layer Security Model

```
repos.yaml (管理員)              atlantis.yaml (開發者)
┌──────────────────────┐         ┌──────────────────────────┐
│ "這個 repo 可以用       │         │ "我要用 notify workflow，  │
│  自訂 workflow"         │ ──允許──▶│  plan 完後 curl Discord"  │
│                        │         │                          │
│ allow_custom_workflows │         │ workflows:               │
│ allowed_overrides:     │         │   notify:                │
│   - workflow           │         │     plan: ...            │
└──────────────────────┘         └──────────────────────────┘
```

- **`repos.yaml`** = 門鎖（管理員控制「能不能」）
- **`atlantis.yaml`** = 房間設定（開發者控制「怎麼做」）
- 門鎖不打開，房間裡怎麼改都沒用
- **Never commit `repos.yaml`** — add to `.gitignore`
- Commit `repos.example.yaml` as template（同 `.env.example` / `.env` 模式）

---

## Webhook Notifications (Discord/Slack)

### Option A: Custom workflow steps (atlantis.yaml)

Runs only on success. If a prior step (init/plan) fails, notification is skipped.

```yaml
workflows:
  notify:
    plan:
      steps:
        - init
        - plan
        - run: "curl -H 'Content-Type: application/json' -X POST -d '{\"content\": \"📋 Plan done: $BASE_REPO_OWNER/$BASE_REPO_NAME #$PULL_NUM\"}' $DISCORD_WEBHOOK_URL"
    apply:
      steps:
        - apply
        - run: "curl -H 'Content-Type: application/json' -X POST -d '{\"content\": \"✅ Apply done: $BASE_REPO_OWNER/$BASE_REPO_NAME #$PULL_NUM\"}' $DISCORD_WEBHOOK_URL"
```

> Requires `allow_custom_workflows: true` + `allowed_overrides: [workflow]` in `repos.yaml`.

### Option B: post_workflow_hooks (repos.yaml)

Runs after workflow completes, but **not on workflow failure** (e.g., init error).

```yaml
repos:
  - id: "gitlab.example.com/team/infra"
    post_workflow_hooks:
      - run: "curl -H 'Content-Type: application/json' -X POST -d '{\"content\": \"🔔 Atlantis done: $BASE_REPO_OWNER/$BASE_REPO_NAME #$PULL_NUM - $COMMAND_NAME\"}' $DISCORD_WEBHOOK_URL"
```

### Available Environment Variables

| Variable | workflow steps | post_workflow_hooks |
|----------|:---:|:---:|
| `$BASE_REPO_OWNER` | ✅ | ✅ |
| `$BASE_REPO_NAME` | ✅ | ✅ |
| `$PULL_NUM` | ✅ | ✅ |
| `$COMMAND_NAME` | ✅ | ✅ |
| `$WORKSPACE` | ✅ | ✅ |
| `$BASE_REPO_FULL_NAME` | ✅ | ❌ may be empty |
| `$COMMAND_OUTPUT` | ❌ | ❌ |

---

## GCP Authentication for Atlantis

| Method | Use Case |
|--------|----------|
| **ADC** (`gcloud auth application-default login`) | Local development / testing |
| **Environment variable** (`GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json`) | Local Atlantis server |
| **Workload Identity** (GKE pod → GCP SA, no key file) | Production (recommended) |

For local Atlantis with Service Account:
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/sa-key.json"
atlantis server --atlantis-url="..." ...
```

> **Never commit SA key files.** Add `*.json` key files to `.gitignore`.

---

## Atlantis Server Startup

```bash
atlantis server \
  --atlantis-url="https://{ngrok-or-public-url}" \
  --gitlab-hostname="{gitlab-host}" \
  --gitlab-user="{gitlab-username}" \
  --gitlab-token="{personal-access-token}" \
  --gitlab-webhook-secret="{webhook-secret}" \
  --repo-allowlist="{gitlab-host}/{repo-path}" \
  --repo-config=/path/to/repos.yaml
```

**GitLab Token requirements:** Must have `api` scope (not just `read_api`).

**GitLab Webhook settings** (`Settings → Webhooks`):
- URL: `https://{atlantis-url}/events`
- Secret Token: must match `--gitlab-webhook-secret`
- Triggers: ✅ Push events, ✅ Comments, ✅ Merge request events

---

## State Migration

When restructuring (e.g., inline resources → modules), existing resources must be migrated in state:

```bash
terraform state mv google_storage_bucket.test module.bucket_test.google_storage_bucket.this
```

Always run `terraform plan` after migration to confirm **No changes** before pushing.

---

## Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| HTTP 405 on webhook | Push/test events — Atlantis only handles MR + Comment | Normal, ignore |
| `X-Gitlab-Token did not match` | Webhook secret mismatch | Match GitLab webhook secret with `--gitlab-webhook-secret` |
| `insufficient_scope` | Token only has `read_api` | Recreate token with `api` scope |
| `bucket doesn't exist` | Remote backend bucket missing | Create the state bucket first |
| `not allowed to define custom workflows` | Missing server-side permission | Add `allow_custom_workflows: true` to `repos.yaml` |
| `not allowed to set workflow key` | Missing override permission | Add `allowed_overrides: [workflow]` to `repos.yaml` |
| Plan shows recreate existing resources | State doesn't know about them | `terraform import` the resources |
| MR merged before apply | `action: "merge"` event ignored by Atlantis | Always plan → apply → then merge |
