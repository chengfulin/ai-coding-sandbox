# Reference — AI coding 容器環境設計

> 本檔為此工具的設計依據（原始參考資料），供需要理解架構與安全考量時查閱。
> 實際操作一律以 `scripts/` 內的腳本執行，不要手動複製這裡的片段。

## 核心思路

把 AI coding 工具的設定、認證、插件一次打包進 Docker image，讓每個專案 spin up 一個隔離的容器。

## 架構概念

```
Host Machine
├── ~/.claude/          ← 設定來源
├── ~/.codex/
└── scripts/build-sandbox.sh    ← 一鍵建立 template image
Docker Image (ai-sandbox:<project>)
├── Claude Code CLI / Codex CLI / Copilot CLI（可選一或多個）
├── 你的 skills / plugins
└── 共用設定
Per-Project Container
├── mount ./project → /workspace
└── 繼承 base image 的所有工具
```

## 安裝來源（CLI）

| 工具 | 安裝指令 | API 金鑰（API 計費） |
|------|----------|--------------|
| Claude Code | `npm install -g @anthropic-ai/claude-code` | `ANTHROPIC_API_KEY` |
| Codex | `npm install -g @openai/codex` | `OPENAI_API_KEY` |
| Copilot CLI | `npm install -g @github/copilot` | `GITHUB_TOKEN` / `GH_TOKEN` |

## 訂閱帳號登入（容器內，複製 URL 流程）

實測 v2.1.158 / Codex / Copilot 的登入皆無需 localhost callback：

| 工具 | 登入指令 | callback 方式 | 認證存放（容器內） |
|------|----------|---------------|--------------------|
| Claude Code | `claude auth login` | redirect → `platform.claude.com/oauth/code/callback`，顯示 code 由使用者貼回 | `~/.claude/.credentials.json` |
| Codex | `codex login --device-auth` | device flow（複製 URL+code）；預設 `codex login` 走 `localhost:1455`，容器內不通 | `~/.codex/auth.json` |
| Copilot CLI | `copilot login` | OAuth device flow（`github.com/login/device`） | 無 cred store 時落到 `~/.copilot/` |

- 訂閱登入需外網（`--network bridge`）；API 金鑰 env 會覆蓋訂閱，故訂閱模式用 `--no-keys`。
- `--persist-auth` 為上述三個目錄掛 named volume，登入跨次保存；named volume 首次使用會以 image 內容初始化，故 seed 的 `settings.json` 仍在。

## 已知限制：Claude Code sandbox 與 Docker 衝突

Claude Code 內建 **sandbox 功能**（以 bubblewrap 實作的 OS-level 隔離），啟用後會在容器內再起一層 namespace 隔離，與 Docker 的 user namespace 產生衝突，導致 Claude Code 無法啟動。

**症狀**：進容器後執行 `claude` 報錯（`Failed to create sandbox` / `bwrap` 相關錯誤）。

**解法**：在 host 的 `~/.claude/settings.json` 或專案的 `.claude/settings.json` 將 sandbox 停用，build image 時該設定會 seed 進去：

```json
{
  "sandbox": {
    "enabled": false
  }
}
```

`failIfUnavailable`（預設 `true`）在 sandbox 停用後不影響行為，可一併保留或移除。

## 安全注意事項（腳本已內建對應防護）

| 風險點 | 建議做法 | 本工具 的落實 |
|--------|---------|----------------|
| API Key 洩漏 | 用 `.env` + 環境變數，不進 image | `run-sandbox.sh` 以 `--env-file` / `-e` 注入；`build` 不寫入金鑰 |
| Image 包含認證 | build 時定期 `--no-cache` rotate | `build-sandbox.sh --no-cache`；自動刪除 seed 進來的 `auth.json`/`.credentials.json`/`*token*` |
| 過度權限 | 預設限制網路 | `run-sandbox.sh --network none\|bridge\|host`（預設 bridge） |
| docker.sock mount | 非必要不掛，有 host escape 風險 | 預設不掛；需要才 `--docker-sock`，並印出警告 |

## 團隊共用

base image 可推到私有 registry（ECR / GHCR），讓團隊 `docker pull` 後直接 `run-sandbox.sh` 使用。

## 原始參考差異說明

- 原參考使用 Ubuntu 內建 `npm`；本工具 改用 **nvm** 管控 Node.js（預設裝 `NODE_MAJOR`，可 `nvm use` 切換版本），**uv** 管控 Python（預設裝 `PYTHON_VERSION`，並提供 `python`/`python3` shim）。
- 原參考 CLI 為固定安裝；本工具 以 build args 讓 Claude Code / Codex / Copilot CLI 可選一或多個組合。
- 原參考將設定無條件 COPY；本工具 僅 seed 已選工具的設定，且主動剔除認證檔。
