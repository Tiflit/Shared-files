$Project = "D:\AI_upscaling\AoMEE"

$Extracted = "$Project\extracted"
$OutputCsv = "$Project\reports\player_color_bti.csv"
$OutputTxt = "$Project\reports\player_color_bti_summary.txt"

if (-not (Test-Path $Extracted)) {
    Write-Host "ERROR: Extracted directory not found:"
    Write-Host $Extracted
    exit
}

$btiFiles = Get-ChildItem `
    -LiteralPath $Extracted `
    -Recurse `
    -File `
    -Filter "*.bti" `
    -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "BTI files found: $($btiFiles.Count)"
Write-Host "Scanning for noalphatest..."
Write-Host ""

$results = New-Object System.Collections.Generic.List[object]

$count = 0

foreach ($file in $btiFiles) {

    $count++

    if (($count % 1000) -eq 0) {
        Write-Host "Scanned $count / $($btiFiles.Count)"
    }

    try {
        $matches = Select-String `
            -LiteralPath $file.FullName `
            -Pattern "noalphatest" `
            -SimpleMatch `
            -CaseSensitive:$false `
            -ErrorAction SilentlyContinue
    }
    catch {
        continue
    }

    if ($null -eq $matches) {
        continue
    }

    foreach ($match in $matches) {

        $results.Add(
            [PSCustomObject]@{
                BTIFile   = $file.FullName
                Filename  = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                Line      = $match.Line.Trim()
            }
        )
    }
}

$results |
    Sort-Object BTIFile |
    Export-Csv `
        -LiteralPath $OutputCsv `
        -NoTypeInformation `
        -Encoding UTF8

$summary = @()

$summary += "AoM:EE Player-Color BTI Report"
$summary += "=============================="
$summary += ""
$summary += "BTI files scanned: $($btiFiles.Count)"
$summary += "BTI files containing noalphatest: $(($results | Select-Object -ExpandProperty BTIFile -Unique).Count)"
$summary += "Total noalphatest matches: $($results.Count)"
$summary += ""
$summary += "PLAYER-COLOR CANDIDATES"
$summary += "-----------------------"

$results |
    Select-Object Filename -Unique |
    Sort-Object Filename |
    ForEach-Object {
        $summary += $_.Filename
    }

$summary += ""
$summary += "OUTPUT"
$summary += "------"
$summary += $OutputCsv
$summary += $OutputTxt

$summary |
    Set-Content -LiteralPath $OutputTxt -Encoding UTF8

Write-Host ""
Write-Host "=============================="
Write-Host "DONE"
Write-Host "=============================="
Write-Host ""
Write-Host "BTI files scanned: $($btiFiles.Count)"
Write-Host "noalphatest BTIs: $(($results | Select-Object -ExpandProperty BTIFile -Unique).Count)"
Write-Host ""
Write-Host "Report:"
Write-Host $OutputTxt