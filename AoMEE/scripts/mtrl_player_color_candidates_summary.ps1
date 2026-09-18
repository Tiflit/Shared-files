$Project = "D:\AI_upscaling\AoMEE"

$InputCsv = "$Project\reports\mtrl_player_color_candidates.csv"
$OutputTxt = "$Project\reports\mtrl_player_color_candidates_summary_v2.txt"

if (-not (Test-Path $InputCsv)) {
    Write-Host "ERROR: File not found:"
    Write-Host $InputCsv
    exit
}

$rows = Import-Csv -LiteralPath $InputCsv

Write-Host ""
Write-Host "Candidate/material rows: $($rows.Count)"
Write-Host ""

# Unique candidate textures
$uniqueTextures = @(
    $rows |
        Select-Object -ExpandProperty Filename -Unique |
        Sort-Object
)

# Unique material files
$uniqueMaterials = @(
    $rows |
        Select-Object -ExpandProperty MaterialFile -Unique
)

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$out = @()

$out += "AoM:EE Player-Color Candidate Material Analysis"
$out += "================================================"
$out += ""
$out += "Candidate/material references: $($rows.Count)"
$out += "Unique candidate textures matched: $($uniqueTextures.Count)"
$out += "Unique material files involved: $($uniqueMaterials.Count)"
$out += ""

$out += "MATCHES BY CATEGORY"
$out += "-------------------"

$rows |
    Group-Object Category |
    Sort-Object Name |
    ForEach-Object {
        $out += ("{0,-22} {1,6}" -f $_.Name, $_.Count)
    }

$out += ""
$out += "UNIQUE CANDIDATES WITH COLOR_TRANSFORM 4"
$out += "----------------------------------------"

$ct4Textures = @(
    $rows |
        Where-Object { $_.ColorTransform -eq "4" } |
        Select-Object -ExpandProperty Filename -Unique |
        Sort-Object
)

$out += "Count: $($ct4Textures.Count)"
$out += ""

foreach ($name in $ct4Textures) {
    $out += $name
}

$out += ""
$out += "UNIQUE CANDIDATES WITH COLOR_TRANSFORM 0"
$out += "----------------------------------------"

$ct0Textures = @(
    $rows |
        Where-Object { $_.ColorTransform -eq "0" } |
        Select-Object -ExpandProperty Filename -Unique |
        Sort-Object
)

$out += "Count: $($ct0Textures.Count)"
$out += ""

foreach ($name in $ct0Textures) {
    $out += $name
}

$out += ""
$out += "UNIQUE CANDIDATES WITH BOTH CT0 AND CT4"
$out += "---------------------------------------"

$both = @()

foreach ($name in $uniqueTextures) {

    $has0 = $rows |
        Where-Object {
            $_.Filename -eq $name -and
            $_.ColorTransform -eq "0"
        }

    $has4 = $rows |
        Where-Object {
            $_.Filename -eq $name -and
            $_.ColorTransform -eq "4"
        }

    if ($has0 -and $has4) {
        $both += $name
    }
}

$out += "Count: $($both.Count)"
$out += ""

$both |
    Sort-Object |
    ForEach-Object {
        $out += $_
    }

$out += ""
$out += "UNIQUE CANDIDATES WITH NO CT0 OR CT4"
$out += "------------------------------------"

$other = @()

foreach ($name in $uniqueTextures) {

    $known = $rows |
        Where-Object {
            $_.Filename -eq $name -and
            (
                $_.ColorTransform -eq "0" -or
                $_.ColorTransform -eq "4"
            )
        }

    if (-not $known) {
        $other += $name
    }
}

$out += "Count: $($other.Count)"
$out += ""

$other |
    Sort-Object |
    ForEach-Object {
        $out += $_
    }

$out += ""
$out += "REFERENCE COUNTS PER CANDIDATE"
$out += "------------------------------"

$rows |
    Group-Object Filename |
    Sort-Object @{Expression='Count';Descending=$true}, Name
    ForEach-Object {

        $g = $_

        $ct0 = @(
            $g.Group |
                Where-Object { $_.ColorTransform -eq "0" }
        ).Count

        $ct4 = @(
            $g.Group |
                Where-Object { $_.ColorTransform -eq "4" }
        ).Count

        $out += (
            "{0,-55} Total={1,5} CT0={2,5} CT4={3,5}" -f `
            $g.Name,
            $g.Count,
            $ct0,
            $ct4
        )
    }

$out += ""
$out += "OUTPUT"
$out += "------"
$out += $InputCsv
$out += $OutputTxt

$out |
    Set-Content -LiteralPath $OutputTxt -Encoding UTF8

Write-Host ""
Write-Host "DONE"
Write-Host ""
Write-Host "Unique candidate textures: $($uniqueTextures.Count)"
Write-Host "Unique candidate textures with CT4: $($ct4Textures.Count)"
Write-Host "Unique candidate textures with CT0: $($ct0Textures.Count)"
Write-Host "Unique candidate textures with both: $($both.Count)"
Write-Host ""
Write-Host $OutputTxt