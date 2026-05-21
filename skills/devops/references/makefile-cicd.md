# Makefile 完整範本（含 Container Runtime 偵測 + CI/CD 目標）

以下提供完整的 Makefile 範本，供偵測到服務後參考生成。

> **核心設計**：Makefile 是 CI/CD 管線的**唯一入口**，所有 `docker build`、`push`、`scan` 操作都透過 `make` 目標執行。

---

## 通用 Makefile 範本

此範本適用於所有語言/框架，依掃描結果調整 `DOCKER_IMAGE_NAME` 與 `DOCKERFILE_PATH`。

```makefile
# =============================================================================
# {Service Name} Makefile
# =============================================================================

.DEFAULT_GOAL := help

# -----------------------------------------------------------------------------
# Container Runtime 自動偵測：優先 docker，fallback nerdctl
# -----------------------------------------------------------------------------
CR := $(shell command -v docker >/dev/null 2>&1 && echo docker || echo nerdctl)

# nerdctl 需要 -n namespace 來指定 containerd namespace；docker 沒有 namespace 概念。
# NAMESPACE 預設值依「主要部署場景」決定：
#   - 純 docker build → push registry → K8s pull：預設 default 即可（docker 不受影響）
#   - 地端 nerdctl build → K8s pod 直接拉取：建議改預設為 k8s.io
#     原因：ACK / k3s 上的 K8s 只看 containerd 的 k8s.io namespace，
#     若 build 進 default，pod 必 ImagePullBackOff。
NAMESPACE ?= default
CR_NS = $(if $(filter nerdctl,$(CR)),-n $(NAMESPACE))

# -----------------------------------------------------------------------------
# 專案設定（依掃描結果填入）
# -----------------------------------------------------------------------------
DOCKER_IMAGE_NAME := {service-name}
DOCKERFILE_PATH := .devops/dockerfile

# -----------------------------------------------------------------------------
# 顏色定義
# -----------------------------------------------------------------------------
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m
BOLD := \033[1m

# =============================================================================
# 幫助資訊
# =============================================================================

help: ## 顯示此幫助資訊
	@echo ""
	@echo "$(CYAN)╭─────────────────────────────────────────────────────────╮$(RESET)"
	@echo "$(CYAN)│  $(BOLD)$(YELLOW){Service Display Name}$(RESET)$(CYAN)                         │$(RESET)"
	@echo "$(CYAN)╰─────────────────────────────────────────────────────────╯$(RESET)"
	@echo ""
	@echo "$(YELLOW)Container Runtime: $(BOLD)$(CR)$(RESET)"
	@echo ""
	@echo "$(BOLD)$(CYAN)可用指令:$(RESET)"
	@echo "$(CYAN)═══════════════════════════════════════════════════════════$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# Build 相關指令
# =============================================================================

build-dev: ## 建置開發環境映像
	@echo "$(CYAN)建置開發環境映像: $(DOCKER_IMAGE_NAME):dev$(RESET)"
	$(CR) $(CR_NS) build -f $(DOCKERFILE_PATH) -t $(DOCKER_IMAGE_NAME):dev .
	@echo "$(GREEN)建置完成！$(RESET)"

build-prod: ## 建置生產環境映像（需指定 REPO，例如：make build-prod REPO=registry/proj/svc:1.0.0）
	$(MAKE) check-repo-param
	@echo "$(CYAN)建置生產環境映像: $(REPO)$(RESET)"
	$(CR) $(CR_NS) build -f $(DOCKERFILE_PATH) -t $(REPO) .
	$(MAKE) info-image

# =============================================================================
# CI/CD 相關指令
# =============================================================================

push: ## 推送映像至 Registry（需指定 REPO）
	$(MAKE) check-repo-param
	@echo "$(CYAN)推送映像: $(REPO)$(RESET)"
	$(CR) $(CR_NS) push $(REPO)
	@echo "$(GREEN)推送完成！$(RESET)"

scan: ## 掃描映像安全漏洞（需指定 REPO）
	$(MAKE) check-repo-param
	@echo "$(CYAN)掃描映像漏洞: $(REPO)$(RESET)"
	@if command -v trivy >/dev/null 2>&1; then \
		trivy image --severity HIGH,CRITICAL $(REPO); \
	elif command -v docker >/dev/null 2>&1 && docker scout version >/dev/null 2>&1; then \
		docker scout cves $(REPO); \
	else \
		echo "$(YELLOW)未找到 trivy 或 docker scout，跳過漏洞掃描$(RESET)"; \
	fi

lint-dockerfile: ## 檢查 dockerfile 最佳實踐
	@echo "$(CYAN)檢查 dockerfile: $(DOCKERFILE_PATH)$(RESET)"
	@if command -v hadolint >/dev/null 2>&1; then \
		hadolint $(DOCKERFILE_PATH); \
		echo "$(GREEN)Lint 通過！$(RESET)"; \
	else \
		echo "$(YELLOW)未找到 hadolint，跳過 lint 檢查$(RESET)"; \
		echo "$(YELLOW)安裝方式: brew install hadolint$(RESET)"; \
	fi

# =============================================================================
# 輔助指令
# =============================================================================

info-image: ## 顯示映像詳細資訊（需指定 REPO）
	@echo ""
	@echo "$(CYAN)╔═══════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(CYAN)║  $(GREEN)映像建置完成$(CYAN)                                          ║$(RESET)"
	@echo "$(CYAN)╠═══════════════════════════════════════════════════════════╣$(RESET)"
	@echo "$(CYAN)║$(RESET)  Image:     $(BOLD)$(REPO)$(RESET)"
	@echo "$(CYAN)║$(RESET)  Runtime:   $(BOLD)$(CR)$(RESET)"
	@echo "$(CYAN)║$(RESET)  Size:      $(BOLD)$$($(CR) $(CR_NS) image inspect $(REPO) --format='{{.Size}}' 2>/dev/null | awk '{printf "%.1f MB", $$1/1024/1024}' || echo 'N/A')$(RESET)"
	@echo "$(CYAN)╚═══════════════════════════════════════════════════════════╝$(RESET)"
	@echo ""

clean: ## 清理本地開發映像與懸掛映像
	@echo "$(YELLOW)清理開發映像...$(RESET)"
	-$(CR) $(CR_NS) rmi $(DOCKER_IMAGE_NAME):dev 2>/dev/null
	@echo "$(YELLOW)清理懸掛映像...$(RESET)"
	-$(CR) $(CR_NS) image prune -f
	@echo "$(GREEN)清理完成！$(RESET)"

# =============================================================================
# 版本管理
# =============================================================================

auto-version: ## 🔄 安裝自動版本管理（Git hook + Python 腳本）
	@echo "$(CYAN)安裝自動版本管理...$(RESET)"
	mkdir -p .git/hooks .dev
	cp .devops/exec/autoversion/post-commit .git/hooks/post-commit
	chmod +x .git/hooks/post-commit
	cp -rf .devops/exec/autoversion/autoversion.py .dev/
	@echo "$(GREEN)自動版本管理已安裝！$(RESET)"
	@echo "$(YELLOW)提示: commit message 使用 feat:/fix:/break: 等前綴即可自動 bump 版本$(RESET)"

# =============================================================================
# 內部輔助（非公開目標）
# =============================================================================

check-repo-param:
	@if [ -z "$(REPO)" ]; then \
		echo ""; \
		echo "$(RED)╔═══════════════════════════════════════════════════════════╗$(RESET)"; \
		echo "$(RED)║  錯誤: 必須指定 REPO 參數！                                ║$(RESET)"; \
		echo "$(RED)╚═══════════════════════════════════════════════════════════╝$(RESET)"; \
		echo ""; \
		echo "$(YELLOW)範例:$(RESET)"; \
		echo "  make build-prod REPO=gcr.io/myproj/$(DOCKER_IMAGE_NAME):1.0.0"; \
		echo "  make push       REPO=gcr.io/myproj/$(DOCKER_IMAGE_NAME):1.0.0"; \
		echo ""; \
		exit 1; \
	fi

# =============================================================================
# 偽目標聲明
# =============================================================================

.PHONY: help \
	build-dev \
	build-prod \
	push \
	scan \
	lint-dockerfile \
	info-image \
	clean \
	auto-version \
	check-repo-param
```

