$ErrorActionPreference = 'Stop'

# ============================================================
# AoM:EE PBRIFY V4 — FULL CURRENT-BUILD DDT COMPILE
#
# Input:
#   processed\PBRify_V4\*.tga
#   authoritative original BTIs under extracted\
#
# Output:
#   processed\DDT_PBRify_V4\*.ddt
#   processed\PBRify_V4_compile_manifest.csv
#   processed\PBRify_V4_compile.log
#
# Deliberately excludes:
#   textures\icons\special c black tortoise icon.tga
#
# The clean game and extracted source are never modified.
# ============================================================

$Root = 'D:\AI_upscaling\AoMEE'

$PBRifyRoot    = Join-Path $Root 'processed\PBRify_V4'
$PBRifyShaPath = Join-Path $Root 'processed\PBRify_V4_sha256.csv'
$ExtractedRoot = Join-Path $Root 'extracted'
$Compiler      = Join-Path $Root 'tools\TextureCompiler.exe'

$DDTRoot       = Join-Path $Root 'processed\DDT_PBRify_V4'
$ManifestPath  = Join-Path $Root 'processed\PBRify_V4_compile_manifest.csv'
$LogPath       = Join-Path $Root 'processed\PBRify_V4_compile.log'

$ExpectedTotal = 7487
$ExcludedRelative = 'textures\icons\special c black tortoise icon.tga'
$ExpectedCompile = 7486

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

