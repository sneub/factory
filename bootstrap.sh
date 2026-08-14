#!/usr/bin/env bash
# bootstrap.sh — fresh Ubuntu box → operational prisma/studio factory host, in one run as root.
#
# Human instructions live in SERVER.md. The short version, from your laptop:
#
#   scp bootstrap.sh root@BOX:/root/
#   ssh -A root@BOX 'GH_TOKEN=<bot-pat> FACTORY_GIT_NAME="Factory Bot" \
#       FACTORY_GIT_EMAIL=bot@example.com bash /root/bootstrap.sh'
#
# ssh -A matters on the FIRST run: the factory clone happens before the bot's own key
# is on GitHub, so it rides your forwarded agent. Re-runs pull as the runtime user.
#
# FULLY IDEMPOTENT — re-run it any time to update packages, refresh config, and pull
# the factory repo. Every step is guarded; managed blocks (.bashrc, crontab) are
# stripped and re-written rather than appended twice.
#
# Environment (all optional unless noted):
#   FACTORY_USER        runtime user                      default: factory
#   FACTORY_GIT_URL     the factory repo to clone         default: git@github.com:sneub/factory-studio.git
#   FACTORY_GIT_NAME    bot git identity — REQUIRED on first run
#   FACTORY_GIT_EMAIL   bot git identity — REQUIRED on first run
#   GH_TOKEN            bot account PAT (classic, repo scope) — wired into gh if given
#   FACTORY_TOOLCHAINS  space-separated extras for hosted projects   default: "bun node"
#   FACTORY_HARDEN_SSH  1 = disable root login + password auth       default: 1
#
# Ends by printing: the bot's public key (the one manual GitHub step), any remaining
# auth steps, and the onboarding one-liner.
set -uo pipefail

FACTORY_USER="${FACTORY_USER:-factory}"
FACTORY_GIT_URL="${FACTORY_GIT_URL:-git@github.com:sneub/factory-studio.git}"
FACTORY_TOOLCHAINS="${FACTORY_TOOLCHAINS:-bun node}"
FACTORY_HARDEN_SSH="${FACTORY_HARDEN_SSH:-1}"
HOME_DIR="/home/${FACTORY_USER}"

log()  { echo; echo "==> $*"; }
warn() { echo "  WARN $*"; }
die()  { echo "FATAL: $*" >&2; exit 1; }

MANUAL_STEPS=()

[ "$(id -u)" = 0 ] || die "run as root (sudo bash bootstrap.sh)"
command -v apt-get >/dev/null 2>&1 || die "this script targets Ubuntu/Debian (apt-get not found)"

# Run a command as the runtime user with a sane HOME.
as_user() { sudo -u "$FACTORY_USER" -H bash -c "$1"; }

# ---- 1. runtime user + passwordless sudo -----------------------------------------------
log "runtime user: $FACTORY_USER"
if ! id "$FACTORY_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$FACTORY_USER"
  echo "  created"
else
  echo "  exists"
fi
SUDOERS_FILE="/etc/sudoers.d/90-${FACTORY_USER}"
if [ ! -f "$SUDOERS_FILE" ]; then
  # Validate BEFORE installing — a bad file in sudoers.d breaks sudo for the whole box.
  SUDOERS_TMP="$(mktemp)"
  echo "${FACTORY_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_TMP"
  visudo -cf "$SUDOERS_TMP" >/dev/null || { rm -f "$SUDOERS_TMP"; die "sudoers entry failed validation"; }
  install -m 440 "$SUDOERS_TMP" "$SUDOERS_FILE"
  rm -f "$SUDOERS_TMP"
  echo "  passwordless sudo installed"
fi

# ---- 2. swap — long agent runs OOM-kill on small VPSes without it (learned the hard way)
log "swap (2G)"
if [ -f /swapfile ]; then
  echo "  /swapfile exists"
else
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  echo "  created"
fi
swapon /swapfile 2>/dev/null || true
grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

# ---- 3. system packages ------------------------------------------------------------------
log "system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq unzip curl git tmux ncurses-term build-essential \
  ca-certificates jq unattended-upgrades >/dev/null
echo "  base packages installed"

# ---- 4. gh via the official apt repo (so it updates through apt) --------------------------
log "GitHub CLI"
if [ ! -f /etc/apt/sources.list.d/github-cli.list ]; then
  mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -qq
fi
apt-get install -y -qq gh >/dev/null
echo "  $(gh --version | head -1)"

# ---- 5. unattended-upgrades (the package ships with the timer off) -------------------------
log "unattended upgrades"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
echo "  enabled"

# ---- 6. per-user toolchains (each guarded for idempotency) ---------------------------------
log "agent CLI (claude)"
if [ -x "$HOME_DIR/.local/bin/claude" ]; then
  echo "  present"
