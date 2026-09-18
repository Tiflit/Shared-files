$Project = "D:\AI_upscaling\AoMEE"

$Inventory = "$Project\reports\tga_inventory.csv"
$Metadata  = "$Project\reports\bti_metadata_analysis.csv"

$Extracted = "$Project\extracted"

$OutCsv = "$Project\reports\player_color_signal_matrix_v2.csv"
$OutTxt = "$Project\reports\player_color_signal_matrix_v2_summary.txt"

if (-not (Test-Path $Inventory)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Inventory
    exit
}

if (-not (Test-Path $Metadata)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Metadata
    exit
}

$inventory = Import-Csv -LiteralPath $Inventory
$metadata  = Import-Csv -LiteralPath $Metadata

function Get-RelativeKey {
    param(
        [string]$FullPath,
        [string]$Root
    )

    $full = [System.IO.Path]::GetFullPath($FullPath)
    $rootPath = [System.IO.Path]::GetFullPath($Root)

    if (-not $rootPath.EndsWith("\")) {
        $rootPath += "\"
    }

    if ($full.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($rootPath.Length).ToLowerInvariant()
    }

    return $full.ToLowerInvariant()
}

# ------------------------------------------------------------
# Index TGA inventory by EXACT relative path
# ------------------------------------------------------------

$tgaLookup = @{}
$tgaDuplicates = @()

foreach ($row in $inventory) {

    if ([string]::IsNullOrWhiteSpace($row.Path)) {
        continue
    }

    $tgaFullPath = $row.Path

    if (-not [System.IO.Path]::IsPathRooted($tgaFullPath)) {
        $tgaFullPath = Join-Path $Extracted $tgaFullPath
    }

    $key = Get-RelativeKey $tgaFullPath $Extracted

    if ($tgaLookup.ContainsKey($key)) {
        $tgaDuplicates += $key
        continue
    }

    $tgaLookup[$key] = $row
}

# ------------------------------------------------------------
# Index BTI metadata by EXACT relative path
# ------------------------------------------------------------

$btiLookup = @{}
$btiDuplicates = @()

foreach ($row in $metadata) {

    if ([string]::IsNullOrWhiteSpace($row.BTIFile)) {
        continue
    }

    $key = Get-RelativeKey $row.BTIFile $Extracted

    if ($btiLookup.ContainsKey($key)) {
        $btiDuplicates += $key
        continue
    }

    $btiLookup[$key] = $row
}

Write-Host ""
Write-Host "TGA inventory entries: $($inventory.Count)"
Write-Host "TGA unique paths:      $($tgaLookup.Count)"
Write-Host "BTI metadata entries:  $($metadata.Count)"
Write-Host "BTI unique paths:      $($btiLookup.Count)"
Write-Host "TGA duplicate keys:    $($tgaDuplicates.Count)"
Write-Host "BTI duplicate keys:    $($btiDuplicates.Count)"
Write-Host ""

# ------------------------------------------------------------
# Match BTI -> corresponding TGA by exact relative path
# ------------------------------------------------------------

$results = @()

foreach ($key in $btiLookup.Keys) {

    $m = $btiLookup[$key]

    if ($m.NoAlphaTest -ne "True") {
        continue
    }

    # Corresponding TGA path:
    # foo.bti -> foo.tga
    $tgaKey = [System.IO.Path]::ChangeExtension($key, ".tga")

    if (-not $tgaLookup.ContainsKey($tgaKey)) {
        continue
    }

    $t = $tgaLookup[$tgaKey]

    $results += [PSCustomObject]@{
        RelativePath       = $tgaKey
        Filename           = $t.Filename
        Category           = $t.Category
        Width              = $t.Width
        Height             = $t.Height

        BTI_AlphaBits      = $m.AlphaBits
        BTI_Format         = $m.Format

        TGA_AlphaType      = $t.AlphaType
        TGA_AlphaValues    = $t.AlphaValueCount
        OpaqueCoveragePct  = $t.OpaqueCoveragePct
        CoverageGroup      = $t.CoverageGroup
    }
}

# ------------------------------------------------------------
# Output CSV
# ------------------------------------------------------------

$results |
    Sort-Object RelativePath |
    Export-Csv `
        -LiteralPath $OutCsv `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$summary = @()

$summary += "AoM:EE Player-Color Signal Matrix v2"
$summary += "===================================="
$summary += ""
$summary += "TGA inventory entries: $($inventory.Count)"
$summary += "BTI metadata entries: $($metadata.Count)"
$summary += "TGA duplicate relative paths: $($tgaDuplicates.Count)"
$summary += "BTI duplicate relative paths: $($btiDuplicates.Count)"
$summary += ""
$summary += "noalphatest BTIs: $(($metadata | Where-Object {$_.NoAlphaTest -eq 'True'}).Count)"
$summary += "Exact BTI -> TGA matches: $($results.Count)"
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
    Where-Object {$_.BTI_AlphaBits -eq "1"} |
    Group-Object TGA_AlphaType |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "ALPHA=1: COVERAGE"
$summary += "-----------------"

$results |
    Where-Object {$_.BTI_AlphaBits -eq "1"} |
    Group-Object CoverageGroup |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "ALPHA=4: TGA ALPHA TYPE"
$summary += "------------------------"

$results |
    Where-Object {$_.BTI_AlphaBits -eq "4"} |
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
Write-Host "Exact matches: $($results.Count)"
Write-Host ""
Write-Host $OutTxt