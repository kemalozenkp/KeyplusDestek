param(
  [Parameter(Mandatory = $true)][string]$Config,
  [string]$Source = (Join-Path $PSScriptRoot '..\work\rustdesk')
)
$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitProcess) { throw 'Windows x64 geliştirici terminali gereklidir.' }
& node (Join-Path $PSScriptRoot 'doctor.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Derleme araçları eksik. Araçlar otomatik kurulmadı.' }
$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$configPath = (Resolve-Path -LiteralPath $Config).Path
$bridgeFiles = @('src\bridge_generated.rs', 'src\bridge_generated.io.rs', 'flutter\lib\generated_bridge.dart', 'flutter\lib\generated_bridge.freezed.dart')
foreach ($file in $bridgeFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $sourcePath $file))) {
    throw "Sabit kaynak sürümünün CI bridge çıktısı eksik: $file. Yerel codegen otomatik çalıştırılmaz."
  }
}
& node (Join-Path $PSScriptRoot 'prepare.mjs') --source $sourcePath --config $configPath
if ($LASTEXITCODE -ne 0) { throw 'Keyplus kaynak uyarlaması başarısız.' }
Push-Location -LiteralPath $sourcePath
try {
  & python build.py --flutter --portable --skip-portable-pack
  if ($LASTEXITCODE -ne 0) { throw 'Windows derlemesi başarısız.' }
  $executable = Join-Path $sourcePath 'flutter\build\windows\x64\runner\Release\rustdesk.exe'
  if (-not (Test-Path -LiteralPath $executable)) { throw 'Beklenen Windows uygulama çıktısı oluşmadı.' }
  Write-Output "Derleme klasörü: $(Split-Path -Parent $executable)"
  Write-Output 'Bu çıktı tek dosyalı dağıtım değildir; DLL/data klasörleri, ikon, imza ve iki bilgisayar testi ayrıca tamamlanmalıdır.'
} finally {
  Pop-Location
}
