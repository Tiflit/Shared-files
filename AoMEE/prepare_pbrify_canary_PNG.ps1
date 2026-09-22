$ErrorActionPreference = 'Stop'
$Root='D:\AI_upscaling\AoMEE'
$Canary=Join-Path $Root 'tests\production_canary'
$Source=Join-Path $Canary 'original'
$PngInput=Join-Path $Canary 'png_input'
$Graph=Join-Path $Root 'AoMEE_PBRifyV4_production_canary.chn'
$NewGraph=Join-Path $Root 'AoMEE_PBRifyV4_production_canary_PNG.chn'
$Converter=Join-Path $Root 'convert_aom_tga_to_png.py'
foreach($p in @($Source,$Graph,$Converter)){ if(-not(Test-Path -LiteralPath $p)){throw "Missing required path: $p"} }
Remove-Item -LiteralPath $PngInput -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $PngInput | Out-Null
& python $Converter $Source $PngInput
if($LASTEXITCODE -ne 0){throw "TGA -> PNG conversion failed."}
$json=Get-Content -LiteralPath $Graph -Raw -Encoding UTF8 | ConvertFrom-Json
$loads=@($json.content.nodes|Where-Object{$_.data.schemaId -eq 'chainner:image:load_images'})
$saves=@($json.content.nodes|Where-Object{$_.data.schemaId -eq 'chainner:image:save'})
if($loads.Count -ne 1){throw "Expected exactly one Load Images node; found $($loads.Count)."}
if($saves.Count -ne 1){throw "Expected exactly one Save Image node; found $($saves.Count)."}
$loads[0].data.inputData.'0'=$PngInput
$saves[0].data.inputData.'1000'=0
$json.timestamp=(Get-Date).ToUniversalTime().ToString("o")
$json|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $NewGraph -Encoding UTF8
Write-Host ''
Write-Host 'PNG canary staging: PASS' -ForegroundColor Green
Write-Host "PNG input : $PngInput"
Write-Host "Graph     : $NewGraph"
