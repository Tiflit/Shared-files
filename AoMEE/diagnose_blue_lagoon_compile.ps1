$ErrorActionPreference = 'Continue'

$Root = 'D:\AI_upscaling\AoMEE'

$Compiler = Join-Path $Root 'tools\TextureCompiler.exe'

$OriginalTGA = Join-Path `
    $Root `
    'extracted\textures\ui\ui map blue lagoon.tga'

$GeneratedTGA = Join-Path `
    $Root `
    'processed\PBRify_V4\textures\ui\ui map blue lagoon.tga'

$OriginalBTI = Join-Path `
    $Root `
    'extracted\textures\ui\ui map blue lagoon.bti'

$DiagRoot = Join-Path `
    $Root `
    'tests\production_compile_diagnostic\blue_lagoon'

if (Test-Path -LiteralPath $DiagRoot) {
    Remove-Item -LiteralPath $DiagRoot -Recurse -Force
}

$null = New-Item -ItemType Directory -Force -Path $DiagRoot

foreach ($p in @(
    $Compiler,
    $OriginalTGA,
    $GeneratedTGA,
    $OriginalBTI
)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Required path not found: $p"
    }
}

function Test-Compile {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TGA,
        [Parameter(Mandatory)][string]$BTIText
    )

    $dir = Join-Path $DiagRoot $Name
    $null = New-Item -ItemType Directory -Force -Path $dir

    $testTGA = Join-Path $dir 'test.tga'
    $testBTI = Join-Path $dir 'test.bti'
    $testDDT = Join-Path $dir 'test.ddt'
    $testLog = Join-Path $dir 'compiler_output.txt'

    Copy-Item -LiteralPath $TGA -Destination $testTGA -Force

    [IO.File]::WriteAllText(
        $testBTI,
        $BTIText,
        [Text.Encoding]::ASCII
    )

    Write-Host ""
    Write-Host "============================================"
    Write-Host $Name
    Write-Host "============================================"
    Write-Host "BTI: $BTIText"
    Write-Host "TGA: $TGA"
    Write-Host ""

    $output = @(
        & $Compiler `
            -i $testTGA `
            -o $testDDT `
            2>&1
    )

    $exit = $LASTEXITCODE

    $output |
        ForEach-Object { [string]$_ } |
        Set-Content -LiteralPath $testLog -Encoding UTF8

    $exists = Test-Path -LiteralPath $testDDT
    $bytes = 0

    if ($exists) {
        $bytes = (Get-Item -LiteralPath $testDDT).Length
    }

    $success = (
        $exit -eq 0 -and
        $exists -and
        $bytes -gt 0
    )

    if ($success) {
        Write-Host "RESULT: SUCCESS"
    }
    else {
        Write-Host "RESULT: FAILED"
    }

    Write-Host "Exit code: $exit"
    Write-Host "DDT size: $bytes bytes"

    $output |
        Where-Object {
            [string]$_ -match 'UNHANDLED|Running Texture Compiler|Processed:|texture\(s\)'
        } |
        ForEach-Object {
            Write-Host "  $_"
        }

    return [pscustomobject]@{
        Variant  = $Name
        TGA      = $TGA
        BTI      = $BTIText
        ExitCode = $exit
        DDTBytes = $bytes
        Success  = $success
    }
}

$Results = @()

# ------------------------------------------------------------
# Read the authoritative BTI.
# Confirm its actual text and BOM state.
# ------------------------------------------------------------

$OriginalBytes = [IO.File]::ReadAllBytes($OriginalBTI)

$hasBOM = (
    $OriginalBytes.Count -ge 3 -and
    $OriginalBytes[0] -eq 0xEF -and
    $OriginalBytes[1] -eq 0xBB -and
    $OriginalBytes[2] -eq 0xBF
)

$offset = if ($hasBOM) { 3 } else { 0 }

$OriginalText = [Text.Encoding]::UTF8.GetString(
    $OriginalBytes,
    $offset,
    $OriginalBytes.Count - $offset
).Trim()

Write-Host "============================================"
Write-Host "BLUE LAGOON COMPILE DIAGNOSTIC"
Write-Host "============================================"
Write-Host ""
Write-Host "Original BTI BOM : $hasBOM"
Write-Host "Original BTI text: $OriginalText"
Write-Host ""

# ------------------------------------------------------------
# TEST 1: original extracted TGA + original metadata
# ------------------------------------------------------------

$Results += Test-Compile `
    -Name '01_original_tga_original_bti' `
    -TGA $OriginalTGA `
    -BTIText $OriginalText

# ------------------------------------------------------------
# TEST 2: production PBRify TGA + original metadata
# ------------------------------------------------------------

$Results += Test-Compile `
    -Name '02_pbrify_tga_original_bti' `
    -TGA $GeneratedTGA `
    -BTIText $OriginalText

# ------------------------------------------------------------
# TEST 3: PBRify TGA + BC3, same alpha directive
# ------------------------------------------------------------

$Results += Test-Compile `
    -Name '03_pbrify_alpha4_bc3' `
    -TGA $GeneratedTGA `
    -BTIText 'alpha=4 fmt=BC3'

# ------------------------------------------------------------
# TEST 4: PBRify TGA + DeflatedRGBA8, same alpha directive
# ------------------------------------------------------------

$Results += Test-Compile `
    -Name '04_pbrify_alpha4_deflatedrgba8' `
    -TGA $GeneratedTGA `
    -BTIText 'alpha=4 fmt=DeflatedRGBA8'

# ------------------------------------------------------------
# TEST 5: PBRify TGA + BC1 but alpha=1
# Diagnostic only; not a proposed production setting.
# ------------------------------------------------------------

$Results += Test-Compile `
    -Name '05_pbrify_alpha1_bc1' `
    -TGA $GeneratedTGA `
    -BTIText 'alpha=1 fmt=BC1'

# ------------------------------------------------------------
# TEST 6: PBRify TGA + BC1, alpha disabled
# Diagnostic only; this deliberately discards alpha semantics.
# ------------------------------------------------------------

$Results += Test-Compile `
    -Name '06_pbrify_alpha0_bc1' `
    -TGA $GeneratedTGA `
    -BTIText 'alpha=0 fmt=BC1'

# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------

$Report = Join-Path $DiagRoot 'variant_results.csv'

$Results |
    Export-Csv `
        -LiteralPath $Report `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host ""
Write-Host "============================================"
Write-Host "BLUE LAGOON DIAGNOSTIC SUMMARY"
Write-Host "============================================"
Write-Host ""

$Results |
    Format-Table `
        Variant,
        ExitCode,
        DDTBytes,
        Success `
        -AutoSize

Write-Host ""
Write-Host "Results:"
Write-Host $Report
Write-Host ""
Write-Host "Diagnostic folder:"
Write-Host $DiagRoot
