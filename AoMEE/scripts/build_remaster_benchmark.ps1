$ErrorActionPreference = 'Stop'

$Root       = 'D:\AI_upscaling\AoMEE'
$Extracted  = Join-Path $Root 'extracted'
$Reports    = Join-Path $Root 'reports'
$Tests      = Join-Path $Root 'tests'
$Benchmark  = Join-Path $Tests 'remaster_benchmark'

$Classification = Join-Path $Reports 'tga_classification.csv'

$InputRoot      = Join-Path $Benchmark 'input'
$RecoveredRoot  = Join-Path $Benchmark 'recovered'
$EdgeRoot       = Join-Path $Benchmark 'edge_cases'
$Manifest       = Join-Path $Benchmark 'remaster_benchmark_manifest.csv'
$SummaryPath    = Join-Path $Benchmark 'remaster_benchmark_summary.txt'
if (-not (Test-Path -LiteralPath $Classification)) {
    throw "Classification file not found: $Classification"
}

New-Item -ItemType Directory -Force -Path $InputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $RecoveredRoot | Out-Null
New-Item -ItemType Directory -Force -Path $EdgeRoot | Out-Null

$data = Import-Csv -LiteralPath $Classification

if ($data.Count -ne 7487) {
    throw "Expected 7487 classified textures, found $($data.Count)."
}

# ------------------------------------------------------------
# Deterministic ordering
# ------------------------------------------------------------
# SHA-256 of the logical path provides stable pseudo-random
# ordering without depending on PowerShell's random generator.
# ------------------------------------------------------------

function Get-StableKey {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant())
        $hash  = $sha.ComputeHash($bytes)

        return (
            $hash |
            ForEach-Object { $_.ToString('x2') }
        ) -join ''
    }
    finally {
        $sha.Dispose()
    }
}

foreach ($row in $data) {
    $row | Add-Member -NotePropertyName StableKey `
                      -NotePropertyValue (Get-StableKey $row.Path) `
                      -Force
}

# ------------------------------------------------------------
# Alpha bands
# ------------------------------------------------------------

function Get-AlphaBand {
    param([double]$Coverage)

    if ($Coverage -eq 0) {
        return 'Empty'
    }

    if ($Coverage -eq 100) {
        return 'Opaque'
    }

    if ($Coverage -le 5) {
        return 'Sparse'
    }

    if ($Coverage -le 25) {
        return 'Moderate'
    }

    if ($Coverage -le 75) {
        return 'Broad'
    }

    return 'VeryBroad'
}

