$ErrorActionPreference = 'Stop'
$Root='D:\AI_upscaling\AoMEE'
$Source=Join-Path $Root 'input\production_source'
$PngInput=Join-Path $Root 'input\production_source_png'
$Converter=Join-Path $Root 'convert_aom_tga_to_png.py'
foreach($p in @($Source,$Converter)){if(-not(Test-Path -LiteralPath $p)){throw "Missing required path: $p"}}
Remove-Item -LiteralPath $PngInput -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $PngInput|Out-Null
& python $Converter $Source $PngInput
if($LASTEXITCODE -ne 0){throw "Production TGA -> PNG conversion failed."}
$count=@(Get-ChildItem -LiteralPath $PngInput -Recurse -File -Filter *.png).Count
if($count -ne 7487){throw "Expected 7487 PNGs, found $count"}
Write-Host "Production PNG staging: PASS ($count files)" -ForegroundColor Green
