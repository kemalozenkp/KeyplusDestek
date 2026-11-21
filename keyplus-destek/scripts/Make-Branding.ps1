param([Parameter(Mandatory = $true)][string]$Source)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$logo = Join-Path $PSScriptRoot '..\assets\logo.png'
foreach ($name in @('logo.png', 'logo_light.png', 'logo_dark.png')) {
  Copy-Item -LiteralPath $logo -Destination (Join-Path $sourcePath "flutter\assets\$name") -Force
}
# The geometry mirrors assets/mark.svg. Render each icon separately at 4x for
# crisp Windows taskbar / tray / Alt-Tab sizes; do not upscale a small bitmap.
$images = @()
foreach ($size in @(16,20,24,32,40,48,64,128,256)) {
  $bitmap = New-Object System.Drawing.Bitmap ($size * 4),($size * 4)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.Clear([System.Drawing.Color]::Transparent)
  $graphics.ScaleTransform(($size * 4 / 256),($size * 4 / 256))
  $shape = New-Object System.Drawing.Drawing2D.GraphicsPath
  $radius = 116
  $shape.AddArc(0,0,$radius,$radius,180,90)
  $shape.AddArc(140,0,$radius,$radius,270,90)
  $shape.AddArc(140,140,$radius,$radius,0,90)
  $shape.AddArc(0,140,$radius,$radius,90,90)
  $shape.CloseFigure()
  $red = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(223,25,42))
  $graphics.FillPath($red,$shape)
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White),23
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  $graphics.DrawLine($pen,76,62,76,194)
  $points = [System.Drawing.PointF[]]@([System.Drawing.PointF]::new(177,62),[System.Drawing.PointF]::new(97,128),[System.Drawing.PointF]::new(177,194))
  $graphics.DrawLines($pen,$points)
  $graphics.FillEllipse([System.Drawing.Brushes]::White,160,45,34,34)
  $graphics.FillEllipse([System.Drawing.Brushes]::White,160,177,34,34)
  $final = New-Object System.Drawing.Bitmap $size,$size
  $resample = [System.Drawing.Graphics]::FromImage($final)
  $resample.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $resample.DrawImage($bitmap,0,0,$size,$size)
  $stream = New-Object System.IO.MemoryStream
  $final.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png)
  $images += ,$stream.ToArray()
  $resample.Dispose(); $final.Dispose(); $stream.Dispose()
  $shape.Dispose(); $red.Dispose(); $pen.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
$sizes = @(16,20,24,32,40,48,64,128,256)
$png = $images[-1]
$iconStream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter $iconStream
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i=0; $i -lt $sizes.Count; $i++) {
  $dimension = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
  $writer.Write([byte]$dimension); $writer.Write([byte]$dimension); $writer.Write([byte]0); $writer.Write([byte]0)
  $writer.Write([uint16]1); $writer.Write([uint16]32)
  $writer.Write([uint32]$images[$i].Length); $writer.Write([uint32]$offset)
  $offset += $images[$i].Length
}
foreach ($entry in $images) { $writer.Write([byte[]]$entry) }
$writer.Flush()
foreach ($relative in @('res\icon.ico','flutter\windows\runner\resources\app_icon.ico','flutter\assets\icon.ico')) {
  [System.IO.File]::WriteAllBytes((Join-Path $sourcePath $relative), $iconStream.ToArray())
}
[System.IO.File]::WriteAllBytes((Join-Path $sourcePath 'flutter\assets\icon.png'), $png)
$writer.Dispose(); $iconStream.Dispose()
Write-Output 'Keyplus adı ve logosuyla Windows varlıkları hazırlandı.'
