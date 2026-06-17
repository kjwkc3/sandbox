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
- Oh My OpenCode plugin with multi-agent orchestration
- LSP support for code analysis
- Background agents for parallel tasks
