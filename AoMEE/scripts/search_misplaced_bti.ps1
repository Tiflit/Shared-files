$Root      = 'D:\AI_upscaling\AoMEE'
$Extracted = Join-Path $Root 'extracted'
$Game      = Join-Path $Root 'Age of Mythology'
$Reports   = Join-Path $Root 'reports'

$Tga = Join-Path $Extracted 'textures\special e anubite[pixelxform1].tga'
$Bti = Join-Path $Extracted 'textures\special e anubite[pixelxform1].bti'
$Ddt = Join-Path $Game      'textures\special e anubite[pixelxform1].ddt'

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "AoM:EE authoritative inventory refresh" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/4] Checking Anubite source files..." -ForegroundColor Cyan

Write-Host "TGA:"
if (Test-Path -LiteralPath $Tga) {
    Write-Host "  FOUND  $Tga" -ForegroundColor Green
} else {
    Write-Host "  MISSING $Tga" -ForegroundColor Red
}

Write-Host "BTI:"
if (Test-Path -LiteralPath $Bti) {
    Write-Host "  FOUND  $Bti" -ForegroundColor Green
} else {
    Write-Host "  MISSING $Bti" -ForegroundColor Red
}

Write-Host "DDT:"
if (Test-Path -LiteralPath $Ddt) {
    Write-Host "  FOUND  $Ddt" -ForegroundColor Green
} else {
    Write-Host "  MISSING $Ddt" -ForegroundColor Red
}

Write-Host ""

# Search for same-name BTIs elsewhere in the project in case it was moved.
Write-Host "[2/4] Searching for misplaced Anubite BTIs..." -ForegroundColor Cyan

$MovedBti = Get-ChildItem `
    -LiteralPath $Root `
    -Recurse `
    -File `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -ieq 'special e anubite[pixelxform1].bti'
    }

if ($MovedBti.Count -gt 0) {
    foreach ($f in $MovedBti) {
        Write-Host "  FOUND: $($f.FullName)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  No copy found elsewhere." -ForegroundColor Yellow
}

Write-Host ""

# If the expected BTI is missing but the pristine DDT exists,
# re-extract the original DDT to the canonical location.
if (
    (-not (Test-Path -LiteralPath $Bti)) -and
    (Test-Path -LiteralPath $Ddt)
) {
    Write-Host "[3/4] Recreating missing BTI from pristine DDT..." -ForegroundColor Cyan

    $Extractor = Join-Path $Root 'tools\TextureExtractor.exe'

    if (-not (Test-Path -LiteralPath $Extractor)) {
        throw "TextureExtractor.exe not found: $Extractor"
    }

    if (-not (Test-Path -LiteralPath (Split-Path $Tga -Parent))) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Tga -Parent) | Out-Null
    }

    & $Extractor `
        -i $Ddt `
        -o $Tga

    $ExitCode = $LASTEXITCODE

    if ($ExitCode -ne 0) {
        throw "TextureExtractor failed with exit code $ExitCode."
    }

    if (-not (Test-Path -LiteralPath $Tga)) {
        throw "TextureExtractor completed but TGA was not produced."
    }

    if (-not (Test-Path -LiteralPath $Bti)) {
        throw "TextureExtractor completed but BTI is still missing."
    }

    Write-Host "  TGA recreated: OK" -ForegroundColor Green
    Write-Host "  BTI recreated: OK" -ForegroundColor Green
}
else {
    Write-Host "[3/4] No extraction repair required." -ForegroundColor Green
}

Write-Host ""

# Refresh the canonical TGA inventory.
Write-Host "[4/4] Rebuilding 7,487-texture inventory and classification..." -ForegroundColor Cyan

$InventoryScript = Join-Path $Root 'scripts\inventory_tga.ps1'
$ClassificationScript = Join-Path $Root 'scripts\master_classification.ps1'

if (-not (Test-Path -LiteralPath $InventoryScript)) {
    throw "Missing script: $InventoryScript"
}

if (-not (Test-Path -LiteralPath $ClassificationScript)) {
    throw "Missing script: $ClassificationScript"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InventoryScript

if ($LASTEXITCODE -ne 0) {
    throw "TGA inventory script failed."
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ClassificationScript

if ($LASTEXITCODE -ne 0) {
    throw "TGA classification script failed."
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "REFRESH COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

Write-Host "Canonical files now refreshed:"
Write-Host ""
Write-Host "  $($Reports)\tga_inventory.csv"
Write-Host "  $($Reports)\ttga_classification.csv"
Write-Host "  $($Reports)\ttga_classification_summary.txt"
Write-Host ""

# Final BTI sanity check
$AllTga = @(
    Get-ChildItem -LiteralPath $Extracted -Recurse -File |
        Where-Object {
            $_.Extension -ieq '.tga' -and
            $_.FullName -notlike "$(Join-Path $Extracted 'patched_to_verify')\*"
        }
)

$RecoveredTga = @(
    Get-ChildItem -LiteralPath (Join-Path $Extracted 'patched_to_verify') -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -ieq '.tga' }
)

$TotalTga = $AllTga.Count + $RecoveredTga.Count

Write-Host "Final TGA count: $TotalTga"

if (Test-Path -LiteralPath $Bti) {
    Write-Host "Anubite BTI: PRESENT" -ForegroundColor Green
}
else {
    Write-Host "Anubite BTI: STILL MISSING" -ForegroundColor Red
}

Write-Host ""