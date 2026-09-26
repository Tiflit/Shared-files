$ErrorActionPreference = 'Stop'

# ============================================================
# AoM:EE REMASTER BENCHMARK
# HAT Sharper PNG + ORIGINAL BTI -> TGA + BTI -> DDT
#
# Corrected:
#   - no double-dot BTI paths
#   - recovered exceptions use authoritative BTIs
#   - clean game files are never touched
# ============================================================

$Root = 'D:\AI_upscaling\AoMEE'

$BenchmarkRoot = Join-Path $Root 'tests\remaster_benchmark'

$ManifestPath = Join-Path $BenchmarkRoot 'remaster_benchmark_manifest.csv'
$QAPath       = Join-Path $BenchmarkRoot 'benchmark_output_qa_v3.csv'

$ExtractedRoot = Join-Path $Root 'extracted'

$StageRoot = Join-Path $BenchmarkRoot 'compile_sharper'
$DDTRoot   = Join-Path $BenchmarkRoot 'ddt_sharper'

$Compiler = Join-Path $Root 'tools\TextureCompiler.exe'

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

foreach ($path in @(
    $ManifestPath,
    $QAPath,
    $ExtractedRoot,
    $Compiler
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required path not found: $path"
    }
}

py -c "import PIL" 2>$null

if ($LASTEXITCODE -ne 0) {
    throw "Python Pillow is required but was not found."
}

# ------------------------------------------------------------
# Recreate ONLY our temporary compile directories.
# This never touches extracted\ or the clean game.
# ------------------------------------------------------------

if (Test-Path -LiteralPath $StageRoot) {
    Remove-Item -LiteralPath $StageRoot -Recurse -Force
}

if (Test-Path -LiteralPath $DDTRoot) {
    Remove-Item -LiteralPath $DDTRoot -Recurse -Force
}

$null = New-Item -ItemType Directory -Force -Path $StageRoot
$null = New-Item -ItemType Directory -Force -Path $DDTRoot

# ------------------------------------------------------------
# Load benchmark manifest and validated HAT output paths.
# ------------------------------------------------------------

$Manifest = @(Import-Csv -LiteralPath $ManifestPath)
$QA       = @(Import-Csv -LiteralPath $QAPath)

if ($Manifest.Count -ne 115) {
    throw "Expected 115 manifest entries, found $($Manifest.Count)."
}

if ($QA.Count -ne 115) {
    throw "Expected 115 QA entries, found $($QA.Count)."
}

$QAMap = @{}

foreach ($row in $QA) {
    $key = ($row.RelativePath -replace '/', '\').ToLowerInvariant()
    $QAMap[$key] = $row
}

# ------------------------------------------------------------
# Create a robust index of ALL BTIs under extracted\.
#
# This lets us resolve both:
#
#   extracted\textures\foo.bti
#
# and recovered:
#
#   extracted\patched_to_verify\textures\foo.tga
#
# to the same authoritative texture BTI.
# ------------------------------------------------------------

$BTIIndex = @{}

$AllBTIs = Get-ChildItem `
    -LiteralPath $ExtractedRoot `
    -Filter '*.bti' `
    -Recurse `
    -File

foreach ($bti in $AllBTIs) {

    $rel = $bti.FullName.Substring(
        $ExtractedRoot.Length + 1
    )

    $rel = $rel -replace '/', '\'

    # Normal authoritative logical path.
    $logical = $rel

    # Recovered files:
    # patched_to_verify\textures\foo.bti
    # maps logically to:
    # textures\foo.bti
    if ($logical.StartsWith(
        'patched_to_verify\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        $logical = $logical.Substring(
            'patched_to_verify\'.Length
        )
    }

    $key = $logical.ToLowerInvariant()

    if (-not $BTIIndex.ContainsKey($key)) {
        $BTIIndex[$key] = $bti.FullName
    }
}

Write-Host "Indexed BTIs: $($BTIIndex.Count)"
Write-Host ""

# ------------------------------------------------------------
# Python helper: PNG -> 32-bit uncompressed TGA
# ------------------------------------------------------------

$PythonScript = @'
from pathlib import Path
from PIL import Image
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

dst.parent.mkdir(parents=True, exist_ok=True)

with Image.open(src) as img:
    img = img.convert("RGBA")
    img.save(
        dst,
        format="TGA",
        compression=None
    )

print(f"{img.width}x{img.height}")
'@

$PythonTemp = Join-Path $env:TEMP 'aom_png_to_tga.py'

$PythonScript |
    Set-Content `
        -LiteralPath $PythonTemp `
        -Encoding UTF8

$Problems = @()
$Staged = 0
$BTICopied = 0

# ------------------------------------------------------------
# Helper: convert benchmark relative path into authoritative
# logical BTI path.
# ------------------------------------------------------------

function Get-LogicalBTIRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$RelativeTGA
    )

    $relative = $RelativeTGA -replace '/', '\'

    # Remove .tga WITHOUT using ChangeExtension(..., $null),
    # which can create a trailing dot.
    if ($relative.EndsWith(
        '.tga',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        $relative = $relative.Substring(
            0,
            $relative.Length - 4
        )
    }

    # Recovered benchmark files are stored beneath
    # patched_to_verify\, but the authoritative BTI belongs
    # to the normal logical texture path.
    if ($relative.StartsWith(
        'patched_to_verify\',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        $relative = $relative.Substring(
            'patched_to_verify\'.Length
        )
    }

    return ($relative + '.bti')
}

