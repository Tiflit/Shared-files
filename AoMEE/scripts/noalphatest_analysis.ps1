$Project = "D:\AI_upscaling\AoMEE"

$Inventory = "$Project\reports\tga_inventory.csv"
$Bti       = "$Project\reports\player_color_bti.csv"
$Candidates = "$Project\reports\player_color_candidates.csv"
$Intersection = "$Project\reports\player_color_intersection.csv"

$OutCsv = "$Project\reports\noalphatest_alpha_analysis.csv"
$OutTxt = "$Project\reports\noalphatest_alpha_analysis_summary.txt"

if (-not (Test-Path $Inventory)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Inventory
    exit
}

if (-not (Test-Path $Bti)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Bti
    exit
}

$inventory = Import-Csv -LiteralPath $Inventory
$bti = Import-Csv -LiteralPath $Bti

# ------------------------------------------------------------
# Build TGA inventory lookup
# ------------------------------------------------------------

$inventoryLookup = @{}

foreach ($row in $inventory) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension($row.Filename)

    if ([string]::IsNullOrWhiteSpace($name)) {
        continue
    }

    $inventoryLookup[$name.ToLowerInvariant()] = $row
}

# ------------------------------------------------------------
# Analyze all noalphatest textures
# ------------------------------------------------------------

$results = @()

foreach ($row in $bti) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension($row.Filename)

    if ([string]::IsNullOrWhiteSpace($name)) {
        continue
    }

    $key = $name.ToLowerInvariant()

    if (-not $inventoryLookup.ContainsKey($key)) {
        continue
    }

    $tga = $inventoryLookup[$key]

    $width = 0
    $height = 0
    $pixels = 0
    $alphaValues = 0
    $transparent = 0
    $partial = 0
    $opaque = 0

    [void][int]::TryParse($tga.Width, [ref]$width)
    [void][int]::TryParse($tga.Height, [ref]$height)
    [void][int]::TryParse($tga.Pixels, [ref]$pixels)
    [void][int]::TryParse($tga.AlphaValueCount, [ref]$alphaValues)
    [void][int]::TryParse($tga.TransparentPixels, [ref]$transparent)
    [void][int]::TryParse($tga.PartialAlphaPixels, [ref]$partial)
    [void][int]::TryParse($tga.OpaquePixels, [ref]$opaque)

    if ($pixels -le 0) {
        continue
    }

    $alphaCoverage = (($partial + $opaque) / [double]$pixels) * 100
    $opaqueCoverage = ($opaque / [double]$pixels) * 100

    if ($alphaValues -le 2) {
        $alphaType = "Binary"
    }
    else {
        $alphaType = "MultiValue"
    }

    if ($opaqueCoverage -le 10) {
        $coverageGroup = "0-10%"
    }
    elseif ($opaqueCoverage -le 25) {
        $coverageGroup = "10-25%"
    }
    elseif ($opaqueCoverage -le 50) {
        $coverageGroup = "25-50%"
    }
    elseif ($opaqueCoverage -le 75) {
        $coverageGroup = "50-75%"
    }
    else {
        $coverageGroup = "75-100%"
    }

    $results += [PSCustomObject]@{
        Filename          = $tga.Filename
        Category          = $tga.Category
        Width             = $width
        Height            = $height
        AlphaValueCount   = $alphaValues
        AlphaType         = $alphaType
        TransparentPixels = $transparent
        PartialAlpha      = $partial
        OpaquePixels      = $opaque
        AlphaCoveragePct  = [math]::Round($alphaCoverage, 3)
        OpaqueCoveragePct = [math]::Round($opaqueCoverage, 3)
        CoverageGroup     = $coverageGroup
        BTIFile           = $row.BTIFile
    }
}

# ------------------------------------------------------------
# Save detailed analysis
# ------------------------------------------------------------

$results |
    Sort-Object Category, OpaqueCoveragePct, Filename |
    Export-Csv `
        -LiteralPath $OutCsv `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$summary = @()

$summary += "AoM:EE noalphatest Alpha Analysis"
$summary += "================================="
$summary += ""
$summary += "noalphatest BTIs: $($bti.Count)"
$summary += "Matched TGA inventory entries: $($results.Count)"
$summary += ""

$summary += "ALPHA TYPE"
$summary += "----------"

$results |
    Group-Object AlphaType |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "OPAQUE COVERAGE"
$summary += "---------------"

$results |
    Group-Object CoverageGroup |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "BY CATEGORY"
$summary += "-----------"

$results |
    Group-Object Category |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-22} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "BINARY ALPHA + <=10% OPAQUE"
$summary += "----------------------------"

$results |
    Where-Object {
        $_.AlphaType -eq "Binary" -and
        $_.OpaqueCoveragePct -le 10
    } |
    Sort-Object Category, OpaqueCoveragePct, Filename |
    ForEach-Object {
        $summary += $_.Filename
    }

$summary += ""
$summary += "BINARY ALPHA + >10% OPAQUE"
$summary += "---------------------------"

$results |
    Where-Object {
        $_.AlphaType -eq "Binary" -and
        $_.OpaqueCoveragePct -gt 10
    } |
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
Write-Host "noalphatest BTIs: $($bti.Count)"
Write-Host "Analyzed: $($results.Count)"
Write-Host ""
Write-Host $OutTxt