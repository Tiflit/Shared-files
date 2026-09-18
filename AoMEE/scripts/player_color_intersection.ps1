$Project = "D:\AI_upscaling\AoMEE"

$CandidatesCsv = "$Project\reports\player_color_candidates.csv"
$BtiCsv        = "$Project\reports\player_color_bti.csv"

$OutCsv = "$Project\reports\player_color_intersection.csv"
$OutTxt = "$Project\reports\player_color_intersection_summary.txt"

if (-not (Test-Path $CandidatesCsv)) {
    Write-Host "ERROR: $CandidatesCsv not found"
    exit
}

if (-not (Test-Path $BtiCsv)) {
    Write-Host "ERROR: $BtiCsv not found"
    exit
}

$candidates = Import-Csv -LiteralPath $CandidatesCsv
$bti        = Import-Csv -LiteralPath $BtiCsv

# Candidate lookup by filename without extension.
$candidateLookup = @{}

foreach ($c in $candidates) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension($c.Filename)

    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $candidateLookup[$name.ToLowerInvariant()] = $c
    }
}

$results = @()

foreach ($b in $bti) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension($b.Filename)

    if ([string]::IsNullOrWhiteSpace($name)) {
        continue
    }

    $key = $name.ToLowerInvariant()

    if ($candidateLookup.ContainsKey($key)) {

        $c = $candidateLookup[$key]

        $results += [PSCustomObject]@{
            Filename          = $c.Filename
            Category          = $c.Category
            Width             = $c.Width
            Height            = $c.Height
            OpaquePixels      = $c.OpaquePixels
            OpaqueCoveragePct = $c.OpaqueCoveragePct
            AlphaValueCount   = $c.AlphaValueCount
            BTIFile           = $b.BTIFile
            BTILine           = $b.Line
        }
    }
}

$results |
    Sort-Object Category, Filename |
    Export-Csv `
        -LiteralPath $OutCsv `
        -NoTypeInformation `
        -Encoding UTF8

$uniqueMatches = @(
    $results |
    Select-Object -ExpandProperty Filename -Unique
)

$summary = @(
    "AoM:EE Player-Color Signal Intersection"
    "========================================"
    ""
    "Sparse/binary-alpha candidates: $($candidates.Count)"
    "noalphatest BTI files: $(($bti | Select-Object -ExpandProperty BTIFile -Unique).Count)"
    "Intersection matches: $($results.Count)"
    "Unique candidate textures in intersection: $($uniqueMatches.Count)"
    ""
    "BY CATEGORY"
    "-----------"
)

$results |
    Group-Object Category |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-22} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "INTERSECTION"
$summary += "------------"

$uniqueMatches |
    Sort-Object |
    ForEach-Object {
        $summary += $_
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
Write-Host "Intersection: $($uniqueMatches.Count) unique textures"
Write-Host ""
Write-Host $OutTxt