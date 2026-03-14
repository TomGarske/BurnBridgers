# CLAUDE.md

Claude agents in this repository must follow `AGENTS.md` as the canonical policy.

## Required Behavior

1. Read `AGENTS.md` first for every non-trivial task.
2. Read relevant ADRs in `/docs/adr` before architecture-sensitive implementation.
3. Classify work as Type A/B/C/D (implementation-only, ADR-extension, ADR-required, ADR-conflicting).
4. If Type C or D, draft ADR work first and do not silently modify architecture-sensitive code.
5. Include architecture compliance notes in task/PR summaries.
6. Create a short-lived branch from `main` before coding material changes.
7. After pushing that branch, immediately open a PR to `main` unless explicitly told not to.
8. Use a real PR creation command (for example `gh pr create`) and return the resulting PR URL.

## If Instructions Conflict

Follow environment/system safety instructions first, then `AGENTS.md`, then this file.
