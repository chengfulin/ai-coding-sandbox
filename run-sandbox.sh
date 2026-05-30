#!/usr/bin/env bash
# run-sandbox.sh — start an isolated container for one project.
#
# Usage:
#   ./run-sandbox.sh [PROJECT_NAME] [PROJECT_PATH] [options]
#
# Options:
#   --subscription   Log in with subscription accounts (Claude/ChatGPT/GitHub
#                    Copilot) instead of API keys. Implies --no-keys + --persist-auth.
#   --persist-auth   Keep CLI logins across runs via named volumes for
#                    /root/.claude, /root/.codex, /root/.copilot
#   --no-keys        Do NOT inject API-key env vars (API keys override subscription login)
#   --network MODE   Docker network: none|bridge|host (default: bridge; login needs bridge/host)
#   --docker-sock    Mount /var/run/docker.sock (nested docker; HOST-ESCAPE RISK)
#   --env-file FILE  Load env vars from FILE (default: ./.env if present)
#   --detach         Run detached (-d) instead of interactive shell
#   -h, --help       Show this help
#
# API keys are read from the environment / --env-file and injected at runtime.
# They are NEVER baked into the image. Keys passed through (when set):
#   ANTHROPIC_API_KEY  OPENAI_API_KEY  GITHUB_TOKEN  GH_TOKEN
#
# Subscription login (no localhost callback needed — copy URL / device code):
#   claude :  claude auth login            # copy URL -> authorize -> paste code back
#   codex  :  codex login --device-auth    # copy URL + device code
#   copilot:  copilot login                # OAuth device flow (github.com/login/device)
set -euo pipefail

PROJECT_NAME="default"
PROJECT_PATH=""
NETWORK="bridge"
MOUNT_SOCK=0
ENV_FILE=""
DETACH=0
PERSIST_AUTH=0
NO_KEYS=0
SUBSCRIPTION=0

POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --subscription) SUBSCRIPTION=1; shift ;;
    --persist-auth) PERSIST_AUTH=1; shift ;;
    --no-keys)      NO_KEYS=1; shift ;;
    --network)      NETWORK="$2"; shift 2 ;;
    --docker-sock)  MOUNT_SOCK=1; shift ;;
    --env-file)     ENV_FILE="$2"; shift 2 ;;
    --detach)       DETACH=1; shift ;;
    -h|--help)      grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)             echo "Unknown option: $1" >&2; exit 2 ;;
    *)              POSITIONAL+=("$1"); shift ;;
  esac
done
[ "${POSITIONAL[0]:-}" != "" ] && PROJECT_NAME="${POSITIONAL[0]}"
[ "${POSITIONAL[1]:-}" != "" ] && PROJECT_PATH="${POSITIONAL[1]}"
[ -z "$PROJECT_PATH" ] && PROJECT_PATH="$(pwd)"

# --subscription is shorthand for "I want to OAuth-login inside the container".
if [ "$SUBSCRIPTION" -eq 1 ]; then NO_KEYS=1; PERSIST_AUTH=1; fi

IMAGE_NAME="ai-sandbox:${PROJECT_NAME}"
CONTAINER_NAME="ai-sbx-${PROJECT_NAME}"

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Image '$IMAGE_NAME' not found. Build it first:" >&2
  echo "  $(dirname "$0")/build-sandbox.sh ${PROJECT_NAME} --tools claude,codex,copilot" >&2
  exit 1
fi

# Default env-file = ./.env in the project path, if it exists (skipped with --no-keys).
[ "$NO_KEYS" -eq 0 ] && [ -z "$ENV_FILE" ] && [ -f "${PROJECT_PATH}/.env" ] && ENV_FILE="${PROJECT_PATH}/.env"

ARGS=( --rm --name "$CONTAINER_NAME"
       -v "${PROJECT_PATH}:/workspace"
       -w /workspace
       --network "$NETWORK" )

# Persist CLI logins across runs. Named volumes are seeded from the image's
# /root/.<tool> on first use, so baked-in settings.json survives too.
if [ "$PERSIST_AUTH" -eq 1 ]; then
  for d in claude codex copilot; do
    ARGS+=( -v "ai-sbx-${PROJECT_NAME}-${d}:/root/.${d}" )
  done
fi

# Inject API keys unless asked not to. (An API key makes the CLI use API billing,
# which overrides subscription login — so subscription mode skips this.)
if [ "$NO_KEYS" -eq 0 ]; then
  [ -n "$ENV_FILE" ] && ARGS+=( --env-file "$ENV_FILE" )
  for k in ANTHROPIC_API_KEY OPENAI_API_KEY GITHUB_TOKEN GH_TOKEN; do
    [ -n "${!k:-}" ] && ARGS+=( -e "$k" )
  done
fi

if [ "$MOUNT_SOCK" -eq 1 ]; then
  echo "WARNING: mounting docker.sock grants host-level control from the container." >&2
  ARGS+=( -v /var/run/docker.sock:/var/run/docker.sock )
fi

# OAuth login needs outbound network.
if [ "$NETWORK" = "none" ] && { [ "$SUBSCRIPTION" -eq 1 ] || [ "$NO_KEYS" -eq 1 ]; }; then
  echo "WARNING: --network none blocks OAuth login. Use --network bridge to sign in." >&2
fi

if [ "$SUBSCRIPTION" -eq 1 ]; then
  cat <<'EOF'
Subscription login (run inside the container; copy the printed URL to your browser):
  claude  -> claude auth login           # paste the code back when prompted
  codex   -> codex login --device-auth   # enter the device code in the browser
  copilot -> copilot login               # device flow at github.com/login/device
Logins persist across runs for this project (named volumes).
EOF
fi

if [ "$DETACH" -eq 1 ]; then
  docker run -d "${ARGS[@]}" "$IMAGE_NAME" sleep infinity
  echo "Started detached: $CONTAINER_NAME  (exec in: docker exec -it $CONTAINER_NAME bash)"
else
  exec docker run -it "${ARGS[@]}" "$IMAGE_NAME" bash
fi
