$Project = "D:\AI_upscaling\AoMEE"
$XmlDir  = Join-Path $Project "reports\materials_xml"
$Reports = Join-Path $Project "reports"

$OutputCsv = Join-Path $Reports "mtrl_secondary_texture_analysis.csv"
$OutputTxt = Join-Path $Reports "mtrl_secondary_texture_analysis_summary.txt"

if (-not (Test-Path $XmlDir)) {
    throw "Directory not found: $XmlDir"
}

$files = Get-ChildItem -Path $XmlDir -Filter "*.mtrl.xml" -File -Recurse

Write-Host "MTRL XML files found: $($files.Count)"
Write-Host "Scanning..."
Write-Host ""

$results = New-Object System.Collections.Generic.List[object]

$processed = 0
$errors = 0

foreach ($file in $files) {

    $processed++

    if (($processed % 1000) -eq 0) {
        Write-Host "Processed $processed / $($files.Count)..."
    }

    try {

        [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop

        $material = $xml.Material

        if ($null -eq $material) {
            continue
        }

        $texture = ""
        $secondary = ""

        if ($null -ne $material.texture) {
            $texture = [string]$material.texture
        }

        if ($null -ne $material.secondary_texture) {
            $secondary = [string]$material.secondary_texture
        }

        $texture = $texture.Trim()
        $secondary = $secondary.Trim()

        if ([string]::IsNullOrWhiteSpace($secondary)) {
            continue
        }

        $sameBitmap = $false

        if (
            -not [string]::IsNullOrWhiteSpace($texture) -and
            $texture.Equals(
                $secondary,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            $sameBitmap = $true
        }

        # Also record every non-empty secondary texture so we can
        # inspect what the field is actually doing.
        $results.Add([PSCustomObject]@{
            MaterialFile  = $file.FullName
            Texture       = $texture
            SecondaryTexture = $secondary
            SameBitmap    = $sameBitmap
        })

    }
    catch {
        $errors++
    }
}

$results |
    Sort-Object Texture, SecondaryTexture, MaterialFile |
    Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$sameBitmapRows = @(
    $results | Where-Object { $_.SameBitmap }
)

$differentBitmapRows = @(
    $results | Where-Object { -not $_.SameBitmap }
)

$uniqueSameBitmapTextures = @(
    $sameBitmapRows |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.Texture) } |
    Select-Object -ExpandProperty Texture -Unique |
    Sort-Object
)

$uniqueSecondaryTextures = @(
    $results |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.SecondaryTexture) } |
    Select-Object -ExpandProperty SecondaryTexture -Unique |
    Sort-Object
)

$summary = New-Object System.Collections.Generic.List[string]

$summary.Add("AoM:EE MTRL Secondary Texture Analysis")
$summary.Add("=======================================")
$summary.Add("")
$summary.Add("MTRL XML files found:           $($files.Count)")
$summary.Add("Successfully processed:         $processed")
$summary.Add("Parse errors:                   $errors")
$summary.Add("")
$summary.Add("Materials with secondary_texture: $($results.Count)")
$summary.Add("Materials where texture == secondary_texture: $($sameBitmapRows.Count)")
$summary.Add("Materials where they differ:    $($differentBitmapRows.Count)")
$summary.Add("")
$summary.Add("Unique secondary textures:       $($uniqueSecondaryTextures.Count)")
$summary.Add("Unique textures used as both texture + secondary_texture: $($uniqueSameBitmapTextures.Count)")
$summary.Add("")

$summary.Add("TEXTURES USED AS BOTH MAIN AND SECONDARY")
$summary.Add("-----------------------------------------")

if ($uniqueSameBitmapTextures.Count -eq 0) {
    $summary.Add("(none)")
}
else {
    foreach ($name in $uniqueSameBitmapTextures) {
        $summary.Add($name)
    }
}

$summary.Add("")
$summary.Add("SAMPLE MATERIAL REFERENCES")
$summary.Add("---------------------------")

foreach ($row in (
    $sameBitmapRows |
    Sort-Object Texture, MaterialFile |
    Select-Object -First 100
)) {
    $summary.Add(
        "{0}`t{1}" -f
        $row.Texture,
        $row.MaterialFile
    )
}

$summary.Add("")
$summary.Add("OUTPUT")
$summary.Add("------")
$summary.Add($OutputCsv)

$summary |
    Set-Content $OutputTxt -Encoding UTF8

Write-Host ""
Write-Host "=========================================="
Write-Host "Analysis complete."
Write-Host ""
Write-Host "Materials with secondary_texture:"
Write-Host $results.Count
Write-Host ""
Write-Host "texture == secondary_texture:"
Write-Host $sameBitmapRows.Count
Write-Host ""
Write-Host "Unique textures in both:"
Write-Host $uniqueSameBitmapTextures.Count
Write-Host ""
Write-Host "Summary:"
Write-Host $OutputTxt
Write-Host "=========================================="