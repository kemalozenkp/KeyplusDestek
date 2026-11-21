param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Payload,
    [Parameter(Mandatory=$true)][string]$BuildMetadata,
    [Parameter(Mandatory=$true)][string]$Config,
    [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath $Source).Path
$payloadRoot = (Resolve-Path -LiteralPath $Payload).Path
$configFile = (Resolve-Path -LiteralPath $Config).Path
$kitRoot = Split-Path -Parent $PSScriptRoot
$outputRoot = [IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $outputRoot) { throw 'Output already exists; existing artifacts preserved' }
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
Copy-Item -LiteralPath $configFile -Destination (Join-Path $payloadRoot 'data/keyplus-server.json')
Rename-Item -LiteralPath (Join-Path $payloadRoot 'rustdesk.exe') -NewName 'KeyplusDestek.exe'
Copy-Item -LiteralPath (Join-Path $kitRoot 'LICENSE.txt') -Destination (Join-Path $payloadRoot 'KEYPLUS-LICENSE.txt')
$guide = @'
Keyplus Destek - Windows 64 bit pilot

ERP hesabi veya ERP sunucusuna baglanti gerektirmez.
Kurulum varsa yeni paket mevcut kurulumu Windows yonetici izniyle gunceller
ve kurulu uygulamadan devam eder. Ayni veya daha yeni surum kuruluysa
yeniden kurulum yapmadan kurulu uygulama acilir; kimlik ve parola korunur.
Baslangic modu Hizli Destek: musteri baglantiyi kabul eder.
Kalici erisim icin yetkili kisi uygulamanin Kurulum secenegiyle Windows
hizmetini bir kez kurar; Guvenlik bolumunde cihaza ozel kalici parola belirler,
kabul yontemini parola yapar ve yalniz pencere acikken baglanti kisitini kapatir.
Sonraki baglantilarda bilgisayar kimligi ve bu cihaz parolasi kullanilir.
Ortak parola yoktur. Parola indirme paketine veya kaynak koda yazilmaz.
Erisim Guvenlik ekranindan kapatilabilir; hizmet kaldirilabilir.

Bu pilot paket Authenticode ile imzalanmamistir. Sanal monitor, gizlilik modu
ve uzaktan yazici suruculeri bu pakete dahil degildir.
Iki ayri Windows cihazinda farkli aglar, UAC ve yeniden baslama testi gerekir.

AGPL-3.0 lisansi ve RustDesk telif bildirimleri korunmustur.
Tam kaynak: https://portal.keyplus.com.tr/downloads/keyplus-destek/KeyplusDestek-source.tar.gz
SHA-256: https://portal.keyplus.com.tr/downloads/keyplus-destek/SHA256SUMS.txt
'@
[IO.File]::WriteAllText((Join-Path $payloadRoot 'KEYPLUS-OKU.txt'), $guide, $utf8)
$exe = Join-Path $payloadRoot 'KeyplusDestek.exe'
$version = (& $exe --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $version -ne '1.5.3') { throw "Unexpected native executable version: '$version'" }
$packer = Join-Path $sourceRoot 'libs/portable'
# Leave a previous running portable payload intact while preparing this build.
$portableMain = Join-Path $packer 'src/main.rs'
$portableText = [IO.File]::ReadAllText($portableMain)
$cacheAnchor = 'fn is_timestamp_matches(dir: &Path, ts: &mut u64) -> bool {'
$directoryAnchor = 'dir.join(app_dir_name(&reader.exe))'
foreach ($anchor in @($cacheAnchor,$directoryAnchor)) {
    if ([regex]::Matches($portableText,[regex]::Escape($anchor)).Count -ne 1) { throw 'Unexpected portable cache source; files preserved.' }
}
$cacheHelper = @'
fn keyplus_cache_dir(base: &Path, exe: &str) -> PathBuf {
    let root = base.join(app_dir_name(exe));
    #[cfg(windows)]
    if app_dir_name(exe) == "keyplusdestek" {
        return root.join(format!("build-{:x}", md5::compute(APP_METADATA)));
    }
    root
}

