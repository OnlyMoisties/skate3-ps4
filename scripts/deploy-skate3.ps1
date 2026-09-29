# Build the Skate 3 PS4 eboot, package it and upload it to the console's /data/pkg/Skate3.pkg.
#   powershell -ExecutionPolicy Bypass -File scripts\deploy-skate3.ps1   (edit scripts\config.ps1 first)
# Native tools print warnings on stderr, so errors are judged by exit codes, not by stderr.
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\config.ps1"
. "$Workspace\skate3-ps4-port\toolchain\env.ps1"
Remove-Item Env:CC, Env:CXX -ErrorAction SilentlyContinue
Set-Location "$Workspace\skate3recomp"
cmd /c "ninja -C out/build/ps4 -j 12 skate3 > $Workspace\ps4-deploy-build.log 2>&1"
if ($LASTEXITCODE) {
  Select-String -Path "$Workspace\ps4-deploy-build.log" -Pattern ' error: |undefined symbol' |
    Select-Object -First 20 | ForEach-Object Line
  Write-Output "BUILD FAILED"
  exit 1
}
Write-Output "build ok"
Set-Location $Workspace
$extras = @("$Workspace\art\pic1.png=sce_sys/pic1.png", "$PSScriptRoot\..\config\settings.toml=defaults/settings.toml")
if (Test-Path "$Workspace\art\defaults\save\SKATER.P") {
  foreach ($n in "SKATER.P", "RMCDEL", "ALIAS_SKATER.header") { $extras += "$Workspace\art\defaults\save\$n=defaults/save/$n" }
}
& "$PSScriptRoot\make-pkg.ps1" -Eboot skate3recomp\out\build\ps4\eboot.bin -OutDir out-skate3 -TitleId SKAT00001 -Title "Skate 3 | XeMoisties" -Icon "$Workspace\art\icon0.png" -Extra $extras
python -c @"
import ftplib, os
p = r'$Workspace\out-skate3\IV0000-SKAT00001_00-SKAT000010000000.pkg'
f = ftplib.FTP(); f.connect('$ConsoleIp', 2121, timeout=60); f.login()
f.storbinary('STOR /data/pkg/Skate3.pkg', open(p, 'rb'), blocksize=1 << 20)
print('uploaded', os.path.getsize(p), 'console', f.size('/data/pkg/Skate3.pkg'))
f.quit()
"@
