$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE'
$VisualRoot = Join-Path $Root 'tests\visual_model_comparison'
$FinalRoot = Join-Path $Root 'tests\final_model_comparison'
$UltraModel = 'D:\AI_upscaling\AoMEE\models\PBRify\4x-UltraSharpV2.pth'

$ManifestSource = Join-Path $VisualRoot 'visual_model_comparison_manifest.csv'
$OriginalSource = Join-Path $VisualRoot 'original'
$PBRifySource = Join-Path $Root 'tests\pbrify_model_comparison\PBRify_V4'

if (-not (Test-Path -LiteralPath $UltraModel)) { throw "UltraSharp V2 model not found: $UltraModel" }
if (-not (Test-Path -LiteralPath $ManifestSource)) { throw "80-texture manifest not found: $ManifestSource" }
if (-not (Test-Path -LiteralPath $OriginalSource)) { throw "Original benchmark folder not found: $OriginalSource" }

$dirs = @(
    $FinalRoot,
    (Join-Path $FinalRoot 'original'),
    (Join-Path $FinalRoot 'PBRify_V4'),
    (Join-Path $FinalRoot 'UltraSharp_V2'),
    (Join-Path $FinalRoot 'visual_review'),
    (Join-Path $FinalRoot 'visual_review\individual'),
    (Join-Path $FinalRoot 'visual_review\overview')
)
foreach ($d in $dirs) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

Copy-Item -LiteralPath $ManifestSource -Destination (Join-Path $FinalRoot 'final_model_comparison_manifest.csv') -Force
$manifest = @(Import-Csv -LiteralPath $ManifestSource)

$copiedOriginal = 0
foreach ($row in $manifest) {
    $rel = [string]$row.Path
    $src = Join-Path $OriginalSource $rel
    $dst = Join-Path (Join-Path $FinalRoot 'original') $rel
    if (-not (Test-Path -LiteralPath $src)) { throw "Missing original benchmark texture: $rel" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Path $dst -Parent) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $copiedOriginal++
}

$pbrifyCopied = 0
$pbrifyMissing = @()
foreach ($row in $manifest) {
    $rel = [string]$row.Path
    $src = Join-Path $PBRifySource $rel
    $dst = Join-Path (Join-Path $FinalRoot 'PBRify_V4') $rel
    if (Test-Path -LiteralPath $src) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Path $dst -Parent) | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
        $pbrifyCopied++
    } else { $pbrifyMissing += $rel }
}

$modelCsv = @"
Name,Path,License,Role
PBRify V4,$(Join-Path $Root 'models\PBRify\4x-PBRify_UpscalerV4.pth'),CC0,final comparison
UltraSharp V2,$UltraModel,CC BY-NC-SA 4.0,final comparison
"@
Set-Content -LiteralPath (Join-Path $FinalRoot 'model_paths.csv') -Value $modelCsv -Encoding UTF8

$readme = @"
AoM:EE FINAL MODEL COMPARISON

Test set: the existing 80-texture visual benchmark.
Categories: 40 Icon, 25 UI, 10 Portrait/Artwork, 5 Effect/Misc.

Models:
- Original: extracted source texture
- PBRify V4: 4x-PBRify_UpscalerV4.pth
- UltraSharp V2: 4x-UltraSharpV2.pth

UltraSharp model path:
$UltraModel

PBRify V4 model path:
$(Join-Path $Root 'models\PBRify\4x-PBRify_UpscalerV4.pth')

The manifest is copied unchanged from the previous 80-texture benchmark.
Do not alter the selection if this is intended to remain a controlled comparison.

Originals copied: $copiedOriginal
PBRify V4 copied: $pbrifyCopied / $($manifest.Count)
PBRify missing: $($pbrifyMissing.Count)

The UltraSharp_V2 folder is intentionally prepared for the new upscale output.
"@
Set-Content -LiteralPath (Join-Path $FinalRoot 'README.txt') -Value $readme -Encoding UTF8

Write-Host ''
Write-Host 'FINAL AoM:EE MODEL COMPARISON PREPARED' -ForegroundColor Cyan
Write-Host "Root: $FinalRoot"
Write-Host "Manifest: $($manifest.Count) textures"
Write-Host "Originals copied: $copiedOriginal"
Write-Host "PBRify V4 copied: $pbrifyCopied / $($manifest.Count)"
Write-Host "PBRify V4 missing: $($pbrifyMissing.Count)"
Write-Host "UltraSharp model: $UltraModel"
Write-Host ''
if ($pbrifyMissing.Count -gt 0) {
    Write-Host 'PBRify missing files:' -ForegroundColor Yellow
    $pbrifyMissing | ForEach-Object { Write-Host "  $_" }
}
Write-Host 'Next: create/run the UltraSharp V2 ChaiNNer branch using the UltraSharp model above.' -ForegroundColor Green
