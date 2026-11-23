---
description: One-time. Explore this repo and fill in the TODOs in AGENTS.md with verified facts; finish a pending CLAUDE.md merge.
---

Fill in `AGENTS.md` for this repository. Rules:

1. Explore first: README, build files (pom.xml / build.gradle / package.json / Makefile / etc.), CI config, top-level layout, existing docs.
2. Replace every `TODO` with facts you verified. Actually run the build/test/lint commands you list (or the cheapest safe variant) and only keep commands that work. If one cannot run here, mark it `(unverified)`.
3. Write only what cannot be inferred from the code. Keep the file under 150 lines.
4. Do not invent conventions: derive them from existing code and CI, and quote the file that proves each one.
5. Fill the `Testing` section from real tests: read several existing test files, shared test support (base classes, builders, fixtures) and the CI config. Identify which levels exist (unit, component/API, e2e) by what the tests actually load and call (for example a full application context plus HTTP client = component/API; a rendered component = component), and fill one table row per level with the real runner command and one real example path. Delete rows for levels that do not exist. Record the default level (it only breaks ties), the environment needed to run tests, what is faked and what is not, the shared support to reuse, and any test rules the repo already states elsewhere in `AGENTS.md` or `CLAUDE.md` (point to them from this section, e.g. `see Change Guidelines`; never delete or move the team's own lines, and do not duplicate them). Do not write volatile numbers (test counts, dates) in the file; they go stale. Do not edit the team's own command lines to annotate them; report what you verified in your summary instead. If the repo has no tests, write `No tests yet` and recommend a framework without installing it. If `AGENTS.md` has no `Testing` section (for example it was kept from before the kit), add one.
6. Files you may touch: `AGENTS.md`, and `CLAUDE.md` only under the merge rule below. At the end, list what you could not determine so a human can answer.

## Pending AGENTS.md augment

Only if `AGENTS.md` contains the line `<!-- ai-repo-kit: augment-pending ... -->` (the original is also saved as `AGENTS.md.bak`). Everything above the marker is the team's own content: do not rewrite or reorder it. Below it the kit appended generic `Boundaries` and/or `Workflow` sections.

1. Tailor the appended sections to this repo: keep the generic rules, add what the repo makes concrete (for example real infra or auth paths under "Ask first"). Do not invent rules; derive them from code, CI and the existing content.
2. If an appended rule contradicts the team's content above, do not pick one: keep both marked `(conflict: ask the team)` and list it.
3. Verify the commands already in the file the same way as rule 2 above and mark what cannot run `(unverified)`. Fix only what is demonstrably wrong and say so.
4. Remove the marker line. If the file is now over 150 lines, do not cut the team's content: report it so a human can prune.
5. Summarize what was appended, tailored, found in conflict or flagged. Do not delete `AGENTS.md.bak`; tell the human to delete it after reviewing.

## Pending CLAUDE.md merge

Only if `CLAUDE.md` contains the line `<!-- ai-repo-kit: merge-pending ... -->` (the original is also saved as `CLAUDE.md.bak`):

1. Split the original content (the part between the marker and `## Claude Code specifics`) into two groups:
   - **Shared**: commands, architecture, conventions, deployment notes, boundaries. Anything any agent or person needs.
   - **Claude Code specific**: slash commands, subagents, worktrees, hooks, anything about how Claude Code itself behaves.
2. Move **shared** content into the matching `AGENTS.md` section. Merge, do not append blindly:
   - If `AGENTS.md` already says the same thing, keep one copy. If the two disagree, do not pick: list the conflict for the human and keep both versions marked `(conflict: ask the team)`.
   - Keep `AGENTS.md` under 150 lines; compress or drop what the code already makes obvious, and say what you dropped.
   - Verify moved commands the same way as rule 2.
3. Leave in `CLAUDE.md` only: `@AGENTS.md`, then the Claude Code specifics section (plus any Claude-only content from the original). Remove the marker line.
4. Fix references that point to the old layout (for example "update CLAUDE.md" in plans or docs) only if they are in `AGENTS.md`/`CLAUDE.md`; list the rest for the human.
5. Show a summary before finishing: what moved where, what was dropped as duplicate, conflicts found. Do not delete `CLAUDE.md.bak`; tell the human to delete it after reviewing the result.
