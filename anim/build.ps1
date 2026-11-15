# Builds the R6 parkour animations: anim/r6/Clips.luau -> src/client/Anims.rbxm (Rojo syncs it).
#   .\anim\build.ps1
Set-Location (Split-Path $PSScriptRoot -Parent)
$env:Path = "$env:USERPROFILE\.rokit\bin;$env:Path"
lune run tools/r6_build
exit $LASTEXITCODE
