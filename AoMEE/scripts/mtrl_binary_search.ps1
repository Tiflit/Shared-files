$Project = "D:\AI_upscaling\AoMEE"

$Candidates = "$Project\reports\player_color_candidates.csv"
$Materials  = "$Project\Age of Mythology\materials"

$OutCsv = "$Project\reports\player_color_mtrl_matches.csv"
$OutTxt = "$Project\reports\player_color_mtrl_matches_summary.txt"

$candidates = Import-Csv -LiteralPath $Candidates

# Build candidate texture names.
$patterns = @()

foreach ($c in $candidates) {

    $name = [System.IO.Path]::GetFileNameWithoutExtension($c.Filename)

    if (-not [string]::IsNullOrWhiteSpace($name)) {

        $patterns += [PSCustomObject]@{
            Name = $name
            Key  = $name.ToLowerInvariant()
        }
    }
}

Write-Host "Candidate textures: $($patterns.Count)"
Write-Host ""

$mtrlFiles = Get-ChildItem `
    -LiteralPath $Materials `
    -Recurse `
    -File `
    -Filter "*.mtrl" `
    -ErrorAction SilentlyContinue

Write-Host "MTRL files: $($mtrlFiles.Count)"
Write-Host ""
Write-Host "Scanning binary contents..."
Write-Host ""

$results = New-Object System.Collections.Generic.List[object]

$fileCount = 0

# Latin-1 preserves every byte 0-255 exactly, making ASCII strings
# inside the binary files searchable without assuming the whole file
# is valid text.
$encoding = [System.Text.Encoding]::Latin1

foreach ($file in $mtrlFiles) {

    $fileCount++

    if (($fileCount % 1000) -eq 0) {
        Write-Host "Scanned $fileCount / $($mtrlFiles.Count)"
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $text  = $encoding.GetString($bytes).ToLowerInvariant()
    }
    catch {
        continue
    }

    foreach ($p in $patterns) {

        if ($text.Contains($p.Key)) {

            $candidate = $candidates |
                Where-Object {
                    [System.IO.Path]::GetFileNameWithoutExtension($_.Filename).ToLowerInvariant() -eq $p.Key
                } |
                Select-Object -First 1

            $results.Add(
                [PSCustomObject]@{
                    CandidateFilename = $candidate.Filename
                    Category          = $candidate.Category
                    MtrlFile          = $file.FullName
                    MtrlFilename       = $file.Name
                }
            )
        }
    }
}

# Save detailed results.
$results |
    Sort-Object CandidateFilename, MtrlFile |
    Export-Csv `
        -LiteralPath $OutCsv `
        -NoTypeInformation `
        -Encoding UTF8

# Summary.
$matchedCandidates = @(
    $results |
        Select-Object -ExpandProperty CandidateFilename -Unique
)

$matchedMtrl = @(
    $results |
        Select-Object -ExpandProperty MtrlFile -Unique
)

$summary = @(
    "AoM:EE Player-Color MTRL Binary Search"
    "======================================="
    ""
    "Candidate textures: $($candidates.Count)"
    "MTRL files scanned: $($mtrlFiles.Count)"
    "Texture/MTRL matches: $($results.Count)"
    "Unique candidate textures matched: $($matchedCandidates.Count)"
    "Unique MTRL files matched: $($matchedMtrl.Count)"
    ""
    "MATCHES BY CATEGORY"
    "-------------------"
)

$results |
    Group-Object Category |
    Sort-Object Name |
    ForEach-Object {
        $summary += ("{0,-22} {1,6}" -f $_.Name, $_.Count)
    }

$summary += ""
$summary += "MATCHED CANDIDATE TEXTURES"
$summary += "--------------------------"

$matchedCandidates |
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
Write-Host "Texture/MTRL matches: $($results.Count)"
Write-Host "Unique candidate textures: $($matchedCandidates.Count)"
Write-Host "Unique MTRL files: $($matchedMtrl.Count)"
Write-Host ""
Write-Host "Report:"
Write-Host $OutTxt