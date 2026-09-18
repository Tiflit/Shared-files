$Project = "D:\AI_upscaling\AoMEE"

$SourceRoot = "$Project\Age of Mythology\materials"
$OutputRoot = "$Project\reports\materials_xml"
$Converter  = "$Project\tools\AoM File Converter\AoM File Converter.exe"

$LogFile    = "$Project\reports\mtrl_conversion_log.txt"
$ErrorFile  = "$Project\reports\mtrl_conversion_errors.txt"

if (-not (Test-Path $SourceRoot)) {
    Write-Host "ERROR: Source directory not found:"
    Write-Host $SourceRoot
    exit
}

if (-not (Test-Path $Converter)) {
    Write-Host "ERROR: Converter not found:"
    Write-Host $Converter
    exit
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

# Start a fresh log only if one doesn't already exist.
if (-not (Test-Path $LogFile)) {
    Set-Content -LiteralPath $LogFile -Value "AoM:EE MTRL batch conversion" -Encoding UTF8
    Add-Content -LiteralPath $LogFile -Value "Started: $(Get-Date)"
}

if (-not (Test-Path $ErrorFile)) {
    Set-Content -LiteralPath $ErrorFile -Value "AoM:EE MTRL conversion errors" -Encoding UTF8
}

$mtrlFiles = Get-ChildItem `
    -LiteralPath $SourceRoot `
    -Recurse `
    -File `
    -Filter "*.mtrl" `
    -ErrorAction Stop

$total = $mtrlFiles.Count
$processed = 0
$skipped = 0
$success = 0
$failed = 0

Write-Host ""
Write-Host "=============================================="
Write-Host "AoM:EE MTRL Batch Converter"
Write-Host "=============================================="
Write-Host ""
Write-Host "MTRL files found: $total"
Write-Host "Output directory:"
Write-Host $OutputRoot
Write-Host ""
Write-Host "Starting..."
Write-Host ""

foreach ($sourceFile in $mtrlFiles) {

    $processed++

    # Calculate path relative to the clean materials directory.
    $relativePath = $sourceFile.FullName.Substring(
        $SourceRoot.Length
    ).TrimStart('\')

    $outputMtrl = Join-Path $OutputRoot $relativePath
    $outputDir  = Split-Path $outputMtrl -Parent
    $outputXml  = "$outputMtrl.xml"

    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

    # Resume support.
    if (Test-Path $outputXml) {
        $skipped++
        continue
    }

    try {

        # Copy the original MTRL into the staging tree.
        Copy-Item `
            -LiteralPath $sourceFile.FullName `
            -Destination $outputMtrl `
            -Force `
            -ErrorAction Stop

        # Run converter and wait for it to finish.
        $argument = '"' + $outputMtrl + '"'

        $process = Start-Process `
            -FilePath $Converter `
            -ArgumentList $argument `
            -PassThru `
            -WindowStyle Hidden

        $finished = $process.WaitForExit(60000)

        if (-not $finished) {

            try {
                $process.Kill()
            }
            catch {}

            $failed++

            Add-Content `
                -LiteralPath $ErrorFile `
                -Value "TIMEOUT`t$($sourceFile.FullName)"

            Write-Host ""
            Write-Host "TIMEOUT:"
            Write-Host $sourceFile.Name

            continue
        }

        if (Test-Path $outputXml) {

            $success++

        }
        else {

            $failed++

            Add-Content `
                -LiteralPath $ErrorFile `
                -Value "NO_XML`t$($sourceFile.FullName)`tExitCode=$($process.ExitCode)"
        }

    }
    catch {

        $failed++

        Add-Content `
            -LiteralPath $ErrorFile `
            -Value "ERROR`t$($sourceFile.FullName)`t$($_.Exception.Message)"
    }

    # Progress every 100 files.
    if (($processed % 100) -eq 0 -or $processed -eq $total) {

        $percent = [math]::Round(
            ($processed / $total) * 100,
            1
        )

        Write-Host (
            "{0}/{1} ({2}%)  Success={3}  Skipped={4}  Failed={5}" -f `
            $processed,
            $total,
            $percent,
            $success,
            $skipped,
            $failed
        )
    }
}

Add-Content -LiteralPath $LogFile -Value ""
Add-Content -LiteralPath $LogFile -Value "Finished: $(Get-Date)"
Add-Content -LiteralPath $LogFile -Value "Total:   $total"
Add-Content -LiteralPath $LogFile -Value "Success: $success"
Add-Content -LiteralPath $LogFile -Value "Skipped: $skipped"
Add-Content -LiteralPath $LogFile -Value "Failed:  $failed"

Write-Host ""
Write-Host "=============================================="
Write-Host "CONVERSION COMPLETE"
Write-Host "=============================================="
Write-Host ""
Write-Host "Total:   $total"
Write-Host "Success: $success"
Write-Host "Skipped: $skipped"
Write-Host "Failed:  $failed"
Write-Host ""
Write-Host "XML output:"
Write-Host $OutputRoot
Write-Host ""
Write-Host "Error log:"
Write-Host $ErrorFile