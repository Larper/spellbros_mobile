---
description: Write a self-contained handoff doc so another AI can continue this work cold
---

Produce a **session handoff document** that lets a different AI (with no access to
this conversation) pick up exactly where we are and keep going. Treat everything
in the current conversation as the source of truth; the repo is the second source.

First gather live state (do not guess — run these):

- `git branch -a` and `git branch --show-current`
- `git log --oneline -12` on the current branch, and `git log --oneline -6` on each other local branch that matters
- `git status --short`
- The exact headless test / build / deploy commands used this session (find them in the repo, e.g. `deploy.ps1`, any test runner, README)
- Skim the key source files touched this session so file paths and responsibilities are accurate

Then write the handoff to **`docs/handoff-<YYYY-MM-DD>.md`** (create `docs/` if needed;
get the date from the environment context, never fabricate it). Structure it like this,
filling every section from real state — omit a section only if truly N/A:

1. **Task / goal** — what this project is and what we're building, in 3-4 sentences.
2. **Environment** — OS, shell, engine/runtime + exact version and path, repo path, any external accounts/hosts/tokens (name the token *file path*, never the secret).
3. **Working preferences** — how the human wants the AI to work (verification method, commit/push policy, code style, anything they've corrected the AI on). Pull these from the conversation and from any memory/CLAUDE.md.
4. **Current state** — what's done and verified vs. in progress. Name the branch each thing lives on. Quote the latest passing-test line if there is one.
5. **Branches** — one line per branch: what it contains, latest commit hash, whether it's pushed.
6. **Key files** — the load-bearing files and what each owns (path + one line).
7. **Commands** — the exact copy-pasteable commands for test / run / build / deploy, with any gotchas (e.g. re-import after adding a class).
8. **Design decisions & gotchas** — non-obvious choices, tuning constants that matter, bugs already fixed and why, traps to avoid. This is where the hard-won context goes — be generous.
9. **Next steps / open threads** — numbered, concrete, most important first. Include anything the human asked for that isn't done yet, and any known-rough areas.

Write for a competent stranger: expand every codename or shorthand, spell out
paths, and prefer specifics over summary. When done, print the file path and a
2-3 sentence description of what the next AI should tackle first.

$ARGUMENTS
