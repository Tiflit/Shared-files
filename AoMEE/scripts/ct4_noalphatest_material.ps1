$Project = "D:\AI_upscaling\AoMEE"
$Reports = Join-Path $Project "reports"

$UsageCsv = Join-Path $Reports "mtrl_texture_usage.csv"
$BtiCsv = Join-Path $Reports "bti_metadata_analysis.csv"
$NoCt4Csv = Join-Path $Reports "noalphatest_without_ct4.csv"

$OutputCsv = Join-Path $Reports "noalphatest_without_ct4_material_signals.csv"
$OutputTxt = Join-Path $Reports "noalphatest_without_ct4_material_signals.txt"

foreach ($file in @($UsageCsv, $BtiCsv, $NoCt4Csv)) {
    if (-not (Test-Path $file)) {
        throw "File not found: $file"
    }
}

$usage = Import-Csv $UsageCsv
$bti = Import-Csv $BtiCsv
$noCt4 = Import-Csv $NoCt4Csv

# ------------------------------------------------------------
# Build target texture set
# ------------------------------------------------------------

$targetSet = @{}

foreach ($row in $noCt4) {
    $name = [string]$row.Texture

    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $targetSet[$name.Trim().ToLowerInvariant()] = $name.Trim()
    }
}

Write-Host "Target textures: $($targetSet.Count)"

# ------------------------------------------------------------
# Collect all material references for target textures
# ------------------------------------------------------------

$refs = New-Object System.Collections.Generic.List[object]

foreach ($row in $usage) {

    $texture = [string]$row.Texture

    if ([string]::IsNullOrWhiteSpace($texture)) {
        continue
    }

    $key = $texture.Trim().ToLowerInvariant()

    if (-not $targetSet.ContainsKey($key)) {
        continue
    }

    $ct = 0
    [void][int]::TryParse([string]$row.ColorTransform, [ref]$ct)

    $px = 0
    [void][int]::TryParse([string]$row.PixelXForm, [ref]$px)

    $refs.Add([PSCustomObject]@{
        Texture      = $targetSet[$key]
        MaterialFile = $row.MaterialFile
        ColorTransform = $ct
        PixelXForm   = $px
    })
}

Write-Host "Material references found: $($refs.Count)"

# ------------------------------------------------------------
# Aggregate by texture
# ------------------------------------------------------------

$results = New-Object System.Collections.Generic.List[object]

foreach ($group in ($refs | Group-Object Texture | Sort-Object Name)) {

    $r = $group.Group

    $ctValues = @(
        $r |
        Select-Object -ExpandProperty ColorTransform -Unique |
        Sort-Object
    )

    $pxValues = @(
        $r |
        Select-Object -ExpandProperty PixelXForm -Unique |
        Sort-Object
    )

    $hasCT4 = @(
        $r | Where-Object { $_.ColorTransform -eq 4 }
    ).Count -gt 0

    $hasPixelXForm = @(
        $r | Where-Object { $_.PixelXForm -ne 0 }
    ).Count -gt 0

    $results.Add([PSCustomObject]@{
        Texture             = $group.Name
        MaterialReferences  = $r.Count
        ColorTransforms      = ($ctValues -join ",")
        PixelXForms          = ($pxValues -join ",")
        HasCT4               = $hasCT4
        HasPixelXForm        = $hasPixelXForm
    })
}

$results |
    Sort-Object Texture |
    Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$summary = New-Object System.Collections.Generic.List[string]

$summary.Add("AoM:EE noalphatest WITHOUT CT4 - Material Signals")
$summary.Add("=================================================")
$summary.Add("")
$summary.Add("Target textures:        $($targetSet.Count)")
$summary.Add("Textures with materials: $($results.Count)")
$summary.Add("")

$summary.Add("COLOR TRANSFORM DISTRIBUTION")
$summary.Add("----------------------------")

$ctDistribution = @{}

foreach ($row in $results) {

    foreach ($ct in ($row.ColorTransforms -split ",")) {

        if ([string]::IsNullOrWhiteSpace($ct)) {
            continue
        }

        if (-not $ctDistribution.ContainsKey($ct)) {
            $ctDistribution[$ct] = 0
        }

        $ctDistribution[$ct]++
    }
}

foreach ($key in ($ctDistribution.Keys | Sort-Object { [int]$_ })) {
    $summary.Add(("{0,-8} {1,6}" -f $key, $ctDistribution[$key]))
}

$summary.Add("")
$summary.Add("PIXELXFORM DISTRIBUTION")
$summary.Add("-----------------------")

$pxDistribution = @{}

foreach ($row in $results) {

    foreach ($px in ($row.PixelXForms -split ",")) {

        if ([string]::IsNullOrWhiteSpace($px)) {
            continue
        }

        if (-not $pxDistribution.ContainsKey($px)) {
            $pxDistribution[$px] = 0
        }

        $pxDistribution[$px]++
    }
}

foreach ($key in ($pxDistribution.Keys | Sort-Object { [int]$_ })) {
    $summary.Add(("{0,-8} {1,6}" -f $key, $pxDistribution[$key]))
}

$summary.Add("")
$summary.Add("TEXTURES WITH PIXELXFORM != 0")
$summary.Add("-----------------------------")

$results |
    Where-Object { $_.HasPixelXForm } |
    Sort-Object Texture |
    ForEach-Object {
        $summary.Add((
            "{0}`tCT={1}`tPixelXForm={2}" -f
            $_.Texture,
            $_.ColorTransforms,
            $_.PixelXForms
        ))
    }

$summary.Add("")
$summary.Add("TEXTURES WITH UNUSUAL COLOR TRANSFORM")
$summary.Add("------------------------------------")

$results |
    Where-Object {
        $_.ColorTransforms -ne "0"
    } |
    Sort-Object Texture |
    ForEach-Object {
        $summary.Add((
            "{0}`tCT={1}`tPixelXForm={2}" -f
            $_.Texture,
            $_.ColorTransforms,
            $_.PixelXForms
        ))
    }

$summary.Add("")
$summary.Add("OUTPUT")
$summary.Add("------")
$summary.Add($OutputCsv)

$summary |
    Set-Content $OutputTxt -Encoding UTF8

Write-Host ""
Write-Host "=============================================="
Write-Host "Analysis complete."
Write-Host ""
Write-Host "Target textures:       $($targetSet.Count)"
Write-Host "With material refs:    $($results.Count)"
Write-Host "PixelXForm != 0:       $(
    @($results | Where-Object { $_.HasPixelXForm }).Count
)"
Write-Host "Non-zero CT:           $(
    @($results | Where-Object { $_.ColorTransforms -ne "0" }).Count
)"
Write-Host ""
Write-Host "Summary:"
Write-Host $OutputTxt
Write-Host "=============================================="