# ------------------------------------------------------------
# STAGE
# ------------------------------------------------------------

foreach ($m in $Manifest) {

    $relative = ($m.OriginalRelativePath -replace '/', '\')
    $key = $relative.ToLowerInvariant()

    Write-Host "Staging: $relative"

    # --------------------------------------------------------
    # Resolve HAT Sharper output.
    # --------------------------------------------------------

    if (-not $QAMap.ContainsKey($key)) {
        $Problems += "Missing QA entry: $relative"
        continue
    }

    $qa = $QAMap[$key]

    $pngPath = $qa.SharperOutput

    if ([string]::IsNullOrWhiteSpace($pngPath)) {
        $Problems += "Missing Sharper path: $relative"
        continue
    }

    if (-not (Test-Path -LiteralPath $pngPath)) {
        $Problems += "Sharper output missing: $pngPath"
        continue
    }

    # --------------------------------------------------------
    # Resolve ORIGINAL authoritative BTI.
    # --------------------------------------------------------

    $logicalBTIRelative = Get-LogicalBTIRelativePath $relative
    $btiKey = $logicalBTIRelative.ToLowerInvariant()

    if (-not $BTIIndex.ContainsKey($btiKey)) {

        $Problems += @(
            "Missing BTI for: $relative"
            "Expected logical BTI: $logicalBTIRelative"
        )

        continue
    }

    $btiPath = $BTIIndex[$btiKey]

    if (-not (Test-Path -LiteralPath $btiPath)) {
        $Problems += "Resolved BTI does not exist: $btiPath"
        continue
    }

    # --------------------------------------------------------
    # Staging paths.
    # --------------------------------------------------------

    $tgaPath = Join-Path $StageRoot $relative

    $ddtRelative = $relative.Substring(
        0,
        $relative.Length - 4
    ) + '.ddt'

    $ddtPath = Join-Path $DDTRoot $ddtRelative

    $tgaDir = Split-Path -Parent $tgaPath
    $ddtDir = Split-Path -Parent $ddtPath

    $null = New-Item `
        -ItemType Directory `
        -Force `
        -Path $tgaDir

    $null = New-Item `
        -ItemType Directory `
        -Force `
        -Path $ddtDir

    # --------------------------------------------------------
    # PNG -> TGA
    # --------------------------------------------------------

    & py $PythonTemp `
        $pngPath `
        $tgaPath | Out-Host

    if (
        $LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $tgaPath)
    ) {
        $Problems += "PNG -> TGA failed: $relative"
        continue
    }

    # --------------------------------------------------------
    # Copy original BTI beside staged TGA.
    # --------------------------------------------------------

    $stageBTI = Join-Path `
        $tgaDir `
        ([IO.Path]::GetFileName(
            $logicalBTIRelative
        ))

    Copy-Item `
        -LiteralPath $btiPath `
        -Destination $stageBTI `
        -Force

    if (-not (Test-Path -LiteralPath $stageBTI)) {
        $Problems += "BTI copy failed: $relative"
        continue
    }

    $Staged++
    $BTICopied++

    Write-Host "  BTI: $btiPath"
}

# ------------------------------------------------------------
# Stop before compilation if staging failed.
# ------------------------------------------------------------

if ($Problems.Count -gt 0) {

    Remove-Item `
        -LiteralPath $PythonTemp `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "============================================"
    Write-Host "STAGING FAILED"
    Write-Host "============================================"
    Write-Host ""

    $Problems | ForEach-Object {
        Write-Host $_
    }

    throw "Staging encountered $($Problems.Count) problem(s)."
}

# ------------------------------------------------------------
# Verify staging counts.
# ------------------------------------------------------------

$StageTGAs = @(
    Get-ChildItem `
        -LiteralPath $StageRoot `
        -Filter '*.tga' `
        -Recurse `
        -File
)

$StageBTIs = @(
    Get-ChildItem `
        -LiteralPath $StageRoot `
        -Filter '*.bti' `
        -Recurse `
        -File
)

if ($StageTGAs.Count -ne 115) {
    throw "Expected 115 staged TGAs, found $($StageTGAs.Count)."
}

if ($StageBTIs.Count -ne 115) {
    throw "Expected 115 staged BTIs, found $($StageBTIs.Count)."
}

Write-Host ""
Write-Host "Staging successful:"
Write-Host "  TGAs: $($StageTGAs.Count)"
Write-Host "  BTIs: $($StageBTIs.Count)"
Write-Host ""

# ------------------------------------------------------------
# COMPILE
# ------------------------------------------------------------

$Compiled = 0

Push-Location $Root

try {

    foreach ($tga in $StageTGAs) {

        $relative = $tga.FullName.Substring(
            $StageRoot.Length + 1
        )

        $relative = $relative -replace '/', '\'

        $ddtRelative = $relative.Substring(
            0,
            $relative.Length - 4
        ) + '.ddt'

        $ddtPath = Join-Path $DDTRoot $ddtRelative

        $btiPath = [IO.Path]::ChangeExtension(
            $tga.FullName,
            '.bti'
        )

        if (-not (Test-Path -LiteralPath $btiPath)) {

            $Problems += `
                "BTI missing before compile: $relative"

            continue
        }

        $ddtDir = Split-Path -Parent $ddtPath

        $null = New-Item `
            -ItemType Directory `
            -Force `
            -Path $ddtDir

        Write-Host "Compiling: $relative"

        # No -c parameter:
        # use the settings from the supplied BTI.
        & $Compiler `
            -i $tga.FullName `
            -o $ddtPath

        if ($LASTEXITCODE -ne 0) {

            $Problems += `
                "TextureCompiler failed ($LASTEXITCODE): $relative"

            continue
        }

        if (-not (Test-Path -LiteralPath $ddtPath)) {

            $Problems += `
                "Compiler reported success but DDT is missing: $relative"

            continue
        }

        $Compiled++
    }

}
finally {
    Pop-Location
}

Remove-Item `
    -LiteralPath $PythonTemp `
    -Force `
    -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# FINAL QA
# ------------------------------------------------------------

$DDTFiles = @(
    Get-ChildItem `
        -LiteralPath $DDTRoot `
        -Filter '*.ddt' `
        -Recurse `
        -File
)

Write-Host ""
Write-Host "============================================"
Write-Host "AoM:EE REMASTER BENCHMARK COMPILE"
Write-Host "============================================"
Write-Host ""

Write-Host "Benchmark entries:       $($Manifest.Count)"
Write-Host "Staged TGAs:             $($StageTGAs.Count)"
Write-Host "Staged BTIs:             $($StageBTIs.Count)"
Write-Host "Compiled DDTs:           $($DDTFiles.Count)"
Write-Host "Successful compilations: $Compiled"
Write-Host "Problems:                $($Problems.Count)"
Write-Host ""

if (
    $Manifest.Count -eq 115 -and
    $StageTGAs.Count -eq 115 -and
    $StageBTIs.Count -eq 115 -and
    $DDTFiles.Count -eq 115 -and
    $Compiled -eq 115 -and
    $Problems.Count -eq 0
) {
    Write-Host "ALL 115 BENCHMARK TEXTURES COMPILED SUCCESSFULLY."
}
else {

    Write-Host "COMPILE QA FAILED."

    if ($Problems.Count -gt 0) {
        Write-Host ""
        Write-Host "Problems:"
        $Problems | ForEach-Object {
            Write-Host " - $_"
        }
    }
}

Write-Host ""
Write-Host "Staging:"
Write-Host $StageRoot
Write-Host ""
Write-Host "DDT output:"
Write-Host $DDTRoot