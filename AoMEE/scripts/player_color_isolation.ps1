$Csv = "D:\AI_upscaling\AoMEE\reports\tga_classification.csv"
$OutCsv = "D:\AI_upscaling\AoMEE\reports\player_color_candidates.csv"
$OutTxt = "D:\AI_upscaling\AoMEE\reports\player_color_candidates_summary.txt"

if (-not (Test-Path $Csv)) {
    Write-Host "ERROR: Classification CSV not found:"
    Write-Host $Csv
    exit 1
}

$rows = Import-Csv $Csv

$candidates = foreach ($row in $rows) {

    $width  = 0
    $height = 0
    $alphaValues = 0
    $transparent = 0
    $partial = 0
    $opaque = 0

    [void][int]::TryParse($row.Width, [ref]$width)
    [void][int]::TryParse($row.Height, [ref]$height)
    [void][int]::TryParse($row.AlphaValueCount, [ref]$alphaValues)
    [void][int]::TryParse($row.TransparentPixels, [ref]$transparent)
    [void][int]::TryParse($row.PartialAlphaPixels, [ref]$partial)
    [void][int]::TryParse($row.OpaquePixels, [ref]$opaque)

    $pixels = $width * $height

    if ($pixels -le 0) {
        continue
    }

    $alphaCoverage = ($partial + $opaque) / [double]$pixels
    $opaqueCoverage = $opaque / [double]$pixels

    # Strong candidate:
    # - has transparency
    # - alpha is binary or nearly binary
    # - relatively small opaque region
    # - not an empty texture
    if (
        $transparent -gt 0 -and
        $alphaValues -le 2 -and
        $opaque -gt 0 -and
        $opaqueCoverage -le 0.10
    ) {
        [PSCustomObject]@{
            Category           = $row.Category
            Filename           = $row.Filename
            Path               = $row.Path
            Width              = $width
            Height             = $height
            AlphaValueCount    = $alphaValues
            TransparentPixels  = $transparent
            PartialAlphaPixels = $partial
            OpaquePixels       = $opaque
            AlphaCoveragePct   = [math]::Round($alphaCoverage * 100, 3)
            OpaqueCoveragePct  = [math]::Round($opaqueCoverage * 100, 3)
            MapNamed           = $row.MapNamed
            Variant            = $row.Variant
        }
    }
}

$candidates |
    Sort-Object Category, OpaqueCoveragePct, Path |
    Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

$summary = @()
$summary += "AoM:EE Player-Color Candidate Report"
$summary += "===================================="
$summary += ""
$summary += "Total classified textures: $($rows.Count)"
$summary += "Strong player-color candidates: $($candidates.Count)"
$summary += ""

$summary += "BY CATEGORY"
$summary += "-----------"

$candidates |
    Group-Object Category |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-22} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "BY ALPHA VALUE COUNT"
$summary += "--------------------"

$candidates |
    Group-Object AlphaValueCount |
    Sort-Object {[int]$_.Name} |
    ForEach-Object {
        $summary += ("AlphaValueCount {0,-4} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "NOTES"
$summary += "-----"
$summary += "These are candidates only."
$summary += "They meet all of the following:"
$summary += "  * transparency exists"
$summary += "  * AlphaValueCount <= 2"
$summary += "  * some opaque pixels exist"
$summary += "  * opaque coverage <= 10%"
$summary += ""
$summary += "Do NOT automatically apply the player-color preservation rule to every candidate yet."

$summary | Set-Content -Path $OutTxt -Encoding UTF8

Write-Host ""
Write-Host "Created:"
Write-Host $OutCsv
Write-Host $OutTxt
Write-Host ""
Write-Host "Candidate count: $($candidates.Count)"