# AI Coding Sandbox

把 AI coding CLI 的設定、認證流程、skills 一次打包進 Docker image，讓每個專案啟動一個乾淨、可重現、隔離的容器。可選安裝 **Claude Code / Codex / Copilot CLI**（一個或多個組合）。

> 直接執行 `build-sandbox.sh` 和 `run-sandbox.sh`，或使用 `Makefile`。build 後可自行維護 `docker-compose.yml` 管理多專案。設計依據與登入機制實測見 [reference.md](reference.md)。

---

## 前置需求

- 已安裝並啟動 **Docker**（`docker ps` 不報錯）。
- 視所裝工具準備認證：
  - API 金鑰模式：`ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GITHUB_TOKEN`（見 [.env.example](.env.example)）。
  - 訂閱帳號模式：容器內互動登入（見下方〈訂閱帳號登入〉）。
- **關閉 Claude Code 的 sandbox 功能**：若 `~/.claude/settings.json` 或專案目錄下 `.claude/settings.json` 啟用了 `sandbox`，需先停用，否則 Claude Code 的 bubblewrap 隔離會與 Docker 容器衝突導致無法啟動。

  ```json
  // ~/.claude/settings.json 或 .claude/settings.json
  {
    "sandbox": {
      "enabled": false
    }
  }
  ```

## 目錄結構

```
<repo-root>/
├── README.md             # 本文件
├── reference.md          # 設計依據、安全對照、登入機制實測
├── build-sandbox.sh      # 組裝 build context、依 --tools 安裝 CLI、build image
├── run-sandbox.sh        # 掛載專案、注入金鑰或訂閱登入、設定網路，啟動容器
├── Dockerfile            # base image：Ubuntu 24.04 + nvm 管 Node + uv 管 Python
├── Makefile              # build / shell / detach / rebuild / clean 目標
├── docker-compose.yml    # 多專案 profile 管理範本
├── motd.sh               # 容器啟動時列出可用 CLI 與版本
└── .env.example          # 金鑰範本
```

---

## 快速開始

> 以下範例中 `<REPO_ROOT>` 請替換為你本機 clone 此 repo 的實際路徑，例如 `~/projects/ai-coding-sandbox`。

```bash
# 切到 repo 根目錄
cd <REPO_ROOT>

# 1) 建立 image（選擇要裝的 CLI）
./build-sandbox.sh my-api --tools claude,codex

# 2) 在專案目錄啟動隔離容器
cd /path/to/project
<REPO_ROOT>/run-sandbox.sh my-api
```

進容器後即可使用所裝的 CLI（`claude` / `codex` / `copilot`），`/workspace` 即掛載的專案目錄。

---

## 建置：`build-sandbox.sh`

```bash
./build-sandbox.sh [PROJECT_NAME] [--tools <清單>] [options]
```

| 選項 | 說明 | 預設 |
|------|------|------|
| `--tools LIST` | 逗號分隔，可任意組合：`claude`、`codex`、`copilot` | `claude` |
| `--node MAJOR` | Node.js 主版本（由 nvm 管控） | `22` |
| `--python VER` | Python 版本（由 uv 管控） | `3.12` |
| `--nvm VERSION` | nvm release tag | `v0.40.3` |
| `--extra-apt PKG` | 額外 apt 套件（空白分隔，需引號） | — |
| `--no-config` | 不把 host `~/.claude` / `~/.codex` 設定與 skills seed 進 image | 關閉 |
| `--no-cache` | `docker build --no-cache`（定期 rotate 用） | 關閉 |

範例：

```bash
./build-sandbox.sh my-api --tools claude               # 只裝 Claude Code
./build-sandbox.sh my-api --tools claude,codex,copilot # 三個全裝
./build-sandbox.sh my-api --tools codex --python 3.13  # 指定 Python 版本
```

> 腳本會把 host 已選工具的設定與 skills seed 進 image，並**主動剔除**認證檔（`auth.json`、`.credentials.json`、`*token*`）。金鑰一律在執行階段注入，不進 image。

---

## 啟動：`run-sandbox.sh`

```bash
./run-sandbox.sh [PROJECT_NAME] [PROJECT_PATH] [options]
```

