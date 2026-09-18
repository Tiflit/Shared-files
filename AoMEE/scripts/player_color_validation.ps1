$Project = "D:\AI_upscaling\AoMEE"
$Reports = Join-Path $Project "reports"

$AlphaCsv = Join-Path $Reports "player_color_alpha_analysis.csv"
$ClassCsv = Join-Path $Reports "tga_classification.csv"

$OutputCsv = Join-Path $Reports "player_color_validation_samples.csv"
$OutputTxt = Join-Path $Reports "player_color_validation_samples.txt"

if (-not (Test-Path $AlphaCsv)) {
    throw "Missing: $AlphaCsv"
}

if (-not (Test-Path $ClassCsv)) {
    throw "Missing: $ClassCsv"
}

$alpha = Import-Csv $AlphaCsv
$class = Import-Csv $ClassCsv

# Build lookup by filename.
$classLookup = @{}

foreach ($row in $class) {
    $name = [string]$row.Filename
    if ([string]::IsNullOrWhiteSpace($name)) {
        continue
    }

    $key = $name.ToLowerInvariant()

    if (-not $classLookup.ContainsKey($key)) {
        $classLookup[$key] = $row
    }
}

# Add category and assign a validation tier.
$combined = foreach ($row in $alpha) {

    $key = ([string]$row.Filename).ToLowerInvariant()

    $category = "Unknown"

    if ($classLookup.ContainsKey($key)) {
        $category = [string]$classLookup[$key].Category
    }

    $coverage = [double]$row.NonTransparentPct

    if ($coverage -eq 0) {
        $tier = "Exclude - empty"
    }
    elseif ($coverage -ge 100) {
        $tier = "Exclude - opaque"
    }
    elseif ($coverage -le 5) {
        $tier = "High - sparse"
    }
    elseif ($coverage -le 25) {
        $tier = "Medium - moderate"
    }
    else {
        $tier = "Low - broad"
    }

    [PSCustomObject]@{
        Texture           = $row.Texture
        Filename          = $row.Filename
        Category          = $category
        Width             = $row.Width
        Height            = $row.Height
        NonTransparentPct = [double]$row.NonTransparentPct
        AlphaValueCount   = $row.AlphaValueCount
        MaskClass         = $row.MaskClass
        Tier              = $tier
        Path              = $row.Path
    }
}

# Export the complete classified dataset.
$combined |
    Sort-Object Tier, Category, Texture |
    Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]

$lines.Add("AoM:EE Player-Color Validation Samples")
$lines.Add("======================================")
$lines.Add("")
$lines.Add("Suggested samples are selected deterministically from each")
$lines.Add("mask-size/category group. No files are modified.")
$lines.Add("")

$lines.Add("TIER COUNTS")
$lines.Add("-----------")

$combined |
    Group-Object Tier |
    Sort-Object Name |
    ForEach-Object {
        $lines.Add(("{0,-24} {1,5}" -f $_.Name, $_.Count))
    }

$lines.Add("")
$lines.Add("CATEGORY COUNTS")
$lines.Add("----------------")

$combined |
    Group-Object Category |
    Sort-Object Name |
    ForEach-Object {
        $lines.Add(("{0,-22} {1,5}" -f $_.Name, $_.Count))
    }

$lines.Add("")
$lines.Add("SUGGESTED VALIDATION SAMPLES")
$lines.Add("=============================")
$lines.Add("")
$lines.Add("Use these for the operation-D test before any large batch.")
$lines.Add("")

# We deliberately sample every tier/category combination.
# Taking the first three alphabetically makes the selection reproducible.
$tierOrder = @(
    "High - sparse",
    "Medium - moderate",
    "Low - broad"
)

foreach ($tier in $tierOrder) {

    $lines.Add("")
    $lines.Add("[$tier]")
    $lines.Add(("-" * ($tier.Length + 2)))

    $tierRows = @(
        $combined |
        Where-Object { $_.Tier -eq $tier } |
        Sort-Object Category, Texture
    )

    if ($tierRows.Count -eq 0) {
        $lines.Add("(none)")
        continue
    }

    foreach ($group in ($tierRows | Group-Object Category | Sort-Object Name)) {

        $lines.Add("")
        $lines.Add("Category: $($group.Name)")

        $samples = @(
            $group.Group |
            Sort-Object Texture |
            Select-Object -First 3
        )

        foreach ($sample in $samples) {
            $lines.Add((
                "  {0,8:N3}%  {1}" -f
                $sample.NonTransparentPct,
                $sample.Texture
            ))
        }
    }
}

$lines.Add("")
$lines.Add("[EXCLUDED]")
$lines.Add("----------")

$combined |
    Where-Object { $_.Tier -like "Exclude*" } |
    Sort-Object Tier, Texture |
    ForEach-Object {
        $lines.Add((
            "  {0,-20} {1,8:N3}%  {2}" -f
            $_.Tier,
            $_.NonTransparentPct,
            $_.Texture
        ))
    }

$lines |
    Set-Content $OutputTxt -Encoding UTF8

Write-Host ""
Write-Host "======================================"
Write-Host "Validation sample generation complete."
Write-Host ""
Write-Host "Complete CSV:"
Write-Host $OutputCsv
Write-Host ""
Write-Host "Sample report:"
Write-Host $OutputTxt
Write-Host "======================================"