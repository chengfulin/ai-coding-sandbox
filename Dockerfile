# syntax=docker/dockerfile:1
# AI coding sandbox base image.
# Tool selection is driven by build args set by build-sandbox.sh.
FROM ubuntu:24.04

ARG INSTALL_CLAUDE=false
ARG INSTALL_CODEX=false
ARG INSTALL_COPILOT=false
ARG NODE_MAJOR=22
ARG NVM_VERSION=v0.40.3
ARG PYTHON_VERSION=3.12
ARG EXTRA_APT=""

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NVM_DIR=/root/.nvm \
    UV_INSTALL_DIR=/usr/local/bin \
    UV_PYTHON_INSTALL_DIR=/opt/uv-python

# Base toolchain only — Node is managed by nvm, Python by uv (installed below).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client \
      ripgrep jq less vim xz-utils \
      ${EXTRA_APT} \
 && rm -rf /var/lib/apt/lists/*

# Node.js via nvm; install the default major version and expose it on PATH.
# Global npm bins (the AI CLIs below) land in the same dir, so /usr/local/nodejs covers both.
RUN mkdir -p "$NVM_DIR" \
 && curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash \
 && . "$NVM_DIR/nvm.sh" \
 && nvm install "$NODE_MAJOR" \
 && nvm alias default "$NODE_MAJOR" \
 && ln -s "$(dirname "$(nvm which default)")" /usr/local/nodejs
ENV PATH=/usr/local/nodejs:$PATH

# Python via uv; install the default version and expose `python`/`python3` on PATH.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
 && uv python install "$PYTHON_VERSION" \
 && ln -sf "$(uv python find "$PYTHON_VERSION")" /usr/local/bin/python \
 && ln -sf /usr/local/bin/python /usr/local/bin/python3

# Install the selected AI coding CLIs (one or many).
RUN set -eux; \
    if [ "$INSTALL_CLAUDE" = "true" ];  then npm install -g @anthropic-ai/claude-code; fi; \
    if [ "$INSTALL_CODEX" = "true" ];   then npm install -g @openai/codex;            fi; \
    if [ "$INSTALL_COPILOT" = "true" ]; then npm install -g @github/copilot;          fi; \
    npm cache clean --force

WORKDIR /workspace

# Seed configs / skills assembled by build-sandbox.sh into ./home.
# The directory always exists (created empty when --no-config), so COPY never fails.
# Credentials/auth files are intentionally excluded by build-sandbox.sh; inject via env at runtime.
COPY home/ /root/

COPY motd.sh /usr/local/bin/ai-sandbox-motd
RUN chmod +x /usr/local/bin/ai-sandbox-motd \
 && echo '[ -t 1 ] && ai-sandbox-motd' >> /root/.bashrc

CMD ["bash"]
