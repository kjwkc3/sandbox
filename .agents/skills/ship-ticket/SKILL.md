---
name: ship-ticket
description: >-
  Ship a Linear ticket end-to-end using the Cursor Avatar Team orchestrator.
  Use when the user invokes /ship-ticket, says "ship ticket KJW-N", or asks to
  implement and merge a Linear issue through the full delivery workflow.
disable-model-invocation: true
---

# Ship Ticket

End-to-end delivery workflow for a Linear issue using the **Cursor Avatar Team** root orchestrator. Proven on KJW-5.

## Invocation

```
/ship-ticket KJW-5
/ship-ticket KJW-6
ship ticket KJW-7
```

Parse `LINEAR-TAG` from the argument (e.g. `KJW-5`). The tag format is `<TEAM>-<NUMBER>`.

## Prerequisites

Before starting, confirm these are available:

| Requirement | Purpose |
|-------------|---------|
| **WSL** | Odin builds and `SANDBOX_CAPTURE` run in Linux |
| **Linear MCP plugin** | Fetch issue, comment, set status |
| **Linear CLI** (`@schpet/linear-cli`) | Fallback issue queries; see [linear-cli](../linear-cli/SKILL.md) |
| **`gh` authenticated** | PR create, CI status, merge |
| **Cursor Avatar Team orchestrator** | Root dispatcher at `~/.cursor/rules/orchestrator.mdc` |

## Human gates

**Plan approval is mandatory.** After Phase 2, present the plan and **STOP**. Do not implement until the human replies with explicit approval: `approved`, `go`, or `proceed`.

No other phase requires approval by default. Escalate to the human when scope is ambiguous, CI failures are out of PR scope, or merge would require overriding failing checks.

## Avatar Team routing

The root orchestrator dispatches work; it never implements directly.

| Agent | Role | Fire when |
|-------|------|-----------|
| **Toph** | Explore | Codebase search, docs lookup |
| **Sokka** | Plan | Implementation plan before coding |
| **Appa** | Execute plan | Plan approved — implement step-by-step |
| **Katara** | Surgical fix | Bug fixes, small targeted repairs |
| **Aang** | Architect-executor | No plan + needs building; escalate after 2 Katara failures |
| **Shell** | Git/CI ops | Commit, push, PR, merge commands |
| **Bugbot** | Review | Readonly review of branch changes |
| **Iroh** | Documentation | README/CHANGELOG (not default in this workflow) |

**Executor routing:** Plan exists → Appa. Something broken → Katara. No plan + build → Aang. 2+ Katara failures → Aang.

## Workflow

Track progress through phases. Do not skip human gates or CI checks.

```
Phase 0 — Kickoff
Phase 1 — Explore
Phase 2 — Plan          ← STOP for human approval
Phase 3 — Implement
Phase 4 — Ship
Phase 5 — Review
Phase 6 — CI + merge
Phase 7 — Close loop
```

### Phase 0 — Kickoff

1. Parse `LINEAR-TAG` (e.g. `KJW-5`).
2. Fetch the issue via **Linear MCP** (title, description, acceptance criteria, labels, state).
3. Derive branch slug from issue title (lowercase, hyphenated, max ~40 chars).
4. Branch name: `williamskj93/<tag-lowercase>-<slug>` (e.g. `williamskj93/kjw-5-set-up-3d-rendering-pipeline`).
5. From `main`: checkout branch if it exists, otherwise create it.
6. Confirm working tree is clean before exploration.

### Phase 1 — Explore

`Task(toph)` — gather:

- Full issue context from Linear
- Relevant codebase areas, ADRs (`docs/adr/`), `CONTEXT.md` glossary
- Existing patterns to match (build, test, render pipeline)
- `.out-of-scope/` if triage rejected similar work

Return a concise exploration summary to the orchestrator.

### Phase 2 — Plan

`Task(sokka)` — produce an implementation plan:

- Files to create/modify
- Approach and trade-offs
- Verification steps (build, capture, tests)
- Estimated scope

**Present the plan to the human. STOP.** Wait for `approved`, `go`, or `proceed`. Do not dispatch Appa until approved.

### Phase 3 — Implement

After plan approval:

`Task(appa)` — implement exactly per plan. Self-verify:

1. **Build (WSL):**
   ```bash
   ./build.sh
   ```
   Or `make` per project conventions.

2. **Screenshot validation** (graphics/rendering work):
   ```bash
   SANDBOX_CAPTURE=1 ./build/sandbox-debug
   ```
   Read PNGs from `debug/frames/` (e.g. `frame_000.png`) and validate visuals match acceptance criteria.

3. **Lint** — zero errors on modified files.

**Fixes during implementation:**
- `Task(katara)` for surgical fixes
- After **2 Katara failures** on the same issue → escalate to `Task(aang)`

### Phase 4 — Ship

`Task(shell)`:

1. Stage only in-scope files
2. Commit with a clear message (why, not just what)
3. Push branch to origin
4. Create PR targeting `main`:
   ```bash
   gh pr create --base main --title "<issue title>" --body "$(cat <<'EOF'
   ## Summary
   - ...

   ## Linear
   Closes KJW-N

   ## Test plan
   - [ ] ...
   EOF
   )"
   ```

Do **not** push unless this phase (user typically approves push as part of ship).

### Phase 5 — Review

1. `Task(bugbot)` — readonly review on **branch changes**
2. `Task(katara)` — address **valid** findings only; explain when disagreeing
3. Push fix commits if needed

### Phase 6 — CI + merge

Follow the **babysit** pattern (`~/.cursor/skills-cursor/babysit/SKILL.md`):

1. Watch CI on the PR
2. Fix in-scope failures; merge latest `main` if failures are upstream
3. Resolve merge conflicts preserving intent
4. **`gh pr merge`** only when CI is green and PR is mergeable

**Never merge with failing CI** unless the human explicitly overrides.

### Phase 7 — Close loop

Via **Linear MCP**:

1. Comment on the issue with PR link and brief summary
2. Set issue state to **Done**

## Screenshot validation

For visual/rendering tickets:

| Step | Command / path |
|------|----------------|
| Capture | `SANDBOX_CAPTURE=1 ./build/sandbox-debug` |
| Frames | `debug/frames/frame_*.png` |
| Validate | Read latest frame; compare to issue acceptance criteria |

If capture fails or frames are blank/wrong, treat as implementation failure — fix before Phase 4.

## What NOT to do

- **Scope creep** — implement only what the issue and approved plan cover
- **Skip plan approval** — never dispatch Appa before human says go
- **Merge without green CI** — unless human explicitly overrides
- **Root implements directly** — orchestrator dispatches Task() only
- **Remove failing tests** or suppress types (`as any`, `@ts-ignore`) to pass
- **Force-push to main** — always PR into main
- **Push without ship phase** — commit locally is fine; push belongs in Phase 4

## Example session

```
User: /ship-ticket KJW-6

Orchestrator:
  Phase 0 — fetched KJW-6 "Add dungeon floor mesh", branch williamskj93/kjw-6-add-dungeon-floor-mesh
  Phase 1 — toph explored render/mesh.odin, assets/dungeon/
  Phase 2 — sokka plan presented → WAITING

User: approved

Orchestrator:
  Phase 3 — appa implemented, build OK, capture validated frame_000.png
  Phase 4 — PR #12 opened
  Phase 5 — bugbot: 1 valid fix applied
  Phase 6 — CI green, merged
  Phase 7 — Linear comment posted, KJW-6 → Done
```
