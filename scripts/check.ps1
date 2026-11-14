# The 4 gates. Nothing goes to Studio unless all pass.
# Usage:  .\scripts\check.ps1          (check only)
#         .\scripts\check.ps1 -Fix     (let StyLua reformat first)
param([switch]$Fix)

$env:Path = "$env:USERPROFILE\.rokit\bin;$env:Path"
Set-Location (Split-Path $PSScriptRoot -Parent)
New-Item -ItemType Directory -Force build | Out-Null
$failed = @()

function Gate($name, [scriptblock]$cmd) {
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    & $cmd
    if ($LASTEXITCODE -ne 0) { Write-Host "FAILED: $name" -ForegroundColor Red; $script:failed += $name }
    else { Write-Host "OK: $name" -ForegroundColor Green }
}

$luau = @("src", "tests", "tools", "ui/specs")
if ($Fix) { stylua @luau }

Gate "1. Rojo build" { rojo build default.project.json -o build/game.rbxl }
Gate "2. Tests"      { lune run tests/run }
Gate "3. Lint"       { selene src }
Gate "4. Format"     { stylua --check @luau }
Gate "5. UI check"   { lune run tools/ui check }

if ($failed.Count) { Write-Host "`n$($failed.Count) gate(s) failed: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "`nAll 5 gates passed. Safe to sync to Studio." -ForegroundColor Green
