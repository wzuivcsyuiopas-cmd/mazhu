# SPDX-License-Identifier: GPL-3.0-only
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
[xml]$project = Get-Content -LiteralPath (Join-Path $taskRoot 'windows/Mazhu/Mazhu.csproj') -Raw
$taskVersion = [string]$project.Project.PropertyGroup.Version
if ($taskVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid app version.' }
& (Join-Path $taskRoot 'windows/build.ps1') -Architecture x64 -Check
$payload = Join-Path $taskRoot 'windows/dist/x64'
foreach ($required in @('Mazhu.exe', 'Mazhu.dll', 'Mazhu.pri', 'MainWindow.xbf', 'Assets/AppIcon.ico')) {
    if (-not (Test-Path -LiteralPath (Join-Path $payload $required))) { throw "Missing runtime file: $required" }
}
$releaseDirectory = Join-Path $taskRoot 'release'
New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
$compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
if (-not $compiler) { $compiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe' }
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Inno Setup 6 is required to package the installer.' }
& $compiler "/DAppVersion=$taskVersion" (Join-Path $taskRoot 'packaging/windows.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$installer = Join-Path $releaseDirectory "Mazhu-$taskVersion-windows-x64.exe"
if (-not (Test-Path -LiteralPath $installer)) { throw 'Installer output is missing.' }
$header = [IO.File]::OpenRead($installer)
try { if ($header.ReadByte() -ne 0x4D -or $header.ReadByte() -ne 0x5A) { throw 'Installer is not a Windows executable.' } }
finally { $header.Dispose() }
Get-FileHash -LiteralPath $installer -Algorithm SHA256
