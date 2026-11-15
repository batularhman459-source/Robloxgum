# Renders every spec in anim/specs with the roblox-animation renderer and builds one overview sheet
# (one row per animation, 6 frames from the side) at anim/build/overview.png, plus a GIF per clip.
#   .\anim\render.ps1                 # all specs
#   .\anim\render.ps1 -Name Vault     # one spec
# Embedded rig scripts stay disabled (no --enable-autoexec): the rig UI isn't needed to render.
param([string]$Name)
# Continue: Blender writes deprecation warnings to stderr, which "Stop" would treat as fatal.
$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot -Parent)
$blender = "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe"
$rig = "C:\Users\ghada\Documents\Roblox-Work\rigs\MrXen0_R15RIG_v1.2.blend"
$render = "$env:USERPROFILE\.claude\skills\roblox-animation\scripts\anim_render.py"
$ffmpeg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
New-Item -ItemType Directory -Force anim/build | Out-Null

$specs = if ($Name) { @("anim/specs/$Name.json") } else { (Get-ChildItem anim/specs/*.json).FullName }
$rows = @()
foreach ($spec in $specs) {
    $n = [IO.Path]::GetFileNameWithoutExtension($spec)
    $out = (Join-Path (Resolve-Path anim/build) $n)
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    $log = & $blender -b $rig -P $render -- (Resolve-Path $spec) $out 2>&1
    $verdict = $log | Where-Object { $_ -match "=== done|INTACT|BROKEN|FAIL|Error|Traceback" } | Select-Object -Last 2
    Write-Host ("{0,-12} {1}" -f $n, ($verdict -join " | "))
    $frames = @(Get-ChildItem $out -Filter "side_*.png" | Sort-Object Name)
    if ($frames.Count -eq 0) { continue }
    $step = [Math]::Max(1, [Math]::Floor($frames.Count / 6))
    & $ffmpeg -y -loglevel error -i "$out\side_%03d.png" -vf "select='not(mod(n\,$step))',scale=150:-1,tile=6x1" -frames:v 1 "$out\row.png"
    & $ffmpeg -y -loglevel error -framerate 30 -i "$out\side_%03d.png" -vf "scale=240:-1,split[a][b];[a]palettegen[p];[b][p]paletteuse" -loop 0 "anim/build/$n.gif"
    $rows += "$out\row.png"
}
if ($rows.Count -gt 1) {
    $inputs = @(); foreach ($r in $rows) { $inputs += "-i"; $inputs += $r }
    & $ffmpeg -y -loglevel error @inputs -filter_complex "vstack=inputs=$($rows.Count)" "anim/build/overview.png"
    Write-Host "overview: anim/build/overview.png"
}
