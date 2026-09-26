$ErrorActionPreference = 'Stop'

$Root      = 'D:\AI_upscaling\AoMEE'
$Extracted = Join-Path $Root 'extracted'
$Game      = Join-Path $Root 'Age of Mythology'
$Tools     = Join-Path $Root 'tools'
$Reports   = Join-Path $Root 'reports'

$MissingCsv = Join-Path $Reports 'bti_missing_expected.csv'
$OrphanCsv  = Join-Path $Reports 'bti_orphaned.csv'

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "AoM:EE BTI consistency diagnostic" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# 1. Build TGA -> expected BTI map
# ------------------------------------------------------------

$Tgas = @(
    Get-ChildItem -LiteralPath $Extracted -Recurse -File |
        Where-Object { $_.Extension -ieq '.tga' }
)

$BtiFiles = @(
    Get-ChildItem -LiteralPath $Extracted -Recurse -File |
        Where-Object { $_.Extension -ieq '.bti' }
)

Write-Host "TGAs found:  $($Tgas.Count)"
Write-Host "BTIs found:  $($BtiFiles.Count)"
Write-Host ""

$Missing = New-Object System.Collections.Generic.List[object]

foreach ($tga in $Tgas) {

    $expectedBti = [System.IO.Path]::ChangeExtension(
        $tga.FullName,
        '.bti'
    )

    if (-not (Test-Path -LiteralPath $expectedBti -PathType Leaf)) {

        $relative = $tga.FullName.Substring(
            $Extracted.Length
        ).TrimStart('\')

        $Missing.Add([PSCustomObject]@{
            TGA           = $tga.FullName
            RelativeTGA   = $relative
            ExpectedBTI   = $expectedBti
            TGABytes      = $tga.Length
        })
    }
}

# ------------------------------------------------------------
# 2. Build expected BTI map and find orphan BTIs
# ------------------------------------------------------------

$ExpectedBtiKeys = @{}

foreach ($tga in $Tgas) {

    $expectedBti = [System.IO.Path]::ChangeExtension(
        $tga.FullName,
        '.bti'
    )

    $key = $expectedBti.ToLowerInvariant()

    $ExpectedBtiKeys[$key] = $true
}

$Orphans = New-Object System.Collections.Generic.List[object]

foreach ($bti in $BtiFiles) {

    $key = $bti.FullName.ToLowerInvariant()

    if (-not $ExpectedBtiKeys.ContainsKey($key)) {

        $relative = $bti.FullName.Substring(
            $Extracted.Length
        ).TrimStart('\')

        $Orphans.Add([PSCustomObject]@{
            BTI         = $bti.FullName
            RelativeBTI = $relative
            Bytes       = $bti.Length
        })
    }
}

$Missing |
    Export-Csv -LiteralPath $MissingCsv -NoTypeInformation -Encoding UTF8

$Orphans |
    Export-Csv -LiteralPath $OrphanCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 3. Display exact problem
# ------------------------------------------------------------

Write-Host "EXPECTED BTI MISSING" -ForegroundColor Yellow
Write-Host "--------------------"

if ($Missing.Count -eq 0) {
    Write-Host "None." -ForegroundColor Green
}
else {
    foreach ($m in $Missing) {
        Write-Host ""
        Write-Host "TGA:" -ForegroundColor Yellow
        Write-Host "  $($m.TGA)"
        Write-Host "Expected BTI:"
        Write-Host "  $($m.ExpectedBTI)"
        Write-Host "TGA size: $($m.TGABytes) bytes"
    }
}

Write-Host ""
Write-Host "ORPHAN BTIs" -ForegroundColor Yellow
Write-Host "-----------"

if ($Orphans.Count -eq 0) {
    Write-Host "None." -ForegroundColor Green
}
else {
    foreach ($o in $Orphans) {
        Write-Host ""
        Write-Host "BTI:" -ForegroundColor Yellow
        Write-Host "  $($o.BTI)"
        Write-Host "Size: $($o.Bytes) bytes"
    }
}

# ------------------------------------------------------------
# 4. Search specifically for the known missing Anubite BTI
# ------------------------------------------------------------

$KnownName = 'special e anubite[pixelxform1].bti'

Write-Host ""
Write-Host "SEARCHING FOR:" -ForegroundColor Cyan
Write-Host "  $KnownName"

$KnownMatches = @(
    Get-ChildItem `
        -LiteralPath $Root `
        -Recurse `
        -File `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ieq $KnownName
        }
)

if ($KnownMatches.Count -eq 0) {
    Write-Host "  No matching BTI exists anywhere in the project." -ForegroundColor Red
}
else {
    foreach ($match in $KnownMatches) {
        Write-Host ""
        Write-Host "  FOUND:" -ForegroundColor Green
        Write-Host "  $($match.FullName)"
        Write-Host "  Size: $($match.Length) bytes"
    }
}

# ------------------------------------------------------------
# 5. If the known BTI exists elsewhere, copy it to its
#    canonical location.
# ------------------------------------------------------------

$KnownTga = Join-Path `
    $Extracted `
    'textures\special e anubite[pixelxform1].tga'

$KnownExpectedBti = [System.IO.Path]::ChangeExtension(
    $KnownTga,
    '.bti'
)

if (
    (-not (Test-Path -LiteralPath $KnownExpectedBti -PathType Leaf)) -and
    ($KnownMatches.Count -eq 1)
) {

    $source = $KnownMatches[0].FullName

    Write-Host ""
    Write-Host "One misplaced matching BTI was found." -ForegroundColor Yellow
    Write-Host "Copying it to the canonical location..."

    Copy-Item `
        -LiteralPath $source `
        -Destination $KnownExpectedBti `
        -Force

    Write-Host "  Installed:" -ForegroundColor Green
    Write-Host "  $KnownExpectedBti"
}

# ------------------------------------------------------------
# 6. If still missing, recreate from pristine DDT.
# ------------------------------------------------------------

if (
    (-not (Test-Path -LiteralPath $KnownExpectedBti -PathType Leaf)) -and
    (Test-Path -LiteralPath $KnownTga -PathType Leaf)
) {

    $KnownDdt = Join-Path `
        $Game `
        'textures\special e anubite[pixelxform1].ddt'

    $Extractor = Join-Path $Tools 'TextureExtractor.exe'

    if (Test-Path -LiteralPath $KnownDdt -PathType Leaf) {

        Write-Host ""
        Write-Host "The BTI is still missing." -ForegroundColor Yellow
        Write-Host "Re-extracting the pristine Anubite DDT..."

        & $Extractor `
            -i $KnownDdt `
            -o $KnownTga

        if ($LASTEXITCODE -ne 0) {
            throw "TextureExtractor failed with exit code $LASTEXITCODE."
        }

        if (-not (Test-Path -LiteralPath $KnownExpectedBti -PathType Leaf)) {
            throw "TextureExtractor completed but the Anubite BTI is still missing."
        }

        Write-Host "  Anubite TGA: OK" -ForegroundColor Green
        Write-Host "  Anubite BTI: OK" -ForegroundColor Green
    }
}

# ------------------------------------------------------------
# 7. Final consistency check
# ------------------------------------------------------------

$TgasFinal = @(
    Get-ChildItem -LiteralPath $Extracted -Recurse -File |
        Where-Object { $_.Extension -ieq '.tga' }
)

$BtiFinal = @(
    Get-ChildItem -LiteralPath $Extracted -Recurse -File |
        Where-Object { $_.Extension -ieq '.bti' }
)

$FinalMissing = @()

foreach ($tga in $TgasFinal) {

    $expectedBti = [System.IO.Path]::ChangeExtension(
        $tga.FullName,
        '.bti'
    )

    if (-not (Test-Path -LiteralPath $expectedBti -PathType Leaf)) {
        $FinalMissing += $tga.FullName
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "FINAL BTI CONSISTENCY CHECK" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "TGAs:             $($TgasFinal.Count)"
Write-Host "BTIs:             $($BtiFinal.Count)"
Write-Host "Missing siblings: $($FinalMissing.Count)"
Write-Host ""

if ($FinalMissing.Count -eq 0) {
    Write-Host "ALL TGA FILES HAVE A MATCHING BTI." -ForegroundColor Green
}
else {
    Write-Host "MISSING BTI FILES:" -ForegroundColor Red

    foreach ($path in $FinalMissing) {
        Write-Host "  $path"
    }
}

Write-Host ""
Write-Host "Reports:"
Write-Host "  $MissingCsv"
Write-Host "  $OrphanCsv"
Write-Host ""