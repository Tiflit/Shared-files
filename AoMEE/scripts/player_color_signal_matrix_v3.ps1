$Project = "D:\AI_upscaling\AoMEE"

$Metadata = "$Project\reports\bti_metadata_analysis.csv"
$Alpha    = "$Project\reports\noalphatest_alpha_analysis.csv"

$OutCsv = "$Project\reports\player_color_signal_matrix_v3.csv"
$OutTxt = "$Project\reports\player_color_signal_matrix_v3_summary.txt"

if (-not (Test-Path $Metadata)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Metadata
    exit
}

if (-not (Test-Path $Alpha)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Alpha
    exit
}

$metadataRows = Import-Csv -LiteralPath $Metadata
$alphaRows    = Import-Csv -LiteralPath $Alpha

# ------------------------------------------------------------
# Index TGA alpha analysis by exact BTI path
# ------------------------------------------------------------

$alphaLookup = @{}

foreach ($row in $alphaRows) {

    if ([string]::IsNullOrWhiteSpace($row.BTIFile)) {
        continue
    }

    $key = [System.IO.Path]::GetFullPath(
        $row.BTIFile
    ).ToLowerInvariant()

    $alphaLookup[$key] = $row
}

Write-Host ""
Write-Host "BTI metadata rows: $($metadataRows.Count)"
Write-Host "Alpha-analysis rows: $($alphaRows.Count)"
Write-Host ""

# ------------------------------------------------------------
# Build matrix
# ------------------------------------------------------------

$results = @()

foreach ($m in $metadataRows) {

    if ($m.NoAlphaTest -ne "True") {
        continue
    }

    if ([string]::IsNullOrWhiteSpace($m.BTIFile)) {
        continue
    }

    $key = [System.IO.Path]::GetFullPath(
        $m.BTIFile
    ).ToLowerInvariant()

    if (-not $alphaLookup.ContainsKey($key)) {
        continue
    }

    $a = $alphaLookup[$key]

    $results += [PSCustomObject]@{
        Filename          = $a.Filename
        Category          = $a.Category
        Width             = $a.Width
        Height            = $a.Height

        BTI_AlphaBits     = $m.AlphaBits
        BTI_Format        = $m.Format

        TGA_AlphaType     = $a.AlphaType
        TGA_AlphaValues   = $a.AlphaValueCount
        OpaquePixels      = $a.OpaquePixels
        OpaqueCoveragePct = $a.OpaqueCoveragePct
        CoverageGroup     = $a.CoverageGroup

        BTIFile           = $m.BTIFile
    }
}

# ------------------------------------------------------------
# Save CSV
# ------------------------------------------------------------

$results |
    Sort-Object BTI_AlphaBits, TGA_AlphaType, OpaqueCoveragePct, Filename |
    Export-Csv `
        -LiteralPath $OutCsv `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$summary = @()

$summary += "AoM:EE Player-Color Signal Matrix v3"
$summary += "===================================="
$summary += ""
$summary += "noalphatest metadata entries: $($metadataRows | Where-Object {$_.NoAlphaTest -eq 'True'} | Measure-Object | Select-Object -ExpandProperty Count)"
$summary += "Exact BTI -> alpha-analysis matches: $($results.Count)"
$summary += ""

$summary += "BTI ALPHA BITS"
$summary += "--------------"

$results |
    Group-Object BTI_AlphaBits |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "BTI ALPHA BITS x TGA ALPHA TYPE"
$summary += "--------------------------------"

$results |
    Group-Object BTI_AlphaBits, TGA_AlphaType |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-35} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "ALPHA=1: TGA ALPHA TYPE"
$summary += "------------------------"

$results |
    Where-Object { $_.BTI_AlphaBits -eq "1" } |
    Group-Object TGA_AlphaType |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "ALPHA=1: OPAQUE COVERAGE"
$summary += "------------------------"

$results |
    Where-Object { $_.BTI_AlphaBits -eq "1" } |
    Group-Object CoverageGroup |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "ALPHA=4: TGA ALPHA TYPE"
$summary += "------------------------"

$results |
    Where-Object { $_.BTI_AlphaBits -eq "4" } |
    Group-Object TGA_AlphaType |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "ALPHA=4: OPAQUE COVERAGE"
$summary += "------------------------"

$results |
    Where-Object { $_.BTI_AlphaBits -eq "4" } |
    Group-Object CoverageGroup |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "OUTPUT"
$summary += "------"
$summary += $OutCsv
$summary += $OutTxt

$summary |
    Set-Content -LiteralPath $OutTxt -Encoding UTF8

Write-Host ""
Write-Host "=============================="
Write-Host "DONE"
Write-Host "=============================="
Write-Host ""
Write-Host "Exact matches: $($results.Count)"
Write-Host ""
Write-Host $OutTxt