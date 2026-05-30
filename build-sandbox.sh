#!/usr/bin/env bash
# build-sandbox.sh — assemble build context and build the ai-sandbox image.
#
# Usage:
#   ./build-sandbox.sh [PROJECT_NAME] [--tools claude,codex,copilot] [options]
#
# Options:
#   --tools LIST     Comma-separated CLIs to install: claude,codex,copilot (default: claude)
#   --node MAJOR     Node.js major version, managed by nvm (default: 22)
#   --python VER     Python version, managed by uv (default: 3.12)
#   --nvm VERSION    nvm release tag to install (default: v0.40.3)
#   --extra-apt PKG  Extra apt packages (space-separated, quoted)
#   --no-config      Do NOT seed host ~/.claude / ~/.codex settings & skills into the image
#   --no-cache       docker build --no-cache (recommended periodically; see SKILL.md security)
#   -h, --help       Show this help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_NAME="default"
TOOLS="claude"
NODE_MAJOR="22"
PYTHON_VERSION="3.12"
NVM_VERSION="v0.40.3"
EXTRA_APT=""
SEED_CONFIG=1
NO_CACHE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --tools)     TOOLS="$2"; shift 2 ;;
    --node)      NODE_MAJOR="$2"; shift 2 ;;
    --python)    PYTHON_VERSION="$2"; shift 2 ;;
    --nvm)       NVM_VERSION="$2"; shift 2 ;;
    --extra-apt) EXTRA_APT="$2"; shift 2 ;;
    --no-config) SEED_CONFIG=0; shift ;;
    --no-cache)  NO_CACHE="--no-cache"; shift ;;
    -h|--help)   grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          echo "Unknown option: $1" >&2; exit 2 ;;
    *)           PROJECT_NAME="$1"; shift ;;
  esac
done

IMAGE_NAME="ai-sandbox:${PROJECT_NAME}"

# --- Resolve tool selection into build args ---------------------------------
INSTALL_CLAUDE=false; INSTALL_CODEX=false; INSTALL_COPILOT=false
IFS=',' read -ra _tools <<< "$TOOLS"
for t in "${_tools[@]}"; do
  case "$(echo "$t" | tr '[:upper:]' '[:lower:]' | xargs)" in
    claude)  INSTALL_CLAUDE=true ;;
    codex)   INSTALL_CODEX=true ;;
    copilot) INSTALL_COPILOT=true ;;
    "" )     ;;
    *)       echo "Unknown tool: '$t' (valid: claude, codex, copilot)" >&2; exit 2 ;;
  esac
done
if [ "$INSTALL_CLAUDE$INSTALL_CODEX$INSTALL_COPILOT" = "falsefalsefalse" ]; then
  echo "No valid tools selected. Use --tools claude,codex,copilot" >&2; exit 2
fi

echo "Building AI sandbox '${IMAGE_NAME}'"
echo "  tools : claude=$INSTALL_CLAUDE codex=$INSTALL_CODEX copilot=$INSTALL_COPILOT"
echo "  node  : ${NODE_MAJOR} (nvm ${NVM_VERSION})   python: ${PYTHON_VERSION} (uv)"
echo "  seed-config: $([ $SEED_CONFIG -eq 1 ] && echo yes || echo no)"

# --- Assemble a clean build context -----------------------------------------
CTX="$(mktemp -d "${TMPDIR:-/tmp}/ai-sandbox-ctx.XXXXXX")"
trap 'rm -rf "$CTX"' EXIT
cp "$SCRIPT_DIR/Dockerfile" "$CTX/Dockerfile"
cp "$SCRIPT_DIR/motd.sh"    "$CTX/motd.sh"
mkdir -p "$CTX/home"

# Seed host settings & skills (NEVER credentials — those go in via env at runtime).
seed() { [ -e "$1" ] && { mkdir -p "$(dirname "$2")"; cp -R "$1" "$2"; echo "  + seeded $(basename "$1")"; } || true; }
if [ $SEED_CONFIG -eq 1 ]; then
  if [ "$INSTALL_CLAUDE" = "true" ]; then
    seed "$HOME/.claude/settings.json" "$CTX/home/.claude/settings.json"
    seed "$HOME/.claude/skills"        "$CTX/home/.claude/skills"
    seed "$HOME/.claude/CLAUDE.md"     "$CTX/home/.claude/CLAUDE.md"
  fi
  if [ "$INSTALL_CODEX" = "true" ]; then
    seed "$HOME/.codex/config.toml"  "$CTX/home/.codex/config.toml"
    seed "$HOME/.codex/config.yaml"  "$CTX/home/.codex/config.yaml"
    seed "$HOME/.codex/AGENTS.md"    "$CTX/home/.codex/AGENTS.md"
  fi
  if [ "$INSTALL_COPILOT" = "true" ]; then
    seed "$HOME/.copilot/config.json" "$CTX/home/.copilot/config.json"
  fi
  # Strip any auth/credential files that may have been pulled in with directories.
  find "$CTX/home" \( -name '.credentials.json' -o -name 'auth.json' -o -name '*.key' \
    -o -name 'hosts.json' -o -name '*token*' \) -type f -print -delete 2>/dev/null || true
fi

# --- Build -------------------------------------------------------------------
docker build $NO_CACHE \
  --build-arg INSTALL_CLAUDE="$INSTALL_CLAUDE" \
  --build-arg INSTALL_CODEX="$INSTALL_CODEX" \
  --build-arg INSTALL_COPILOT="$INSTALL_COPILOT" \
  --build-arg NODE_MAJOR="$NODE_MAJOR" \
  --build-arg NVM_VERSION="$NVM_VERSION" \
  --build-arg PYTHON_VERSION="$PYTHON_VERSION" \
  --build-arg EXTRA_APT="$EXTRA_APT" \
  -t "$IMAGE_NAME" \
  -f "$CTX/Dockerfile" \
  "$CTX"

echo "Image built: ${IMAGE_NAME}"
echo "Run: ${SCRIPT_DIR}/run-sandbox.sh ${PROJECT_NAME}"
