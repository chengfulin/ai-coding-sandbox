#!/usr/bin/env bash
# Printed once on interactive shell start — shows which CLIs are available.
echo "=== AI coding sandbox ==="
for c in "claude:Claude Code" "codex:Codex" "copilot:Copilot CLI"; do
  bin="${c%%:*}"; name="${c#*:}"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "  [x] $name  ($bin)"
  fi
done
command -v node >/dev/null 2>&1 && echo "  node: $(node -v) (nvm)"
command -v uv   >/dev/null 2>&1 && echo "  python: $(python --version 2>&1 | awk '{print $2}') (uv)"
echo "  workspace: $(pwd)"
echo "========================="
