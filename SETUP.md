# Setup — add the factory to a repo

Read [`README.md`](README.md) first for the concept. About fifteen minutes, most of it
waiting for the image build. No server anywhere: everything below is GitHub configuration.

## 1. Copy the files

Copy `.factory/` and the three `.github/workflows/factory*.yml` workflows into the target
repo, on its default branch. Fill the `<placeholders>` in `.factory/FACTORY.md` (maintainer
handle, local gates) — the setup workflow will warn about any you miss.

If your default branch isn't `main`, adjust the `branches:` line in
`.github/workflows/factory-image.yml`.

## 2. The bot identity — a GitHub App

The bot is a GitHub App, separate from your account: agent activity must be distinguishable,
the write-access steering checks key off the `<slug>[bot]` login, and — the load-bearing
part — **App-minted tokens trigger CI on the bot's PRs**, which the default `GITHUB_TOKEN`
deliberately does not. Without this, the reviewer's "CI green" gate could never pass.

Create it once (**Settings → Developer settings → GitHub Apps → New**): permissions
Contents, Pull requests, Issues — all read & write; webhook off. Then **install it on the
target repo**. There is no bot account, no PAT, and no SSH key.

## 3. Secrets and variables

In the target repo: **Settings → Secrets and variables → Actions**.

| Secret | Why |
|---|---|
| `FACTORY_APP_ID` | The App's ID (from the App settings page) |
| `FACTORY_APP_PRIVATE_KEY` | The App's private key `.pem`, pasted whole — the bot's root credential |
| `ANTHROPIC_API_KEY` **or** `CLAUDE_CODE_OAUTH_TOKEN` | The agent. See below. |

A **Claude subscription works**: run `claude setup-token` once on a machine with a browser
and store the result as `CLAUDE_CODE_OAUTH_TOKEN`. Two things to know before you do:

- **Shared limits.** Subscription usage draws on the same pool as your own interactive
  Claude Code. A long build can exhaust the window and lock you out of your own terminal
  until it resets.
- **Tokens expire.** An API key does not. A stale token means red jobs, so put a reminder on
  the rotation.

Optionally, under **Variables**: `FACTORY_MODEL` pins the model id the loops run; leave it
unset for the CLI default.

`GITHUB_TOKEN` needs nothing from you — the workflows use it only to pull the container
image; all git and GitHub work runs on the App token.

## 4. Build the image and run setup

From the repo's **Actions** tab:

1. Run **factory-image** — builds `.factory/Dockerfile` and pushes to
   `ghcr.io/<owner>/<repo>/factory:latest`. (It also rebuilds automatically whenever the
   Dockerfile changes on the default branch, and weekly.) If the resulting package is
   private, jobs pull it with `GITHUB_TOKEN` — that's already wired in `factory.yml`.
2. Run **factory-setup** — verifies the App token mints and has write access, creates the 8
   protocol labels idempotently, and confirms a Claude credential is present.

The labels it creates:

| label | who uses it | meaning |
|---|---|---|
| `bot:build` | maintainers | opt-in: the bot builds this issue. The label is the trust boundary — applying it vouches for the build order (the body, or the newest 📋 build-order comment on a shaped issue) |
| `bot:idea` | maintainers (bot too, as proposals) | intake: the bot shapes a fuzzy idea into a versioned 📋 build order in-thread and stops; promote by swapping to `bot:build` |
| `bot:review` | maintainers | opt-in: the bot posts review-only passes on this PR (comments + suggestions, never pushes). Re-reviews on new commits while the label stays; remove to stop |
| `agent:in-progress` | loops | an agent holds the lock on this item |
| `agent:needs-reply` | loops | parked on a question — answer in-thread to resume |
| `needs:human` | loops | true takeover needed; comes with an actionable handoff |
| `risk:low` | reviewer | honest low-risk call — required before `ready:merge` |
| `ready:merge` | reviewer | passed the full review gate — a human clicks merge |

