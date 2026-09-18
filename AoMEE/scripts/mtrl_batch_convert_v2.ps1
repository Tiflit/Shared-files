$Project = "D:\AI_upscaling\AoMEE"

$SourceRoot = "$Project\Age of Mythology\materials"
$OutputRoot = "$Project\reports\materials_xml"
$Converter  = "$Project\tools\AoM File Converter\AoM File Converter.exe"

$LogFile   = "$Project\reports\mtrl_conversion_log.txt"
$ErrorFile = "$Project\reports\mtrl_conversion_errors.txt"

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

if (-not (Test-Path $LogFile)) {
    Set-Content -LiteralPath $LogFile `
        -Value "AoM:EE MTRL batch conversion" `
        -Encoding UTF8
}

if (-not (Test-Path $ErrorFile)) {
    Set-Content -LiteralPath $ErrorFile `
        -Value "AoM:EE MTRL conversion errors" `
        -Encoding UTF8
}

$mtrlFiles = Get-ChildItem `
    -LiteralPath $SourceRoot `
    -Recurse `
    -File `
    -Filter "*.mtrl" `
    -ErrorAction Stop

$total = $mtrlFiles.Count

$success = 0
$skipped = 0
$failed  = 0

Write-Host ""
Write-Host "=============================================="
Write-Host "AoM:EE MTRL Batch Converter"
Write-Host "=============================================="
Write-Host ""
Write-Host "MTRL files found: $total"
Write-Host ""
Write-Host "Starting..."
Write-Host ""

$startTime = Get-Date
$number = 0

foreach ($sourceFile in $mtrlFiles) {

    $number++

    $relative = $sourceFile.FullName.Substring(
        $SourceRoot.Length
    ).TrimStart('\')

    $outputMtrl = Join-Path $OutputRoot $relative
    $outputXml  = "$outputMtrl.xml"
    $outputDir  = Split-Path $outputMtrl -Parent

    New-Item `
        -ItemType Directory `
        -Path $outputDir `
        -Force |
        Out-Null

    # Already completed.
    if (Test-Path $outputXml) {

        $skipped++
        continue
    }

    try {

        # Copy source MTRL to the staging tree.
        if (-not (Test-Path $outputMtrl)) {

            Copy-Item `
                -LiteralPath $sourceFile.FullName `
                -Destination $outputMtrl `
                -Force `
                -ErrorAction Stop
        }

        # Start converter.
        $process = Start-Process `
            -FilePath $Converter `
            -ArgumentList ('"' + $outputMtrl + '"') `
            -PassThru `
            -WindowStyle Hidden

        # Wait ONLY for the XML to appear.
        $converted = $false

        for ($i = 0; $i -lt 300; $i++) {

            if (Test-Path $outputXml) {
                $converted = $true
                break
            }

            Start-Sleep -Milliseconds 100
        }

        if ($converted) {

            $success++

            # Conversion is finished. We no longer need the converter process.
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                }
            }
            catch {}

        }
        else {

            $failed++

            Add-Content `
                -LiteralPath $ErrorFile `
                -Value "TIMEOUT`t$($sourceFile.FullName)"

            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                }
            }
            catch {}
        }

    }
    catch {

        $failed++

        Add-Content `
            -LiteralPath $ErrorFile `
            -Value "ERROR`t$($sourceFile.FullName)`t$($_.Exception.Message)"
    }

    if (
        ($number % 100) -eq 0 -or
        $number -eq $total
    ) {

        $elapsed = (Get-Date) - $startTime

        if ($number -gt 0) {
            $rate = $number / [math]::Max($elapsed.TotalMinutes, 0.001)
            $remaining = ($total - $number) / [math]::Max($rate, 0.001)
        }
        else {
            $remaining = 0
        }

        $percent = [math]::Round(
            ($number / $total) * 100,
            1
        )

        Write-Host (
            "{0}/{1} ({2}%)  Success={3}  Skipped={4}  Failed={5}  ETA={6} min" -f `
            $number,
            $total,
            $percent,
            $success,
            $skipped,
            $failed,
            [math]::Round($remaining, 1)
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
Write-Host "Errors:"
Write-Host $ErrorFile