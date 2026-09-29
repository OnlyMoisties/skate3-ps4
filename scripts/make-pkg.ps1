# Windows port of orbis-compat/scripts/ps4/make-pkg.sh: eboot.bin -> fake PKG.
#   .\make-pkg.ps1 -Eboot build-probe\eboot.bin -OutDir out-probe -TitleId SKAT00099 -Title "Skate 3 Probe"
# Extras are "source=target" pairs placed inside the package (e.g. "icon.png=sce_sys/icon0.png").
param(
  [Parameter(Mandatory)] [string]$Eboot,
  [Parameter(Mandatory)] [string]$OutDir,
  [Parameter(Mandatory)] [ValidatePattern('^[A-Z]{4}[0-9]{5}$')] [string]$TitleId,
  [Parameter(Mandatory)] [string]$Title,
  [string]$Version = "01.00",
  [string]$Icon = "",
  [string[]]$Extra = @(),
  [string[]]$Tree = @()   # "sourcedir=targetdir": a whole folder tree, packed without copying
)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\config.ps1"
$Bin = "$Workspace\orbis-sdk-v1\sdk\bin\windows"
$Modules = "$Workspace\oo054\OpenOrbis\PS4Toolchain\src\modules"
$PkgTool = Join-Path $Bin "PkgTool.Core.exe"
$CreateGp4 = Join-Path $Bin "create-gp4.exe"
$env:DOTNET_ROLL_FORWARD = "LatestMajor"          # PkgTool.Core targets .NET Core 3.0
$env:DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1"

$label = ($TitleId.ToUpper() -replace '[^A-Z0-9]', '') + "0000000000000000"
$ContentId = "IV0000-${TitleId}_00-" + $label.Substring(0, 16)

$Stage = Join-Path $OutDir "pkg-stage"
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Force "$Stage\sce_sys", "$Stage\sce_module" | Out-Null
Copy-Item $Eboot "$Stage\eboot.bin"
$files = @("eboot.bin", "sce_sys/param.sfo")
foreach ($prx in "libc", "libSceFios2") {
  Copy-Item "$Modules\$prx.prx" "$Stage\sce_module\$prx.prx"
  $files += "sce_module/$prx.prx"
}
if ($Icon) { Copy-Item $Icon "$Stage\sce_sys\icon0.png"; $files += "sce_sys/icon0.png" }
foreach ($pair in $Extra) {
  $src, $targ = $pair -split '=', 2
  $dst = Join-Path $Stage $targ
  New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
  Copy-Item $src $dst
  $files += $targ
}

$sfo = "$Stage\sce_sys\param.sfo"
& $PkgTool sfo_new $sfo | Out-Null
function SfoSet($name, $type, $max, $value) {
  & $PkgTool sfo_setentry $sfo $name --type $type --maxsize $max --value $value | Out-Null
  if ($LASTEXITCODE) { throw "sfo_setentry $name failed" }
}
SfoSet APP_TYPE Integer 4 1
SfoSet APP_VER Utf8 8 $Version
SfoSet ATTRIBUTE Integer 4 0
SfoSet CATEGORY Utf8 4 gd
SfoSet CONTENT_ID Utf8 48 $ContentId
SfoSet DOWNLOAD_DATA_SIZE Integer 4 0
SfoSet SYSTEM_VER Integer 4 0
SfoSet TITLE Utf8 128 $Title
SfoSet TITLE_ID Utf8 12 $TitleId
SfoSet VERSION Utf8 8 $Version

Push-Location $Stage
try {
  & $CreateGp4 -out pkg.gp4 --content-id=$ContentId --files ($files -join ' ') | Out-Null
  if ($LASTEXITCODE) { throw "create-gp4 failed" }
  # create-gp4 declares only a fixed set of folders, and PkgTool fails ("Sequence contains no
  # elements") on a file in any other. Add the -Tree files (read in place: orig_path is absolute,
  # nothing is copied) and declare every folder any file sits in.
  $gp4Path = (Resolve-Path pkg.gp4).Path
  [xml]$gp4 = Get-Content $gp4Path
  $filesNode = $gp4.psproject.files
  foreach ($pair in $Tree) {
    $src, $targ = $pair -split '=', 2
    $srcRoot = (Resolve-Path $src).Path.TrimEnd('\')
    Get-ChildItem -Recurse -File $srcRoot | ForEach-Object {
      $rel = $_.FullName.Substring($srcRoot.Length + 1).Replace('\', '/')
      $node = $gp4.CreateElement("file")
      $node.SetAttribute("targ_path", "$targ/$rel")
      $node.SetAttribute("orig_path", $_.FullName)
      [void]$filesNode.AppendChild($node)
    }
  }
  $rootdir = $gp4.psproject.rootdir
  foreach ($f in $filesNode.file) {
    $parts = $f.targ_path -split '/'
    $parent = $rootdir
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
      $existing = $parent.ChildNodes | Where-Object { $_.Name -eq 'dir' -and $_.targ_name -eq $parts[$i] } | Select-Object -First 1
      if (-not $existing) {
        $existing = $gp4.CreateElement("dir")
        $existing.SetAttribute("targ_name", $parts[$i])
        [void]$parent.AppendChild($existing)
      }
      $parent = $existing
    }
  }
  $gp4.Save($gp4Path)
  & $PkgTool pkg_build pkg.gp4 . *> pkg-build.log
  if ($LASTEXITCODE) { Get-Content pkg-build.log | Select-Object -Last 30; throw "pkg_build failed" }
} finally { Pop-Location }

$pkg = Join-Path $Stage "$ContentId.pkg"
if (-not (Test-Path $pkg)) { Get-Content "$Stage\pkg-build.log" | Select-Object -Last 30; throw "no $ContentId.pkg produced" }
Move-Item -Force $pkg (Join-Path $OutDir "$ContentId.pkg")
$out = Get-Item (Join-Path $OutDir "$ContentId.pkg")
"pkg: $($out.FullName) ($([math]::Round($out.Length / 1MB, 1)) MB)"
