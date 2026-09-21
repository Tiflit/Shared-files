$ErrorActionPreference = 'Stop'

$Root      = 'D:\AI_upscaling\AoMEE'
$Extracted = Join-Path $Root 'extracted'
$TestRoot  = Join-Path $Root 'tests\greek_model_comparison'

$ModelDirs = @(
    'original',
    'HAT',
    'SwinIR',
    'DRCT',
    'DAT'
)

$Textures = @(
    'textures\building g settlementage1.tga',
    'textures\building g settlementage2.tga',
    'textures\building g settlementage3.tga',
    'textures\building g shared05 2 map.tga',
    'textures\building g shrine.tga',
    'textures\building g temple.tga',
    'textures\building g templeage1.tga',
    'textures\building g towers.tga',
    'textures\building g wallsage1.tga',
    'textures\building g wonder.tga',

    'textures\cavalry g hippikon standard.tga',
    'textures\cavalry g hippikon horse standard.tga',
    'textures\cavalry g prodromos horse standard.tga',

    'textures\hero g achilles cape.tga',
    'textures\hero g heracles head.tga',
    'textures\hero g theseus shield.tga',
    'textures\hero g atalanta shield.tga',

    'textures\infantry g hoplite head iron.tga',
    'textures\infantry g hoplite standard.tga',
    'textures\infantry g hypaspist standard.tga',
    'textures\infantry g myrmidon head iron.tga',
    'textures\infantry g myrmidon iron.tga',

    'textures\siege g petrobolos.tga',
    'textures\special g centaur.tga'
)

New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

foreach ($dir in $ModelDirs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $TestRoot $dir) | Out-Null
}

$manifest = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[string]

foreach ($relative in $Textures) {

    $source = Join-Path -Path $Extracted -ChildPath $relative

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        $missing.Add($relative)
        continue
    }

    $destination = Join-Path -Path $TestRoot -ChildPath ('original\' + $relative)
    $destinationDir = Split-Path -Path $destination -Parent

    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force

    $category = switch -Regex ($relative) {
        '^textures\\building g ' { 'Building'; break }
        '^textures\\cavalry g '  { 'Character/Unit'; break }
        '^textures\\hero g '     { 'Character/Unit'; break }
        '^textures\\infantry g ' { 'Character/Unit'; break }
        '^textures\\siege g '    { 'Other'; break }
        '^textures\\special g '  { 'Other'; break }
        default                  { 'Other' }
    }

    $manifest.Add([PSCustomObject]@{
        RelativePath = $relative
        Category     = $category
        Source       = $source
        Original     = $destination
    })
}

if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host 'MISSING SOURCE TEXTURES:' -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" }
    throw "Missing $($missing.Count) source texture(s). Nothing was processed beyond the copies above."
}

$manifestPath = Join-Path $TestRoot 'greek_model_comparison_manifest.csv'
$manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

$modelMap = @(
    [PSCustomObject]@{ Model='HAT';    Checkpoint='D:\AI_upscaling\AoMEE\models\HAT\Real_HAT_GAN_sharper.pth' },
    [PSCustomObject]@{ Model='SwinIR'; Checkpoint='D:\AI_upscaling\AoMEE\models\SwinIR\001_classicalSR_DF2K_s64w8_SwinIR-M_x4.pth' },
    [PSCustomObject]@{ Model='DRCT';   Checkpoint='D:\AI_upscaling\AoMEE\models\DRCT\DRCT-L_X4.pth' },
    [PSCustomObject]@{ Model='DAT';    Checkpoint='D:\AI_upscaling\AoMEE\models\DAT\DAT_x4.pth' }
)

$modelPath = Join-Path $TestRoot 'model_paths.csv'
$modelMap | Export-Csv -LiteralPath $modelPath -NoTypeInformation -Encoding UTF8

$readmePath = Join-Path $TestRoot 'comparison_layout.txt'
@'
Greek model comparison
======================

Input set:
  tests\greek_model_comparison\original

Output folders:
  tests\greek_model_comparison\HAT
  tests\greek_model_comparison\SwinIR
  tests\greek_model_comparison\DRCT
  tests\greek_model_comparison\DAT

Pipeline for EVERY model:
  RGB -> model x4
  Alpha -> nearest-neighbour x4
  Merge RGBA
  Save lossless image for visual comparison

Do not use the clean game/source tree as an output location.

Recommended:
  - Keep the same ChaiNNer 0.25.1 graph structure used for the HAT benchmark.
  - Change ONLY the model checkpoint and output directory between runs.
  - Use the same 24 original inputs for all four models.
  - Save PNG during the comparison stage, before any DDT compilation.
'@ | Set-Content -LiteralPath $readmePath -Encoding UTF8

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host 'AoM:EE GREEK MODEL COMPARISON PREPARED' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "Textures prepared: $($manifest.Count)"
Write-Host "Test root:         $TestRoot"
Write-Host "Manifest:          $manifestPath"
Write-Host "Model paths:       $modelPath"
Write-Host ''
Write-Host 'Model checkpoints:' -ForegroundColor Yellow
$modelMap | Format-Table -AutoSize
