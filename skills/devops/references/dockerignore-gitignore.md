# .dockerignore 與 .gitignore 範本

依偵測到的語言選用對應的 `.dockerignore` 範本。

---

## Go 後端 .dockerignore

```
bin/
tmp/
*.exe
*.test
.git/
.gitignore
.env
storage/
*.log
.DS_Store
.devops/
.air.toml
```

## Python 後端 .dockerignore

```
.venv/
venv/
__pycache__/
*.pyc
*.pyo
.pytest_cache/
.mypy_cache/
.coverage
htmlcov/
*.egg-info/
.git/
.gitignore
.env
storage/*.db
*.log
tmp/
.DS_Store
.devops/
```

## Node.js 後端 .dockerignore

```
node_modules/
dist/
.git/
.gitignore
.env
*.log
tmp/
.DS_Store
.devops/
coverage/
.nyc_output/
```

## 前端（Vite）.dockerignore

```
node_modules/
dist/
.git/
.gitignore
.env
*.log
tmp/
.DS_Store
.devops/
```

## PHP 後端 .dockerignore

```
vendor/
.git/
.gitignore
.env
*.log
tmp/
storage/
.DS_Store
.devops/
tests/
phpunit.xml
```

---

## 通用排除原則

- **依賴目錄**（`node_modules/`、`vendor/`、`.venv/`）— 建置階段會重新安裝。
- **建置產物**（`dist/`、`bin/`）— 建置階段會重新產生。
- **機密資料**（`.env`）— 必須在運行時注入，絕不烘焙進映像。
- **版控**（`.git/`）— 顯著減少映像大小。
- **DevOps 配置**（`.devops/`）— dockerfile 本身不應存在於映像內部。

---

## .gitignore 更新

將以下 Docker 相關條目附加到專案根目錄的 `.gitignore`（如尚未存在）：

```gitignore
# Docker
docker-compose.override.yml
```

`docker-compose.override.yml` 用於本地開發者自訂配置，不應提交至版控。
