$Project = "D:\AI_upscaling\AoMEE"

$Usage = "$Project\reports\mtrl_texture_usage.csv"
$BTI   = "$Project\reports\bti_metadata_analysis.csv"

$OutCsv = "$Project\reports\player_color_texture_set.csv"
$OutTxt = "$Project\reports\player_color_texture_set_summary.txt"

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

$usage = Import-Csv -LiteralPath $Usage
$bti   = Import-Csv -LiteralPath $BTI

# ------------------------------------------------------------
# BTI lookup
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
# Determine all textures used by CT4
# ------------------------------------------------------------

$textureStats = @{}

foreach ($row in $usage) {

    if ([string]::IsNullOrWhiteSpace($row.Texture)) {
        continue
    }

    $texture = $row.Texture.Trim()
    $key = $texture.ToLowerInvariant()

    if (-not $textureStats.ContainsKey($key)) {

        $textureStats[$key] = [PSCustomObject]@{
            Texture    = $texture
            Total      = 0
            CT0        = 0
            CT4        = 0
            OtherCT    = 0
        }
    }

    $s = $textureStats[$key]

    $s.Total++

    if ($row.ColorTransform -eq "0") {
        $s.CT0++
    }
    elseif ($row.ColorTransform -eq "4") {
        $s.CT4++
    }
    else {
        $s.OtherCT++
    }
}

# ------------------------------------------------------------
# Select CT4 + noalphatest
# ------------------------------------------------------------

$results = @()

foreach ($key in $textureStats.Keys) {

    $s = $textureStats[$key]

    if ($s.CT4 -le 0) {
        continue
    }

    if (-not $btiLookup.ContainsKey($key)) {
        continue
    }

    $b = $btiLookup[$key]

    if ($b.NoAlphaTest -ne "True") {
        continue
    }

    $results += [PSCustomObject]@{
        Texture       = $s.Texture
        MaterialUses  = $s.Total
        CT0Uses       = $s.CT0
        CT4Uses       = $s.CT4
        OtherCTUses   = $s.OtherCT

        BTI_AlphaBits = $b.AlphaBits
        BTI_Format    = $b.Format
        BTI_File      = $b.BTIFile
    }
}

# ------------------------------------------------------------
# Save CSV
# ------------------------------------------------------------

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

$summary += "AoM:EE Player-Color Texture Set"
$summary += "==============================="
$summary += ""
$summary += "Unique CT4 textures: $($textureStats.Values | Where-Object {$_.CT4 -gt 0} | Measure-Object | Select-Object -ExpandProperty Count)"
$summary += "CT4 + noalphatest textures: $($results.Count)"
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
$summary += "BTI FORMAT"
$summary += "----------"

$results |
    Group-Object BTI_Format |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "CT0 / CT4 USAGE"
$summary += "---------------"

$results |
    Group-Object {
        if ($_.CT0Uses -gt 0 -and $_.CT4Uses -gt 0) {
            "Both CT0 + CT4"
        }
        elseif ($_.CT4Uses -gt 0) {
            "CT4 only"
        }
        else {
            "Unexpected"
        }
    } |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "PLAYER-COLOR TEXTURES"
$summary += "---------------------"

$results |
    Sort-Object Texture |
    ForEach-Object {
        $summary += (
            "{0,-55} Alpha={1,-2} Format={2,-15} CT0={3,4} CT4={4,4}" -f `
            $_.Texture,
            $_.BTI_AlphaBits,
            $_.BTI_Format,
            $_.CT0Uses,
            $_.CT4Uses
        )
    }

$summary += ""
$summary += "OUTPUT"
$summary += "------"
$summary += $OutCsv
$summary += $OutTxt

$summary |
    Set-Content -LiteralPath $OutTxt -Encoding UTF8

Write-Host ""
Write-Host "=============================================="
Write-Host "DONE"
Write-Host "=============================================="
Write-Host ""
Write-Host "Player-color texture set: $($results.Count)"
Write-Host ""
Write-Host $OutTxt