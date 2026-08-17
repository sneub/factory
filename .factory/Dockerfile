# The factory run environment, built by .github/workflows/factory-image.yml and pulled
# by every job. Keep it lean — a fat image costs pull time on every run. No secrets and
# no repo code live here; both arrive at run time.
FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates jq ripgrep \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI — the loops' hands (issues, PRs, labels, reviews).
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# The agent.
RUN npm install -g @anthropic-ai/claude-code

# pnpm/yarn via corepack, for repos that use them.
RUN corepack enable

# ── Your repo's toolchain goes below ─────────────────────────────────────────────────
# The builder runs your local gates (FACTORY.md § Local gates) inside this image, so
# install whatever those need that isn't already here (a Python runtime, bun, playwright
# deps, …). Editing this file rebuilds the image automatically on the next push.
