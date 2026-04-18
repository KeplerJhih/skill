# Auto-Version 自動版本管理

基於 Git post-commit hook，依 commit message 前綴自動 bump `version.json` 中的語意化版本號。

---

## 機制概覽

```
git commit -m "feat: 新功能"
    ↓ post-commit hook
.dev/autoversion.py 解析 commit message
    ↓ 匹配前綴
version.json 版本號 bump（minor +1）
    ↓ 自動提交
git commit -m "v0.2.0" --no-verify
```

## 版本前綴對照表

| 版本等級 | 前綴關鍵字 | 範例 |
|---------|-----------|------|
| **Major** (x.0.0) | `break:`, `breaking:`, `breaking-change:`, `publish:` | `break: 移除舊版 API` |
| **Minor** (0.x.0) | `feat:`, `feature:`, `refactor:`, `perf:`, `performance:`, `dep:`, `deprecated:` | `feat: 新增收藏功能` |
| **Patch** (0.0.x) | `fix:`, `bug:`, `add:`, `remove:`, `update:`, `rename:`, `adjust:`, `style:` | `fix: 修正登入錯誤` |

> 若 commit message 不匹配任何前綴，則不觸發版本更新。

## 排除分支

以下分支**不觸發**版本自動更新：`main`、`master`、`test`

---

## 檔案結構

```text
{service-dir}/
├── .devops/
│   └── exec/
│       └── autoversion/
│           ├── post-commit       # Git hook 腳本（shell）
│           └── autoversion.py    # 版本管理核心邏輯（Python）
├── .dev/                         # make auto-version 安裝後產生
│   └── autoversion.py            # （從 .devops 複製過來）
├── version.json                  # 版本號檔案（自動產生）
└── Makefile                      # 含 auto-version 目標
```

---

## Makefile 目標

```makefile
auto-version: ## 🔄 安裝自動版本管理（Git hook + Python 腳本）
	@echo "$(CYAN)安裝自動版本管理...$(RESET)"
	mkdir -p .git/hooks .dev
	cp .devops/exec/autoversion/post-commit .git/hooks/post-commit
	chmod +x .git/hooks/post-commit
	cp -rf .devops/exec/autoversion/autoversion.py .dev/
	@echo "$(GREEN)自動版本管理已安裝！$(RESET)"
	@echo "$(YELLOW)提示: commit message 使用 feat:/fix:/break: 等前綴即可自動 bump 版本$(RESET)"
```

> 注意：安裝後 `.dev/` 和 `version.json` 應加入 `.gitignore`（`.dev/` 是安裝副本，`version.json` 由 hook 自動管理）。

---

## post-commit Hook 範本

路徑：`{service-dir}/.devops/exec/autoversion/post-commit`

```sh
#!/bin/sh
#
# Git post-commit hook
# 由 make auto-version 安裝到 .git/hooks/post-commit
#

# 獲取最新的 commit message
commit_message=$(git log -1 --pretty=%B)

# 獲取 Python 腳本的絕對路徑
script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
autoversion_script="$project_root/.dev/autoversion.py"

# 檢查腳本是否存在
if [ ! -f "$autoversion_script" ]; then
    echo "錯誤: 找不到 autoversion.py 腳本在 $autoversion_script"
    echo "請執行 make auto-version 安裝"
    exit 1
fi

# 執行自動版本管理
echo "執行自動版本檢查..."
echo "Commit message: $commit_message"

# 切換到項目根目錄
cd "$project_root"

# 執行版本更新腳本
python3 "$autoversion_script" "$commit_message"

# 檢查執行結果
if [ $? -eq 0 ]; then
    echo "自動版本檢查完成"
else
    echo "自動版本檢查失敗"
fi
```

---

## autoversion.py 範本