function Normalize-RelativePath {
    param([Parameter(Mandatory)][string]$Path)
    return ($Path -replace '/', '\').TrimStart('\')
}

function Get-LogicalBTIRelativePath {
    param([Parameter(Mandatory)][string]$RelativeTGA)

    $relative = Normalize-RelativePath $RelativeTGA

    if ($relative.EndsWith('.tga', [StringComparison]::OrdinalIgnoreCase)) {
        $relative = $relative.Substring(0, $relative.Length - 4)
    }

    return ($relative + '.bti')
}

function Get-LogicalRelativeFromExtracted {
    param(
        [Parameter(Mandatory)][string]$FullPath
    )

    $rel = $FullPath.Substring($ExtractedRoot.Length + 1)
    $rel = Normalize-RelativePath $rel

    if ($rel.StartsWith('patched_to_verify\', [StringComparison]::OrdinalIgnoreCase)) {
        $rel = $rel.Substring('patched_to_verify\'.Length)
    }

    return $rel
}

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

foreach ($p in @(
    $PBRifyRoot,
    $PBRifyShaPath,
    $ExtractedRoot,
    $Compiler
)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Required path not found: $p"
    }
}

if (Test-Path -LiteralPath $DDTRoot) {
    Remove-Item -LiteralPath $DDTRoot -Recurse -Force
}

if (Test-Path -LiteralPath $ManifestPath) {
    Remove-Item -LiteralPath $ManifestPath -Force
}

if (Test-Path -LiteralPath $LogPath) {
    Remove-Item -LiteralPath $LogPath -Force
}

$null = New-Item -ItemType Directory -Force -Path $DDTRoot

# ------------------------------------------------------------
# Load authoritative PBRify output SHA baseline.
# ------------------------------------------------------------

$SHARows = @(Import-Csv -LiteralPath $PBRifyShaPath)

if ($SHARows.Count -ne $ExpectedTotal) {
    throw "Expected $ExpectedTotal PBRify SHA rows, found $($SHARows.Count)."
}

$SHAMap = @{}

foreach ($row in $SHARows) {
    $key = (Normalize-RelativePath $row.RelativePath).ToLowerInvariant()

    if ($SHAMap.ContainsKey($key)) {
        throw "Duplicate PBRify SHA entry: $($row.RelativePath)"
    }

    $SHAMap[$key] = $row.SHA256
}

# ------------------------------------------------------------
# Inventory production TGAs.
# ------------------------------------------------------------

$TGAs = @(
    Get-ChildItem -LiteralPath $PBRifyRoot -Filter '*.tga' -Recurse -File
)

if ($TGAs.Count -ne $ExpectedTotal) {
    throw "Expected $ExpectedTotal production PBRify TGAs, found $($TGAs.Count)."
}

$TGAByKey = @{}

foreach ($tga in $TGAs) {
    $relative = Normalize-RelativePath $tga.FullName.Substring($PBRifyRoot.Length + 1)
    $key = $relative.ToLowerInvariant()

    if ($TGAByKey.ContainsKey($key)) {
        throw "Duplicate production TGA relative path: $relative"
    }

    $TGAByKey[$key] = $tga
}

if (-not $TGAByKey.ContainsKey($ExcludedRelative.ToLowerInvariant())) {
    throw "Expected legacy/unreferenced Black Tortoise exclusion was not found."
}

# ------------------------------------------------------------
# Index authoritative BTIs.
#
# Normal:
#   extracted\textures\foo.bti
#
# Recovered:
#   extracted\patched_to_verify\textures\foo.bti
#
# Exact logical paths are required to be unique.
# ------------------------------------------------------------

$BTIIndex = @{}

$AllBTIs = @(
    Get-ChildItem -LiteralPath $ExtractedRoot -Filter '*.bti' -Recurse -File
)

foreach ($bti in $AllBTIs) {

    $logical = Get-LogicalRelativeFromExtracted -FullPath $bti.FullName
    $key = $logical.ToLowerInvariant()

    if ($BTIIndex.ContainsKey($key)) {
        throw "Duplicate authoritative BTI logical path: $logical`n  Existing: $($BTIIndex[$key])`n  Duplicate: $($bti.FullName)"
    }

    $BTIIndex[$key] = $bti.FullName
}

Write-Host "============================================"
Write-Host "AoM:EE PBRIFY V4 FULL COMPILE"
Write-Host "============================================"
Write-Host ""
Write-Host "Production TGAs      : $($TGAs.Count)"
Write-Host "Expected total       : $ExpectedTotal"
Write-Host "Excluded             : $ExcludedRelative"
Write-Host "Expected compilation : $ExpectedCompile"
Write-Host "Authoritative BTIs   : $($BTIIndex.Count)"
Write-Host "Compiler             : $Compiler"
Write-Host "DDT output           : $DDTRoot"
Write-Host ""

# ------------------------------------------------------------
# Write a start marker to the log.
# ------------------------------------------------------------

"=== AoM:EE PBRify V4 full compile ===" | Set-Content -LiteralPath $LogPath -Encoding UTF8
"Started: $(Get-Date -Format o)" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Expected compile count: $ExpectedCompile" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Excluded: $ExcludedRelative" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"" | Add-Content -LiteralPath $LogPath -Encoding UTF8

# ------------------------------------------------------------
# Compile manifest rows.
# ------------------------------------------------------------

$Results = [System.Collections.Generic.List[object]]::new()

$Compiled = 0
$SkippedExcluded = 0
$Failed = 0
$Warnings = 0

$Index = 0

foreach ($tga in ($TGAs | Sort-Object FullName)) {

    $Index++

    $relative = Normalize-RelativePath $tga.FullName.Substring($PBRifyRoot.Length + 1)
    $key = $relative.ToLowerInvariant()

    if ($key -eq $ExcludedRelative.ToLowerInvariant()) {
        $SkippedExcluded++

        $Results.Add([pscustomobject]@{
            RelativePath      = $relative
            SourceTgaSHA256   = $SHAMap[$key]
            SourceBtiSHA256   = ''
            DDTSHA256         = ''
            DDTBytes          = ''
            CompilerExitCode  = ''
            WarningCount      = ''
            Status            = 'EXCLUDED'
            ExcludedReason    = 'Unused legacy/unreferenced Black Tortoise asset; known TextureCompiler crash with nomip+BC1'
        })

        Write-Host "[$Index/$ExpectedTotal] EXCLUDED: $relative"
        continue
    }

    $logicalBTIRelative = Get-LogicalBTIRelativePath $relative
    $btiKey = $logicalBTIRelative.ToLowerInvariant()

    if (-not $SHAMap.ContainsKey($key)) {
        throw "PBRify SHA baseline missing: $relative"
    }

    if (-not $BTIIndex.ContainsKey($btiKey)) {
        throw "Authoritative BTI missing for: $relative`nExpected: $logicalBTIRelative"
    }

    $btiPath = $BTIIndex[$btiKey]

    $ddtRelative = $relative.Substring(0, $relative.Length - 4) + '.ddt'
    $ddtPath = Join-Path $DDTRoot $ddtRelative
    $ddtDir = Split-Path -Parent $ddtPath

    $null = New-Item -ItemType Directory -Force -Path $ddtDir

    $expectedTgaSha = $SHAMap[$key]
    $actualTgaSha = (Get-FileHash -LiteralPath $tga.FullName -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($actualTgaSha -ne $expectedTgaSha.ToLowerInvariant()) {
        throw "Production TGA SHA-256 mismatch: $relative`nExpected: $expectedTgaSha`nActual:   $actualTgaSha"
    }

    $sourceTgaSha = $actualTgaSha
    $sourceBtiSha = (Get-FileHash -LiteralPath $btiPath -Algorithm SHA256).Hash.ToLowerInvariant()

    Write-Host "[$Index/$ExpectedTotal] Compiling: $relative"

    # Preserve the exact original BTI bytes.
    # The compiler reads metadata from the .bti beside the .tga.
    $stageBTI = [IO.Path]::ChangeExtension($tga.FullName, '.bti')

    # Use a unique temporary sibling directory so production source is never
    # modified. The staged pair is recreated per texture and deleted afterward.
    $stageDir = Join-Path $Root 'tests\production_full_compile_stage'
    $stageTga = Join-Path $stageDir $relative
    $stageTgaDir = Split-Path -Parent $stageTga

    if (-not (Test-Path -LiteralPath $stageTgaDir)) {
        $null = New-Item -ItemType Directory -Force -Path $stageTgaDir
    }

    Copy-Item -LiteralPath $tga.FullName -Destination $stageTga -Force

    $stageBTI = [IO.Path]::ChangeExtension($stageTga, '.bti')
    Copy-Item -LiteralPath $btiPath -Destination $stageBTI -Force

    try {

        $compilerOutput = @(
            & $Compiler `
                -i $stageTga `
                -o $ddtPath `
                2>&1
        )

        $exitCode = $LASTEXITCODE

        $outputLines = @(
            $compilerOutput | ForEach-Object { [string]$_ }
        )

        $warningLines = @(
            $outputLines |
            Where-Object {
                $_ -match 'UNHANDLED token encountered'
            }
        )

        if ($warningLines.Count -gt 0) {
            $Warnings += $warningLines.Count

            "[$relative]" | Add-Content -LiteralPath $LogPath -Encoding UTF8
            $outputLines | Add-Content -LiteralPath $LogPath -Encoding UTF8
            "" | Add-Content -LiteralPath $LogPath -Encoding UTF8
        }

        if ($exitCode -eq 0 -and (Test-Path -LiteralPath $ddtPath)) {

            $ddtInfo = Get-Item -LiteralPath $ddtPath
            $ddtSha = (Get-FileHash -LiteralPath $ddtPath -Algorithm SHA256).Hash.ToLowerInvariant()

            $Compiled++

            $Results.Add([pscustomobject]@{
                RelativePath      = $relative
                SourceTgaSHA256   = $sourceTgaSha
                SourceBtiSHA256   = $sourceBtiSha
                DDTSHA256         = $ddtSha
                DDTBytes          = $ddtInfo.Length
                CompilerExitCode  = $exitCode
                WarningCount      = $warningLines.Count
                Status            = 'OK'
                ExcludedReason    = ''
            })

        } else {

            $Failed++

            "=== COMPILE FAILURE ===" | Add-Content -LiteralPath $LogPath -Encoding UTF8
            "Texture: $relative" | Add-Content -LiteralPath $LogPath -Encoding UTF8
            "Exit code: $exitCode" | Add-Content -LiteralPath $LogPath -Encoding UTF8
            "Compiler output:" | Add-Content -LiteralPath $LogPath -Encoding UTF8
            $outputLines | Add-Content -LiteralPath $LogPath -Encoding UTF8
            "" | Add-Content -LiteralPath $LogPath -Encoding UTF8

            $Results.Add([pscustomobject]@{
                RelativePath      = $relative
                SourceTgaSHA256   = $sourceTgaSha
                SourceBtiSHA256   = $sourceBtiSha
                DDTSHA256         = ''
                DDTBytes          = ''
                CompilerExitCode  = $exitCode
                WarningCount      = $warningLines.Count
                Status            = 'FAIL'
                ExcludedReason    = ''
            })
        }

    } finally {
        # Remove only this texture's temporary staged pair.
        Remove-Item -LiteralPath $stageTga -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stageBTI -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------
# Remove empty temporary stage tree.
# ------------------------------------------------------------

$FullStageRoot = Join-Path $Root 'tests\production_full_compile_stage'

if (Test-Path -LiteralPath $FullStageRoot) {
    Remove-Item -LiteralPath $FullStageRoot -Recurse -Force
}

# ------------------------------------------------------------
# Final DDT inventory.
# ------------------------------------------------------------

$DDTs = @(
    Get-ChildItem -LiteralPath $DDTRoot -Filter '*.ddt' -Recurse -File
)

$ddtKeys = @{}

foreach ($ddt in $DDTs) {
    $rel = Normalize-RelativePath $ddt.FullName.Substring($DDTRoot.Length + 1)
    $key = $rel.ToLowerInvariant()

    if ($ddtKeys.ContainsKey($key)) {
        throw "Duplicate output DDT relative path: $rel"
    }

    $ddtKeys[$key] = $ddt
}

$expectedCompileKeys = @(
    $TGAs |
    ForEach-Object {
        Normalize-RelativePath $_.FullName.Substring($PBRifyRoot.Length + 1)
    } |
    Where-Object {
        $_.ToLowerInvariant() -ne $ExcludedRelative.ToLowerInvariant()
    } |
    ForEach-Object {
        $_.Substring(0, $_.Length - 4) + '.ddt'
    } |
    ForEach-Object {
        $_.ToLowerInvariant()
    }
)

$missingDDTs = @(
    $expectedCompileKeys | Where-Object { -not $ddtKeys.ContainsKey($_) }
)

$unexpectedDDTs = @(
    $ddtKeys.Keys | Where-Object { $_ -notin $expectedCompileKeys }
)

# ------------------------------------------------------------
# Write manifest.
# ------------------------------------------------------------

$Results |
    Sort-Object RelativePath |
    Export-Csv -LiteralPath $ManifestPath -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# Final summary.
# ------------------------------------------------------------

"" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Finished: $(Get-Date -Format o)" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Compiled: $Compiled" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Excluded: $SkippedExcluded" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Failed: $Failed" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Warnings: $Warnings" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"DDTs present: $($DDTs.Count)" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Missing DDTs: $($missingDDTs.Count)" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Unexpected DDTs: $($unexpectedDDTs.Count)" | Add-Content -LiteralPath $LogPath -Encoding UTF8

Write-Host ""
Write-Host "============================================"
Write-Host "FULL CURRENT-BUILD COMPILE RESULT"
Write-Host "============================================"
Write-Host ""
Write-Host "Expected textures : $ExpectedCompile"
Write-Host "Compiled          : $Compiled"
Write-Host "DDTs produced     : $($DDTs.Count)"
Write-Host "Excluded          : $SkippedExcluded"
Write-Host "Failures          : $Failed"
Write-Host "Warning tokens    : $Warnings"
Write-Host "Missing DDTs      : $($missingDDTs.Count)"
Write-Host "Unexpected DDTs   : $($unexpectedDDTs.Count)"
Write-Host ""
Write-Host "Manifest          : $ManifestPath"
Write-Host "Compiler log      : $LogPath"
Write-Host "DDT output        : $DDTRoot"
Write-Host ""

if ($missingDDTs.Count -gt 0) {
    Write-Host "MISSING DDTs:"
    $missingDDTs | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
}

if ($unexpectedDDTs.Count -gt 0) {
    Write-Host "UNEXPECTED DDTs:"
    $unexpectedDDTs | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
}

$pass = (
    $Compiled -eq $ExpectedCompile -and
    $DDTs.Count -eq $ExpectedCompile -and
    $SkippedExcluded -eq 1 -and
    $Failed -eq 0 -and
    $missingDDTs.Count -eq 0 -and
    $unexpectedDDTs.Count -eq 0
)

if ($pass) {
    Write-Host "FULL CURRENT-BUILD PBRIFY V4 COMPILE: PASS"
    exit 0
}

Write-Host "FULL CURRENT-BUILD PBRIFY V4 COMPILE: FAIL"
exit 1
