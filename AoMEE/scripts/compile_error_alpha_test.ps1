$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE'

$Compiler = Join-Path `
    $Root `
    'tools\TextureCompiler.exe'

$OriginalTGA = Join-Path `
    $Root `
    'extracted\patched_to_verify\textures\icons\special c black tortoise icon.tga'

$DiagRoot = Join-Path `
    $Root `
    'tests\remaster_benchmark\black_tortoise_bti_variants'

foreach ($p in @(
    $Compiler,
    $OriginalTGA
)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Required file not found: $p"
    }
}

if (Test-Path -LiteralPath $DiagRoot) {
    Remove-Item `
        -LiteralPath $DiagRoot `
        -Recurse `
        -Force
}

$null = New-Item `
    -ItemType Directory `
    -Force `
    -Path $DiagRoot

# ------------------------------------------------------------
# Test definitions
# ------------------------------------------------------------

$Variants = @(
    @{
        Name = '01_original'
        Text = 'alpha=0 nomip fmt=BC1'
    },
    @{
        Name = '02_no_nomip'
        Text = 'alpha=0 fmt=BC1'
    },
    @{
        Name = '03_bc3'
        Text = 'alpha=0 nomip fmt=BC3'
    },
    @{
        Name = '04_alpha1_bc1'
        Text = 'alpha=1 nomip fmt=BC1'
    },
    @{
        Name = '05_deflated_rgb8'
        Text = 'alpha=0 nomip fmt=DeflatedRGB8'
    }
)

$Results = @()

# ------------------------------------------------------------
# Create and test each BTI variant.
# ------------------------------------------------------------

foreach ($variant in $Variants) {

    $dir = Join-Path `
        $DiagRoot `
        $variant.Name

    $null = New-Item `
        -ItemType Directory `
        -Force `
        -Path $dir

    $tga = Join-Path $dir 'test.tga'
    $bti = Join-Path $dir 'test.bti'
    $ddt = Join-Path $dir 'test.ddt'

    Copy-Item `
        -LiteralPath $OriginalTGA `
        -Destination $tga `
        -Force

    # Write ASCII deliberately:
    # no UTF-8 BOM, no Unicode encoding.
    [IO.File]::WriteAllText(
        $bti,
        $variant.Text,
        [Text.Encoding]::ASCII
    )

    Write-Host ""
    Write-Host "============================================"
    Write-Host $variant.Name
    Write-Host "============================================"
    Write-Host ""
    Write-Host "BTI:"
    Write-Host $variant.Text
    Write-Host ""

    & $Compiler `
        -i $tga `
        -o $ddt

    $exit = $LASTEXITCODE

    $exists = Test-Path -LiteralPath $ddt

    $size = 0

    if ($exists) {
        $size = (Get-Item -LiteralPath $ddt).Length
    }

    $success = (
        $exit -eq 0 -and
        $exists -and
        $size -gt 0
    )

    if ($success) {
        Write-Host "RESULT: SUCCESS"
        Write-Host "Exit code: $exit"
        Write-Host "DDT size: $size bytes"
    }
    else {
        Write-Host "RESULT: FAILED"
        Write-Host "Exit code: $exit"
        Write-Host "DDT size: $size bytes"
    }

    $Results += [PSCustomObject]@{
        Variant  = $variant.Name
        BTI      = $variant.Text
        ExitCode = $exit
        DDTBytes = $size
        Success  = $success
    }
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$Report = Join-Path `
    $DiagRoot `
    'variant_results.csv'

$Results |
    Export-Csv `
        -LiteralPath $Report `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host ""
Write-Host "============================================"
Write-Host "BLACK TORTOISE BTI VARIANT TEST"
Write-Host "============================================"
Write-Host ""

$Results |
    Format-Table `
        Variant,
        BTI,
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