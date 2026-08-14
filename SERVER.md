# Fresh Ubuntu box → operational studio factory

The whole thing is one script run, three paste-a-credential steps, and one verify command.
Total hands-on time: about ten minutes.

## What you need before starting

1. **A fresh Ubuntu box** (22.04+, 1GB+ RAM — the script adds swap) that you can
   `ssh root@<box>` into with your key.
2. **A bot GitHub account** (separate from yours — agent activity must be distinguishable,
   and the write-access steering checks key off it), with a **classic PAT with `repo` scope**
   from that account, and **write (collaborator) access to prisma/studio**.
3. **Claude credentials** — a Claude subscription (you'll paste a login code) or an Anthropic
   API key.

## 1 — Run the bootstrap

From your laptop, in this repo:

```bash
scp bootstrap.sh root@<box>:/root/
ssh -A root@<box> 'GH_TOKEN=<bot-pat> FACTORY_GIT_NAME="Studio Factory Bot" FACTORY_GIT_EMAIL=<bot-email> bash /root/bootstrap.sh'
```

The `-A` matters on the first run: the box clones this factory repo before the bot's key
exists on GitHub, so the clone rides your forwarded ssh agent.

The script is **fully idempotent** — re-run it any time to update packages, toolchains, and
the factory clone, or to repair a half-configured box. It creates the `factory` user, adds
swap, installs git/gh/jq/claude (+ node/pnpm via corepack for the studio gates), generates
the bot's SSH key, clones this repo, sets up the layout (`~/repos`, `~/worktrees`, `~/logs`),
installs the two sweep cron lines, and hardens sshd (root login off — from now on it's
`ssh factory@<box>`).

## 2 — The three credential steps

The script ends by printing exactly what's left. It's these:

1. **Bot SSH key → GitHub.** The script prints the public key. Add it to the **bot** account
   (Settings → SSH and GPG keys), then verify from the box:
   `ssh factory@<box>` → `ssh -T git@github.com`.
2. **gh auth** — already done if you passed `GH_TOKEN` above. Otherwise:
   `ssh factory@<box>` → `gh auth login` and paste the bot PAT.
3. **claude auth** — `ssh factory@<box>` → `claude setup-token` (prints a URL; open it
   anywhere, paste the code back). Or put `ANTHROPIC_API_KEY=...` at the top of
   `crontab -e` instead.

## 3 — Onboard the repo and verify

```bash
ssh factory@<box>
factory setup     # clones prisma/studio, checks bot access, creates the 7 labels
factory doctor    # everything ok → operational
```

Sweeps are already running every 5 minutes; with no `bot:build`/`bot:review` labels applied
they cost ~nothing (the pre-check is a couple of gh calls). See `SETUP.md` for the verify
tests worth running once.

## Day-2 operation

- **Steering** happens entirely from GitHub — label an issue `bot:build` to feed the
  builder, label a PR `bot:review` for a review-only pass, answer `agent:needs-reply`
  threads, merge `ready:merge` PRs. Blockers and questions @mention you on the item itself.
- **Updates ship themselves** — every sweep starts by ff-pulling this factory clone; merge a
  change to this repo's default branch and the loops run it within 5 minutes. Re-run
  `bootstrap.sh` only for package/toolchain updates or config repair:
  `ssh factory@<box>` → `sudo bash ~/factory/bootstrap.sh` (the clone lands at `~/factory`
  whatever the repo is named).
- **Health**: `factory doctor` (auth, cron, locks, repo access, labels, last cycles), logs
  in `~/logs/studio-<loop>.log` and `~/logs/sweep-<loop>.log`.
