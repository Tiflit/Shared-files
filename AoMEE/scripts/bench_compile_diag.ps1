$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE'

$Compiler = Join-Path $Root 'tools\TextureCompiler.exe'

$OriginalTGA = Join-Path `
    $Root `
    'extracted\patched_to_verify\textures\icons\special c black tortoise icon.tga'

$GeneratedTGA = Join-Path `
    $Root `
    'tests\remaster_benchmark\compile_sharper\patched_to_verify\textures\icons\special c black tortoise icon.tga'

$GeneratedBTI = Join-Path `
    $Root `
    'tests\remaster_benchmark\compile_sharper\patched_to_verify\textures\icons\special c black tortoise icon.bti'

$DiagRoot = Join-Path `
    $Root `
    'tests\remaster_benchmark\black_tortoise_diagnostic'

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

foreach ($p in @(
    $Compiler,
    $OriginalTGA,
    $GeneratedTGA,
    $GeneratedBTI
)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Required file not found: $p"
    }
}

# ------------------------------------------------------------
# Find EVERY matching original BTI.
# ------------------------------------------------------------

$BTIMatches = @(
    Get-ChildItem `
        -LiteralPath (Join-Path $Root 'extracted') `
        -Filter 'special c black tortoise icon.bti' `
        -Recurse `
        -File
)

if ($BTIMatches.Count -eq 0) {
    throw "No Black Tortoise BTI found anywhere under extracted\."
}

Write-Host ""
Write-Host "Found $($BTIMatches.Count) matching BTI file(s):"
$BTIMatches | ForEach-Object {
    Write-Host "  $($_.FullName)"
}

# ------------------------------------------------------------
# Prefer the BTI that matches the recovered logical path:
#
# extracted\patched_to_verify\textures\icons\...
# becomes logical:
# textures\icons\...
#
# ------------------------------------------------------------

$ExpectedLogical =
    'textures\icons\special c black tortoise icon.bti'

$OriginalBTI = $null

