$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE'
$FinalRoot = Join-Path $Root 'tests\final_model_comparison'
$Manifest = Join-Path $FinalRoot 'final_model_comparison_manifest.csv'
$ReviewRoot = Join-Path $FinalRoot 'visual_review'

if (-not (Test-Path -LiteralPath $Manifest)) { throw "Manifest not found: $Manifest" }
New-Item -ItemType Directory -Force -Path $ReviewRoot | Out-Null

$rows = @(Import-Csv -LiteralPath $Manifest)
function Find-Texture([string]$base, [string]$rel) {
    $p = Join-Path $base $rel
    if (Test-Path -LiteralPath $p) { return $p }
    $png = [System.IO.Path]::ChangeExtension($p,'.png')
    if (Test-Path -LiteralPath $png) { return $png }
    return $null
}

$results = foreach ($row in $rows) {
    $rel = [string]$row.Path
    $orig = Find-Texture (Join-Path $FinalRoot 'original') $rel
    $pbr  = Find-Texture (Join-Path $FinalRoot 'PBRify_V4') $rel
    $ultra = Find-Texture (Join-Path $FinalRoot 'UltraSharp_V2') $rel
    [pscustomobject]@{
        Path=$rel
        Category=[string]$row.Category
        Original=[bool]$orig
        PBRify_V4=[bool]$pbr
        UltraSharp_V2=[bool]$ultra
    }
}

$results | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $ReviewRoot 'comparison_availability.csv')
$missing = @($results | Where-Object { -not ($_.Original -and $_.PBRify_V4 -and $_.UltraSharp_V2) })

$summary = @(
    'AoM:EE FINAL MODEL COMPARISON AVAILABILITY',
    '',
    "Manifest textures: $($rows.Count)",
    "Complete: $($rows.Count - $missing.Count)",
    "Incomplete: $($missing.Count)",
    '',
    'Columns: Original | PBRify V4 | UltraSharp V2',
    ''
)
if ($missing.Count) {
    $summary += 'Missing:'
    $missing | ForEach-Object { $summary += $_.Path }
}
Set-Content -LiteralPath (Join-Path $ReviewRoot 'comparison_availability.txt') -Value $summary -Encoding UTF8

Write-Host "Checked $($rows.Count) textures. Complete: $($rows.Count-$missing.Count). Incomplete: $($missing.Count)." -ForegroundColor Cyan
if ($missing.Count) { Write-Host "See: $(Join-Path $ReviewRoot 'comparison_availability.txt')" -ForegroundColor Yellow }
else { Write-Host 'All three columns are present for every texture.' -ForegroundColor Green }