---

## 前端專用擴展

前端服務可在上述通用範本基礎上加入以下目標：

```makefile
# =============================================================================
# 前端專用目標（追加到通用範本之後）
# =============================================================================

build-dev: ## 建置開發環境映像（啟用 Mock）
	@echo "$(CYAN)建置開發環境映像: $(DOCKER_IMAGE_NAME):dev$(RESET)"
	$(CR) $(CR_NS) build -f $(DOCKERFILE_PATH) --build-arg VITE_SOCKET_MOCK=true -t $(DOCKER_IMAGE_NAME):dev .
	@echo "$(GREEN)建置完成！$(RESET)"

build-prod: ## 建置生產環境映像（需指定 REPO）
	$(MAKE) check-repo-param
	@echo "$(CYAN)建置生產環境映像: $(REPO)$(RESET)"
	$(CR) $(CR_NS) build -f $(DOCKERFILE_PATH) --build-arg VITE_SOCKET_MOCK=false -t $(REPO) .
	$(MAKE) info-image
```

### 重點說明

- **`--build-arg`**：前端如有建置時期需要注入的旗標（如 Mock 開關），透過 `--build-arg` 傳入，而非 `ENV`。
- **開發 vs 生產**：`build-dev` 啟用 Mock，`build-prod` 關閉 Mock。

---

## Optional：本地預覽 `run` target（含 port 自動偵測）

