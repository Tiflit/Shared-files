$Project = "D:\AI_upscaling\AoMEE"

$Extracted = "$Project\extracted"

$OutCsv = "$Project\reports\bti_metadata_analysis.csv"
$OutTxt = "$Project\reports\bti_metadata_analysis_summary.txt"

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
Write-Host "BTI files: $($btiFiles.Count)"
Write-Host "Reading metadata..."
Write-Host ""

$results = @()

$count = 0

foreach ($file in $btiFiles) {

    $count++

    if (($count % 1000) -eq 0) {
        Write-Host "Processed $count / $($btiFiles.Count)"
    }

    try {
        $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
    }
    catch {
        continue
    }

    $noAlphaTest = $false
    $alphaBits = ""
    $format = ""

    if ($text -match '(?i)\bnoalphatest\b') {
        $noAlphaTest = $true
    }

    if ($text -match '(?i)\balpha\s*=\s*(\d+)') {
        $alphaBits = $Matches[1]
    }

    if ($text -match '(?i)\bfmt\s*=\s*([A-Za-z0-9_]+)') {
        $format = $Matches[1]
    }

    $results += [PSCustomObject]@{
        Filename    = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        BTIFile     = $file.FullName
        NoAlphaTest = $noAlphaTest
        AlphaBits   = $alphaBits
        Format      = $format
    }
}

$results |
    Export-Csv `
        -LiteralPath $OutCsv `
        -NoTypeInformation `
        -Encoding UTF8

$summary = @()

$summary += "AoM:EE BTI Metadata Analysis"
$summary += "============================"
$summary += ""
$summary += "BTI files scanned: $($results.Count)"
$summary += ""

$summary += "NOALPHATEST"
$summary += "-----------"

$results |
    Group-Object NoAlphaTest |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-20} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "NOALPHATEST + ALPHA BITS"
$summary += "------------------------"

$results |
    Where-Object { $_.NoAlphaTest -eq $true } |
    Group-Object AlphaBits |
    Sort-Object Name |
    ForEach-Object {
        $name = $_.Name
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = "(blank)"
        }

        $summary += ("{0,-20} {1,6}" -f $name, $_.Count)
    }

$summary += ""
$summary += "NOALPHATEST + FORMAT"
$summary += "--------------------"

$results |
    Where-Object { $_.NoAlphaTest -eq $true } |
    Group-Object Format |
    Sort-Object Name |
    ForEach-Object {
        $name = $_.Name
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = "(blank)"
        }

        $summary += ("{0,-20} {1,6}" -f $name, $_.Count)
    }

$summary += ""
$summary += "NOALPHATEST + ALPHA BITS + FORMAT"
$summary += "---------------------------------"

$results |
    Where-Object { $_.NoAlphaTest -eq $true } |
    Group-Object AlphaBits, Format |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-35} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "OUTPUT"
$summary += "------"
$summary += $OutCsv
$summary += $OutTxt

$summary |
    Set-Content -LiteralPath $OutTxt -Encoding UTF8

Write-Host ""
Write-Host "=============================="
Write-Host "DONE"
Write-Host "=============================="
Write-Host ""
Write-Host "Report:"
Write-Host $OutTxt