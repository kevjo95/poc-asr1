@AGENTS.md

## Claude Code specifics

- Claude Code reads this file, not AGENTS.md; the import above keeps a single source of truth. Put only Claude-specific guidance below.
- Start non-trivial work in plan mode (Shift+Tab) or with `/plan`.
- Delegate to subagents in `.claude/agents/`: `planner` (design a plan, read-mostly), `test-writer` (writes unit tests, edits test files only; use `/test`) and `reviewer` (read-only review of the diff).
- Parallel work: one task per worktree (`claude --worktree <name>`), never two sessions in the same directory.
- Context getting heavy or off-track: `/handoff` (writes state to a file), then `/clear`, then resume from that file.
- Personal preferences go in `CLAUDE.local.md` (gitignored) or `~/.claude/CLAUDE.md`, not here.