foreach ($row in $data) {

    $coverage = 0

    if (-not [double]::TryParse(
        $row.AlphaCoveragePercent,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$coverage
    )) {
        $coverage = 0
    }

    $row | Add-Member `
        -NotePropertyName AlphaBand `
        -NotePropertyValue (Get-AlphaBand $coverage) `
        -Force
}

# ------------------------------------------------------------
# Category quotas
# ------------------------------------------------------------

$Quotas = [ordered]@{
    'Building'       = 8
    'Character/Unit' = 8
    'Animal'         = 6
    'Other'          = 10
    'Icon'           = 10
    'UI'             = 10
    'World/Terrain'  = 8
    'Effect'         = 5
    'Shadow'         = 5
}

# ------------------------------------------------------------
# Select category samples using alpha-band round-robin
# ------------------------------------------------------------

$Selected = New-Object System.Collections.Generic.List[object]
$SelectedKeys = @{}

$BandOrder = @(
    'Opaque',
    'Sparse',
    'Moderate',
    'Broad',
    'VeryBroad',
    'Empty'
)

foreach ($category in $Quotas.Keys) {

    $quota = $Quotas[$category]

    $pool = @(
        $data |
        Where-Object {
            $_.Category -eq $category
        }
    )

    if ($pool.Count -eq 0) {
        Write-Warning "No textures found for category: $category"
        continue
    }

    $categorySelected = 0

    # First pass: deliberately distribute across alpha bands.
    foreach ($band in $BandOrder) {

        if ($categorySelected -ge $quota) {
            break
        }

        $candidates = @(
            $pool |
            Where-Object {
                $_.AlphaBand -eq $band
            } |
            Sort-Object StableKey
        )

        foreach ($candidate in $candidates) {

            if ($categorySelected -ge $quota) {
                break
            }

            if ($SelectedKeys.ContainsKey($candidate.Path)) {
                continue
            }

            $Selected.Add([PSCustomObject]@{
                Row        = $candidate
                Selection  = 'CategorySample'
                SelectionGroup = "$category / $band"
            })

            $SelectedKeys[$candidate.Path] = $true
            $categorySelected++
        }
    }

    # Fallback if some alpha bands were unavailable.
    if ($categorySelected -lt $quota) {

        $fallback = @(
            $pool |
            Where-Object {
                -not $SelectedKeys.ContainsKey($_.Path)
            } |
            Sort-Object StableKey
        )

        foreach ($candidate in $fallback) {

            if ($categorySelected -ge $quota) {
                break
            }

            $Selected.Add([PSCustomObject]@{
                Row           = $candidate
                Selection     = 'CategorySampleFallback'
                SelectionGroup = "$category / fallback"
            })

            $SelectedKeys[$candidate.Path] = $true
            $categorySelected++
        }
    }
}

# ------------------------------------------------------------
# Small / unusual resolution edge cases
# ------------------------------------------------------------

$EdgeCandidates = @(
    $data |
    Where-Object {
        (
            ([int]$_.Width -le 16 -and [int]$_.Height -le 16)
        ) -or
        (
            ([int]$_.Width -le 32 -and [int]$_.Height -le 8) -or
            ([int]$_.Height -le 8 -and [int]$_.Width -le 128)
        )
    } |
    Sort-Object StableKey
)

$EdgeSelected = 0

foreach ($candidate in $EdgeCandidates) {

    if ($EdgeSelected -ge 10) {
        break
    }

    if ($SelectedKeys.ContainsKey($candidate.Path)) {
        continue
    }

    $Selected.Add([PSCustomObject]@{
        Row            = $candidate
        Selection      = 'EdgeCase'
        SelectionGroup = 'SmallOrUnusualResolution'
    })

    $SelectedKeys[$candidate.Path] = $true
    $EdgeSelected++
}

# ------------------------------------------------------------
# ALWAYS include all 35 recovered exceptions
# ------------------------------------------------------------

$RecoveredCandidates = @(
    $data |
    Where-Object {
        $_.Path -like 'patched_to_verify\*'
    } |
    Sort-Object StableKey
)

if ($RecoveredCandidates.Count -ne 35) {
    throw "Expected 35 recovered exception textures, found $($RecoveredCandidates.Count)."
}

foreach ($candidate in $RecoveredCandidates) {

    if ($SelectedKeys.ContainsKey($candidate.Path)) {
        continue
    }

    $Selected.Add([PSCustomObject]@{
        Row            = $candidate
        Selection      = 'RecoveredException'
        SelectionGroup = 'RecoveredException'
    })

    $SelectedKeys[$candidate.Path] = $true
}

# ------------------------------------------------------------
# Copy benchmark files
# ------------------------------------------------------------

$ManifestRows = New-Object System.Collections.Generic.List[object]

foreach ($item in $Selected) {

    $row = $item.Row

    $source = Join-Path $Extracted $row.Path

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Source TGA not found: $source"
    }

    switch ($item.Selection) {

        'RecoveredException' {
            $destinationRoot = $RecoveredRoot
        }

        'EdgeCase' {
            $destinationRoot = $EdgeRoot
        }

        default {
            $destinationRoot = $InputRoot
        }
    }

    # Preserve the logical relative texture path.
    $safeRelative = $row.Path

    $destination = Join-Path $destinationRoot $safeRelative
    $destinationDirectory = Split-Path -Path $destination -Parent

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $destinationDirectory |
        Out-Null

    Copy-Item `
        -LiteralPath $source `
        -Destination $destination `
        -Force

    $ManifestRows.Add([PSCustomObject]@{
        BenchmarkPath       = $destination
        OriginalRelativePath = $row.Path
        Selection             = $item.Selection
        SelectionGroup       = $item.SelectionGroup
        Category              = $row.Category
        SuggestedGroup        = $row.SuggestedGroup
        Width                 = $row.Width
        Height                = $row.Height
        AlphaBand             = $row.AlphaBand
        AlphaCoveragePercent = $row.AlphaCoveragePercent
        AlphaValueCount      = $row.AlphaValueCount
        Flags                = $row.Flags
    })
}