路徑：`{service-dir}/.devops/exec/autoversion/autoversion.py`

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Git 自動版本管理系統
根據 commit message 前綴自動更新 version.json 中的語意化版本號
"""

import json
import os
import subprocess
import sys
from pathlib import Path


class AutoVersionManager:
    """自動版本管理器"""

    def __init__(self):
        self.prefixes = {
            'major': ['break', 'breaking', 'breaking-change', 'publish'],
            'minor': ['feat', 'feature', 'refactor', 'perf', 'performance', 'dep', 'deprecated'],
            'patch': ['fix', 'bug', 'add', 'remove', 'update', 'rename', 'adjust', 'style']
        }
        self.version_file = Path.cwd() / 'version.json'

    def get_prefix_list(self, prefix_type):
        """獲取指定類型的前綴列表"""
        return [f"{prefix}:" for prefix in self.prefixes[prefix_type]]

    def in_range(self, prefix_list, search_str):
        """檢查字串是否以指定範圍的前綴開頭"""
        return any(search_str.lower().startswith(prefix.lower()) for prefix in prefix_list)

    def get_current_branch(self):
        """獲取當前分支名稱"""
        try:
            result = subprocess.run(
                ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            return None

    def is_excluded_branch(self, branch_name=None):
        """檢查是否為排除分支（不觸發版本更新的分支）"""
        if branch_name is None:
            branch_name = self.get_current_branch()

        if branch_name is None:
            return False

        excluded_branches = ['main', 'master', 'test']
        return branch_name in excluded_branches

    def get_package_info(self):
        """獲取版本資訊"""
        if not self.version_file.exists():
            initial_version = {'version': '0.0.0'}
            self.save_package_info(initial_version)
            return initial_version

        try:
            with open(self.version_file, 'r', encoding='utf-8') as f:
                package_info = json.load(f)

            if 'version' not in package_info:
                package_info['version'] = '0.0.0'

            return package_info
        except (json.JSONDecodeError, FileNotFoundError):
            return {'version': '0.0.0'}

    def save_package_info(self, package_info):
        """儲存版本資訊"""
        try:
            with open(self.version_file, 'w', encoding='utf-8') as f:
                json.dump(package_info, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"保存版本文件失敗: {e}")
            return False
        return True

    def execute_git_command(self, command):
        """執行 Git 命令"""
        try:
            subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                check=True
            )
            return True
        except subprocess.CalledProcessError:
            return False

    def commit_version_update(self, new_version):
        """提交版本更新"""
        add_command = f"git add {self.version_file}"
        if not self.execute_git_command(add_command):
            print("添加版本文件到暫存區失敗")
            return False

        commit_command = f'git commit -m "v{new_version}" --no-verify'
        if not self.execute_git_command(commit_command):
            print("提交版本更新失敗")
            return False

        return True

    def update_version(self, commit_message):
        """根據 commit message 更新版本"""
        if self.is_excluded_branch():
            current_branch = self.get_current_branch()
            print(f"當前分支 '{current_branch}' 在排除列表中，跳過版本更新")
            return

        package_info = self.get_package_info()

        try:
            major, minor, patch = map(int, package_info['version'].split('.'))
        except ValueError:
            print("版本號格式錯誤，重置為 0.0.0")
            major, minor, patch = 0, 0, 0

        if self.in_range(self.get_prefix_list('major'), commit_message):
            major += 1
            minor = 0
            patch = 0
            print(f"檢測到 major 版本更新: {commit_message}")
        elif self.in_range(self.get_prefix_list('minor'), commit_message):
            minor += 1
            patch = 0
            print(f"檢測到 minor 版本更新: {commit_message}")
        elif self.in_range(self.get_prefix_list('patch'), commit_message):
            patch += 1
            print(f"檢測到 patch 版本更新: {commit_message}")
        else:
            print("未檢測到版本更新關鍵詞，跳過版本更新")
            return

        new_version = f"{major}.{minor}.{patch}"
        package_info['version'] = new_version

        if not self.save_package_info(package_info):
            print("保存版本資訊失敗")
            return

        print(f"版本已更新為: {new_version}")

        if self.commit_version_update(new_version):
            print(f"版本更新已自動提交: v{new_version}")
        else:
            print("自動提交版本更新失敗")


def parse_arguments():
    """解析命令列參數"""
    if len(sys.argv) < 2:
        print("使用方式: python autoversion.py <commit-message>")
        sys.exit(1)

    commit_message = ""

    for arg in sys.argv[1:]:
        if arg.startswith('--commit-message='):
            commit_message = arg.split('--commit-message=', 1)[1]
            break
        elif not arg.startswith('--'):
            commit_message = arg
            break

    if not commit_message:
        print("錯誤: 未提供 commit message")
        sys.exit(1)

    return commit_message


def main():
    """主程式入口"""
    try:
        commit_message = parse_arguments()
        version_manager = AutoVersionManager()
        version_manager.update_version(commit_message)
    except KeyboardInterrupt:
        print("\n程式已被中斷")
        sys.exit(1)
    except Exception as e:
        print(f"發生錯誤: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
```

---

## .gitignore 建議追加

```gitignore
# Auto-version（安裝副本，非來源檔）
.dev/
```

> `version.json` 是否加入版控視團隊需求而定 — 若希望版本號可追蹤則保留，若純粹自動化則排除。
