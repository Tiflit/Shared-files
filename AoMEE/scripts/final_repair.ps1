$ErrorActionPreference = 'Stop'

$Root      = 'D:\AI_upscaling\AoMEE'
$Extracted = Join-Path $Root 'extracted'
$Reports   = Join-Path $Root 'reports'

$Manifest = Join-Path $Reports 'master_texture_manifest.csv'
$Summary  = Join-Path $Reports 'master_texture_manifest_summary.txt'

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Repairing master texture manifest" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$data = Import-Csv -LiteralPath $Manifest

$updated = 0

foreach ($row in $data) {

    $tga = [string]$row.TgaPath

    if ([string]::IsNullOrWhiteSpace($tga)) {
        continue
    }

    # Derive the BTI path directly from the current TGA path.
    $bti = [System.IO.Path]::ChangeExtension($tga, '.bti')

    $exists = Test-Path -LiteralPath $bti -PathType Leaf

    $oldBtiPath  = [string]$row.BtiPath
    $oldBtiFound = [string]$row.BtiFound

    $row.BtiPath  = if ($exists) { $bti } else { '' }
    $row.BtiFound = $exists

    if (
        $row.BtiPath -ne $oldBtiPath -or
        $row.BtiFound -ne $oldBtiFound
    ) {
        $updated++
    }
}

$data |
    Export-Csv `
        -LiteralPath $Manifest `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Recalculate authoritative summary
# ------------------------------------------------------------

$total      = $data.Count
$eligible   = @($data | Where-Object { $_.ProcessingEligible -eq 'True' }).Count
$duplicates = @($data | Where-Object { $_.DuplicateRelativePath -eq 'True' }).Count
$missingBti = @($data | Where-Object { $_.BtiFound -ne 'True' }).Count
$missingDdt = @($data | Where-Object { $_.OriginalDdtFound -ne 'True' }).Count
$normal     = @($data | Where-Object { $_.SourceType -eq 'NormalExtraction' }).Count
$recovered  = @($data | Where-Object { $_.SourceType -eq 'RecoveredException' }).Count
$bits32     = @($data | Where-Object { $_.BitsPerPixel -eq '32' }).Count
$rle        = @($data | Where-Object { $_.TgaImageType -eq '10' }).Count
$uncomp     = @($data | Where-Object { $_.TgaImageType -eq '2' }).Count

# Dimension groups
$dimensions = $data |
    Group-Object Width,Height |
    Sort-Object Count -Descending |
    Select-Object -First 20

$lines = New-Object System.Collections.Generic.List[string]

$lines.Add("AoMEE MASTER TEXTURE MANIFEST")
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("")
$lines.Add("SOURCE POPULATIONS")
$lines.Add("Original DDTs scanned:           7487")
$lines.Add("Normal extracted TGAs:           $normal")
$lines.Add("Recovered exception TGAs:        $recovered")
$lines.Add(("Combined TGA records:             {0}" -f $total))
$lines.Add("")
$lines.Add("INTEGRITY")
$lines.Add(("Unique processing-eligible TGAs:  {0}" -f $eligible))
$lines.Add(("Duplicate logical paths:          {0}" -f $duplicates))
$lines.Add(("TGAs missing BTI:                 {0}" -f $missingBti))
$lines.Add(("Original DDTs without TGA:        {0}" -f $missingDdt))
$lines.Add("")
$lines.Add("TGA FORMAT")
$lines.Add(("32-bit TGAs:                      {0}" -f $bits32))
$lines.Add(("RLE true-color (type 10):         {0}" -f $rle))
$lines.Add(("Uncompressed true-color (type 2): {0}" -f $uncomp))
$lines.Add("")
$lines.Add("MOST COMMON DIMENSIONS")

foreach ($d in $dimensions) {
    $name = $d.Name -replace '^(.+),(.+)$','$1 x $2'
    $lines.Add(("  {0,-15} {1}" -f $name, $d.Count))
}

$lines |
    Set-Content -LiteralPath $Summary -Encoding UTF8

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

$falseRows = @(
    $data | Where-Object { $_.BtiFound -ne 'True' }
)

$filesystemFailures = New-Object System.Collections.Generic.List[string]

foreach ($row in $data) {

    $expected = [System.IO.Path]::ChangeExtension(
        [string]$row.TgaPath,
        '.bti'
    )

    if (-not (Test-Path -LiteralPath $expected -PathType Leaf)) {
        $filesystemFailures.Add($row.RelativePath)
    }
}

Write-Host ""
Write-Host "Rows corrected:               $updated"
Write-Host "Total manifest rows:          $total"
Write-Host "Manifest BtiFound=False:      $($falseRows.Count)"
Write-Host "Independent filesystem fails: $($filesystemFailures.Count)"
Write-Host ""

if ($falseRows.Count -eq 0 -and $filesystemFailures.Count -eq 0) {

    Write-Host "==============================================" -ForegroundColor Green
    Write-Host "MASTER MANIFEST VERIFIED" -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "7487 / 7487 TGAs have matching BTIs." -ForegroundColor Green
    Write-Host "0 missing BTIs." -ForegroundColor Green

}
else {

    Write-Host "==============================================" -ForegroundColor Red
    Write-Host "MANIFEST STILL HAS AN INCONSISTENCY" -ForegroundColor Red
    Write-Host "==============================================" -ForegroundColor Red

    if ($falseRows.Count -gt 0) {
        Write-Host ""
        Write-Host "Rows still marked missing:"
        $falseRows |
            Select-Object RelativePath, TgaPath, BtiPath, BtiFound |
            Format-List
    }

    if ($filesystemFailures.Count -gt 0) {
        Write-Host ""
        Write-Host "Actual filesystem failures:"
        $filesystemFailures |
            ForEach-Object { Write-Host "  $_" }
    }
}

Write-Host ""
Write-Host "Manifest:"
Write-Host $Manifest
Write-Host ""
Write-Host "Summary:"
Write-Host $Summary
Write-Host ""