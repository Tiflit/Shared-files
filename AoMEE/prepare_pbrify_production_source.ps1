$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE'
$Extracted = Join-Path $Root 'extracted'
$SourceBaseline = Join-Path $Root 'reports\extraction_integrity_gate_v7\extracted_tga_bti_sha256_baseline.csv'
$Stage = Join-Path $Root 'input\production_source'
$Manifest = Join-Path $Stage 'production_source_manifest.csv'

if (-not (Test-Path -LiteralPath $Extracted)) { throw "Missing extracted source: $Extracted" }
if (-not (Test-Path -LiteralPath $SourceBaseline)) { throw "Missing v7 extracted SHA-256 baseline: $SourceBaseline" }

Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

$rows = @(Import-Csv -LiteralPath $SourceBaseline)
if ($rows.Count -ne 7487) {
    throw "Expected 7,487 baseline rows, found $($rows.Count)."
}

foreach ($row in $rows) {
    $logical = [string]$row.LogicalTGA
    $class = [string]$row.SourceClass

    if ($class -eq 'normal') {
        $src = Join-Path $Extracted $logical
    }
    elseif ($class -eq 'recovered') {
        $src = Join-Path $Extracted ("patched_to_verify\" + $logical)
    }
    else {
        throw "Unexpected SourceClass '$class' for $logical"
    }

    if (-not (Test-Path -LiteralPath $src)) {
        throw "Baseline source file missing: $src"
    }

    $dest = Join-Path $Stage $logical
    $parent = Split-Path -Path $dest -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    Copy-Item -LiteralPath $src -Destination $dest

    if ((Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant() -ne ([string]$row.TGASHA256).ToLowerInvariant()) {
        throw "Source hash changed while staging: $logical"
    }
}

$staged = @(Get-ChildItem -LiteralPath $Stage -Recurse -File -Filter *.tga)
if ($staged.Count -ne 7487) {
    throw "Production source staging produced $($staged.Count) TGA files; expected 7487."
}

$manifestRows = foreach ($f in $staged | Sort-Object FullName) {
    $rel = $f.FullName.Substring($Stage.Length).TrimStart('\')
    [pscustomobject]@{
        RelativePath = $rel
        Bytes = $f.Length
        SHA256 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$manifestRows | Export-Csv -LiteralPath $Manifest -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host 'Production source staging: PASS'
Write-Host "Staged TGA files: $($staged.Count)"
Write-Host "Source: $Extracted (READ-ONLY)"
Write-Host "Stage : $Stage"
Write-Host "Manifest: $Manifest"
