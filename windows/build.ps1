param(
    [ValidateSet('x64', 'ARM64')][string]$Architecture = 'x64',
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'WinUI 3 必须使用 Windows 构建。请使用 PowerShell 7。' }
$project = Join-Path $PSScriptRoot 'Mazhu/Mazhu.csproj'
$destination = Join-Path $PSScriptRoot "dist/$Architecture"
$runtime = if ($Architecture -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
dotnet publish $project -c Release -p:Platform=$Architecture -r $runtime -o $destination
if ($LASTEXITCODE -ne 0) { throw 'Windows 构建失败。' }
if ($Check) {
    if ($Architecture -ne 'x64' -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw '自动渲染检查当前需要 x64 Windows。' }
    $process = Start-Process -FilePath (Join-Path $destination 'Mazhu.exe') -ArgumentList '--render-checks' -PassThru
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw '渲染检查超时。' }
    if ($process.ExitCode -ne 0) { throw "渲染检查失败，退出码 $($process.ExitCode)。请查看 render-checks-failure.txt。" }
}
