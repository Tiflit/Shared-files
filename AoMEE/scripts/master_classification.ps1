$Root = "D:\AI_upscaling\AoMEE"

$InputCsv = Join-Path $Root "reports\tga_inventory.csv"
$OutputCsv = Join-Path $Root "reports\tga_classification.csv"
$SummaryTxt = Join-Path $Root "reports\tga_classification_summary.txt"

if (-not (Test-Path -LiteralPath $InputCsv)) {
    throw "Input inventory not found: $InputCsv"
}

$data = Import-Csv -LiteralPath $InputCsv

$results = foreach ($row in $data) {

    $path = [string]$row.Path
    $name = [string]$row.Filename
    $combined = ($path + "\" + $name).ToLowerInvariant()

    $width = 0
    $height = 0
    $pixels = 0
    $transparent = 0
    $partial = 0
    $opaque = 0
    $alphaValues = 0

    [int]::TryParse($row.Width, [ref]$width) | Out-Null
    [int]::TryParse($row.Height, [ref]$height) | Out-Null
    [int]::TryParse($row.Pixels, [ref]$pixels) | Out-Null
    [int]::TryParse($row.TransparentPixels, [ref]$transparent) | Out-Null
    [int]::TryParse($row.PartialAlphaPixels, [ref]$partial) | Out-Null
    [int]::TryParse($row.OpaquePixels, [ref]$opaque) | Out-Null
    [int]::TryParse($row.AlphaValueCount, [ref]$alphaValues) | Out-Null

    if ($pixels -gt 0) {
        $alphaCoverage = (($opaque + $partial) / $pixels) * 100
        $transparentCoverage = ($transparent / $pixels) * 100
    }
    else {
        $alphaCoverage = 0
        $transparentCoverage = 0
    }

    # --------------------------------------------------------
    # CATEGORY
    # --------------------------------------------------------

    $category = "Other"

    if ($combined -match "\\textures\\ui\\|\\textures\\menu\\|\\\bui\b|\bmenu\b|\bsplash\b|\bfont\b") {
        $category = "UI"
    }
    elseif ($combined -match "\\icons\\|icon") {
        $category = "Icon"
    }
    elseif ($combined -match "shadow") {
        $category = "Shadow"
    }
    elseif ($combined -match "\\terrain\\|\\world\\|terrain|world") {
        $category = "World/Terrain"
    }
    elseif ($combined -match "building|roof|wall|fortress|temple|lighthouse|tower|house|palace|pyramid|wonder|settlement|dock|gate") {
        $category = "Building"
    }
    elseif ($combined -match "\\animal\\|animal") {
        $category = "Animal"
    }
    elseif ($combined -match "\\archer\\|\\unit\\|\\units\\|character|hero|soldier|warrior") {
        $category = "Character/Unit"
    }
    elseif ($combined -match "\\effect\\|\\effects\\|effect|particle|fire|smoke|water") {
        $category = "Effect"
    }

    # --------------------------------------------------------
    # SPECIAL FLAGS
    # --------------------------------------------------------

    $flags = New-Object System.Collections.Generic.List[string]

    if ($alphaValues -gt 2 -and $alphaCoverage -lt 25) {
        $flags.Add("SparseAlpha")
    }

    if ($partial -gt 0) {
        $flags.Add("PartialAlpha")
    }

    if ($combined -match "shadow") {
        $flags.Add("Shadow")
    }

    if ($combined -match "normal|bump") {
        $flags.Add("Normal/Bump")
    }

    if ($combined -match "spec") {
        $flags.Add("Specular")
    }

    if ($combined -match "gloss") {
        $flags.Add("Gloss")
    }

    if ($combined -match "emiss") {
        $flags.Add("Emissive")
    }

    if ($combined -match "map") {
        $flags.Add("MapNamed")
    }

    if ($combined -match "construction|destruct|dead|corpse") {
        $flags.Add("Variant")
    }

    # --------------------------------------------------------
    # AUTOMATIC 4x TARGET
    # --------------------------------------------------------

    $targetWidth = if ($width -gt 0) { $width * 4 } else { "" }
    $targetHeight = if ($height -gt 0) { $height * 4 } else { "" }

    $suggestedGroup = switch ($category) {
        "Building"       { "General AI Upscale" }
        "Animal"         { "General AI Upscale" }
        "Character/Unit" { "General AI Upscale" }
        "Icon"           { "UI/Icon AI Upscale" }
        "UI"             { "UI AI Upscale" }
        "Shadow"         { "Shadow Review" }
        "World/Terrain"  { "World/Terrain Review" }
        "Effect"         { "Effect Review" }
        default          { "General AI Upscale" }
    }

    [PSCustomObject]@{
        Path                    = $row.Path
        Filename                = $row.Filename
        Category                = $category
        SuggestedGroup          = $suggestedGroup
        Width                   = $width
        Height                  = $height
        Pixels                  = $pixels
        TargetWidth4x           = $targetWidth
        TargetHeight4x          = $targetHeight
        HasAlpha                = $row.HasAlpha
        AlphaCoveragePercent    = [math]::Round($alphaCoverage, 3)
        TransparentPercent      = [math]::Round($transparentCoverage, 3)
        TransparentPixels       = $transparent
        PartialAlphaPixels      = $partial
        OpaquePixels            = $opaque
        AlphaValueCount         = $alphaValues
        FileSizeKB              = $row.FileSizeKB
        Flags                   = ($flags -join "; ")
    }
}

$results |
    Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------

$summary = New-Object System.Collections.Generic.List[string]

$summary.Add("AoM:EE TGA Classification")
$summary.Add("==========================")
$summary.Add("")
$summary.Add("Total textures: $($results.Count)")
$summary.Add("")

$summary.Add("CATEGORY COUNTS")
$summary.Add("---------------")

$results |
    Group-Object Category |
    Sort-Object Count -Descending |
    ForEach-Object {
        $summary.Add(("{0,-20} {1,6}" -f $_.Name, $_.Count))
    }

$summary.Add("")
$summary.Add("SUGGESTED GROUP COUNTS")
$summary.Add("----------------------")

$results |
    Group-Object SuggestedGroup |
    Sort-Object Count -Descending |
    ForEach-Object {
        $summary.Add(("{0,-25} {1,6}" -f $_.Name, $_.Count))
    }

$summary.Add("")
$summary.Add("RESOLUTION COUNTS")
$summary.Add("-----------------")

$results |
    Group-Object { "$($_.Width)x$($_.Height)" } |
    Sort-Object Count -Descending |
    ForEach-Object {
        $summary.Add(("{0,-15} {1,6}" -f $_.Name, $_.Count))
    }

$summary.Add("")
$summary.Add("SPECIAL FLAGS")
$summary.Add("-------------")

$results |
    ForEach-Object {
        if ($_.Flags) {
            $_.Flags -split "; " |
                ForEach-Object { $_ }
        }
    } |
    Group-Object |
    Sort-Object Count -Descending |
    ForEach-Object {
        $summary.Add(("{0,-25} {1,6}" -f $_.Name, $_.Count))
    }

$summary | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "AoM:EE TGA classification complete" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Textures: $($results.Count)"
Write-Host ""
Write-Host "CSV:"
Write-Host $OutputCsv
Write-Host ""
Write-Host "Summary:"
Write-Host $SummaryTxt
Write-Host ""

$results |
    Group-Object Category |
    Sort-Object Count -Descending |
    Format-Table Name, Count -AutoSize