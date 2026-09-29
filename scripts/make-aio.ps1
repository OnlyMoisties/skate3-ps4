# All-in-one Skate 3 package: the current eboot plus the game files (disc + TU3 xexp), default
# settings and the starter save, so a console needs nothing but this pkg. The eboot finds the game
# at /app0/game when /data/skate3/game does not exist.
#   powershell -ExecutionPolicy Bypass -File scripts\make-aio.ps1   (edit scripts\config.ps1 first)
# Build the eboot first (deploy-skate3.ps1). Output: out-skate3-aio\Skate3_AIO.pkg (~6.5 GB).
#
# make-pkg.ps1 stages everything and writes the gp4 (game files referenced in place), but the
# final pack uses the patched Sony orbis-pub-cmd: PkgTool.Core crashes on a package this size.
# orbis-pub-cmd additionally wants FORMAT=obs in param.sfo and no empty sce_sys/about folder.
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\config.ps1"
Set-Location $Workspace
$art = "$Workspace\art"
$out = "$Workspace\out-skate3-aio"
# Default settings always; a starter save only if you put one in art\defaults\save
# (SKATER.P, RMCDEL, ALIAS_SKATER.header from /data/skate3/B13E07DFF9AB6772/454108E6/...).
$extras = @("$art\pic1.png=sce_sys/pic1.png", "$PSScriptRoot\..\config\settings.toml=defaults/settings.toml")
if (Test-Path "$art\defaults\save\SKATER.P") {
  $extras += "$art\defaults\save\SKATER.P=defaults/save/SKATER.P",
             "$art\defaults\save\RMCDEL=defaults/save/RMCDEL",
             "$art\defaults\save\ALIAS_SKATER.header=defaults/save/ALIAS_SKATER.header"
}
try { & "$PSScriptRoot\make-pkg.ps1" -Eboot skate3recomp\out\build\ps4\eboot.bin -OutDir $out -TitleId SKAT00001 -Title "Skate 3 | XeMoisties" `
  -Icon "$art\icon0.png" -Extra $extras `
  -Tree "$Workspace\skate3recomp\game=game" 2>&1 | Out-Null } catch { }  # PkgTool's own pack fails; the stage is what we need

$stage = "$out\pkg-stage"
if (-not (Test-Path "$stage\pkg.gp4")) { "AIO build FAILED (no gp4)"; exit 1 }
$env:DOTNET_ROLL_FORWARD = "LatestMajor"
$env:DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1"
& "$Workspace\orbis-sdk-v1\sdk\bin\windows\PkgTool.Core.exe" sfo_setentry "$stage\sce_sys\param.sfo" FORMAT --type Utf8 --maxsize 4 --value obs | Out-Null
[xml]$g = Get-Content "$stage\pkg.gp4"
$about = $g.SelectSingleNode("//dir[@targ_name='sce_sys']/dir[@targ_name='about']")
if ($about) { [void]$about.ParentNode.RemoveChild($about) }
$g.Save("$stage\pkg.gp4")

New-Item -ItemType Directory -Force C:\Games\pkgtmp | Out-Null
$env:TEMP = "C:\Games\pkgtmp"; $env:TMP = "C:\Games\pkgtmp"
Remove-Item "$out\*.pkg" -ErrorAction SilentlyContinue
Push-Location $stage
& $OrbisPubCmd img_create --oformat pkg --skip_digest pkg.gp4 $out 2>&1 | Select-Object -Last 3
Pop-Location
$pkg = Get-ChildItem "$out\IV0000-SKAT00001_00-*.pkg" | Select-Object -First 1
if ($pkg) {
  Move-Item -Force $pkg.FullName "$out\Skate3_AIO.pkg"
  "AIO pkg: $out\Skate3_AIO.pkg ($([math]::Round((Get-Item "$out\Skate3_AIO.pkg").Length / 1GB, 2)) GB)"
} else {
  "AIO build FAILED"
}