Also worth having (almost certainly already true): **branch protection on the default
branch** — required CI checks, no force-pushes. Human review requirements are fine to keep;
the bot never merges, so nothing in the factory conflicts with them.

Recommended, not required, on a public repo: a short note for the community — a paragraph in
CONTRIBUTING or a pinned discussion saying what the bot is, what the labels mean, and that
only maintainers direct it. People *will* see its PRs and ask.

## The trust model in one paragraph

Only write-access users (GitHub author association OWNER/MEMBER/COLLABORATOR) can steer the
loops — everyone else's issues, comments, and PRs are data the maintainers may act on, never
instructions the bot acts on. The builder sees only `bot:build` and `bot:idea` issues; the reviewer sees only
the bot's own PRs and `bot:review` PRs. The workflow's trigger conditions and the dispatcher's
pre-check apply the same gate, so drive-by comments don't even cost an agent run. And every
job reads its prompts from the **default branch**, so the factory's instructions change only
when a human merges a change to them.

## Verify the machine turns

1. File a small, well-specified test issue ("add a health-check util returning `{ok:true}`,
   with a test") and label it `bot:build`.
2. Within a minute (or a sweep cycle): the builder labels it `agent:in-progress`, a
   `bot/<n>-…` branch and draft PR appear, then it flips ready with a tour comment.
3. The reviewer cold-reviews it over the next cycles, fixes anything it finds, and — from a
   clean cycle — labels it `ready:merge` with a handoff comment tagging the maintainer. It
   stops there: **the merge click is yours.**
4. File a deliberately ambiguous issue, label it `bot:build`, and confirm the builder
   **asks** (an optioned, phone-answerable question + `agent:needs-reply`) instead of
   guessing — then answer in-thread and watch it resume.
5. Label one open PR `bot:review` and confirm the reviewer posts a single COMMENT review with
   inline suggestions and a `🔍 reviewed <sha>` marker, and pushes nothing.
6. Optionally: comment on a bot PR from an account with no write access and confirm nothing
   wakes up.
7. Label a vague one-liner issue `bot:idea` and confirm the builder replies with a full
   `📋 Build order` (plus questions) and builds nothing. Reply with a change, watch it repost
   the full revised order, then swap the label to `bot:build` and watch it build exactly
   that.

Tests 4 and 6 matter as much as the happy path — the escalation protocol and the trust gate
are the factory's actual safety systems.

For a free end-to-end dry run of the dispatcher itself, run `.factory/route.sh builder`
locally with `FACTORY_DRY_RUN=1` (needs `gh` authed and `FACTORY_BOT_LOGIN` set): it prints
the go/no-go decision and writes the fully assembled prompt to a file without invoking the
agent.

## Day-to-day operation

Everything happens from the GitHub app on your phone:

- **Feed the queue** — label well-specified issues `bot:build`.
- **Toss in ideas** — label fuzzy issues `bot:idea`; the bot shapes them into build orders
  in-thread. Promote one by swapping the label to `bot:build` — promotion is always your
  act, including for the bot's own proposals.
- **Request reviews** — label PRs `bot:review`; remove the label to stop the passes.
- **Answer parked questions** — anything `agent:needs-reply` resumes on your reply.
- **Merge gated PRs** — anything `ready:merge` has passed the full gate and waits on your
  click.
- **Take over rarely** — `needs:human` items come with a self-contained handoff.

Operational notes:

- **Updates ship by merge** — change anything under `.factory/` on the default branch and
  the very next run uses it. There is nothing else to restart.
- **Health**: the Actions tab is the log. Each factory run shows the pre-check decision and
  the full agent transcript; re-run **factory-setup** any time as a doctor check.
- **Idle cost is ~nothing**: with no `bot:*` labels applied, event runs are filtered out by
  the workflow's conditions and sweep runs exit at the pre-check in seconds.
- GitHub disables scheduled workflows after ~60 days without repo activity — any commit
  re-enables them, and event-triggered runs are unaffected.
