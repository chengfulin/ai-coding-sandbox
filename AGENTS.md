# AI Coding Sandbox — Agent Instructions

完整專案說明見 [CLAUDE.md](CLAUDE.md)，以下為快速摘要。

## 專案用途

把 AI coding CLI（Claude Code / Codex / Copilot CLI）打包進 Docker image，讓每個專案啟動隔離容器。主要入口：`build-sandbox.sh`（build image）、`run-sandbox.sh`（啟動容器）、`Makefile`（便捷包裝）。

## 修改前必確認

1. **認證檔不進 image**：`build-sandbox.sh` 的 seed 邏輯會自動刪除 `auth.json`、`.credentials.json`、`*token*`，修改時不得移除此防護。
2. **金鑰只在 runtime 注入**：Dockerfile 與 image build 階段不寫任何 key / token。
3. **Claude Code sandbox 需停用**：`settings.json` 須有 `"sandbox": {"enabled": false}`，否則 bubblewrap 與 Docker namespace 衝突。

詳細設計、登入機制實測、安全對照見 [reference.md](reference.md)。
