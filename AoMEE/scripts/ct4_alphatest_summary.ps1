$Project = "D:\AI_upscaling\AoMEE"
$Reports = Join-Path $Project "reports"

$UsageCsv = Join-Path $Reports "mtrl_texture_usage.csv"
$BtiCsv   = Join-Path $Reports "bti_metadata_analysis.csv"

$OutputCsv = Join-Path $Reports "noalphatest_without_ct4.csv"
$OutputTxt = Join-Path $Reports "noalphatest_without_ct4_summary.txt"

if (-not (Test-Path $UsageCsv)) {
    throw "File not found: $UsageCsv"
}

if (-not (Test-Path $BtiCsv)) {
    throw "File not found: $BtiCsv"
}

Write-Host "Loading material usage..."
$usage = Import-Csv $UsageCsv

Write-Host "Loading BTI metadata..."
$bti = Import-Csv $BtiCsv

# ------------------------------------------------------------
# Inspect columns
# ------------------------------------------------------------

Write-Host ""
Write-Host "Material CSV columns:"
$usage[0].PSObject.Properties.Name |
    ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "BTI CSV columns:"
$bti[0].PSObject.Properties.Name |
    ForEach-Object { Write-Host "  $_" }

# ------------------------------------------------------------
# Build CT4 texture set
# ------------------------------------------------------------

Write-Host ""
Write-Host "Building CT4 texture set..."

$ct4Textures = @{}

foreach ($row in $usage) {

    $texture = [string]$row.Texture

    if ([string]::IsNullOrWhiteSpace($texture)) {
        continue
    }

    $ct = 0
    [void][int]::TryParse([string]$row.ColorTransform, [ref]$ct)

    if ($ct -eq 4) {
        $key = $texture.Trim().ToLowerInvariant()
        $ct4Textures[$key] = $texture.Trim()
    }
}

Write-Host "Unique CT4 textures: $($ct4Textures.Count)"

# ------------------------------------------------------------
# Find likely BTI columns
# ------------------------------------------------------------

$btiColumns = $bti[0].PSObject.Properties.Name

$filenameColumn = $btiColumns |
    Where-Object {
        $_ -in @("Filename", "FileName", "Name", "BTI", "BtiFile")
    } |
    Select-Object -First 1

$textureColumn = $btiColumns |
    Where-Object {
        $_ -in @("Texture", "TextureName")
    } |
    Select-Object -First 1

$noAlphaColumn = $btiColumns |
    Where-Object {
        $_ -in @("NoAlphaTest", "noalphatest", "No_Alpha_Test")
    } |
    Select-Object -First 1

if (-not $filenameColumn -and -not $textureColumn) {
    throw "Could not find either a BTI filename or texture-name column."
}

if (-not $noAlphaColumn) {
    throw "Could not find the NoAlphaTest column in bti_metadata_analysis.csv."
}

Write-Host ""
Write-Host "Using BTI columns:"
if ($filenameColumn) {
    Write-Host "  Filename:    $filenameColumn"
}
if ($textureColumn) {
    Write-Host "  Texture:     $textureColumn"
}
Write-Host "  NoAlphaTest: $noAlphaColumn"

# ------------------------------------------------------------
# Extract noalphatest textures
# ------------------------------------------------------------

$noAlphaTextures = @{}

foreach ($row in $bti) {

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

    # Prefer an explicit texture/name column.
    $texture = $null

    if ($textureColumn) {
        $texture = [string]$row.$textureColumn
    }

    # Otherwise derive texture name from BTI filename.
    if ([string]::IsNullOrWhiteSpace($texture) -and $filenameColumn) {
        $texture = [string]$row.$filenameColumn

        if (-not [string]::IsNullOrWhiteSpace($texture)) {
            $texture = [System.IO.Path]::GetFileNameWithoutExtension($texture)
        }
    }

    if ([string]::IsNullOrWhiteSpace($texture)) {
        continue
    }

    $texture = $texture.Trim()
    $key = $texture.ToLowerInvariant()

    $noAlphaTextures[$key] = $texture
}

Write-Host "Unique noalphatest textures: $($noAlphaTextures.Count)"

# ------------------------------------------------------------
# Find noalphatest textures WITHOUT CT4
# ------------------------------------------------------------

$results = New-Object System.Collections.Generic.List[object]

foreach ($key in ($noAlphaTextures.Keys | Sort-Object)) {

    $texture = $noAlphaTextures[$key]

    if (-not $ct4Textures.ContainsKey($key)) {

        $results.Add([PSCustomObject]@{
            Texture = $texture
            HasCT4  = $false
        })
    }
}

$results |
    Sort-Object Texture |
    Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$summary = New-Object System.Collections.Generic.List[string]

$summary.Add("AoM:EE noalphatest Without CT4")
$summary.Add("===============================")
$summary.Add("")
$summary.Add("Unique CT4 textures:             $($ct4Textures.Count)")
$summary.Add("Unique noalphatest textures:     $($noAlphaTextures.Count)")
$summary.Add("noalphatest WITHOUT CT4:         $($results.Count)")
$summary.Add("")

if ($results.Count -eq 0) {

    $summary.Add("RESULT")
    $summary.Add("------")
    $summary.Add("")
    $summary.Add("No noalphatest textures were found without a CT4 material reference.")

}
else {

    $summary.Add("TEXTURES WITH NOALPHATEST BUT NO CT4")
    $summary.Add("------------------------------------")
    $summary.Add("")

    foreach ($row in ($results | Sort-Object Texture)) {
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
Write-Host "=============================================="
Write-Host "Scan complete."
Write-Host ""
Write-Host "CT4 textures:        $($ct4Textures.Count)"
Write-Host "noalphatest textures: $($noAlphaTextures.Count)"
Write-Host "noalphatest without CT4: $($results.Count)"
Write-Host ""
Write-Host "CSV:"
Write-Host $OutputCsv
Write-Host ""
Write-Host "Summary:"
Write-Host $OutputTxt
Write-Host "=============================================="