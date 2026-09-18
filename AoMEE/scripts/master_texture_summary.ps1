$ErrorActionPreference = 'Stop'

$Root       = 'D:\AI_upscaling\AoMEE'
$Extracted  = Join-Path $Root 'extracted'
$Recovered  = Join-Path $Extracted 'patched_to_verify'
$Game       = Join-Path $Root 'Age of Mythology'
$Reports    = Join-Path $Root 'reports'

$Manifest  = Join-Path $Reports 'master_texture_manifest.csv'
$Summary   = Join-Path $Reports 'master_texture_manifest_summary.txt'

New-Item -ItemType Directory -Force -Path $Reports | Out-Null

Write-Host "Scanning normal extracted TGAs..." -ForegroundColor Cyan

# ------------------------------------------------------------
# Helper: read TGA header
# ------------------------------------------------------------
function Read-TgaHeader {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $br = New-Object System.IO.BinaryReader($fs)

        if ($fs.Length -lt 18) {
            return [PSCustomObject]@{
                Width = $null
                Height = $null
                ImageType = $null
                BitsPerPixel = $null
            }
        }

        [void]$br.ReadBytes(2)       # ID length + color map type
        $imageType = $br.ReadByte()

        [void]$br.ReadBytes(9)

        $width  = $br.ReadUInt16()
        $height = $br.ReadUInt16()
        $bpp    = $br.ReadByte()

        return [PSCustomObject]@{
            Width        = $width
            Height       = $height
            ImageType    = $imageType
            BitsPerPixel = $bpp
        }
    }
    finally {
        if ($br) { $br.Dispose() }
        else { $fs.Dispose() }
    }
}

