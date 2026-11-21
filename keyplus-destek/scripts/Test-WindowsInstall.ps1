param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$ExpectedConfig,
    [Parameter(Mandatory=$true)][string]$Report
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'This integration test installs software only on an ephemeral GitHub Windows runner.'
}
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'The isolated Windows test requires an administrator runner.'
}
$exe = (Resolve-Path -LiteralPath $Executable).Path
$config = (Resolve-Path -LiteralPath $ExpectedConfig).Path
$installed = Join-Path $env:ProgramFiles 'KeyplusDestek\KeyplusDestek.exe'
if ((Get-Service -Name KeyplusDestek -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath (Split-Path -Parent $installed))) {
    throw 'An existing installation was preserved; this test requires a clean runner.'
}
$installProcess = Start-Process -FilePath $exe -ArgumentList @('--silent-install','printer=0') -WindowStyle Hidden -PassThru
if (-not $installProcess.WaitForExit(30000)) { throw 'Portable installer did not exit within 30 seconds.' }
$ready = $false
for ($attempt = 0; $attempt -lt 90; $attempt++) {
    $service = Get-Service -Name KeyplusDestek -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running' -and (Test-Path -LiteralPath $installed)) { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) { throw 'The real Windows installer did not create a running KeyplusDestek service.' }
$serviceInfo = Get-CimInstance Win32_Service -Filter "Name='KeyplusDestek'"
if ($serviceInfo.StartMode -ne 'Auto' -or $serviceInfo.PathName -notmatch 'KeyplusDestek\.exe') {
    throw 'The Windows service has an unexpected executable or startup mode.'
}
$installedConfig = Join-Path (Split-Path -Parent $installed) 'data\keyplus-server.json'
if ((Get-FileHash -LiteralPath $installedConfig).Hash -ne (Get-FileHash -LiteralPath $config).Hash) {
    throw 'The Windows installer did not preserve the pinned server configuration.'
}
Start-Sleep -Seconds 3
if ((Get-Service -Name KeyplusDestek).Status -ne 'Running') { throw 'Installed service stopped after startup.' }
$record = [ordered]@{
    technicalAppName='KeyplusDestek'; installation=$true; serviceRunning=$true;
    serviceAutoStart=$true; installedServerConfigVerified=$true; uninstallation=$false;
    runnerOs=$env:ImageOS; testedAt=(Get-Date).ToUniversalTime().ToString('o')
}
# Exercise the same native uninstall path that customers receive.
$uninstallProcess = Start-Process -FilePath $exe -ArgumentList '--uninstall' -WindowStyle Hidden -PassThru
if (-not $uninstallProcess.WaitForExit(30000)) { throw 'Portable uninstaller did not exit within 30 seconds.' }
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    if (-not (Get-Service -Name KeyplusDestek -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $installed)) {
        $record.uninstallation = $true
        break
    }
    Start-Sleep -Seconds 1
}
if (-not $record.uninstallation) { throw 'The native Windows uninstaller did not remove its service and application.' }
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Report), ($record | ConvertTo-Json) + "`n", $utf8)
Write-Output ($record | ConvertTo-Json)
