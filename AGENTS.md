# Project: Sandbox

## Overview
This is a sandbox project for experimentation and development.

## Development Guidelines
- Follow clean code practices
- Write meaningful commit messages
- Test changes before committing

## Windows Build (SDL2)
Requires a full Odin install (not just `odin.exe`) — the release zip includes `vendor/sdl2/SDL2.lib` and `SDL2.dll`.

```powershell
.\build.ps1        # build debug exe + copy SDL2.dll to build/
.\build.ps1 -Run   # build and launch
```

If you set `ODIN_ROOT`, omit the trailing backslash. Linux CI installs SDL2 via `libsdl2-dev`; Windows uses Odin's bundled vendor libs.

## Tools Available
- **Cursor Avatar Team** — multi-agent orchestration via root dispatcher (`~/.cursor/rules/orchestrator.mdc`)
- **Linear MCP + linear-cli** — issue tracking and ticket workflow
- **`/ship-ticket KJW-N`** — end-to-end delivery skill (see `.agents/skills/ship-ticket/SKILL.md`)
- LSP support for code analysis
- Background agents for parallel tasks

## Agent Skills

Project skills live under `.agents/skills/`. Key workflows:

| Skill | Invoke | Purpose |
|-------|--------|---------|
| ship-ticket | `/ship-ticket KJW-5` | Ship a Linear ticket through explore → plan → implement → PR → merge |
| triage | `/triage` | Issue triage state machine |
| linear-cli | (ambient) | Linear CLI reference |
| diagnose | `/diagnose` | Structured bug diagnosis |
| tdd | `/tdd` | Test-driven development loop |
