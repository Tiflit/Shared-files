$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE'

$Compiler = Join-Path `
    $Root `
    'tools\TextureCompiler.exe'

$OriginalTGA = Join-Path `
    $Root `
    'extracted\patched_to_verify\textures\icons\special c black tortoise icon.tga'

$GeneratedTGA = Join-Path `
    $Root `
    'tests\remaster_benchmark\compile_sharper\patched_to_verify\textures\icons\special c black tortoise icon.tga'

$OriginalBTI = Join-Path `
    $Root `
    'extracted\patched_to_verify\textures\icons\special c black tortoise icon.bti'

$DiagRoot = Join-Path `
    $Root `
    'tests\remaster_benchmark\black_tortoise_bom_test'

if (Test-Path -LiteralPath $DiagRoot) {
    Remove-Item -LiteralPath $DiagRoot -Recurse -Force
}

$null = New-Item -ItemType Directory -Force -Path $DiagRoot

$OriginalTest = Join-Path $DiagRoot 'original'
$GeneratedTest = Join-Path $DiagRoot 'generated'

$null = New-Item -ItemType Directory -Force -Path $OriginalTest
$null = New-Item -ItemType Directory -Force -Path $GeneratedTest

foreach ($p in @(
    $Compiler,
    $OriginalTGA,
    $GeneratedTGA,
    $OriginalBTI
)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Required file not found: $p"
    }
}

# ------------------------------------------------------------
# Read BTI bytes.
# ------------------------------------------------------------

$bytes = [IO.File]::ReadAllBytes($OriginalBTI)

Write-Host ""
Write-Host "Original BTI bytes:"
Write-Host (($bytes | ForEach-Object { $_.ToString('X2') }) -join ' ')
Write-Host ""

if (
    $bytes.Count -ge 3 -and
    $bytes[0] -eq 0xEF -and
    $bytes[1] -eq 0xBB -and
    $bytes[2] -eq 0xBF
) {
    Write-Host "UTF-8 BOM detected. Removing exactly 3 bytes."

    $fixedBytes = New-Object byte[] ($bytes.Count - 3)

    [Array]::Copy(
        $bytes,
        3,
        $fixedBytes,
        0,
        $fixedBytes.Length
    )
}
else {
    throw "The expected UTF-8 BOM was not found."
}

$FixedBTIOriginal = Join-Path $OriginalTest 'test.bti'
$FixedBTIGenerated = Join-Path $GeneratedTest 'test.bti'

[IO.File]::WriteAllBytes(
    $FixedBTIOriginal,
    $fixedBytes
)

[IO.File]::WriteAllBytes(
    $FixedBTIGenerated,
    $fixedBytes
)

# ------------------------------------------------------------
# Copy original and generated TGAs.
# ------------------------------------------------------------

Copy-Item `
    -LiteralPath $OriginalTGA `
    -Destination (Join-Path $OriginalTest 'test.tga') `
    -Force

Copy-Item `
    -LiteralPath $GeneratedTGA `
    -Destination (Join-Path $GeneratedTest 'test.tga') `
    -Force

Write-Host "Fixed BTI contents:"
Write-Host (
    [Text.Encoding]::ASCII.GetString($fixedBytes)
)

Write-Host ""
Write-Host "Fixed BTI bytes:"
Write-Host (($fixedBytes | ForEach-Object { $_.ToString('X2') }) -join ' ')

# ------------------------------------------------------------
# TEST 1
# ------------------------------------------------------------

$OriginalDDT = Join-Path $OriginalTest 'test.ddt'

Write-Host ""
Write-Host "============================================"
Write-Host "TEST 1: ORIGINAL TGA + BOM-FREE BTI"
Write-Host "============================================"
Write-Host ""

& $Compiler `
    -i (Join-Path $OriginalTest 'test.tga') `
    -o $OriginalDDT

$OriginalExit = $LASTEXITCODE

Write-Host ""

if (
    $OriginalExit -eq 0 -and
    (Test-Path -LiteralPath $OriginalDDT) -and
    (Get-Item -LiteralPath $OriginalDDT).Length -gt 0
) {
    Write-Host "Original compilation: SUCCESS"
    Write-Host "Exit code: $OriginalExit"
    Write-Host "DDT size: $((Get-Item $OriginalDDT).Length) bytes"
}
else {
    Write-Host "Original compilation: FAILED"
    Write-Host "Exit code: $OriginalExit"

    if (Test-Path -LiteralPath $OriginalDDT) {
        Write-Host "DDT size: $((Get-Item $OriginalDDT).Length) bytes"
    }
}

# ------------------------------------------------------------
# TEST 2
# ------------------------------------------------------------

$GeneratedDDT = Join-Path $GeneratedTest 'test.ddt'

Write-Host ""
Write-Host "============================================"
Write-Host "TEST 2: HAT TGA + BOM-FREE BTI"
Write-Host "============================================"
Write-Host ""

& $Compiler `
    -i (Join-Path $GeneratedTest 'test.tga') `
    -o $GeneratedDDT

$GeneratedExit = $LASTEXITCODE

Write-Host ""

if (
    $GeneratedExit -eq 0 -and
    (Test-Path -LiteralPath $GeneratedDDT) -and
    (Get-Item -LiteralPath $GeneratedDDT).Length -gt 0
) {
    Write-Host "Generated compilation: SUCCESS"
    Write-Host "Exit code: $GeneratedExit"
    Write-Host "DDT size: $((Get-Item $GeneratedDDT).Length) bytes"
}
else {
    Write-Host "Generated compilation: FAILED"
    Write-Host "Exit code: $GeneratedExit"

    if (Test-Path -LiteralPath $GeneratedDDT) {
        Write-Host "DDT size: $((Get-Item $GeneratedDDT).Length) bytes"
    }
}

# ------------------------------------------------------------
# FINAL INTERPRETATION
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================"
Write-Host "BOM TEST RESULT"
Write-Host "============================================"
Write-Host ""

if (
    $OriginalExit -eq 0 -and
    $GeneratedExit -eq 0
) {
    Write-Host "CONFIRMED: UTF-8 BOM was the cause."
    Write-Host ""
    Write-Host "Both the original and HAT-generated TGA compile"
    Write-Host "successfully using the identical BOM-free BTI."
}
elseif (
    $OriginalExit -ne 0 -and
    $GeneratedExit -ne 0
) {
    Write-Host "BOM removal did NOT resolve the crash."
    Write-Host ""
    Write-Host "Further BTI/source investigation is required."
}
else {
    Write-Host "PARTIAL RESULT."
    Write-Host ""
    Write-Host "Original exit:  $OriginalExit"
    Write-Host "Generated exit: $GeneratedExit"
}

Write-Host ""
Write-Host "Diagnostic output:"
Write-Host $DiagRoot