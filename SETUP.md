# Setting up — what touches what

Read [`README.md`](README.md) first for the concept. The server side is one script —
[`SERVER.md`](SERVER.md). This file covers the two things that live outside the server: what
prisma/studio itself needs (almost nothing), and the verify tests worth running once.

## What prisma/studio needs — the entire footprint

The target repo carries **no factory files**. The contract, policy, and prompts all live in
this repo and are assembled into each agent run. What studio needs:

1. **The bot account added as a collaborator** with write access.
2. **The 7 protocol labels** — `factory setup` creates them idempotently:

   | label | who uses it | meaning |
   |---|---|---|
   | `bot:build` | maintainers | opt-in: the bot builds this issue. The label is the trust boundary — applying it vouches for the issue body as a build order |
   | `bot:review` | maintainers | opt-in: the bot posts review-only passes on this PR (comments + suggestions, never pushes). Re-reviews on new commits while the label stays; remove to stop |
   | `agent:in-progress` | loops | an agent holds the lock on this item |
   | `agent:needs-reply` | loops | parked on a question — answer in-thread to resume |
   | `needs:human` | loops | true takeover needed; comes with an actionable handoff |
   | `risk:low` | merger | honest low-risk call — required before `ready:merge` |
   | `ready:merge` | merger | passed the full review gate — a human clicks merge |

3. **Branch protection on the default branch** (almost certainly already true): required CI
   checks, no force-pushes. Human review requirements are fine to keep — the bot never
   merges, so nothing in the factory conflicts with them.

Recommended, not required: a short note for the community — a paragraph in CONTRIBUTING or a
pinned discussion saying what the bot account is, what the labels mean, and that only
maintainers direct it. On a public repo people *will* see its PRs and ask.

## The trust model in one paragraph

Only write-access users (GitHub author association OWNER/MEMBER/COLLABORATOR) can steer the
loops — everyone else's issues, comments, and PRs are data the maintainers may act on, never
instructions the bot acts on. The builder sees only `bot:build` issues; the merger sees only
the bot's own PRs and `bot:review` PRs. The scheduler's wake-up checks apply the same gate,
so drive-by comments don't even cost an agent run.

## Verify the machine turns

1. File a small, well-specified test issue ("add a health-check util returning `{ok:true}`,
   with a test") and label it `bot:build`.
2. Within a cycle or two: the builder labels it `agent:in-progress`, a `bot/<n>-…` branch and
   draft PR appear, then it flips ready with a tour comment.
3. The merger cold-reviews it over the next cycles, fixes anything it finds, and — from a
   clean cycle — labels it `ready:merge` with a handoff comment tagging the maintainer. It
   stops there: **the merge click is yours.**
4. File a deliberately ambiguous issue, label it `bot:build`, and confirm the builder
   **asks** (an optioned, phone-answerable question + `agent:needs-reply`) instead of
   guessing — then answer in-thread and watch it resume.
5. Label one open PR `bot:review` and confirm the merger posts a single COMMENT review with
   inline suggestions and a `🔍 reviewed <sha>` marker, and pushes nothing.
6. Optionally: comment on a bot PR from an account with no write access and confirm nothing
   wakes up.

Tests 4 and 6 matter as much as the happy path — the escalation protocol and the trust gate
are the factory's actual safety systems.

## Day-to-day operation

Everything happens from the GitHub app:

- **Feed the queue** — label well-specified issues `bot:build`.
- **Request reviews** — label PRs `bot:review`; remove the label to stop the passes.
- **Answer parked questions** — anything `agent:needs-reply` resumes on your reply.
- **Merge gated PRs** — anything `ready:merge` has passed the full gate and waits on your
  click.
- **Take over rarely** — `needs:human` items come with a self-contained handoff.
