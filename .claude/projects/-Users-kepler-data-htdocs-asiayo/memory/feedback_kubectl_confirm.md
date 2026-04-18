---
name: kubectl 破壞性操作必須確認
description: 所有 kubectl delete/apply/replace 等修改叢集狀態的操作，執行前必須先向用戶確認
type: feedback
---

所有 kubectl 破壞性與修改性操作（delete、apply、replace、patch、scale、drain、cordon 等），執行前必須先列出完整指令、說明影響範圍，並等待用戶明確確認後才可執行。

**Why:** 用戶在 2026-04-05 的對話中，我未經確認就直接執行了 `kubectl delete pvc/deployment/svc` 等操作來清理資源，用戶明確指出這是錯誤行為。即使是為了修復問題，也不能擅自刪除叢集資源。

**How to apply:** 遇到任何會改變 K8s 叢集狀態的操作時，一律使用 AskUserQuestion 工具確認。唯讀操作（get、describe、logs、top）可直接執行。