else
  as_user 'curl -fsSL https://claude.ai/install.sh | bash' || warn "claude install failed — install manually"
fi

if [[ " $FACTORY_TOOLCHAINS " == *" bun "* ]]; then
  log "toolchain: bun"
  if [ -x "$HOME_DIR/.bun/bin/bun" ]; then
    echo "  present"
  else
    as_user 'curl -fsSL https://bun.sh/install | bash' >/dev/null || warn "bun install failed"
  fi
fi

if [[ " $FACTORY_TOOLCHAINS " == *" node "* ]]; then
  log "toolchain: node (via fnm)"
  if [ -x "$HOME_DIR/.local/share/fnm/fnm" ]; then
    echo "  fnm present"
  else
    as_user 'curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell' >/dev/null \
      || warn "fnm install failed"
  fi
  as_user '"$HOME/.local/share/fnm/fnm" install --lts && "$HOME/.local/share/fnm/fnm" default lts-latest' \
    >/dev/null 2>&1 || warn "node LTS install failed"
  # prisma/studio is a pnpm repo (packageManager pinned in its package.json) — corepack
  # ships with node and provisions the exact pinned pnpm version on first use.
  as_user 'PATH="$HOME/.local/share/fnm/aliases/default/bin:$PATH" corepack enable --install-directory "$HOME/.local/bin"' \
    >/dev/null 2>&1 || warn "corepack enable failed — install pnpm manually for the studio gates"
fi

# ---- 7. SSH plumbing ------------------------------------------------------------------------
log "ssh plumbing"
# Pre-seed github.com into known_hosts for root AND the runtime user — non-interactive
# git must never hit a host-verification prompt.
for H in /root "$HOME_DIR"; do
  mkdir -p "$H/.ssh" && chmod 700 "$H/.ssh"
  touch "$H/.ssh/known_hosts"
  if ! grep -q '^github.com' "$H/.ssh/known_hosts" 2>/dev/null; then
    ssh-keyscan -t ed25519,rsa github.com >> "$H/.ssh/known_hosts" 2>/dev/null
  fi
done
chown -R "$FACTORY_USER:$FACTORY_USER" "$HOME_DIR/.ssh"
# The runtime user's ed25519 key IS the bot account's credential.
if [ ! -f "$HOME_DIR/.ssh/id_ed25519" ]; then
  as_user "ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C '${FACTORY_USER}-bot'"
  echo "  bot key generated"
else
  echo "  bot key exists"
fi

# ---- 8. clone (or update) the factory repo ---------------------------------------------------
log "factory clone"
if [ -d "$HOME_DIR/factory/.git" ]; then
  as_user 'git -C ~/factory pull --ff-only' || warn "factory pull failed (diverged or offline)"
