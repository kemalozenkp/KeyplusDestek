param(
    [Parameter(Mandatory=$true)][string]$NewPayloadExecutable,
    [Parameter(Mandatory=$true)][string]$NewPortableExecutable,
    [Parameter(Mandatory=$true)][string]$Report
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Upgrade integration testing is restricted to an ephemeral GitHub Windows runner.'
}
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator runner required.' }
$newExe = (Resolve-Path -LiteralPath $NewPayloadExecutable).Path
$newPortable = (Resolve-Path -LiteralPath $NewPortableExecutable).Path
$installedDir = Join-Path $env:ProgramFiles 'KeyplusDestek'
$installed = Join-Path $installedDir 'KeyplusDestek.exe'
if ((Get-Service -Name KeyplusDestek -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $installedDir)) {
    throw 'Existing installation preserved: a clean ephemeral runner is required.'
}
$testDir = Join-Path $env:RUNNER_TEMP ('keyplus-upgrade-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
$previous = Join-Path $testDir 'previous.exe'
Invoke-WebRequest -UseBasicParsing -Uri 'https://portal.keyplus.com.tr/downloads/keyplus-destek/KeyplusDestek.exe' -OutFile $previous
if ((Get-FileHash -LiteralPath $previous -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'eb42f22bae6b85418a4bae37f1d392cddcf72c7daa10e87e54eaf0b0d9707e07') {
    throw 'Previous release content changed. Upgrade baseline must be reviewed instead of silently substituted.'
}
function Invoke-Native([string]$File, [string[]]$Arguments) {
    $tag = [Guid]::NewGuid().ToString('N')
    $stdout = Join-Path $testDir ($tag + '.out')
    $stderr = Join-Path $testDir ($tag + '.err')
    $process = Start-Process -FilePath $File -ArgumentList $Arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    # Windows PowerShell 5 can lose ExitCode after WaitForExit unless its process
    # handle was opened first. Do not mistake a missing code for application failure.
    $processHandle = $process.Handle
    if (-not $process.WaitForExit(60000)) { throw ('Native operation timed out: '+$Arguments[0]) }
    if ($null -eq $process.ExitCode -or $process.ExitCode -ne 0) { throw ('Native operation failed: '+$Arguments[0]+' (exit '+$process.ExitCode+')') }
    # An update can hand its inherited output handle to a detached child.
    # Read the redirected file with sharing, as the portable smoke test does;
    # actual upgrade completion is still verified by fresh service/payload checks.
    $stream = [IO.File]::Open($stdout,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader = New-Object IO.StreamReader($stream)
    try { return $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
}
function Wait-ForService {
    for ($attempt=0; $attempt -lt 90; $attempt++) {
        $service = Get-Service -Name KeyplusDestek -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running' -and (Test-Path -LiteralPath $installed)) { return }
        Start-Sleep -Seconds 1
    }
    throw 'Installed service did not become ready.'
}
function Read-IdentityFields {
    $roots = @(
        (Join-Path $env:WINDIR 'ServiceProfiles\LocalService\AppData\Roaming\Keyplus Destek\config'),
        (Join-Path $env:WINDIR 'System32\config\systemprofile\AppData\Roaming\Keyplus Destek\config')
    )
    $lines = @()
    foreach ($root in $roots) {
        $path = Join-Path $root 'Keyplus Destek.toml'
        if (Test-Path -LiteralPath $path) {
            $fields = Get-Content -LiteralPath $path | Where-Object { $_ -match '^\s*(id|enc_id|password|salt)\s*=' }
            if ($fields) { $lines += ($path + "`n" + ($fields -join "`n")) }
        }
    }
    # TOML permits both basic (double quoted) and literal (single quoted)
    # strings. Encrypted password storage must be nonempty in either format.
    if (-not $lines.Count -or (($lines -join "`n") -notmatch '(?m)^\s*password\s*=\s*(["''])[^"''\r\n]+\1')) {
        throw 'Persisted identity/password fixture could not be verified.'
    }
    return ($lines -join "`n")
}
$result = [ordered]@{previousRelease='2026.11.20.4'; credentialSnapshot='service-profile-persisted-fields'; previousExtractionLocked=$false; mismatchDetected=$false; nativeUpgrade=$false; normalLaunchUpgrade=$false; installedMainWindow=$false; portableMainWindowAbsent=$false; repeatLaunchPreservedService=$false; serviceCompatible=$false; idPreserved=$false; passwordPreserved=$false; approvalPreserved=$false; windowPolicyPreserved=$false; uninstallAfterTest=$false}
$previousLocks = @()
$failure = $null
$stage = 'install-previous'
try {
    $install = Start-Process -FilePath $previous -ArgumentList @('--silent-install','printer=0') -WindowStyle Hidden -PassThru
    if (-not $install.WaitForExit(60000)) { throw 'Previous release installation timed out.' }
    Wait-ForService
    $stage = 'configure-access-fixture'
    $password = [Guid]::NewGuid().ToString('N')
    $setPassword = Invoke-Native $installed @('--password',$password)
    if ($setPassword -notmatch 'Done!') { throw 'Permanent password fixture failed.' }
    $null = Invoke-Native $installed @('--option','approve-mode','password')
    $null = Invoke-Native $installed @('--option','verification-method','use-permanent-password')
    $null = Invoke-Native $installed @('--option','allow-only-conn-window-open','Y')
    Start-Sleep -Seconds 3
    $idBefore = Invoke-Native $installed @('--get-id')
    if (-not $idBefore) { throw 'Previous identity was not available.' }
    $fieldsBefore = Read-IdentityFields
    $stage = 'detect-service-mismatch'
    $health = (Invoke-Native $newExe @('--keyplus-service-status')) | ConvertFrom-Json
    if ($health.state -ne 'mismatch' -or -not $health.canUpdate) { throw 'Old service + new GUI was not correctly reported as updateable mismatch.' }
    $result.mismatchDetected = $true
    $oldHash = (Get-FileHash -LiteralPath (Join-Path $installedDir 'librustdesk.dll')).Hash
    # Reproduce an older extracted EXE/DLL being held by a running client.
    foreach ($name in @('KeyplusDestek.exe','librustdesk.dll')) {
        $oldExtracted = Join-Path (Join-Path $env:LOCALAPPDATA 'keyplusdestek') $name
        $previousLocks += [IO.File]::Open($oldExtracted,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    }
    $result.previousExtractionLocked = $true
    $stage = 'normal-downloaded-package-launch'
    $downloadCopy = Join-Path $testDir 'KeyplusDestek (2).exe'
    Copy-Item -LiteralPath $newPortable -Destination $downloadCopy
    $null = Start-Process -FilePath $downloadCopy -WindowStyle Hidden -PassThru
    Wait-ForService
    for ($attempt=0; $attempt -lt 90; $attempt++) {
        $health = (Invoke-Native $newExe @('--keyplus-service-status')) | ConvertFrom-Json
        if ($health.state -eq 'compatible') { break }
        Start-Sleep -Seconds 1
    }
    $newHash = (Get-FileHash -LiteralPath (Join-Path $installedDir 'librustdesk.dll')).Hash
    if ($health.state -ne 'compatible' -or $oldHash -eq $newHash) { throw 'Upgraded service payload was not verified.' }
    $result.nativeUpgrade = $true; $result.serviceCompatible = $true
    $result.normalLaunchUpgrade = $true
    for ($attempt=0; $attempt -lt 60; $attempt++) {
        $windows = @(Get-Process -Name KeyplusDestek -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
        if ($windows | Where-Object { $_.Path -eq $installed }) { break }
        Start-Sleep -Seconds 1
    }
    if (-not ($windows | Where-Object { $_.Path -eq $installed })) { throw 'Normal package launch did not open the installed main window.' }
    if ($windows | Where-Object { $_.Path -ne $installed }) { throw 'A portable main window remained after handoff.' }
    $result.installedMainWindow = $true; $result.portableMainWindowAbsent = $true
    $stage = 'repeat-downloaded-package-launch'
    $servicePidBefore = (Get-CimInstance Win32_Service -Filter "Name='KeyplusDestek'").ProcessId
    $installedTimeBefore = (Get-Item -LiteralPath $installed).LastWriteTimeUtc
    $null = Start-Process -FilePath $downloadCopy -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 5
    if ((Get-CimInstance Win32_Service -Filter "Name='KeyplusDestek'").ProcessId -ne $servicePidBefore -or (Get-Item -LiteralPath $installed).LastWriteTimeUtc -ne $installedTimeBefore) { throw 'Reopening an identical package reinstalled or restarted the service.' }
    $result.repeatLaunchPreservedService = $true
    $stage = 'verify-preserved-access'
    if ((Invoke-Native $installed @('--get-id')) -ne $idBefore) { throw 'Device ID changed during upgrade.' }
    $result.idPreserved = $true
    if ((Read-IdentityFields) -ne $fieldsBefore) { throw 'Persisted ID/password fields changed during upgrade.' }
    $result.passwordPreserved = $true
    if ((Invoke-Native $installed @('--option','approve-mode')) -ne 'password' -or (Invoke-Native $installed @('--option','verification-method')) -ne 'use-permanent-password') { throw 'Approval method changed.' }
    $result.approvalPreserved = $true
    if ((Invoke-Native $installed @('--option','allow-only-conn-window-open')) -ne 'Y') { throw 'Window policy changed.' }
    $result.windowPolicyPreserved = $true
    $stage = 'capture-native-ui'
    # Capture only the ephemeral fixture. Images never contain a customer session
    # or the generated test password, and are not called a passed visual review.
    foreach ($view in @('simple','operator')) {
        foreach ($theme in @('light','dark')) {
            & (Join-Path $PSScriptRoot 'Test-WindowsUI.ps1') -Executable $newExe -View $view -Theme $theme -Output (Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($Report))) 'native-ui')
        }
    }
} catch {
    $failure = $_
    Write-Warning ('Upgrade verification failed at '+$stage+': '+$_.Exception.Message)
} finally {
    foreach ($lock in $previousLocks) { $lock.Dispose() }
    try {
        if (Test-Path -LiteralPath $installed) {
            # Native uninstall intentionally taskkills KeyplusDestek.exe, including
            # its caller. Verify service/files below instead of requiring exit 0.
            # Cleanup must never replace the original verification failure.
            $cleanup = Start-Process -FilePath $newExe -ArgumentList '--uninstall' -WindowStyle Hidden -PassThru
            if (-not $cleanup.WaitForExit(60000)) { throw 'Upgrade cleanup launcher timed out.' }
        }
    } catch {
        Write-Warning ('Upgrade cleanup failed: '+$_.Exception.Message)
        if ($null -eq $failure) { $failure = $_ }
    }
}
for ($attempt=0; $attempt -lt 60; $attempt++) {
    if (-not (Get-Service -Name KeyplusDestek -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $installed)) { $result.uninstallAfterTest=$true; break }
    Start-Sleep -Seconds 1
}
$result['completedStage'] = $stage
$result['testedAt'] = (Get-Date).ToUniversalTime().ToString('o')
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Report), ($result | ConvertTo-Json) + "`n", (New-Object Text.UTF8Encoding($false)))
Write-Output ($result | ConvertTo-Json)
if ($null -ne $failure) { throw $failure }
if (-not $result.uninstallAfterTest) { throw 'Upgrade test installation was not removed.' }
