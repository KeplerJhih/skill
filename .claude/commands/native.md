# Native iOS Development

此指令用於啟動原生 iOS 開發模式。

## 核心技能
必須載入並遵循以下 Skill：
- **native-ios-development** (`.claude/skills/native-ios/SKILL.md`)

## 工具使用
按需使用以下工具進行構建與模擬：
- **MCP**: `ios-simulator` (若可用)
- **MCP**: `xcodebuild` (若可用)
- **Shell**: 若上述 MCP 不可用，則使用 `xcrun simctl` 與 `xcodebuild` 指令替代。

## 自動化流程
- **自動編譯**：每次完成代碼修改後，**必須**自動執行 `xcodebuild` build 指令（或使用 MCP），確保代碼可編譯通過。若編譯失敗，需立即修復錯誤。

## 執行步驟
1. 讀取並理解 `native-ios-development` Skill 的架構與規範。
2. 根據需求使用 MCP 或 Shell 工具進行開發、測試與模擬器操作。
3. 修改完成後，自動執行編譯檢查。
