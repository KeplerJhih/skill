---
name: Skill 載入不可遺漏
description: 執行 /doit 或 /team 時，必須在藍圖前完整載入所有相關 Skill，不可遺漏
type: feedback
---

執行任務流程時，必須在制定藍圖前完整載入所有相關 Skill，不可遺漏任何一個。

**Why:** 用戶在 2026-04-05 的對話中，我在生成 K8s Makefile 時只載入了 k8s skill，遺漏了 devops-development skill，用戶需要手動提醒「確定有加載 /devops-development」才補上。Skill 包含完整的實作規範，遺漏會導致產出不符合標準。

**How to apply:** 
1. 分析任務涉及的所有領域（如 K8s + DevOps/Makefile）
2. 列出所有需載入的 Skill 清單，明確告知用戶
3. 使用 Skill tool 逐一載入，每個都確認載入成功
4. 全部載入完成後才制定藍圖
