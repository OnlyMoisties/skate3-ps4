# Build environment for the recomp projects: dot-source it (. <workspace>\skate3-ps4-port\toolchain\env.ps1)
# Imports the MSVC x64 environment (headers/libs for clang), then puts CMake, LLVM and Ninja first on PATH.
$vcvars = "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
cmd /c "`"$vcvars`" >nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] }
}
$env:Path = "C:\Program Files\CMake\bin;C:\Program Files\LLVM\bin;" +
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe;" + $env:Path
$env:CC = "clang"
$env:CXX = "clang++"
