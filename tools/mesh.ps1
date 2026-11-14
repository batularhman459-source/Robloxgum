# Mesh pipeline: build -> optimise -> check budget -> render preview. Refuses anything over budget.
#
#   .\tools\mesh.ps1 -Name Lantern        # one model (maps/models/Lantern.py)
#   .\tools\mesh.ps1                       # every model
#
# Output in maps/build/: <Name>.fbx (import this), <Name>.blend, <Name>_shaded.png, <Name>_wire.png,
# <Name>.report.json. Exit code 1 if any model was refused.
param([string]$Name)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
$blender = $env:BLENDER_PATH
if (-not $blender) {
    $blender = Get-ChildItem "C:\Program Files\Blender Foundation" -Recurse -Filter blender.exe -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $blender) { throw "Blender not found. Install it or set BLENDER_PATH." }
New-Item -ItemType Directory -Force maps/build | Out-Null

$models = if ($Name) { @("maps/models/$Name.py") } else { (Get-ChildItem maps/models/*.py).FullName }
$failed = 0
foreach ($model in $models) {
    $n = [IO.Path]::GetFileNameWithoutExtension($model)
    $fbx = (Join-Path (Resolve-Path maps/build) "$n.fbx")
    Write-Host "`n=== $n ===" -ForegroundColor Cyan
    $log = & $blender -b --factory-startup -P tools/blender/check.py -- $model $fbx maps/budgets.toml 2>&1
    $line = $log | Where-Object { $_ -like "MESHREPORT *" } | Select-Object -Last 1
    if (-not $line) { $log | Select-Object -Last 15 | ForEach-Object { Write-Host $_ }; $failed++; continue }
    $json = $line.ToString().Substring(11)
    [IO.File]::WriteAllText((Join-Path (Resolve-Path maps/build) "$n.report.json"), $json)
    $r = $json | ConvertFrom-Json
    Write-Host ("triangles {0} -> {1} (budget {2}: {3})" -f $r.trianglesBefore, $r.triangles, $r.budgetClass, $r.budget)
    foreach ($o in $r.objects) { Write-Host ("  {0,-12} {1,6} tris  size {2} studs" -f $o.name, $o.triangles, ($o.size -join " x ")) }
    foreach ($x in $r.notes) { Write-Host "  note: $x" -ForegroundColor Yellow }
    foreach ($x in $r.problems) { Write-Host "  REFUSED: $x" -ForegroundColor Red }
    if (-not $r.ok) { $failed++; continue }
    $png = (Join-Path (Resolve-Path maps/build) "$n.png")
    & $blender -b ($fbx -replace '\.fbx$', '.blend') -P tools/blender/render.py -- $png 2>&1 | Out-Null
    Write-Host "  OK: maps/build/$n.fbx, preview maps/build/${n}_shaded.png + _wire.png" -ForegroundColor Green
}
if ($failed) { Write-Host "`n$failed model(s) refused" -ForegroundColor Red; exit 1 }
Write-Host "`nAll models within budget." -ForegroundColor Green
