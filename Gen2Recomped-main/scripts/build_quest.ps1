<#
.SYNOPSIS
  Build the Quest sideload APK.

.DESCRIPTION
  Runs scripts/build_android.ps1, then checks the APK for the pieces a
  Quest 3 needs: arm64 liblove, the Khronos OpenXR loader, and the
  com.oculus.intent.category.VR launch category. The checked APK is
  copied to dist/quest/Gen2Recomped-quest.apk.

  This is the same embed package as the phone build. Quest developer
  mode and a USB/wireless adb connection install it. A phone without an
  OpenXR runtime still installs; the VR row fails closed there.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/build_quest.ps1
  powershell -ExecutionPolicy Bypass -File scripts/build_quest.ps1 -Install
#>
[CmdletBinding()]
param(
  [string]$Version,
  [switch]$Install,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

function Say  { param($m) Write-Host "==> $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "warn: $m" -ForegroundColor Yellow }
function Fail { param($m) Write-Host "error: $m" -ForegroundColor Red; exit 1 }

$Root = Split-Path -Parent $PSScriptRoot
$Builder = Join-Path $PSScriptRoot 'build_android.ps1'
$DistDebug = Join-Path $Root 'dist\android\debug'
$QuestDir = Join-Path $Root 'dist\quest'
$QuestApk = Join-Path $QuestDir 'Gen2Recomped-quest.apk'

if (-not $SkipBuild) {
  if (-not (Test-Path $Builder)) { Fail "missing $Builder" }
  $args = @('-ExecutionPolicy', 'Bypass', '-File', $Builder)
  if ($Version) { $args += @('-Version', $Version) }
  Say 'building the embed APK'
  & powershell @args
  if ($LASTEXITCODE -ne 0) { Fail "build_android.ps1 failed ($LASTEXITCODE)" }
}

$built = Get-ChildItem $DistDebug -Filter *.apk -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if (-not $built) {
  Fail "no APK under $DistDebug. Run without -SkipBuild."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($built.FullName)
try {
  $names = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
  foreach ($need in @(
      'lib/arm64-v8a/liblove.so',
      'lib/arm64-v8a/libopenxr_loader.so')) {
    if ($names -notcontains $need) {
      Fail "APK is missing $need ($($built.Name)). Quest 3 cannot open a headset session without it."
    }
  }
  $man = $zip.GetEntry('AndroidManifest.xml')
  if (-not $man) { Fail 'APK has no AndroidManifest.xml' }
  $stream = $man.Open()
  try {
    $buf = New-Object byte[] $man.Length
    $read = 0
    while ($read -lt $buf.Length) {
      $n = $stream.Read($buf, $read, $buf.Length - $read)
      if ($n -le 0) { break }
      $read += $n
    }
  } finally {
    $stream.Dispose()
  }
  $pool = [System.Text.Encoding]::Unicode.GetString($buf)
  if ($pool -notlike '*com.oculus.intent.category.VR*') {
    Fail 'APK manifest has no com.oculus.intent.category.VR. Quest will launch it as a flat phone app.'
  }
} finally {
  $zip.Dispose()
}

New-Item -ItemType Directory -Path $QuestDir -Force | Out-Null
Copy-Item $built.FullName $QuestApk -Force
Say "Quest APK -> $QuestApk"
'    {0}  {1:N1} MB' -f (Split-Path $QuestApk -Leaf), ((Get-Item $QuestApk).Length / 1MB)
Say 'arm64 liblove, OpenXR loader, and the Quest VR category are in the package'

if ($Install) {
  $sdk = $env:ANDROID_SDK_ROOT
  if (-not $sdk) { $sdk = $env:ANDROID_HOME }
  if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
  $adb = Join-Path $sdk 'platform-tools\adb.exe'
  if (-not (Test-Path $adb)) {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { $adb = $cmd.Source }
  }
  if (-not (Test-Path $adb)) {
    Fail "adb not found. Install platform-tools or put adb on PATH, then:`n  adb install -r -d `"$QuestApk`""
  }
  Say 'installing on the connected headset (Quest developer mode, USB or wireless adb)'
  & $adb install -r -d $QuestApk
  if ($LASTEXITCODE -ne 0) { Fail "adb install failed ($LASTEXITCODE)" }
  Say 'installed com.underdecodedhd.gen2recomp'
} else {
  Say 'sideload, with the Quest in developer mode:'
  Say "  adb install -r -d `"$QuestApk`""
  Say 'or rerun this script with -Install while the headset is connected'
}
