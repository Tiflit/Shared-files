$Project = "D:\AI_upscaling\AoMEE"
$Reports = Join-Path $Project "reports"

$Ct4Csv       = Join-Path $Reports "ct4_texture_analysis.csv"
$BtiCsv       = Join-Path $Reports "bti_metadata_analysis.csv"
$CandidateCsv = Join-Path $Reports "player_color_texture_set.csv"

$OutputCsv = Join-Path $Reports "ct4_noalphatest_exact_intersection.csv"
$OutputTxt = Join-Path $Reports "ct4_noalphatest_reconciliation.txt"

foreach ($file in @($Ct4Csv, $BtiCsv, $CandidateCsv)) {
    if (-not (Test-Path $file)) {
        throw "File not found: $file"
    }
}

# ------------------------------------------------------------
# CT4 texture set
# ------------------------------------------------------------

$ct4Rows = Import-Csv $Ct4Csv

if (-not ($ct4Rows[0].PSObject.Properties.Name -contains "Texture")) {
    throw "ct4_texture_analysis.csv does not contain a Texture column."
}

$ct4Set = @{}

foreach ($row in $ct4Rows) {
    $name = [string]$row.Texture

    if ([string]::IsNullOrWhiteSpace($name)) {
        continue
    }

    $key = $name.Trim().ToLowerInvariant()
    $ct4Set[$key] = $name.Trim()
}

# ------------------------------------------------------------
# BTI noalphatest set
# ------------------------------------------------------------

$btiRows = Import-Csv $BtiCsv
$btiColumns = $btiRows[0].PSObject.Properties.Name

Write-Host ""
Write-Host "BTI columns:"
$btiColumns | ForEach-Object { Write-Host "  $_" }

$noAlphaColumn = $btiColumns |
    Where-Object {
        $_ -in @("NoAlphaTest", "noalphatest", "No_Alpha_Test")
    } |
    Select-Object -First 1

if (-not $noAlphaColumn) {
    throw "Could not find NoAlphaTest column."
}

$textureColumn = $btiColumns |
    Where-Object {
        $_ -in @("Texture", "TextureName")
    } |
    Select-Object -First 1

$filenameColumn = $btiColumns |
    Where-Object {
        $_ -in @("Filename", "FileName", "Name", "BTI", "BtiFile")
    } |
    Select-Object -First 1

if (-not $textureColumn -and -not $filenameColumn) {
    throw "Could not find a texture or filename column in BTI metadata."
}

$noAlphaSet = @{}

foreach ($row in $btiRows) {

    $raw = [string]$row.$noAlphaColumn

    $isNoAlpha = $false

    switch ($raw.Trim().ToLowerInvariant()) {
        "true" { $isNoAlpha = $true }
        "1"    { $isNoAlpha = $true }
        "yes"  { $isNoAlpha = $true }
    }

    if (-not $isNoAlpha) {
        continue
    }

    $name = $null

    if ($textureColumn) {
        $name = [string]$row.$textureColumn
    }

    if ([string]::IsNullOrWhiteSpace($name) -and $filenameColumn) {
        $name = [string]$row.$filenameColumn

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($name)
        }
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        continue
    }

    $name = $name.Trim()
    $key = $name.ToLowerInvariant()

    $noAlphaSet[$key] = $name
}

# ------------------------------------------------------------
# Exact intersection
# ------------------------------------------------------------

$intersection = New-Object System.Collections.Generic.List[object]

foreach ($key in $ct4Set.Keys) {

    if ($noAlphaSet.ContainsKey($key)) {

        $intersection.Add([PSCustomObject]@{
            Texture = $ct4Set[$key]
        })
    }
}

$intersection |
    Sort-Object Texture |
    Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# Earlier 447 set
# ------------------------------------------------------------

$candidateRows = Import-Csv $CandidateCsv

if (-not ($candidateRows[0].PSObject.Properties.Name -contains "Texture")) {
    throw "player_color_texture_set.csv does not contain a Texture column."
}

$candidateSet = @{}

foreach ($row in $candidateRows) {

    $name = [string]$row.Texture

    if ([string]::IsNullOrWhiteSpace($name)) {
        continue
    }

    $candidateSet[$name.Trim().ToLowerInvariant()] = $name.Trim()
}

# Find exact-intersection textures missing from the 447 set.
$missingFrom447 = New-Object System.Collections.Generic.List[object]

foreach ($row in $intersection) {

    $key = $row.Texture.ToLowerInvariant()

    if (-not $candidateSet.ContainsKey($key)) {
        $missingFrom447.Add([PSCustomObject]@{
            Texture = $row.Texture
        })
    }
}

# Also find anything in the old 447 set that isn't in the exact intersection.
$extraIn447 = New-Object System.Collections.Generic.List[object]

foreach ($key in $candidateSet.Keys) {

    if (-not $intersection.Texture.ToLowerInvariant().Contains($key)) {
        $extraIn447.Add([PSCustomObject]@{
            Texture = $candidateSet[$key]
        })
    }
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$summary = New-Object System.Collections.Generic.List[string]

$summary.Add("AoM:EE CT4 + noalphatest reconciliation")
$summary.Add("======================================")
$summary.Add("")
$summary.Add("Unique CT4 textures:             $($ct4Set.Count)")
$summary.Add("Unique noalphatest textures:     $($noAlphaSet.Count)")
$summary.Add("Exact CT4 + noalphatest:          $($intersection.Count)")
$summary.Add("Earlier candidate set:            $($candidateSet.Count)")
$summary.Add("Missing from earlier 447 set:    $($missingFrom447.Count)")
$summary.Add("Extra in earlier 447 set:         $($extraIn447.Count)")
$summary.Add("")

$summary.Add("MISSING FROM EARLIER 447")
$summary.Add("------------------------")

if ($missingFrom447.Count -eq 0) {
    $summary.Add("(none)")
}
else {
    foreach ($row in ($missingFrom447 | Sort-Object Texture)) {
        $summary.Add($row.Texture)
    }
}

$summary.Add("")
$summary.Add("EXTRA IN EARLIER 447")
$summary.Add("--------------------")

if ($extraIn447.Count -eq 0) {
    $summary.Add("(none)")
}
else {
    foreach ($row in ($extraIn447 | Sort-Object Texture)) {
        $summary.Add($row.Texture)
    }
}

$summary.Add("")
$summary.Add("OUTPUT")
$summary.Add("------")
$summary.Add($OutputCsv)

$summary |
    Set-Content $OutputTxt -Encoding UTF8

Write-Host ""
Write-Host "=========================================="
Write-Host "Reconciliation complete."
Write-Host ""
Write-Host "CT4:                   $($ct4Set.Count)"
Write-Host "noalphatest:           $($noAlphaSet.Count)"
Write-Host "Exact intersection:    $($intersection.Count)"
Write-Host "Old candidate set:     $($candidateSet.Count)"
Write-Host "Missing from old set:  $($missingFrom447.Count)"
Write-Host "Extra in old set:      $($extraIn447.Count)"
Write-Host ""
Write-Host "Summary:"
Write-Host $OutputTxt
Write-Host "=========================================="