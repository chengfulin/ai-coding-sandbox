# AI Coding Sandbox — Project Context

此 repo 把 AI coding CLI（Claude Code / Codex / Copilot CLI）的設定、認證流程、skills 打包進 Docker image，讓每個專案啟動一個乾淨、可重現的容器。

## 關鍵限制（修改前必讀）

- **認證檔絕對不進 image**：`build-sandbox.sh` seed 設定時會主動刪除 `auth.json`、`.credentials.json`、`*token*`。修改 seed 邏輯時不得破壞此保護。
- **金鑰只在 runtime 注入**：`run-sandbox.sh` 透過 `-e` / `--env-file` 傳入，Dockerfile 不寫任何金鑰。
- **Claude Code sandbox 需停用**：若 `~/.claude/settings.json` 或 `.claude/settings.json` 啟用了 `sandbox`，seed 進 image 後會與 Docker 衝突（bubblewrap vs. Docker namespace）。確保 `sandbox.enabled: false`。

## 檔案職責

| 檔案 | 職責 |
|------|------|
| `build-sandbox.sh` | 組裝 build context、依 `--tools` 選擇安裝的 CLI、seed 設定、docker build |
| `run-sandbox.sh` | 掛載專案目錄、注入金鑰或訂閱登入、設定網路，docker run |
| `Dockerfile` | base image：Ubuntu 24.04 + nvm（Node）+ uv（Python）+ 選裝 CLI |
| `motd.sh` | 容器互動 shell 啟動時印出已安裝的 CLI 與版本 |
| `Makefile` | `build` / `shell` / `detach` / `rebuild` / `clean` 便捷目標 |
| `docker-compose.yml` | 多專案 profile 管理範本（build 後自行維護） |

## 常用指令

```bash
# 建立 image（選擇要裝的 CLI）
./build-sandbox.sh my-api --tools claude,codex

# 啟動容器（互動 shell，API 金鑰模式）
./run-sandbox.sh my-api

# 啟動容器（訂閱登入模式，不注入金鑰）
./run-sandbox.sh my-api --subscription

# Makefile 包裝
make build PROJECT=my-api TOOLS=claude,codex
make shell PROJECT=my-api
make clean PROJECT=my-api

# 多專案（docker compose）
docker compose --profile project-a up -d
```

## Seed 邏輯（build-sandbox.sh）

`--no-config` 未啟用時，腳本把 host 以下路徑複製進暫存 build context，再 COPY 進 image：

- `~/.claude/settings.json` + `~/.claude/skills/` + `~/.claude/CLAUDE.md`（若裝 Claude）
- `~/.codex/config.yaml`（若裝 Codex）

COPY 後立即刪除認證檔（`find … -name 'auth.json' -o -name '*.credentials.json' …`）。修改此段時維持刪除邏輯。

## 訂閱帳號登入（容器內）

三個 CLI 皆走「複製 URL → 瀏覽器授權 → 貼回 code」，不需 localhost callback：

```bash
claude  auth login          # 貼回網頁顯示的 code
codex   login --device-auth # --device-auth 必須加，否則走 localhost:1455
copilot login               # GitHub device flow
```

訂閱與 API 金鑰互斥：環境有 key 時 CLI 走計費，`--subscription`（= `--no-keys` + `--persist-auth`）可避免。

## 安全原則

- 不得在 Dockerfile 或 image build 階段寫入任何 API key / token。
- `--docker-sock` 有 host escape 風險，預設不掛；需要時才開，且腳本已印出警告。
- 定期用 `--no-cache` 重建以 rotate 套件與設定快照。
