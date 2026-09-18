# ============================================================
# AoM:EE - Complete DDT Extraction
# Uses the official AoM:EE TextureExtractor.exe
# ============================================================

$Root        = "D:\AI_upscaling\AoMEE"
$GameRoot    = Join-Path $Root "Age of Mythology"
$Extractor   = Join-Path $Root "tools\TextureExtractor.exe"
$OutputRoot  = Join-Path $Root "extracted"
$Report      = Join-Path $Root "reports\ddt_extraction_report.csv"

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

if (-not (Test-Path -LiteralPath $GameRoot -PathType Container)) {
    throw "Game folder not found: $GameRoot"
}

if (-not (Test-Path -LiteralPath $Extractor -PathType Leaf)) {
    throw "TextureExtractor.exe not found: $Extractor"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $Report -Parent) | Out-Null

# ------------------------------------------------------------
# Find every DDT in the entire game tree
# ------------------------------------------------------------

Write-Host ""
Write-Host "Scanning game directory..." -ForegroundColor Cyan

$Textures = Get-ChildItem `
    -LiteralPath $GameRoot `
    -File `
    -Recurse |
    Where-Object { $_.Extension -ieq ".ddt" } |
    Sort-Object FullName

Write-Host "Found $($Textures.Count) DDT files." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------
# Statistics
# ------------------------------------------------------------

$Extracted = 0
$Skipped   = 0
$Failed    = 0

$ReportRows = New-Object System.Collections.Generic.List[object]

# ------------------------------------------------------------
# Process every DDT individually
# ------------------------------------------------------------

foreach ($Texture in $Textures) {

    # Relative path from the game root
    $RelativePath = $Texture.FullName.Substring($GameRoot.Length).TrimStart('\')

    # Relative directory
    $RelativeDirectory = Split-Path -Path $RelativePath -Parent

    if ([string]::IsNullOrWhiteSpace($RelativeDirectory)) {
        $DestinationDirectory = $OutputRoot
    }
    else {
        $DestinationDirectory = Join-Path $OutputRoot $RelativeDirectory
    }

    # Create matching directory
    New-Item `
        -ItemType Directory `
        -Force `
        -Path $DestinationDirectory |
        Out-Null

    # Remove .ddt extension
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Texture.Name)

    # Expected outputs
    $OutputTGA = Join-Path $DestinationDirectory ($BaseName + ".tga")
    $OutputBTI = Join-Path $DestinationDirectory ($BaseName + ".bti")

    # --------------------------------------------------------
    # Skip only if BOTH expected files already exist
    # --------------------------------------------------------

    if (
        (Test-Path -LiteralPath $OutputTGA -PathType Leaf) -and
        (Test-Path -LiteralPath $OutputBTI -PathType Leaf)
    ) {
        Write-Host "[SKIP] $RelativePath" -ForegroundColor DarkGray

        $Skipped++

        $ReportRows.Add(
            [PSCustomObject]@{
                Source = $RelativePath
                TGA    = $OutputTGA
                BTI    = $OutputBTI
                Status = "Skipped"
            }
        )

        continue
    }

    Write-Host "[EXTRACT] $RelativePath"

    # --------------------------------------------------------
    # Official TextureExtractor:
    #
    #   -i = input DDT
    #   -o = output TGA filename
    #
    # The tool generates the corresponding BTI alongside it.
    # --------------------------------------------------------

    & $Extractor `
        -i $Texture.FullName `
        -o $OutputTGA

    $ExitCode = $LASTEXITCODE

    # --------------------------------------------------------
    # Verify actual output files
    # --------------------------------------------------------

    $TGAExists = Test-Path -LiteralPath $OutputTGA -PathType Leaf
    $BTIExists = Test-Path -LiteralPath $OutputBTI -PathType Leaf

    if ($ExitCode -eq 0 -and $TGAExists -and $BTIExists) {

        Write-Host "    OK" -ForegroundColor Green

        $Extracted++

        $ReportRows.Add(
            [PSCustomObject]@{
                Source = $RelativePath
                TGA    = $OutputTGA
                BTI    = $OutputBTI
                Status = "Extracted"
            }
        )
    }
    else {

        Write-Warning "Extraction failed or incomplete: $RelativePath"

        $Failed++

        $ReportRows.Add(
            [PSCustomObject]@{
                Source = $RelativePath
                TGA    = if ($TGAExists) { $OutputTGA } else { "" }
                BTI    = if ($BTIExists) { $OutputBTI } else { "" }
                Status = "Failed"
            }
        )
    }
}

# ------------------------------------------------------------
# Save report
# ------------------------------------------------------------

$ReportRows |
    Export-Csv `
        -LiteralPath $Report `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "DDT extraction complete" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Found:     $($Textures.Count)"
Write-Host "Extracted: $Extracted" -ForegroundColor Green
Write-Host "Skipped:   $Skipped" -ForegroundColor Yellow
Write-Host "Failed:    $Failed" -ForegroundColor Red
Write-Host ""
Write-Host "Report:"
Write-Host $Report
Write-Host ""