else
  # Chicken-and-egg: the bot key isn't on GitHub yet, so the first clone rides root's
  # forwarded ssh agent (that's why SERVER.md says `ssh -A`).
  if [[ "$FACTORY_GIT_URL" == git@* || "$FACTORY_GIT_URL" == ssh://* ]] && [ -z "${SSH_AUTH_SOCK:-}" ]; then
    die "first clone of $FACTORY_GIT_URL needs your forwarded ssh agent — reconnect with: ssh -A root@<box>"
  fi
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
    git clone "$FACTORY_GIT_URL" "$HOME_DIR/factory" || die "clone failed"
  chown -R "$FACTORY_USER:$FACTORY_USER" "$HOME_DIR/factory"
  echo "  cloned"
fi

# ---- 9. git identity for autonomous commits ---------------------------------------------------
log "git identity"
if [ -z "$(as_user 'git config --global user.name' 2>/dev/null || true)" ]; then
  [ -n "${FACTORY_GIT_NAME:-}" ] && [ -n "${FACTORY_GIT_EMAIL:-}" ] \
    || die "first run needs FACTORY_GIT_NAME and FACTORY_GIT_EMAIL env vars (the bot's commit identity)"
  as_user "git config --global user.name '${FACTORY_GIT_NAME}'"
  as_user "git config --global user.email '${FACTORY_GIT_EMAIL}'"
  echo "  set: ${FACTORY_GIT_NAME} <${FACTORY_GIT_EMAIL}>"
else
  echo "  kept existing"
fi

# ---- 10. .bashrc managed block ------------------------------------------------------------------
log ".bashrc managed block"
BASHRC="$HOME_DIR/.bashrc"
touch "$BASHRC"
sed -i '/# >>> factory >>>/,/# <<< factory <<</d' "$BASHRC"
cat >> "$BASHRC" <<'EOF'
# >>> factory >>>
[ -n "$TERM" ] || export TERM=xterm-256color
export PATH="$HOME/.local/bin:$HOME/factory/bin:$HOME/.bun/bin:$PATH"
if [ -x "$HOME/.local/share/fnm/fnm" ]; then
  export PATH="$HOME/.local/share/fnm:$PATH"
  eval "$(fnm env 2>/dev/null)" || true
fi
# <<< factory <<<
EOF
chown "$FACTORY_USER:$FACTORY_USER" "$BASHRC"
echo "  written"

# ---- 11. human ssh access, then harden sshd (in that order — never lock yourself out) -----------
log "ssh access + hardening"
if [ -f /root/.ssh/authorized_keys ] && [ ! -s "$HOME_DIR/.ssh/authorized_keys" ]; then
  cp /root/.ssh/authorized_keys "$HOME_DIR/.ssh/authorized_keys"
  chown "$FACTORY_USER:$FACTORY_USER" "$HOME_DIR/.ssh/authorized_keys"
  chmod 600 "$HOME_DIR/.ssh/authorized_keys"
  echo "  root's authorized_keys copied to $FACTORY_USER"
fi
if [ "$FACTORY_HARDEN_SSH" = 1 ]; then
  if [ -s "$HOME_DIR/.ssh/authorized_keys" ]; then
    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/90-factory.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
EOF
    if sshd -t 2>/dev/null; then
      systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
      echo "  hardened: root login and password auth disabled (use ssh ${FACTORY_USER}@<box>)"
    else
      rm -f /etc/ssh/sshd_config.d/90-factory.conf
      warn "sshd config failed validation — hardening skipped"
    fi
  else
    warn "no authorized_keys for $FACTORY_USER — hardening skipped so you can't be locked out"
  fi
fi

# ---- 12. gh auth (the classic 'git works but gh doesn't' trap) -----------------------------------
log "gh auth"
if as_user 'gh auth status' >/dev/null 2>&1; then
  echo "  already authenticated"
elif [ -n "${GH_TOKEN:-}" ]; then
  if printf '%s' "$GH_TOKEN" | sudo -u "$FACTORY_USER" -H env -u GH_TOKEN gh auth login --with-token; then
    echo "  authenticated with provided token"
  else
    warn "token login failed"
    MANUAL_STEPS+=("gh auth: ssh ${FACTORY_USER}@<box>, then: gh auth login  (PAT for the BOT account, classic, 'repo' scope)")
  fi
else
  MANUAL_STEPS+=("gh auth: ssh ${FACTORY_USER}@<box>, then: gh auth login  (PAT for the BOT account, classic, 'repo' scope)")
fi

# ---- 13. layout + crontab (managed block, never changes as repos come and go) --------------------
log "layout + crontab"
as_user 'mkdir -p ~/repos ~/worktrees ~/logs'
CRON_CURRENT="$(sudo -u "$FACTORY_USER" crontab -l 2>/dev/null | sed '/# >>> factory >>>/,/# <<< factory <<</d' || true)"
{
  [ -n "$CRON_CURRENT" ] && printf '%s\n' "$CRON_CURRENT"
  cat <<'EOF'
# >>> factory >>>
*/5 * * * *  flock -n /tmp/factory-builder.lock  $HOME/factory/bin/factory-sweep builder >>$HOME/logs/sweep-builder.log 2>&1
*/5 * * * *  flock -n /tmp/factory-merger.lock   $HOME/factory/bin/factory-sweep merger  >>$HOME/logs/sweep-merger.log 2>&1
# <<< factory <<<
EOF
} | sudo -u "$FACTORY_USER" crontab -
echo "  ~/repos ~/worktrees ~/logs + 2 sweep cron lines installed"

# ---- 14. doctor + the finish line ------------------------------------------------------------------
log "factory doctor"
as_user 'PATH="$HOME/.local/bin:$PATH" ~/factory/bin/factory doctor' || true

# Agent auth can't be verified non-interactively — always surface it.
MANUAL_STEPS+=("claude auth (skip if already done): ssh ${FACTORY_USER}@<box>, then: claude setup-token  — or put ANTHROPIC_API_KEY in the crontab")

echo
echo "============================================================================"
echo " BOT PUBLIC KEY — add to the bot GitHub account (Settings → SSH keys):"
echo
cat "$HOME_DIR/.ssh/id_ed25519.pub"
echo
echo " then verify from the box:  ssh ${FACTORY_USER}@<box>  →  ssh -T git@github.com"
echo "============================================================================"
if [ "${#MANUAL_STEPS[@]}" -gt 0 ]; then
  echo " REMAINING MANUAL STEPS:"
  i=1
  for s in "${MANUAL_STEPS[@]}"; do echo "   $i. $s"; i=$((i+1)); done
  echo "============================================================================"
fi
echo " Onboard the repo: ssh ${FACTORY_USER}@<box>  →  factory setup"
echo " Re-run this script any time to update the box. Sweeps run every 5 minutes."
echo "============================================================================"
