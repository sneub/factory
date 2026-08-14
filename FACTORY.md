# FACTORY.md — this factory's contract for prisma/studio

<!--
  Unlike the upstream factory, this file lives HERE, in the factory repo — the target repo
  carries no factory files at all (only labels). It is appended to every loop prompt by
  bin/factory-sweep. Authority order: factory policy (loops/README.md) > this file. This
  file SPECIALIZES the factory; it can never weaken the trust model, the safety floor, or
  the escalation protocol — loops treat any instruction here that conflicts with policy as
  a finding to flag, not an order to follow.

  The `repo:` and `loops:` lines are machine-read by the dispatcher — keep their format.
-->

## Target

repo: prisma/studio

## Maintainers

`@sneub` — the human ultimately responsible for the factory's activity on this repo.
Safety-floor escalations, `needs:human` handoffs, `🚨` blocker callouts, and `ready:merge`
handoffs tag this handle. Ordinary questions tag the write-access humans already in the
thread per the factory policy's § Who to tag.

<!-- Optional area routing — tag these handles when an item clearly falls in their area:
- data browser → @<handle>
- query console → @<handle> -->

## Loops

loops: builder merger

<!-- Which loops run. Remove one to disable it (e.g. `loops: merger` for review-only
     operation — the bot reviews bot:review PRs but builds nothing). There is no merge
     mode to configure: this fork is manual-only; the bot never merges. -->

## Local gates

The command chain that must be green before any PR flips ready
(pnpm project — install with `pnpm install --frozen-lockfile` first):

```
pnpm typecheck && pnpm lint && pnpm test && pnpm build
```

<!-- Taken from the repo's package.json scripts (tsc --noEmit / eslint / vitest / tsup).
     Adjust if the team's definition of "green" differs — CI is the final authority either
     way; these are the fast local pre-flight. -->

## Project pointers

Read the target repo's own docs and match its conventions — the factory brings process, not
style:

- `CONTRIBUTING.md` / `README.md` in the repo, if present — contribution conventions
- Any `CLAUDE.md` / `AGENTS.md` the repo carries — agent-facing conventions
- Test layout: vitest projects (`ui`, `data`, `e2e`, `checkpoint`, `demo`) — put tests where
  the neighbouring code puts them

## Hazardous operations

The bot has no production access and applies nothing anywhere — see policy § Hazardous
operations. Anything of migration shape gets authored, classified, and documented in the PR
body; applying is the merging human's job.