需要在本地跑容器預覽（前端 SPA / Web API 等）時，可在通用範本基礎上加入 `run` target。
**避免寫死容器外部 port** — 用 `lsof` 偵測佔用，自動往上找可用 port。

```makefile
# 本地預覽容器外部 port 預設值；被佔用會自動往上加（10881, 10882, ...）
DEV_PORT ?= <preferred-dev-port>     # 例：10880

run: ## 運行容器（dev image），port 被佔用自動 +1
	@$(MAKE) run-check
	@PORT=$(DEV_PORT); \
	while lsof -nP -iTCP:$$PORT -sTCP:LISTEN >/dev/null 2>&1; do \
		echo "$(YELLOW)Port $$PORT 已被占用，嘗試 $$((PORT + 1))$(RESET)"; \
		PORT=$$((PORT + 1)); \
	done; \
	echo "$(GREEN)容器將在 http://localhost:$$PORT 運行（Ctrl+C 停止）$(RESET)"; \
	$(CR) $(CR_NS) run -it --rm -p $$PORT:<container-port> $(DOCKER_IMAGE_NAME):dev || true

run-check:
	@if ! $(CR) $(CR_NS) image inspect $(DOCKER_IMAGE_NAME):dev >/dev/null 2>&1; then \
		echo "$(RED)映像不存在，請先 make build-dev$(RESET)"; exit 1; \
	fi
```

**重點**：
- `DEV_PORT` 用 `?=` 條件賦值，外部可 override：`make run DEV_PORT=12000`
- `<container-port>` 依服務實際監聽埠號填入（Web SPA Nginx 通常 80 / 8080；後端 API 依 dockerfile EXPOSE）
- 不寫死 `docker` / `nerdctl`，沿用 `$(CR) $(CR_NS)` 自動偵測
- 適用情境：服務需要在本地預覽 UI；純 CI/CD build-and-push 服務無需此 target

---

## 後端專用擴展（Go）

Go 後端可加入測試與格式化相關目標：

```makefile
# =============================================================================
# Go 後端專用目標（追加到通用範本之後）
# =============================================================================

test: ## 執行單元測試
	@echo "$(CYAN)執行單元測試...$(RESET)"
	go test ./... -v -cover
	@echo "$(GREEN)測試完成！$(RESET)"

lint: ## 執行程式碼檢查
	@echo "$(CYAN)執行 golangci-lint...$(RESET)"
	golangci-lint run ./...

fmt: ## 格式化程式碼
	gofmt -s -w .
	goimports -w .
```

---

## 後端專用擴展（Python）

```makefile
# =============================================================================
# Python 後端專用目標（追加到通用範本之後）
# =============================================================================

test: ## 執行單元測試
	@echo "$(CYAN)執行單元測試...$(RESET)"
	python -m pytest tests/ -v --cov
	@echo "$(GREEN)測試完成！$(RESET)"

lint: ## 執行程式碼檢查
	@echo "$(CYAN)執行 ruff check...$(RESET)"
	ruff check .

fmt: ## 格式化程式碼
	ruff format .
```

---

## Container Runtime 偵測機制說明

```makefile
# 偵測邏輯：
# 1. 檢查系統是否有 docker 指令 → 有則使用 docker
# 2. fallback 到 nerdctl（containerd 的 CLI 工具）
CR := $(shell command -v docker >/dev/null 2>&1 && echo docker || echo nerdctl)

# nerdctl 需要 -n namespace 參數來指定 containerd namespace
# docker 不需要此參數
# NAMESPACE 預設為 default，可覆蓋為 k8s.io 等
NAMESPACE ?= default
CR_NS = $(if $(filter nerdctl,$(CR)),-n $(NAMESPACE))
```

### 使用方式

```bash
# 使用預設 docker（或自動 fallback 到 nerdctl）
make build-prod REPO=myregistry/myapp:1.0.0

# 強制使用 nerdctl + 指定 namespace
make build-prod REPO=myregistry/myapp:1.0.0 CR=nerdctl NAMESPACE=k8s.io
```

---

## CI/CD 管線中的 Makefile 呼叫範例

### GitHub Actions

```yaml
steps:
  - name: Lint
    run: make -C {service-dir} lint-dockerfile

  - name: Build
    run: make -C {service-dir} build-prod REPO=$REGISTRY/$IMAGE:$GITHUB_SHA

  - name: Scan
    run: make -C {service-dir} scan REPO=$REGISTRY/$IMAGE:$GITHUB_SHA

  - name: Push
    run: make -C {service-dir} push REPO=$REGISTRY/$IMAGE:$GITHUB_SHA
```

### GitLab CI

```yaml
build:
  script:
    - make -C {service-dir} build-prod REPO=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
    - make -C {service-dir} scan REPO=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
    - make -C {service-dir} push REPO=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
```

### 本地開發

```bash
# 開發環境
make build-dev

# 生產環境測試
make build-prod REPO=myapp:test
make scan REPO=myapp:test

# 清理
make clean
```