foreach ($bti in $BTIMatches) {

    $rel = $bti.FullName.Substring(
        (Join-Path $Root 'extracted').Length + 1
    )

    $rel = $rel -replace '/', '\'

    if ($rel.StartsWith(
        'patched_to_verify\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        $rel = $rel.Substring(
            'patched_to_verify\'.Length
        )
    }

    if ($rel.Equals(
        $ExpectedLogical,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        $OriginalBTI = $bti.FullName
        break
    }
}

# Fallback if there is no exact logical-path match.
if ($null -eq $OriginalBTI -and $BTIMatches.Count -eq 1) {
    $OriginalBTI = $BTIMatches[0].FullName
}

if ($null -eq $OriginalBTI) {
    throw "Multiple Black Tortoise BTIs exist, but none matched the expected logical path."
}

Write-Host ""
Write-Host "Selected authoritative BTI:"
Write-Host "  $OriginalBTI"

# ------------------------------------------------------------
# Recreate diagnostic directory.
# ------------------------------------------------------------

if (Test-Path -LiteralPath $DiagRoot) {
    Remove-Item -LiteralPath $DiagRoot -Recurse -Force
}

$null = New-Item `
    -ItemType Directory `
    -Force `
    -Path $DiagRoot

$OriginalDir = Join-Path $DiagRoot 'original'
$GeneratedDir = Join-Path $DiagRoot 'generated'

$null = New-Item `
    -ItemType Directory `
    -Force `
    -Path $OriginalDir

$null = New-Item `
    -ItemType Directory `
    -Force `
    -Path $GeneratedDir

# ------------------------------------------------------------
# Make both test pairs use the EXACT same simple filenames.
# ------------------------------------------------------------

Copy-Item `
    -LiteralPath $OriginalTGA `
    -Destination (Join-Path $OriginalDir 'test.tga') `
    -Force

Copy-Item `
    -LiteralPath $OriginalBTI `
    -Destination (Join-Path $OriginalDir 'test.bti') `
    -Force

Copy-Item `
    -LiteralPath $GeneratedTGA `
    -Destination (Join-Path $GeneratedDir 'test.tga') `
    -Force

Copy-Item `
    -LiteralPath $GeneratedBTI `
    -Destination (Join-Path $GeneratedDir 'test.bti') `
    -Force

# ------------------------------------------------------------
# Python image diagnostics.
# ------------------------------------------------------------

$Python = @'
from pathlib import Path
from PIL import Image
import sys

for s in sys.argv[1:]:
    p = Path(s)

    print(f"FILE: {p}")
    print(f"SIZE: {p.stat().st_size}")

    if p.suffix.lower() == ".tga":
        with Image.open(p) as im:
            print(f"FORMAT: {im.format}")
            print(f"DIMENSIONS: {im.width}x{im.height}")
            print(f"MODE: {im.mode}")
            print(f"INFO: {dict(im.info)}")

    print()
'@

$PyFile = Join-Path `
    $env:TEMP `
    'aom_black_tortoise_diag.py'

$Python |
    Set-Content `
        -LiteralPath $PyFile `
        -Encoding UTF8

# ------------------------------------------------------------
# Show both pairs.
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================"
Write-Host "ORIGINAL SOURCE PAIR"
Write-Host "============================================"
Write-Host ""

& py $PyFile `
    (Join-Path $OriginalDir 'test.tga') `
    (Join-Path $OriginalDir 'test.bti')

Write-Host ""
Write-Host "============================================"
Write-Host "GENERATED HAT PAIR"
Write-Host "============================================"
Write-Host ""

& py $PyFile `
    (Join-Path $GeneratedDir 'test.tga') `
    (Join-Path $GeneratedDir 'test.bti')

# ------------------------------------------------------------
# Test original.
# ------------------------------------------------------------

$OriginalDDT = Join-Path `
    $OriginalDir `
    'test.ddt'

Write-Host ""
Write-Host "============================================"
Write-Host "TEST 1: ORIGINAL TGA + ORIGINAL BTI"
Write-Host "============================================"
Write-Host ""

& $Compiler `
    -i (Join-Path $OriginalDir 'test.tga') `
    -o $OriginalDDT

$OriginalExit = $LASTEXITCODE

if (Test-Path -LiteralPath $OriginalDDT) {
    Write-Host "Original compilation: SUCCESS"
    Write-Host "Exit code: $OriginalExit"
    Write-Host "DDT size: $((Get-Item $OriginalDDT).Length) bytes"
}
else {
    Write-Host "Original compilation: FAILED"
    Write-Host "Exit code: $OriginalExit"
}

# ------------------------------------------------------------
# Test generated.
# ------------------------------------------------------------

$GeneratedDDT = Join-Path `
    $GeneratedDir `
    'test.ddt'

Write-Host ""
Write-Host "============================================"
Write-Host "TEST 2: HAT TGA + ORIGINAL BTI"
Write-Host "============================================"
Write-Host ""

& $Compiler `
    -i (Join-Path $GeneratedDir 'test.tga') `
    -o $GeneratedDDT

$GeneratedExit = $LASTEXITCODE

if (Test-Path -LiteralPath $GeneratedDDT) {
    Write-Host "Generated compilation: SUCCESS"
    Write-Host "Exit code: $GeneratedExit"
    Write-Host "DDT size: $((Get-Item $GeneratedDDT).Length) bytes"
}
else {
    Write-Host "Generated compilation: FAILED"
    Write-Host "Exit code: $GeneratedExit"
}

# ------------------------------------------------------------
# Interpretation.
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================"
Write-Host "DIAGNOSTIC RESULT"
Write-Host "============================================"
Write-Host ""

switch ("${OriginalExit}:${GeneratedExit}") {

    "0:0" {
        Write-Host "BOTH COMPILE."
        Write-Host "The original benchmark failure appears transient."
    }

    "0:-1073741819" {
        Write-Host "ORIGINAL SUCCEEDS, HAT OUTPUT FAILS."
        Write-Host "The generated TGA is the likely trigger."
    }

    "-1073741819:-1073741819" {
        Write-Host "BOTH CRASH."
        Write-Host "The BTI/source combination is the likely trigger."
    }

    default {
        Write-Host "UNEXPECTED RESULT."
        Write-Host "Original exit:  $OriginalExit"
        Write-Host "Generated exit: $GeneratedExit"
    }
}

Remove-Item `
    -LiteralPath $PyFile `
    -Force `
    -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Diagnostic directory:"
Write-Host $DiagRoot