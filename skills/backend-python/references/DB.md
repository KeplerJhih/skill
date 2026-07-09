# 資料庫生命週期管理 (Database Lifecycle)

## 核心原則

1. **手動遷移，絕不自動** — Migration 永遠由開發者手動執行 `make migrate`，應用程式啟動時不會自動 migrate。
2. **啟動不阻斷** — DB 表不完整時，應用仍可啟動，但會輸出明確警告。API 請求遇到缺表時回傳 503 而非 500 raw error。
3. **CLI 命令友善降級** — `create-admin`、`run-cron` 等命令在 DB 未就緒時輸出一行提示，不噴 traceback。
4. **Scheduler 守護** — 排程器只在 DB 就緒時啟動。

## 關鍵檔案

| 檔案 | 職責 |
|------|------|
| `pkg/db/health.py` | `check_db_ready(app)` — 檢查必要表是否存在，回傳 `(bool, missing_set)` |
| `app/__init__.py` | 啟動時調用 `check_db_ready()`，結果存入 `app.extensions['db_ready']` |
| `app/infrastructure/scheduler.py` | `init_scheduler()` 只在 `db_ready=True` 時由 `create_app()` 調用 |

## 啟動流程

```
create_app()
  ├─ 初始化 Flask 擴展 (db, migrate, jwt, cors)
  ├─ 註冊路由 & CLI
  ├─ 註冊全域 errorhandler (AppError + OperationalError)
  ├─ 判斷是否為 CLI 命令（flask db / flask seed 等）
  │   └─ 是 → 跳過 DB 檢查和 Scheduler
  ├─ check_db_ready(app) → app.extensions['db_ready']
  │   ├─ True  → 正常啟動 + 啟動 Scheduler
  │   └─ False → 輸出醒目警告框，跳過 Scheduler
  └─ return app
```

## 全域 OperationalError 處理

在 `create_app()` 中註冊：

```python
@app.errorhandler(OperationalError)
def handle_db_error(e):
    if "no such table" in str(e):
        return error(message="資料庫尚未初始化，請在後端執行: make migrate", code=503)
    return error(message="資料庫錯誤", code=500)
```

API 遇到缺表時統一回傳：
```json
{"code": 503, "message": "資料庫尚未初始化，請在後端執行: make migrate", "data": null}
```

## CLI 命令守護

CLI 命令（`create-admin`、`run-cron`）內部用 try/except 捕獲 `OperationalError`：

```python
try:
    # DB 操作
except OperationalError as e:
    if "no such table" in str(e):
        click.secho("Error: 資料庫尚未初始化，請先執行: make migrate", fg="red")
        raise SystemExit(1)
    raise
```

## Makefile 命令

| 命令 | 用途 | 說明 |
|------|------|------|
| `make migrate` | 執行遷移 | `flask db upgrade`，只套用尚未執行的 migration |
| `make migrate-create msg="描述"` | 建立遷移腳本 | `flask db migrate -m "描述"` |
| `make init-db` | 首次初始化 | `migrate` + 互動式 `create-admin`，一步到位 |
| `make reset-db` | 重置資料庫 | 刪除 `storage/dev.db` → `migrate` → `create-admin`，有確認提示 |

## 開發流程

```bash
# 首次 clone 專案
cd backend/python
make init-db

# 拉了新的 migration（別人加了表/欄位）
make migrate

# DB 損壞或想清空重來
make reset-db

# 新增/修改 Model 後，產生 migration
make migrate-create msg="add xxx column to yyy"
# 檢查 migrations/versions/ 下新生成的檔案
make migrate
```

## 常見陷阱與防範

### 1. 勿在空 DB 上跑 `flask db migrate`

**問題**：DB 為空時，`flask db migrate` 會生成一個「建立所有表」的 migration，與既有 migration 鏈衝突。

**防範**：永遠先 `make migrate`（upgrade）建表，再 `make migrate-create` 產生差異腳本。

### 2. `storage/dev.db` 在 `.gitignore`

**問題**：git 操作不會保留 DB 檔案，切分支、clone 後 DB 消失。

**防範**：切回分支或 clone 後立即 `make migrate` 或 `make init-db`。

### 3. Scheduler 啟動時查 DB

**防範**：已由 `create_app()` 統一控制 — `db_ready=False` 時不啟動 Scheduler。

### 4. CLI 命令（非 db 相關）在 migrate 前執行

**防範**：CLI 命令內部捕獲 `OperationalError`，輸出友善提示而非 traceback。

### 5. 測試用 `db.drop_all()` 破壞正式 DB

**問題**：`conftest.py` 中若以 `config_name="dev"` 建立 app，`check_db_ready()` 會呼叫 `inspect(db.engine)` 導致引擎快取指向 `storage/dev.db`。之後修改 `SQLALCHEMY_DATABASE_URI` 為 `:memory:` 已無效 — 引擎已被快取。測試結束時 `db.drop_all()` 就會刪除 dev.db 的所有業務表（alembic_version 不受影響因為它不是 Model），造成「DB 只剩 alembic_version」的症狀。

**防範**：`conftest.py` 必須使用 `create_app(config_name="testing")`，而 `TestConfig` 在類屬性中直接設定 `SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"`、`TESTING = True`、`SCHEDULER_ENABLED = False`。這樣引擎從一開始就指向 in-memory DB，絕不會碰到 dev.db。