# ------------------------------------------------------------
# Normalize relative paths so comparisons are case-insensitive
# ------------------------------------------------------------
function Normalize-RelPath {
    param([string]$Path)

    return (($Path -replace '/', '\').TrimStart('\')).ToLowerInvariant()
}

# ------------------------------------------------------------
# Build ORIGINAL DDT lookup
# ------------------------------------------------------------
Write-Host "Scanning original game DDTs..." -ForegroundColor Cyan

$OriginalDdtLookup = @{}
$OriginalDdtCount = 0

if (Test-Path $Game) {
    Get-ChildItem -LiteralPath $Game -Recurse -File |
        Where-Object { $_.Extension -ieq '.ddt' } |
        ForEach-Object {

            $rel = $_.FullName.Substring($Game.Length).TrimStart('\')
            $key = Normalize-RelPath $rel

            if (-not $OriginalDdtLookup.ContainsKey($key)) {
                $OriginalDdtLookup[$key] = $_.FullName
            }

            $OriginalDdtCount++
        }
}

Write-Host "Original DDTs found: $OriginalDdtCount" -ForegroundColor Green

# ------------------------------------------------------------
# Scan normal extraction
# ------------------------------------------------------------
$Records = New-Object System.Collections.Generic.List[object]

$NormalTgas = @()

if (Test-Path $Extracted) {
    $NormalTgas = Get-ChildItem -LiteralPath $Extracted -Recurse -File |
        Where-Object {
            $_.Extension -ieq '.tga' -and
            $_.FullName -notlike "$Recovered\*"
        }
}

Write-Host "Normal extracted TGAs: $($NormalTgas.Count)" -ForegroundColor Green

foreach ($file in $NormalTgas) {

    $rel = $file.FullName.Substring($Extracted.Length).TrimStart('\')
    $key = Normalize-RelPath $rel

    try {
        $header = Read-TgaHeader -Path $file.FullName
    }
    catch {
        $header = [PSCustomObject]@{
            Width = $null
            Height = $null
            ImageType = $null
            BitsPerPixel = $null
        }
    }

    $btiPath = [System.IO.Path]::ChangeExtension($file.FullName, '.bti')

    # Match original DDT by relative path:
    $ddtRel = [System.IO.Path]::ChangeExtension($rel, '.ddt')
    $ddtKey = Normalize-RelPath $ddtRel

    $ddtFound = $OriginalDdtLookup.ContainsKey($ddtKey)

    $Records.Add([PSCustomObject]@{
        RelativePath       = $rel
        SourceType         = 'NormalExtraction'
        TgaPath            = $file.FullName
        BtiPath             = if (Test-Path $btiPath) { $btiPath } else { '' }
        OriginalDdtPath     = if ($ddtFound) { $OriginalDdtLookup[$ddtKey] } else { '' }
        Width               = $header.Width
        Height              = $header.Height
        TgaImageType        = $header.ImageType
        BitsPerPixel        = $header.BitsPerPixel
        TgaBytes            = $file.Length
        BtiFound             = (Test-Path $btiPath)
        OriginalDdtFound    = $ddtFound
        ProcessingEligible  = $true
        DuplicateRelativePath = $false
    })
}

# ------------------------------------------------------------
# Scan recovered exceptions
# ------------------------------------------------------------
$RecoveredTgas = @()

if (Test-Path $Recovered) {
    $RecoveredTgas = Get-ChildItem -LiteralPath $Recovered -Recurse -File |
        Where-Object { $_.Extension -ieq '.tga' }
}

Write-Host "Recovered exception TGAs: $($RecoveredTgas.Count)" -ForegroundColor Green

foreach ($file in $RecoveredTgas) {

    $rel = $file.FullName.Substring($Recovered.Length).TrimStart('\')
    $key = Normalize-RelPath $rel

    try {
        $header = Read-TgaHeader -Path $file.FullName
    }
    catch {
        $header = [PSCustomObject]@{
            Width = $null
            Height = $null
            ImageType = $null
            BitsPerPixel = $null
        }
    }

    $btiPath = [System.IO.Path]::ChangeExtension($file.FullName, '.bti')

    $ddtRel = [System.IO.Path]::ChangeExtension($rel, '.ddt')
    $ddtKey = Normalize-RelPath $ddtRel

    $ddtFound = $OriginalDdtLookup.ContainsKey($ddtKey)

    $duplicate = @(
        $Records | Where-Object {
            (Normalize-RelPath $_.RelativePath) -eq $key
        }
    ).Count -gt 0

    $Records.Add([PSCustomObject]@{
        RelativePath       = $rel
        SourceType         = 'RecoveredException'
        TgaPath            = $file.FullName
        BtiPath             = if (Test-Path $btiPath) { $btiPath } else { '' }
        OriginalDdtPath     = if ($ddtFound) { $OriginalDdtLookup[$ddtKey] } else { '' }
        Width               = $header.Width
        Height              = $header.Height
        TgaImageType        = $header.ImageType
        BitsPerPixel        = $header.BitsPerPixel
        TgaBytes            = $file.Length
        BtiFound             = (Test-Path $btiPath)
        OriginalDdtFound    = $ddtFound
        ProcessingEligible  = -not $duplicate
        DuplicateRelativePath = $duplicate
    })
}

# ------------------------------------------------------------
# Find duplicate logical paths
# ------------------------------------------------------------
$Groups = $Records |
    Group-Object { Normalize-RelPath $_.RelativePath }

foreach ($group in $Groups) {
    if ($group.Count -gt 1) {
        foreach ($item in $group.Group) {
            $item.DuplicateRelativePath = $true
            $item.ProcessingEligible = $false
        }
    }
}

# ------------------------------------------------------------
# Find original DDTs that have no extracted TGA
# ------------------------------------------------------------
$ExtractedDdtKeys = @{}

foreach ($record in $Records) {
    $ddtRel = [System.IO.Path]::ChangeExtension($record.RelativePath, '.ddt')
    $ExtractedDdtKeys[(Normalize-RelPath $ddtRel)] = $true
}

$MissingExtractionDdt = New-Object System.Collections.Generic.List[object]

foreach ($key in $OriginalDdtLookup.Keys) {

    if (-not $ExtractedDdtKeys.ContainsKey($key)) {
        $MissingExtractionDdt.Add([PSCustomObject]@{
            RelativeDdtPath = $key
            OriginalDdtPath = $OriginalDdtLookup[$key]
        })
    }
}

$MissingExtractionPath = Join-Path $Reports 'master_texture_manifest_missing_ddt.csv'

$MissingExtractionDdt |
    Sort-Object RelativeDdtPath |
    Export-Csv -LiteralPath $MissingExtractionPath -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# Export master manifest
# ------------------------------------------------------------
$Records |
    Sort-Object RelativePath, SourceType |
    Export-Csv -LiteralPath $Manifest -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# Statistics
# ------------------------------------------------------------
$TotalRecords       = $Records.Count
$NormalCount        = @($Records | Where-Object SourceType -eq 'NormalExtraction').Count
$RecoveredCount     = @($Records | Where-Object SourceType -eq 'RecoveredException').Count
$DuplicateCount     = @($Records | Where-Object DuplicateRelativePath).Count
$EligibleCount      = @($Records | Where-Object ProcessingEligible).Count
$MissingBtiCount    = @($Records | Where-Object { -not $_.BtiFound }).Count
$MissingDdtCount    = $MissingExtractionDdt.Count
$32BitCount         = @($Records | Where-Object BitsPerPixel -eq 32).Count
$RleCount           = @($Records | Where-Object TgaImageType -eq 10).Count
$UncompressedCount  = @($Records | Where-Object TgaImageType -eq 2).Count

$DimensionGroups = $Records |
    Group-Object Width,Height |
    Sort-Object Count -Descending |
    Select-Object -First 20

# ------------------------------------------------------------
# Summary text
# ------------------------------------------------------------
$summaryLines = New-Object System.Collections.Generic.List[string]

$summaryLines.Add("AoMEE MASTER TEXTURE MANIFEST")
$summaryLines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$summaryLines.Add("")
$summaryLines.Add("SOURCE POPULATIONS")
$summaryLines.Add("Original DDTs scanned:           $OriginalDdtCount")
$summaryLines.Add("Normal extracted TGAs:           $NormalCount")
$summaryLines.Add("Recovered exception TGAs:        $RecoveredCount")
$summaryLines.Add("Combined TGA records:             $TotalRecords")
$summaryLines.Add("")
$summaryLines.Add("INTEGRITY")
$summaryLines.Add("Unique processing-eligible TGAs:  $EligibleCount")
$summaryLines.Add("Duplicate logical paths:          $DuplicateCount")
$summaryLines.Add("TGAs missing BTI:                 $MissingBtiCount")
$summaryLines.Add("Original DDTs without TGA:        $MissingDdtCount")
$summaryLines.Add("")
$summaryLines.Add("TGA FORMAT")
$summaryLines.Add("32-bit TGAs:                      $32BitCount")
$summaryLines.Add("RLE true-color (type 10):         $RleCount")
$summaryLines.Add("Uncompressed true-color (type 2): $UncompressedCount")
$summaryLines.Add("")
$summaryLines.Add("MOST COMMON DIMENSIONS")

foreach ($g in $DimensionGroups) {
    $dims = $g.Name -replace '^(.+),(.+)$','$1 x $2'
    $summaryLines.Add(("  {0,-15} {1}" -f $dims, $g.Count))
}

$summaryLines.Add("")
$summaryLines.Add("OUTPUT")
$summaryLines.Add("Master manifest:")
$summaryLines.Add("  $Manifest")
$summaryLines.Add("Original DDTs with no extracted TGA:")
$summaryLines.Add("  $MissingExtractionPath")

$summaryLines | Set-Content -LiteralPath $Summary -Encoding UTF8

# ------------------------------------------------------------
# Console result
# ------------------------------------------------------------
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " AoMEE MASTER TEXTURE MANIFEST COMPLETE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Original DDTs:              $OriginalDdtCount"
Write-Host "Normal extracted TGAs:      $NormalCount"
Write-Host "Recovered TGAs:             $RecoveredCount"
Write-Host "Combined TGA records:        $TotalRecords"
Write-Host "Processing eligible:         $EligibleCount"
Write-Host "Duplicate logical paths:     $DuplicateCount"
Write-Host "Missing BTIs:                $MissingBtiCount"
Write-Host "DDTs without TGA:            $MissingDdtCount"
Write-Host ""
Write-Host "Manifest:"
Write-Host $Manifest -ForegroundColor Green
Write-Host ""
Write-Host "Summary:"
Write-Host $Summary -ForegroundColor Green
Write-Host ""
Write-Host "Unextracted DDT report:"
Write-Host $MissingExtractionPath -ForegroundColor Green