'@
$portableText = $portableText.Replace($cacheAnchor,$cacheHelper+"`n"+$cacheAnchor).Replace($directoryAnchor,'keyplus_cache_dir(&dir, &reader.exe)')
[IO.File]::WriteAllText($portableMain,$portableText,$utf8)
# Only the packer's metadata is changed; protocol version remains upstream's.
$cargoFile = Join-Path $packer 'Cargo.toml'
$cargo = [IO.File]::ReadAllText($cargoFile)
$cargo = $cargo.Replace('ProductName = "RustDesk"', 'ProductName = "Keyplus Destek"').Replace('OriginalFilename = "rustdesk.exe"', 'OriginalFilename = "KeyplusDestek.exe"').Replace('FileDescription = "RustDesk Remote Desktop"', 'FileDescription = "Keyplus Destek"')
[IO.File]::WriteAllText($cargoFile, $cargo, $utf8)
$manifestFile = Join-Path $sourceRoot 'res/manifest.xml'
[IO.File]::WriteAllLines($manifestFile, ([IO.File]::ReadAllLines($manifestFile) | Where-Object { $_ -notmatch 'dpiAware' }), $utf8)
Push-Location $packer
try {
    python -m pip install -r requirements.txt
    if ($LASTEXITCODE -ne 0) { throw 'Packer dependencies failed' }
    python generate.py -f $payloadRoot -o . -e $exe -l 9
    if ($LASTEXITCODE -ne 0) { throw 'Portable packer build failed' }
} finally { Pop-Location }
$packed = Join-Path $sourceRoot 'target/release/rustdesk-portable-packer.exe'
Copy-Item -LiteralPath $packed -Destination (Join-Path $outputRoot 'KeyplusDestek.exe')
# The portable runner forwards arguments to the real executable after extraction.
$stdout = Join-Path $outputRoot 'portable-version.stdout.txt'
$stderr = Join-Path $outputRoot 'portable-version.stderr.txt'
$process = Start-Process -FilePath (Join-Path $outputRoot 'KeyplusDestek.exe') -ArgumentList '--version' -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Portable extraction timed out' }
$reported = ''
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    $stream = [IO.File]::Open($stdout, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = New-Object IO.StreamReader($stream, $utf8)
    try { $reported = $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
    if ($reported -match '(?m)^1\.5\.3\s*$') { break }
    Start-Sleep -Milliseconds 500
}
if ($reported -notmatch '(?m)^1\.5\.3\s*$') { throw "Portable version check failed: $reported" }
$cacheDigest = [Security.Cryptography.MD5]::Create()
try { $cacheTag = [BitConverter]::ToString($cacheDigest.ComputeHash([IO.File]::ReadAllBytes((Join-Path $packer 'app_metadata.toml')))).Replace('-','').ToLowerInvariant() }
finally { $cacheDigest.Dispose() }
$extract = Join-Path (Join-Path $env:LOCALAPPDATA 'keyplusdestek') ('build-'+$cacheTag)
$actualConfig = Join-Path $extract 'data/keyplus-server.json'
if (-not (Test-Path -LiteralPath $actualConfig)) { throw 'Runtime configuration missing after extraction' }
if ((Get-FileHash $actualConfig).Hash -ne (Get-FileHash $configFile).Hash) { throw 'Extracted server configuration mismatch' }
& (Join-Path $PSScriptRoot 'Test-WindowsInstall.ps1') -Executable (Join-Path $outputRoot 'KeyplusDestek.exe') -ExpectedConfig $configFile -Report (Join-Path $outputRoot 'windows-install-test.json')
& (Join-Path $PSScriptRoot 'Test-WindowsUpgrade.ps1') -NewPayloadExecutable $exe -NewPortableExecutable (Join-Path $outputRoot 'KeyplusDestek.exe') -Report (Join-Path $outputRoot 'windows-upgrade-test.json')
$build = Get-Content -LiteralPath $BuildMetadata -Raw | ConvertFrom-Json
$signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $outputRoot 'KeyplusDestek.exe')
$record = [ordered]@{ nativeBuild=$env:BUILD_RUN; nativeSource=$build.source; packageSource=$env:PACKAGE_SHA; upstream=$build.upstream; version=$version; keyplusRelease='2026.11.21.1'; technicalAppName='KeyplusDestek'; platform='windows-x64'; authenticode=$signature.Status.ToString(); serverHost='31.210.154.245'; serverConfigSHA256=(Get-FileHash $configFile).Hash.ToLowerInvariant(); versionSmokeTest=$true; portableExtractionTest=$true; windowsInstallationTest=$true; windowsUninstallationTest=$true; windowsUpgradeTest=$true; windowsInstalledHandoffTest=$true; twoDeviceSessionTest=$false; brand=@{primary='#DF192A';navy='#102B3B';surface='#F2F5F5'} }
[IO.File]::WriteAllText((Join-Path $outputRoot 'release.json'), ($record | ConvertTo-Json) + "`n", $utf8)
Copy-Item -LiteralPath (Join-Path $payloadRoot 'KEYPLUS-OKU.txt') -Destination $outputRoot
# Include the exact main native source AND the actual packer/config/build scripts.
Copy-Item -LiteralPath $kitRoot -Destination (Join-Path $sourceRoot 'keyplus-distribution-kit') -Recurse
Copy-Item -LiteralPath (Join-Path $outputRoot 'release.json') -Destination (Join-Path $sourceRoot 'keyplus-distribution-kit/release.json')
$workflowFolder = Join-Path $sourceRoot 'keyplus-distribution-kit/build-workflows'
New-Item -ItemType Directory -Path $workflowFolder | Out-Null
$repository = Split-Path -Parent $kitRoot
foreach ($workflow in @('keyplus-destek-windows.yml','keyplus-destek-package.yml')) {
    Copy-Item -LiteralPath (Join-Path $repository ".github/workflows/$workflow") -Destination $workflowFolder
}
tar --exclude='./.git' --exclude='*/.git' --exclude='./target' --exclude='./libs/portable/data.bin' --exclude='./engine' --exclude='./engine.zip' --exclude='./flutter/build' --exclude='./flutter/.dart_tool' --exclude='*/ephemeral' -czf (Join-Path $outputRoot 'KeyplusDestek-source.tar.gz') -C $sourceRoot .
if ($LASTEXITCODE -ne 0) { throw 'Distribution source archive failed' }
$checksums = @('KeyplusDestek.exe','KeyplusDestek-source.tar.gz','release.json','KEYPLUS-OKU.txt','windows-install-test.json','windows-upgrade-test.json') | ForEach-Object {
    $hash = Get-FileHash -LiteralPath (Join-Path $outputRoot $_) -Algorithm SHA256
    "$($hash.Hash.ToLowerInvariant())  $_"
}
[IO.File]::WriteAllText((Join-Path $outputRoot 'SHA256SUMS.txt'), ($checksums -join "`n") + "`n", $utf8)
Write-Output ($record | ConvertTo-Json)
