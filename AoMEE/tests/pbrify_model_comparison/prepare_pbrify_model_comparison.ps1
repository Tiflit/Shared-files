$ErrorActionPreference = 'Stop'

# ============================================================
# AoM:EE PBRify/HAT model comparison preparation
#
# Reuses the EXACT 80-texture visual benchmark selected previously:
#   40 Icon
#   25 UI
#   10 Portrait/Artwork
#    5 Effect/Misc
#
# It copies those source TGA files from the clean extracted source
# tree into a dedicated test folder, preserving their relative paths.
# It does NOT modify the clean game/source tree.
#
# Processing remains separate from preparation. Run this script first,
# then point the ChaiNNer comparison chain at tests\pbrify_model_comparison.
# ============================================================

$Root          = 'D:\AI_upscaling\AoMEE'
$Extracted     = Join-Path $Root 'extracted'
$PreviousSet   = Join-Path $Root 'tests\visual_model_comparison\visual_model_comparison_manifest.csv'
$TestRoot      = Join-Path $Root 'tests\pbrify_model_comparison'
$OriginalRoot  = Join-Path $TestRoot 'original'

$ModelMap = @(
    [PSCustomObject]@{
        Model      = 'HAT'
        Checkpoint = 'D:\AI_upscaling\AoMEE\models\HAT\Real_HAT_GAN_sharper.pth'
    },
    [PSCustomObject]@{
        Model      = 'PBRify_V4'
        Checkpoint = 'D:\AI_upscaling\AoMEE\models\PBRify\4x-PBRify_UpscalerV4.pth'
    },
    [PSCustomObject]@{
        Model      = 'PBRify_RPLKSRd_V3'
        Checkpoint = 'D:\AI_upscaling\AoMEE\models\PBRify\4x-PBRify_RPLKSRd_V3.pth'
    }
)

# ------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Extracted -PathType Container)) {
    throw "Extracted source directory not found: $Extracted"
}

if (-not (Test-Path -LiteralPath $PreviousSet -PathType Leaf)) {
    throw "Previous 80-texture benchmark manifest not found: $PreviousSet"
}

foreach ($m in $ModelMap) {
    if (-not (Test-Path -LiteralPath $m.Checkpoint -PathType Leaf)) {
        throw "Checkpoint not found for $($m.Model): $($m.Checkpoint)"
    }
}

# ------------------------------------------------------------
# Read the exact previous 80-texture selection.
# ------------------------------------------------------------
$Rows = @(Import-Csv -LiteralPath $PreviousSet -Encoding UTF8)

if ($Rows.Count -ne 80) {
    throw "Expected exactly 80 entries in the previous visual benchmark manifest; found $($Rows.Count)."
}

# Confirm there are no duplicate relative paths.
$duplicatePaths = @(
    $Rows |
        Group-Object -Property RelativePath |
        Where-Object Count -gt 1
)

if ($duplicatePaths.Count -gt 0) {
    throw "Previous manifest contains duplicate RelativePath entries. Aborting."
}

# ------------------------------------------------------------
# Validate every source before copying anything.
# ------------------------------------------------------------
$missing = New-Object System.Collections.Generic.List[string]

foreach ($row in $Rows) {
    $source = Join-Path -Path $Extracted -ChildPath $row.RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        $missing.Add($row.RelativePath)
    }
}

if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host 'MISSING SOURCE TEXTURES:' -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" }
    throw "Missing $($missing.Count) source texture(s). No copies were made."
}

# ------------------------------------------------------------
# Create the dedicated test tree.
# ------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null
New-Item -ItemType Directory -Force -Path $OriginalRoot | Out-Null

foreach ($m in $ModelMap) {
    New-Item -ItemType Directory -Force -Path (Join-Path $TestRoot $m.Model) | Out-Null
}

# ------------------------------------------------------------
# Copy exact selected originals, preserving relative paths.
# ------------------------------------------------------------
$manifest = New-Object System.Collections.Generic.List[object]

foreach ($row in $Rows) {
    $relative    = [string]$row.RelativePath
    $source      = Join-Path -Path $Extracted -ChildPath $relative
    $destination = Join-Path -Path $OriginalRoot -ChildPath $relative
    $destDir     = Split-Path -Path $destination -Parent

    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force

    $manifest.Add([PSCustomObject]@{
        Index         = $row.Index
        RelativePath  = $relative
        Category      = $row.Category
        Width         = $row.Width
        Height        = $row.Height
        CategoryScore = $row.CategoryScore
        SelectionScore= $row.SelectionScore
        Source        = $source
        Original      = $destination
    })
}

# ------------------------------------------------------------
# Write a local manifest and model map for the new comparison.
# ------------------------------------------------------------
$manifestPath = Join-Path $TestRoot 'pbrify_model_comparison_manifest.csv'
$manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

$modelPath = Join-Path $TestRoot 'model_paths.csv'
$ModelMap | Export-Csv -LiteralPath $modelPath -NoTypeInformation -Encoding UTF8

$readmePath = Join-Path $TestRoot 'README.txt'
@'
AoM:EE HAT vs PBRify model comparison
======================================

Input set:
  Exact same 80-texture set used in the previous visual model benchmark.

Selection:
  40 Icon
  25 UI
  10 Portrait/Artwork
   5 Effect/Misc

Input folder:
  original\

Models:
  HAT
    Real_HAT_GAN_sharper.pth

  PBRify_V4
    4x-PBRify_UpscalerV4.pth

  PBRify_RPLKSRd_V3
    4x-PBRify_RPLKSRd_V3.pth

Recommended processing pipeline for each model:
  RGB -> AI x4
  Alpha -> nearest-neighbour x4
  Merge RGBA
  Save lossless TGA/PNG for comparison

Do not modify the clean source/game tree.
Do not send alpha through the AI model.

The purpose of this folder is controlled side-by-side model comparison.
'@ | Set-Content -LiteralPath $readmePath -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
$categorySummary = $manifest |
    Group-Object -Property Category |
    Sort-Object Name |
    ForEach-Object { "  {0,-18} {1,3}" -f $_.Name, $_.Count }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'AoM:EE PBRIFY / HAT MODEL COMPARISON PREPARED' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "Textures copied:  $($manifest.Count)"
Write-Host "Test root:       $TestRoot"
Write-Host "Originals:        $OriginalRoot"
Write-Host "Manifest:         $manifestPath"
Write-Host "Model paths:      $modelPath"
Write-Host ''
Write-Host 'Category counts:' -ForegroundColor Yellow
$categorySummary | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host 'Models:' -ForegroundColor Yellow
$ModelMap | Format-Table -AutoSize
Write-Host ''
Write-Host 'Next:' -ForegroundColor Green
Write-Host '  Point the ChaiNNer comparison chain at:'
Write-Host "  $OriginalRoot"
Write-Host ''
Write-Host 'Preparation completed successfully.' -ForegroundColor Green
