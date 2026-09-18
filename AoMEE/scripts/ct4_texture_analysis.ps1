$Project = "D:\AI_upscaling\AoMEE"

$Usage   = "$Project\reports\mtrl_texture_usage.csv"
$BTI     = "$Project\reports\bti_metadata_analysis.csv"
$Alpha   = "$Project\reports\noalphatest_alpha_analysis.csv"

$OutCsv = "$Project\reports\ct4_texture_analysis.csv"
$OutTxt = "$Project\reports\ct4_texture_analysis_summary.txt"

if (-not (Test-Path $Usage)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Usage
    exit
}

if (-not (Test-Path $BTI)) {
    Write-Host "ERROR: Missing:"
    Write-Host $BTI
    exit
}

if (-not (Test-Path $Alpha)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Alpha
    exit
}

Write-Host ""
Write-Host "Loading material usage..."
$usage = Import-Csv -LiteralPath $Usage

Write-Host "Loading BTI metadata..."
$bti = Import-Csv -LiteralPath $BTI

Write-Host "Loading alpha analysis..."
$alpha = Import-Csv -LiteralPath $Alpha

# ------------------------------------------------------------
# Build BTI lookup
# ------------------------------------------------------------

$btiLookup = @{}

foreach ($row in $bti) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension(
        $row.Filename
    )

    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $btiLookup[$name.Trim().ToLowerInvariant()] = $row
    }
}

# ------------------------------------------------------------
# Build alpha-analysis lookup
# ------------------------------------------------------------

$alphaLookup = @{}

foreach ($row in $alpha) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension(
        $row.Filename
    )

    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $alphaLookup[$name.Trim().ToLowerInvariant()] = $row
    }
}

# ------------------------------------------------------------
# Collect unique textures used by CT4
# ------------------------------------------------------------

$textureStats = @{}

foreach ($row in $usage) {

    if ([string]::IsNullOrWhiteSpace($row.Texture)) {
        continue
    }

    if ($row.ColorTransform -ne "4") {
        continue
    }

    $texture = $row.Texture.Trim()
    $key = $texture.ToLowerInvariant()

    if (-not $textureStats.ContainsKey($key)) {

        $textureStats[$key] = [PSCustomObject]@{
            Texture       = $texture
            CT4Count      = 0
            HasCT0        = $false
            HasPixelXForm = $false
        }
    }

    $stat = $textureStats[$key]

    $stat.CT4Count++

    # Check whether this same texture also appears in a CT0 material.
    if ($row.ColorTransform -eq "0") {
        $stat.HasCT0 = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($row.PixelXForm)) {
        $stat.HasPixelXForm = $true
    }
}

# The previous loop only selected CT4 rows, so explicitly determine CT0 usage.
foreach ($row in $usage) {

    if ([string]::IsNullOrWhiteSpace($row.Texture)) {
        continue
    }

    $texture = $row.Texture.Trim()
    $key = $texture.ToLowerInvariant()

    if (-not $textureStats.ContainsKey($key)) {
        continue
    }

    if ($row.ColorTransform -eq "0") {
        $textureStats[$key].HasCT0 = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($row.PixelXForm)) {
        $textureStats[$key].HasPixelXForm = $true
    }
}

# ------------------------------------------------------------
# Combine with BTI / alpha information
# ------------------------------------------------------------

$results = @()

foreach ($key in $textureStats.Keys) {

    $stat = $textureStats[$key]

    $alphaBits = ""
    $format = ""
    $alphaType = ""
    $opaqueCoverage = ""
    $coverageGroup = ""
    $noAlphaTest = $false

    if ($btiLookup.ContainsKey($key)) {

        $b = $btiLookup[$key]

        $alphaBits = $b.AlphaBits
        $format = $b.Format

        if ($b.NoAlphaTest -eq "True") {
            $noAlphaTest = $true
        }
    }

    if ($alphaLookup.ContainsKey($key)) {

        $a = $alphaLookup[$key]

        $alphaType = $a.AlphaType
        $opaqueCoverage = $a.OpaqueCoveragePct
        $coverageGroup = $a.CoverageGroup
    }

    $results += [PSCustomObject]@{
        Texture           = $stat.Texture
        CT4Count          = $stat.CT4Count
        AlsoCT0           = $stat.HasCT0
        PixelXForm        = $stat.HasPixelXForm

        NoAlphaTest       = $noAlphaTest
        BTI_AlphaBits     = $alphaBits
        BTI_Format        = $format

        TGA_AlphaType     = $alphaType
        OpaqueCoveragePct = $opaqueCoverage
        CoverageGroup     = $coverageGroup
    }
}

