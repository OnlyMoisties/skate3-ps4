# Local settings for the build/deploy scripts. Edit these for your machine, or set the
# environment variables instead.
#
# Workspace layout this repo expects (all siblings in one folder):
#   <workspace>\skate3recomp\        skate3recomp clone (patched), with game\ = your extracted game + TU3
#   <workspace>\orbis-sdk-v1\        orbis-ports PS4 bundle (OpenOrbis + orbis-compat + Mesa RADV)
#   <workspace>\oo054\               OpenOrbis v0.5.4 release (for libc.prx / libSceFios2.prx)
#   <workspace>\libcxx-ps4\          libc++ 22 built with toolchain\libcxx-ps4.cmake
#   <workspace>\art\                 icon0.png (512x512), pic1.png (1920x1080), defaults\ (see README)
#   <workspace>\skate3-ps4-port\     this repo

$Workspace = if ($env:SKATE3_WORKSPACE) { $env:SKATE3_WORKSPACE } else { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }

# The PS4 (GoldHEN FTP on port 2121).
$ConsoleIp = if ($env:PS4_IP) { $env:PS4_IP } else { "192.168.1.100" }

# Patched Sony publishing tool (orbis-pub-cmd 3.87) - only needed for the AIO pkg.
$OrbisPubCmd = if ($env:ORBIS_PUB_CMD) { $env:ORBIS_PUB_CMD } else { "$Workspace\tools\orbis-pub-cmd.exe" }
