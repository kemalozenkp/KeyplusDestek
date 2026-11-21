param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$Output,
    [ValidateSet('simple','operator')][string]$View='simple',
    [ValidateSet('light','dark')][string]$Theme='light'
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Native UI capture is restricted to an ephemeral GitHub Windows runner.'
}
$exe = (Resolve-Path -LiteralPath $Executable).Path
$installed = Join-Path $env:ProgramFiles 'KeyplusDestek\KeyplusDestek.exe'
if (-not (Test-Path -LiteralPath $installed)) { throw 'The isolated upgrade fixture must already be installed.' }
if ((Get-FileHash -LiteralPath $exe).Hash -ne (Get-FileHash -LiteralPath $installed).Hash) {
    throw 'UI capture requires the verified new installation.'
}
$outputDir = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Add-Type -AssemblyName System.Drawing
if (-not ('KeyplusUiCapture' -as [type])) { Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class KeyplusUiCapture {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    public delegate bool WindowVisitor(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] public static extern bool EnumWindows(WindowVisitor visitor, IntPtr data);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, System.Text.StringBuilder name, int size);
    public static IntPtr FindFlutterWindow(uint pid) {
        IntPtr found=IntPtr.Zero;
        EnumWindows((window,data) => {
            uint owner; GetWindowThreadProcessId(window,out owner);
            if(owner==pid) {
                var name=new System.Text.StringBuilder(128); GetClassName(window,name,128);
                if(name.ToString()=="FLUTTER_RUNNER_WIN32_WINDOW") { found=window; return false; }
            }
            return true;
        },IntPtr.Zero);
        return found;
    }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);
}
'@
}
$record = [ordered]@{requestedView=$View;requestedTheme=$Theme;syntheticOfflinePeers=2;nativeWindowObserved=$false; captured=$false; visualReview=$false; screenReaderVerified=$false; realDpiVerified=$false}
$configDir = Join-Path $env:APPDATA 'Keyplus Destek\config'
$localConfig = Join-Path $configDir 'Keyplus Destek_local.toml'
$original = if (Test-Path -LiteralPath $localConfig) { [IO.File]::ReadAllBytes($localConfig) } else { $null }
$started = $null
$fixtureFiles = @()
function Stop-FixtureWindows {
    Get-Process -Name KeyplusDestek -ErrorAction SilentlyContinue | Where-Object {
        ($_.Path -eq $exe -or $_.Path -eq $installed) -and [KeyplusUiCapture]::FindFlutterWindow($_.Id) -ne [IntPtr]::Zero
    } | ForEach-Object { Stop-Process -Id $_.Id -Force }
}
try {
    Stop-FixtureWindows
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    $peersDir = Join-Path $configDir 'peers'
    New-Item -ItemType Directory -Path $peersDir -Force | Out-Null
    $fixtureIds = @()
    foreach ($label in @('A','B')) {
        $id = 'kp-ui-fixture-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
        $peerFile = Join-Path $peersDir ($id+'.toml')
        if (Test-Path -LiteralPath $peerFile) { throw 'Fixture collision: existing peer preserved.' }
        $peer = "[info]`nusername = `"UI Fixture`"`nhostname = `"CI-TEST-$label`"`nplatform = `"Windows`"`n[options]`nalias = `"CI test workstation $label`"`n"
        [IO.File]::WriteAllText($peerFile,$peer,(New-Object Text.UTF8Encoding($false)))
        $fixtureFiles += $peerFile; $fixtureIds += $id
    }
    # LocalConfig has serde defaults for every field. Only this disposable UI
    # preference file is replaced; device/password/access config is untouched.
    $preferences = "fav = [`"$($fixtureIds[0])`"]`n[options]`nkeyplus-home-view = `"$View`"`ntheme = `"$Theme`"`n"
    [IO.File]::WriteAllText($localConfig,$preferences,(New-Object Text.UTF8Encoding($false)))
    $started = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
    $window = $null
    for ($attempt=0; $attempt -lt 45; $attempt++) {
        $candidates = @(Get-Process -Name KeyplusDestek -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -eq $exe -or $_.Path -eq $installed
        })
        foreach ($candidate in $candidates) {
            $handle = [KeyplusUiCapture]::FindFlutterWindow($candidate.Id)
            if ($handle -ne [IntPtr]::Zero) { $window=@{Handle=$handle}; break }
        }
        if ($window) { break }
        Start-Sleep -Seconds 1
    }
    if ($window) {
        $record.nativeWindowObserved = $true
        $handle = $window.Handle
        $null = [KeyplusUiCapture]::ShowWindow($handle,9)
        $targetWidth = if ($View -eq 'operator') { 1280 } else { 1000 }
        $null = [KeyplusUiCapture]::SetWindowPos($handle,[IntPtr]::Zero,30,30,$targetWidth,720,0x0040)
        $null = [KeyplusUiCapture]::SetForegroundWindow($handle)
        Start-Sleep -Seconds 4
        $rect = New-Object KeyplusUiCapture+Rect
        if (-not [KeyplusUiCapture]::GetWindowRect($handle,[ref]$rect)) { throw 'Native window bounds unavailable.' }
        $width = $rect.Right-$rect.Left; $height = $rect.Bottom-$rect.Top
        if ($width -lt 200 -or $height -lt 200 -or $width -gt 4096 -or $height -gt 4096) { throw 'Unexpected native window bounds.' }
        $bitmap = New-Object Drawing.Bitmap $width,$height
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $dc = $graphics.GetHdc()
            try { $printed = [KeyplusUiCapture]::PrintWindow($handle,$dc,2) } finally { $graphics.ReleaseHdc($dc) }
            if (-not $printed) {
                $graphics.CopyFromScreen($rect.Left,$rect.Top,0,0,[Drawing.Size]::new($width,$height))
            }
            $colors = New-Object 'Collections.Generic.HashSet[int]'
            for ($x=5; $x -lt $width; $x+=17) { for ($y=5; $y -lt $height; $y+=17) { $null=$colors.Add($bitmap.GetPixel($x,$y).ToArgb()) } }
            if ($colors.Count -gt 16) {
                $bitmap.Save((Join-Path $outputDir ("native-$View-$Theme.png")),[Drawing.Imaging.ImageFormat]::Png)
                $record.captured = $true
            }
            $record['width']=$width; $record['height']=$height; $record['sampleColors']=$colors.Count
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
} finally {
    if ($started -and -not $started.HasExited) { Stop-Process -Id $started.Id -Force }
    Stop-FixtureWindows
    if ($null -ne $original) { [IO.File]::WriteAllBytes($localConfig,$original) }
    elseif (Test-Path -LiteralPath $localConfig) { Remove-Item -LiteralPath $localConfig -Force }
    foreach ($peerFile in $fixtureFiles) { if (Test-Path -LiteralPath $peerFile) { Remove-Item -LiteralPath $peerFile -Force } }
}
$record['testedAt']=(Get-Date).ToUniversalTime().ToString('o')
[IO.File]::WriteAllText((Join-Path $outputDir ("native-$View-$Theme.json")),($record | ConvertTo-Json)+"`n",(New-Object Text.UTF8Encoding($false)))
Write-Output ($record | ConvertTo-Json)
