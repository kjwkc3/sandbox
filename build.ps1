param(
    [switch]$Run,
    [switch]$Release
)

$ErrorActionPreference = "Stop"

function Get-OdinRoot {
    if ($env:ODIN_ROOT) {
        $root = $env:ODIN_ROOT.TrimEnd('\', '/')
    } else {
        $root = (odin root).Trim().TrimEnd('\', '/')
    }

    if (-not (Test-Path $root)) {
        throw @"
Invalid ODIN_ROOT: '$root' does not exist.

Install Odin from https://github.com/odin-lang/Odin/releases (odin-windows-*.zip),
extract the full dist folder, and add it to PATH so odin.exe sits next to base/, core/, and vendor/.

On Windows, do not set ODIN_ROOT with a trailing backslash.
"@
    }

    return $root
}

function Get-Sdl2Paths {
    param([string]$OdinRoot)

    $vendorDir = Join-Path $OdinRoot "vendor\sdl2"
    $lib = Join-Path $vendorDir "SDL2.lib"
    $dll = Join-Path $vendorDir "SDL2.dll"

    if (-not (Test-Path $lib)) {
        throw @"
SDL2 not installed: missing '$lib'.

vendor:sdl2 links against SDL2.lib shipped with Odin. You need a complete Odin install
(odin.exe plus vendor/sdl2/SDL2.lib and SDL2.dll), not just the compiler binary alone.

Fix:
  1. Download odin-windows-*.zip from https://github.com/odin-lang/Odin/releases
  2. Extract and add the dist/ folder to PATH
  3. Unset ODIN_ROOT, or set it to that dist folder without a trailing backslash
"@
    }

    if (-not (Test-Path $dll)) {
        throw "SDL2 not installed: missing '$dll'."
    }

    return @{ Lib = $lib; Dll = $dll; VendorDir = $vendorDir }
}

$OutDir = "build"
if ($Release) {
    $OutFile = Join-Path $OutDir "sandbox-release.exe"
    $BuildArgs = @("build", ".", "-out:$OutFile", "-o:speed", "-vet")
} else {
    $OutFile = Join-Path $OutDir "sandbox-debug.exe"
    $BuildArgs = @("build", ".", "-out:$OutFile", "-debug", "-vet")
}

$odinRoot = Get-OdinRoot
$sdl2 = Get-Sdl2Paths -OdinRoot $odinRoot

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Ensure the linker can find Odin's bundled SDL2 import library on Windows.
$linkerFlags = "-LIBPATH:`"$($sdl2.VendorDir)`""
$BuildArgs += "-extra-linker-flags:$linkerFlags"

odin @BuildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Copy-Item -Path $sdl2.Dll -Destination (Join-Path $OutDir "SDL2.dll") -Force
Write-Host "Built: $OutFile"
Write-Host "Copied SDL2.dll to $OutDir"

if ($Run) {
    Push-Location $OutDir
    try {
        & ".\$(Split-Path $OutFile -Leaf)"
    } finally {
        Pop-Location
    }
}
