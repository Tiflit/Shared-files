$Project = "D:\AI_upscaling\AoMEE"

$Candidates = "$Project\reports\player_color_candidates.csv"
$Materials  = "$Project\Age of Mythology\models\version1.0\materials"
$Output     = "$Project\reports\player_color_reference_search.txt"

$candidates = Import-Csv -LiteralPath $Candidates

$names = @()

foreach ($c in $candidates) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($c.Filename)

    if ($name) {
        $names += [regex]::Escape($name)
    }
}

$pattern = ($names -join "|")

Write-Host "Candidates: $($names.Count)"
Write-Host "Searching..."
Write-Host ""

$files = Get-ChildItem -LiteralPath $Materials -Recurse -File

Write-Host "Files found: $($files.Count)"
Write-Host ""

$matchCount = 0

Remove-Item -LiteralPath $Output -Force -ErrorAction SilentlyContinue

foreach ($file in $files) {

    Select-String `
        -LiteralPath $file.FullName `
        -Pattern $pattern `
        -CaseSensitive:$false `
        -ErrorAction SilentlyContinue |
    ForEach-Object {

        $matchCount++

        Add-Content `
            -LiteralPath $Output `
            -Value "$($_.Path)`t$($_.LineNumber)`t$($_.Line.Trim())"
    }
}

Write-Host ""
Write-Host "DONE"
Write-Host "Matches: $matchCount"
Write-Host "Output:"
Write-Host $Output