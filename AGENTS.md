# <PROJECT NAME>

> Shared instructions for any AI coding agent (Claude Code, Codex, Cursor, Copilot, Gemini CLI).
> Run `/onboard` in Claude Code to fill every TODO from the real repo. Keep this file under ~150 lines:
> write only what an agent cannot infer by reading the code. Delete this note once filled.

## What this is

TODO: 2-3 sentences. What the system does, who uses it, main bounded contexts.

## Commands (verified, copy-paste ready)

- Install: `TODO`
- Build: `TODO`
- Run locally: `TODO`
- Test (all): `TODO`
- Test (single file/class): `TODO`
- Lint / format: `TODO`

## Architecture map

TODO: one line per top-level module/service: `path/` -> responsibility.
Deeper context: `docs/adr/` (decisions) and `docs/plans/` (work in flight).

## Conventions (only the non-obvious ones)

- TODO: naming, layering rules, error handling, logging actually used here.

## Testing

Levels this repo actually uses (keep only the rows that exist; one real example path each):

| Level | Use for | Run (single / all) | Location + example |
|---|---|---|---|
| unit | pure logic and classes with faked collaborators | `TODO` / `TODO` | `TODO` |
| component / API | an endpoint, controller, service wiring, or a UI component/screen with real wiring and faked boundaries | `TODO` / `TODO` | `TODO` |
| e2e | whole flows against a running app (only if the repo already has the tool) | `TODO` / `TODO` | `TODO` |

- Default level: `TODO` (only breaks ties; the agent first picks by what the code is: pure logic -> unit; endpoint/controller/screen -> component/API; `--level` overrides).
- Environment to run tests: `TODO` (JDK/Node version, offline flag, credentials needed, how to filter noisy output).
- Mocking: TODO what is faked (network, DB, clock) and what never is.
- Shared support: TODO base classes, builders, fixtures, test-data folders to reuse (never recreate them).
- Rules: TODO repo-specific test rules (e.g. no reflection, parameterized tests, selector policy). Always: new or changed behavior ships with tests; a failing test is fixed by fixing the cause, never by loosening or skipping it.

## Boundaries

- **Never**: commit secrets or `.env` files, edit generated code, disable tests to make them pass, force-push.
- **Ask first**: DB migrations, public API/contract changes, adding or upgrading dependencies, infra/IaC changes, anything touching auth or payments.

## Workflow

1. Explore the code before proposing changes. Do not guess file locations.
2. Non-trivial change (new behavior, > 3 files, or cross-module): write a plan in `docs/plans/` first (`/plan`) and wait for approval.
3. Architecturally significant decision (new dependency, pattern, data store, boundary): record it in `docs/adr/` (`/adr`).
4. Make small, reviewable commits. Add tests for new behavior (`/test`). Run tests and lint before declaring done.
5. Definition of done: new behavior tested, tests green, lint clean, plan checkboxes updated, ADR added if a decision was made.
