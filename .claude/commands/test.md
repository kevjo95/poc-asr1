---
description: Write tests for a file, class, function, screen, or the current diff using the test-writer subagent.
argument-hint: [target] [--level unit|component|api|e2e] (empty target = current diff)
---

Arguments: $ARGUMENTS

Parse them: the target is everything before `--level` (a file, class, `Class#method`, function, or screen); the level is the word after it, if present. If the target is empty, use the current changes (`git diff` plus staged and untracked files) and write tests for the behavior they add or change.

Use the `test-writer` subagent with that target and level (if no level, it picks one from the Testing section of `AGENTS.md`). When it finishes, show me:

1. The level it chose and why.
2. The test files it wrote or changed and the behaviors they cover (or "no test written" and why).
3. The command it ran and the result, and how each new test was proven able to fail.
4. Anything it found in production code (bugs, untestable design) and any better target it suggests. Do not fix those yet: ask me.
5. Its "Needs a decision" questions, relayed to me as questions (the subagent cannot ask me itself).

Do not edit production code. An e2e level is only allowed when I passed `--level e2e` and the repo already has an e2e tool.
