# Building on Windows

## Prerequisites

1. **Odin** — download [odin-windows-*.zip](https://github.com/odin-lang/Odin/releases) and add the extracted `dist/` folder to `PATH`. `odin.exe` must sit next to `base/`, `core/`, and `vendor/`.
2. **Visual Studio Build Tools** — install the "Desktop development with C++" workload (Windows SDK + MSVC linker).
3. **SDL2** — bundled with Odin at `vendor/sdl2/SDL2.lib` and `SDL2.dll`. No separate SDL install is required if Odin is set up correctly.

## Common SDL2 errors

| Symptom | Cause | Fix |
|---------|-------|-----|
| `SDL2 not installed` / `cannot open input file 'SDL2.lib'` | Incomplete Odin install or bad `ODIN_ROOT` | Use the full release zip; unset `ODIN_ROOT` or point it at the `dist` folder **without** a trailing `\` |
| App exits immediately / `SDL2.dll was not found` | DLL not beside the executable | Run `.\build.ps1` — it copies `SDL2.dll` into `build/` after linking |

## Build and run

```powershell
.\build.ps1          # debug build → build/sandbox-debug.exe
.\build.ps1 -Run     # build and launch
.\build.ps1 -Release # release build → build/sandbox-release.exe
```

Manual build (equivalent):

```powershell
odin build . -out:build/sandbox-debug.exe -debug -vet `
  -extra-linker-flags:"-LIBPATH:`"$((odin root).Trim().TrimEnd('\'))\vendor\sdl2`""
Copy-Item "$((odin root).Trim().TrimEnd('\'))\vendor\sdl2\SDL2.dll" build\
.\build\sandbox-debug.exe
```

Run from the project root so `assets/dungeon/` resolves correctly (or `cd build` after copying assets if needed).
