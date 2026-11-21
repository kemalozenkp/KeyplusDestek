param([string]$Destination = (Join-Path $PSScriptRoot '..\work\rustdesk'))
$ErrorActionPreference = 'Stop'
$project = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\project.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (Test-Path -LiteralPath $Destination) { throw 'Hedef zaten var; kaynak korunuyor. Yeni bir klasör seçin.' }
& git clone --depth 1 --branch $project.upstream.tag --recurse-submodules $project.upstream.repository $Destination
if ($LASTEXITCODE -ne 0) { throw 'Kaynak indirme başarısız.' }
$commit = & git -C $Destination rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $commit -ne $project.upstream.commit) { throw 'İndirilen kaynak sabit commit ile eşleşmiyor.' }
Write-Output "Kaynak indirildi: $Destination"
