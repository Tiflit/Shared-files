$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE'
$Extracted = Join-Path $Root 'extracted'
$Canary = Join-Path $Root 'tests\production_canary'
$Original = Join-Path $Canary 'original'
$Output = Join-Path $Canary 'PBRify_V4'
$Gate = Join-Path $Root 'reports\extraction_integrity_gate_v7'
$Baseline = Join-Path $Gate 'extracted_tga_bti_sha256_baseline.csv'

if (-not (Test-Path -LiteralPath $Extracted)) { throw "Missing extracted source: $Extracted" }
if (-not (Test-Path -LiteralPath $Baseline)) { throw "Missing source SHA-256 baseline: $Baseline" }

Remove-Item -LiteralPath $Original -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $Output -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Original,$Output | Out-Null

# 35 recovered exceptions. Flatten only the technical recovery prefix:
# extracted\patched_to_verify\textures\... -> canary\original\textures\...
$recoveredRoot = Join-Path $Extracted 'patched_to_verify'
$recovered = @(Get-ChildItem -LiteralPath $recoveredRoot -Recurse -File -Filter *.tga)

if ($recovered.Count -ne 35) {
    throw "Expected 35 recovered TGAs, found $($recovered.Count)."
}

foreach ($f in $recovered) {
    $rel = $f.FullName.Substring($recoveredRoot.Length).TrimStart('\')
    $dest = Join-Path $Original $rel
    $parent = Split-Path -Path $dest -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item -LiteralPath $f.FullName -Destination $dest
}

# Ten normal representative textures spanning major visible classes.
$normalSamples = @(
    'textures\building g temple.tga',
    'textures\infantry g hoplite standard.tga',
    'textures\world x earth 01.tga',
    'textures\icons\god major poseidon icon 128.tga',
    'textures\ui\ui button arrow left 64x32.tga',
    'textures\animal dog c map.tga',
    'textures\hero g achilles cape.tga',
    'textures\cavalry g hippikon standard.tga',
    'textures\siege g petrobolos.tga',
    'textures\special g centaur.tga'
)

$copiedNormal = 0
foreach ($rel in $normalSamples) {
    $src = Join-Path $Extracted $rel
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warning "Normal canary sample missing; skipping: $rel"
        continue
    }
    $dest = Join-Path $Original $rel
    $parent = Split-Path -Path $dest -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item -LiteralPath $src -Destination $dest
    $copiedNormal++
}

$tgAs = @(Get-ChildItem -LiteralPath $Original -Recurse -File -Filter *.tga)
if ($tgAs.Count -ne ($recovered.Count + $copiedNormal)) {
    throw "Canary file count mismatch."
}

@(
    "AoM:EE PBRify V4 production canary"
    "Recovered exception TGAs: $($recovered.Count)"
    "Normal representative TGAs: $copiedNormal"
    "Total canary TGAs: $($tgAs.Count)"
    "Source: verified extracted tree; originals are copied only."
) | Set-Content -LiteralPath (Join-Path $Canary 'README.txt') -Encoding UTF8

Write-Host "Canary prepared: $($tgAs.Count) TGAs"
Write-Host "Input : $Original"
Write-Host "Output: $Output"
