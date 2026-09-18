$Project = "D:\AI_upscaling\AoMEE"

$Metadata = "$Project\reports\bti_metadata_analysis.csv"
$Analysis = "$Project\reports\noalphatest_alpha_analysis.csv"

$OutCsv = "$Project\reports\player_color_signal_matrix.csv"
$OutTxt = "$Project\reports\player_color_signal_matrix_summary.txt"

if (-not (Test-Path $Metadata)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Metadata
    exit
}

if (-not (Test-Path $Analysis)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Analysis
    exit
}

$metadata = Import-Csv -LiteralPath $Metadata
$analysis = Import-Csv -LiteralPath $Analysis

# ------------------------------------------------------------
# Build lookup from the TGA analysis
# ------------------------------------------------------------

$analysisLookup = @{}

foreach ($row in $analysis) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension($row.Filename)

    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $analysisLookup[$name.ToLowerInvariant()] = $row
    }
}

$results = @()

foreach ($m in $metadata) {

    if ($m.NoAlphaTest -ne "True") {
        continue
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($m.Filename)

    if ([string]::IsNullOrWhiteSpace($name)) {
        continue
    }

    $key = $name.ToLowerInvariant()

    if (-not $analysisLookup.ContainsKey($key)) {
        continue
    }

    $a = $analysisLookup[$key]

    $results += [PSCustomObject]@{
        Filename          = $a.Filename
        Category          = $a.Category
        Width             = $a.Width
        Height            = $a.Height

        BTI_AlphaBits     = $m.AlphaBits
        BTI_Format        = $m.Format

        TGA_AlphaType     = $a.AlphaType
        TGA_AlphaValues   = $a.AlphaValueCount
        OpaqueCoveragePct = $a.OpaqueCoveragePct
        CoverageGroup     = $a.CoverageGroup
    }
}

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

$summary += "AoM:EE Player-Color Signal Matrix"
$summary += "================================="
$summary += ""
$summary += "noalphatest textures: $($results.Count)"
$summary += ""

$summary += "BTI ALPHA BITS"
$summary += "--------------"

$results |
    Group-Object BTI_AlphaBits |
    Sort-Object Name |
    ForEach-Object {
        $name = $_.Name
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = "(blank)"
        }

        $summary += ("{0,-20} {1,6}" -f $name, $_.Count)
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
$summary += "ALPHA=1: TGA COVERAGE"
$summary += "---------------------"

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
$summary += "ALPHA=0"
$summary += "-------"

$results |
    Where-Object { $_.BTI_AlphaBits -eq "0" } |
    Group-Object TGA_AlphaType |
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
Write-Host "Textures analyzed: $($results.Count)"
Write-Host ""
Write-Host $OutTxt