| 選項 | 說明 |
|------|------|
| `--subscription` | 訂閱帳號登入模式（= `--no-keys` + `--persist-auth`，並印出登入指引） |
| `--persist-auth` | 為 `/root/.claude`、`/root/.codex`、`/root/.copilot` 掛 per-project named volume，登入跨次保存 |
| `--no-keys` | 不注入 API 金鑰（金鑰會讓 CLI 改走 API 計費而非訂閱） |
| `--network MODE` | `none` / `bridge` / `host`（預設 `bridge`；登入需 `bridge`/`host`） |
| `--env-file FILE` | 載入環境變數檔（預設自動讀專案下 `.env`） |
| `--detach` | 背景執行（之後用 `docker exec -it ai-sbx-<project> bash` 進入） |
| `--docker-sock` | 掛 `/var/run/docker.sock`（nested docker，**有 host escape 風險**） |

預設會把目前環境中存在的 `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GITHUB_TOKEN` / `GH_TOKEN` 注入容器。

---

## 訂閱帳號登入（重要）

容器內三個 CLI 都可用**訂閱帳號**登入，全部走「複製 URL → 瀏覽器授權 → 貼回 code / device code」流程，**不需要 localhost callback、不需 port forwarding**（已實測 Claude Code v2.1.158 / Codex 0.135.0 / Copilot）。

```bash
# 以訂閱模式啟動（不注入金鑰、登入跨次保存）
./run-sandbox.sh my-api --subscription
```

進容器後，依已裝工具執行登入，把印出的 URL 複製到本機瀏覽器：

```bash
claude  auth login            # 授權後把網頁顯示的 code 貼回 "Paste code here >"
codex   login --device-auth   # 在瀏覽器輸入 device code
copilot login                 # GitHub device flow（github.com/login/device）
```

注意事項：

- **必須有外網**：預設 `--network bridge`；用 `none` 會擋住 OAuth（腳本會警告）。
- **訂閱與 API 金鑰互斥**：環境若有對應金鑰，CLI 會改走 API 計費而非訂閱。`--subscription`（或單獨 `--no-keys`）會略過金鑰注入。
- **Codex 一定要加 `--device-auth`**：預設登入走 `localhost:1455` callback，容器內本機瀏覽器連不到。
- **持久化非必要**：僅需「容器運行期間」登入可省略；要跨次保留用 `--subscription` 或 `--persist-auth`。named volume 首次使用會以 image 內容初始化，故 seed 的設定仍在。

---

## Makefile 與多專案管理

```bash
# Makefile：最順手的 DX（在 repo 根目錄執行）
make build PROJECT=my-api TOOLS=claude,codex
make shell PROJECT=my-api
make clean PROJECT=my-api
```

build 後可直接維護 `docker-compose.yml` 管理多專案：

```bash
# 複製並調整 profiles，之後直接用 compose 管理（在 repo 根目錄執行）
docker compose --profile project-a up -d
docker compose --profile project-b up -d
```

---

## 安全注意事項

| 風險點 | 本工具 的落實 |
|--------|----------------|
| API Key 洩漏 | 只在 runtime 用 `--env-file` / `-e` 注入，不進 image；訂閱模式用 `--no-keys` |
| Image 含認證 | seed 時主動刪除 `auth.json` / `.credentials.json` / `*token*`；定期 `--no-cache` rotate |
| 過度權限 | 預設限制網路；需要才開 `--network bridge`，不用時可 `none` |
| docker.sock mount | 預設不掛，必要才 `--docker-sock` 並印出警告 |

---

## base image 說明

- 採用 **Ubuntu 24.04**（glibc），Node.js 由 **nvm** 管控（預設裝 `--node`，可 `nvm use` 切版本），Python 由 **uv** 管控（預設裝 `--python`，並提供 `python`/`python3`）。
- **不採用 Alpine**：已實測 nvm 在 musl 上無法用 Node 官方預編譯檔，會 fallback 去原始碼編譯（慢、肥、需額外工具鏈）。若需縮小 image，可改用 `debian:bookworm-slim`（仍是 glibc，nvm + uv 零改動可用）。

---

## 團隊共用

base image 可推到私有 registry（ECR / GHCR），團隊 `docker pull` 後直接 `run-sandbox.sh` 使用。