$ManifestRows |
    Export-Csv `
        -LiteralPath $Manifest `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$summary = New-Object System.Collections.Generic.List[string]

$summary.Add('AoM:EE Remaster Benchmark')
$summary.Add('=========================')
$summary.Add('')
$summary.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$summary.Add('')
$summary.Add("AUTHORITATIVE SOURCE SET")
$summary.Add("------------------------")
$summary.Add("Classified textures: 7487")
$summary.Add('')
$summary.Add("BENCHMARK")
$summary.Add("---------")
$summary.Add("Category samples:      $($ManifestRows.Where({$_.Selection -like 'CategorySample*'}).Count)")
$summary.Add("Small/edge cases:      $($ManifestRows.Where({$_.Selection -eq 'EdgeCase'}).Count)")
$summary.Add("Recovered exceptions:  $($ManifestRows.Where({$_.Selection -eq 'RecoveredException'}).Count)")
$summary.Add("Total benchmark files: $($ManifestRows.Count)")
$summary.Add('')

$summary.Add('CATEGORY COUNTS')
$summary.Add('---------------')

$ManifestRows |
    Group-Object Category |
    Sort-Object Count -Descending |
    ForEach-Object {
        $summary.Add(("{0,-20} {1,5}" -f $_.Name, $_.Count))
    }

$summary.Add('')
$summary.Add('ALPHA BANDS')
$summary.Add('-----------')

$ManifestRows |
    Group-Object AlphaBand |
    Sort-Object Count -Descending |
    ForEach-Object {
        $summary.Add(("{0,-20} {1,5}" -f $_.Name, $_.Count))
    }

$summary.Add('')
$summary.Add('RECOVERED EXCEPTIONS')
$summary.Add('--------------------')

$ManifestRows |
    Where-Object {
        $_.Selection -eq 'RecoveredException'
    } |
    Sort-Object OriginalRelativePath |
    ForEach-Object {
        $summary.Add($_.OriginalRelativePath)
    }

$summary.Add('')
$summary.Add('OUTPUT')
$summary.Add('------')
$summary.Add($InputRoot)
$summary.Add($EdgeRoot)
$summary.Add($RecoveredRoot)
$summary.Add($Manifest)

$summary |
    Set-Content `
        -LiteralPath $SummaryPath `
        -Encoding UTF8

# ------------------------------------------------------------
# Final sanity check
# ------------------------------------------------------------

$missing = @(
    $ManifestRows |
    Where-Object {
        -not (Test-Path -LiteralPath $_.BenchmarkPath -PathType Leaf)
    }
)

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host 'AoM:EE REMASTER BENCHMARK CREATED' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "Source textures:       7487"
Write-Host "Benchmark textures:    $($ManifestRows.Count)"
Write-Host "Category samples:      $($ManifestRows.Where({$_.Selection -like 'CategorySample*'}).Count)"
Write-Host "Edge cases:            $($ManifestRows.Where({$_.Selection -eq 'EdgeCase'}).Count)"
Write-Host "Recovered exceptions:  $($ManifestRows.Where({$_.Selection -eq 'RecoveredException'}).Count)"
Write-Host "Missing benchmark files: $($missing.Count)"
Write-Host ''

if ($missing.Count -eq 0) {
    Write-Host 'BENCHMARK SANITY CHECK PASSED.' -ForegroundColor Green
}
else {
    Write-Host 'BENCHMARK HAS MISSING FILES.' -ForegroundColor Red

    foreach ($item in $missing) {
        Write-Host "  $($item.OriginalRelativePath)"
    }
}

Write-Host ''
Write-Host 'Manifest:'
Write-Host $Manifest -ForegroundColor Green
Write-Host ''
Write-Host 'Summary:'
Write-Host $SummaryPath -ForegroundColor Green
Write-Host ''