$results |
    Sort-Object Texture |
    Export-Csv `
        -LiteralPath $OutCsv `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$summary = @()

$total = $results.Count

$noAlpha = @(
    $results |
        Where-Object { $_.NoAlphaTest -eq $true }
).Count

$alpha1 = @(
    $results |
        Where-Object { $_.BTI_AlphaBits -eq "1" }
).Count

$alpha4 = @(
    $results |
        Where-Object { $_.BTI_AlphaBits -eq "4" }
).Count

$binary = @(
    $results |
        Where-Object { $_.TGA_AlphaType -eq "Binary" }
).Count

$both = @(
    $results |
        Where-Object { $_.AlsoCT0 -eq $true }
).Count

$pixel = @(
    $results |
        Where-Object { $_.PixelXForm -eq $true }
).Count

$summary += "AoM:EE CT4 Texture Analysis"
$summary += "==========================="
$summary += ""
$summary += "Unique textures used by CT4 materials: $total"
$summary += "Also used by CT0 materials: $both"
$summary += "noalphatest: $noAlpha"
$summary += "BTI alpha=1: $alpha1"
$summary += "BTI alpha=4: $alpha4"
$summary += "TGA binary alpha: $binary"
$summary += "Has PixelXForm material usage: $pixel"
$summary += ""

$summary += "CT4 TEXTURES BY BTI ALPHA BITS"
$summary += "------------------------------"

$results |
    Group-Object BTI_AlphaBits |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-15} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "CT4 TEXTURES BY TGA ALPHA TYPE"
$summary += "------------------------------"

$results |
    Group-Object TGA_AlphaType |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-15} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "CT4 TEXTURES BY COVERAGE"
$summary += "------------------------"

$results |
    Group-Object CoverageGroup |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-15} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "CT4 + NOALPHATEST"
$summary += "-----------------"

$results |
    Where-Object { $_.NoAlphaTest -eq $true } |
    Sort-Object TGA_AlphaType, OpaqueCoveragePct, Texture |
    ForEach-Object {
        $summary += (
            "{0,-55} AlphaBits={1,-2} Alpha={2,-10} Coverage={3}" -f `
            $_.Texture,
            $_.BTI_AlphaBits,
            $_.TGA_AlphaType,
            $_.OpaqueCoveragePct
        )
    }

$summary += ""
$summary += "CT4 + PIXELXFORM"
$summary += "----------------"

$results |
    Where-Object { $_.PixelXForm -eq $true } |
    Sort-Object Texture |
    ForEach-Object {
        $summary += $_.Texture
    }

$summary += ""
$summary += "OUTPUT"
$summary += "------"
$summary += $OutCsv
$summary += $OutTxt

$summary |
    Set-Content `
        -LiteralPath $OutTxt `
        -Encoding UTF8

Write-Host ""
Write-Host "=============================================="
Write-Host "DONE"
Write-Host "=============================================="
Write-Host ""
Write-Host "Unique CT4 textures: $total"
Write-Host "Also CT0:            $both"
Write-Host "noalphatest:         $noAlpha"
Write-Host "BTI alpha=1:         $alpha1"
Write-Host "BTI alpha=4:         $alpha4"
Write-Host "Binary TGA alpha:    $binary"
Write-Host "PixelXForm:          $pixel"
Write-Host ""
Write-Host "Summary:"
Write-Host $OutTxt