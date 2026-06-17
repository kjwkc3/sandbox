$ErrorActionPreference = "Stop"

$OutDir = "build"
$OutFile = Join-Path $OutDir "sandbox-debug.exe"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

odin build . -out:$OutFile -debug -vet
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Built: $OutFile"
