# Builds src/client/Anims.rbxm from the pose specs: make_specs.py -> to_roblox.py -> Lune -> .rbxm.
# Rojo syncs src/client/Anims.rbxm into the client scripts (Client.Anims). Run after changing anim/make_specs.py.
#   .\anim\build.ps1
$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot -Parent)
$env:Path = "$env:USERPROFILE\.rokit\bin;$env:Path"
$py = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$toRoblox = "$env:USERPROFILE\.claude\skills\roblox-animation\scripts\to_roblox.py"
New-Item -ItemType Directory -Force anim/build | Out-Null

& $py anim/make_specs.py
$specs = (Get-ChildItem anim/specs/*.json).FullName
& $py $toRoblox @specs --folder ReplicatedStorage.Anims --no-verify | Out-File -Encoding utf8 anim/build/build.luau
if ($LASTEXITCODE -ne 0) { Write-Host "to_roblox failed" -ForegroundColor Red; exit 1 }
lune run tools/anim_build anim/build/build.luau src/client/Anims.rbxm
exit $LASTEXITCODE

