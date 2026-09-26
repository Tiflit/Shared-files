$ErrorActionPreference = 'Stop'

# ============================================================
# AoM:EE PBRIFY V4 — FULL CURRENT-BUILD DDT COMPILE V2
#
# Purpose:
#   Deterministic production compile with controlled fallback
#   handling and hardened output validation.
#
# Source policy:
#   - Clean game and extracted source are never modified.
#   - Original BTI bytes are preserved.
#   - Only temporary staged BTIs may be altered.
#
# Current explicit policies:
#
#   EXCLUDED:
#     textures\icons\special c black tortoise icon.tga
#
#   KNOWN FALLBACK:
#     textures\ui\ui map blue lagoon.tga
#       BC1 -> BC2 after confirmed BC1 compiler failure
#
#   PROVISIONAL BUT INCLUDED:
#     textures\special g griffon map.tga
#
# ============================================================

$Root = 'D:\AI_upscaling\AoMEE'

$PBRifyRoot    = Join-Path $Root 'processed\PBRify_V4'
$PBRifyShaPath = Join-Path $Root 'processed\PBRify_V4_sha256.csv'
$ExtractedRoot = Join-Path $Root 'extracted'
$Compiler      = Join-Path $Root 'tools\TextureCompiler.exe'

$DDTRoot       = Join-Path $Root 'processed\DDT_PBRify_V4'
$ManifestPath  = Join-Path $Root 'processed\PBRify_V4_compile_manifest.csv'
$LogPath       = Join-Path $Root 'processed\PBRify_V4_compile.log'

$StageRoot     = Join-Path $Root 'tests\production_full_compile_stage'

$ExpectedTotal = 7487

$ExcludedRelative = 'textures\icons\special c black tortoise icon.tga'
$ExpectedCompile  = 7486

# ------------------------------------------------------------
# Explicit known fallback policy.
#
# IMPORTANT:
# Do not automatically change formats for arbitrary failures.
# New failures must remain visible and require investigation.
# ------------------------------------------------------------

$KnownFallbackFormats = @{
    'textures\ui\ui map blue lagoon.tga' = 'BC2'
}

# ------------------------------------------------------------
# Provisional assets.
#
# These remain in the production candidate set but are marked
# explicitly in the manifest.
# ------------------------------------------------------------

$ProvisionalAssets = @{
    'textures\special g griffon map.tga' =
        'Recovered exception asset; bundled Gryphon asset family exists in the clean game; runtime usage not yet established.'
}

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

function Normalize-RelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return ($Path -replace '/', '\').TrimStart('\')
}

function Get-LogicalBTIRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$RelativeTGA
    )

    $relative = Normalize-RelativePath $RelativeTGA

    if (
        $relative.EndsWith(
            '.tga',
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        $relative =
            $relative.Substring(
                0,
                $relative.Length - 4
            )
    }

    return ($relative + '.bti')
}

function Get-LogicalRelativeFromExtracted {
    param(
        [Parameter(Mandatory)]
        [string]$FullPath
    )

    $rel =
        $FullPath.Substring(
            $ExtractedRoot.Length + 1
        )

    $rel = Normalize-RelativePath $rel

    if (
        $rel.StartsWith(
            'patched_to_verify\',
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        $rel =
            $rel.Substring(
                'patched_to_verify\'.Length
            )
    }

    return $rel
}

function Get-BTIFormat {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = [IO.File]::ReadAllBytes($Path)

    $text =
        [Text.Encoding]::UTF8.GetString(
            $raw
        )

    $match =
        [regex]::Match(
            $text,
            '\bfmt\s*=\s*([A-Za-z0-9_]+)',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

    if ($match.Success) {
        return $match.Groups[1].Value.ToUpperInvariant()
    }

    return ''
}

function Set-StagedBTIFormat {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$NewFormat
    )

    $raw = [IO.File]::ReadAllBytes($Path)

    $text =
        [Text.Encoding]::UTF8.GetString(
            $raw
        )

    $updated =
        [regex]::Replace(
            $text,
            '(\bfmt\s*=\s*)BC1\b',
            {
                param($m)
                return $m.Groups[1].Value + $NewFormat
            },
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

    if ($updated -eq $text) {
        throw "Could not replace BTI fmt=BC1 in staged BTI: $Path"
    }

    # Preserve BOM state from the staged text.
    $hasBom =
        $raw.Length -ge 3 -and
        $raw[0] -eq 0xEF -and
        $raw[1] -eq 0xBB -and
        $raw[2] -eq 0xBF

    $encoding =
        New-Object System.Text.UTF8Encoding(
            $hasBom
        )

    [IO.File]::WriteAllText(
        $Path,
        $updated,
        $encoding
    )
}

function Test-DdtUsable {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $item = Get-Item -LiteralPath $Path

        # Minimum structural size used by the current project audit.
        return ($item.Length -gt 24)
    }
    catch {
        return $false
    }
}

function Remove-InvalidDdt {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {

        if (-not (Test-DdtUsable -Path $Path)) {

            Remove-Item `
                -LiteralPath $Path `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-TextureCompiler {
    param(
        [Parameter(Mandatory)]
        [string]$InputTga,

        [Parameter(Mandatory)]
        [string]$OutputDdt
    )

    $output = @(
        & $Compiler `
            -i $InputTga `
            -o $OutputDdt `
            2>&1
    )

    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = @(
            $output |
            ForEach-Object {
                [string]$_
            }
        )
    }
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

# Fresh production output.

if (Test-Path -LiteralPath $DDTRoot) {
    Remove-Item `
        -LiteralPath $DDTRoot `
        -Recurse `
        -Force
}

if (Test-Path -LiteralPath $ManifestPath) {
    Remove-Item `
        -LiteralPath $ManifestPath `
        -Force
}

if (Test-Path -LiteralPath $LogPath) {
    Remove-Item `
        -LiteralPath $LogPath `
        -Force
}

if (Test-Path -LiteralPath $StageRoot) {
    Remove-Item `
        -LiteralPath $StageRoot `
        -Recurse `
        -Force
}

$null = New-Item `
    -ItemType Directory `
    -Force `
    -Path $DDTRoot

$null = New-Item `
    -ItemType Directory `
    -Force `
    -Path $StageRoot

# ------------------------------------------------------------
# Load authoritative PBRify SHA baseline.
# ------------------------------------------------------------

$SHARows = @(
    Import-Csv `
        -LiteralPath $PBRifyShaPath
)

if ($SHARows.Count -ne $ExpectedTotal) {
    throw `
        "Expected $ExpectedTotal PBRify SHA rows, " +
        "found $($SHARows.Count)."
}

$SHAMap = @{}

foreach ($row in $SHARows) {

    $key =
        (
            Normalize-RelativePath $row.RelativePath
        ).ToLowerInvariant()

    if ($SHAMap.ContainsKey($key)) {
        throw `
            "Duplicate PBRify SHA entry: " +
            $row.RelativePath
    }

    $SHAMap[$key] =
        $row.SHA256
}

# ------------------------------------------------------------
# Inventory production TGAs.
# ------------------------------------------------------------

$TGAs = @(
    Get-ChildItem `
        -LiteralPath $PBRifyRoot `
        -Filter '*.tga' `
        -Recurse `
        -File
)

if ($TGAs.Count -ne $ExpectedTotal) {
    throw `
        "Expected $ExpectedTotal production PBRify TGAs, " +
        "found $($TGAs.Count)."
}

$TGAByKey = @{}

foreach ($tga in $TGAs) {

    $relative =
        Normalize-RelativePath (
            $tga.FullName.Substring(
                $PBRifyRoot.Length + 1
            )
        )

    $key =
        $relative.ToLowerInvariant()

    if ($TGAByKey.ContainsKey($key)) {
        throw `
            "Duplicate production TGA relative path: $relative"
    }

    $TGAByKey[$key] = $tga
}

if (
    -not $TGAByKey.ContainsKey(
        $ExcludedRelative.ToLowerInvariant()
    )
) {
    throw `
        "Expected Black Tortoise exclusion was not found."
}

# ------------------------------------------------------------
# Index authoritative BTIs.
# ------------------------------------------------------------

$BTIIndex = @{}

$AllBTIs = @(
    Get-ChildItem `
        -LiteralPath $ExtractedRoot `
        -Filter '*.bti' `
        -Recurse `
        -File
)

foreach ($bti in $AllBTIs) {

    $logical =
        Get-LogicalRelativeFromExtracted `
            -FullPath $bti.FullName

    $key =
        $logical.ToLowerInvariant()

    if ($BTIIndex.ContainsKey($key)) {
        throw `
            "Duplicate authoritative BTI logical path: $logical`n" +
            "Existing: $($BTIIndex[$key])`n" +
            "Duplicate: $($bti.FullName)"
    }

    $BTIIndex[$key] =
        $bti.FullName
}

# ------------------------------------------------------------
# Start log.
# ------------------------------------------------------------

Write-Host "============================================"
Write-Host "AoM:EE PBRIFY V4 FULL COMPILE V2"
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

"=== AoM:EE PBRify V4 full compile V2 ===" |
    Set-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Started: $(Get-Date -Format o)" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Expected compile count: $ExpectedCompile" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Excluded: $ExcludedRelative" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

# ------------------------------------------------------------
# Manifest.
# ------------------------------------------------------------

$Results =
    [System.Collections.Generic.List[object]]::new()

$Compiled = 0
$SkippedExcluded = 0
$Failed = 0
$Warnings = 0
$Fallbacks = 0

$Index = 0

foreach ($tga in ($TGAs | Sort-Object FullName)) {

    $Index++

    $relative =
        Normalize-RelativePath (
            $tga.FullName.Substring(
                $PBRifyRoot.Length + 1
            )
        )

    $key =
        $relative.ToLowerInvariant()

    # --------------------------------------------------------
    # Explicit Black Tortoise exclusion.
    # --------------------------------------------------------

    if ($key -eq $ExcludedRelative.ToLowerInvariant()) {

        $SkippedExcluded++

        $Results.Add(
            [pscustomobject]@{
                RelativePath     = $relative
                SourceTgaSHA256  = $SHAMap[$key]
                SourceBtiSHA256  = ''
                OriginalBTIFormat = ''
                CompileFormat    = ''
                FallbackUsed     = 'NO'
                FallbackReason   = ''
                Provisional      = 'NO'
                ProvisionalReason = ''
                DDTSHA256        = ''
                DDTBytes         = ''
                CompilerExitCode = ''
                WarningCount     = ''
                Status           = 'EXCLUDED'
                ExcludedReason   =
                    'Unused/unreferenced legacy Black Tortoise asset; ' +
                    'archived for provenance only.'
            }
        )

        Write-Host `
            "[$Index/$ExpectedTotal] EXCLUDED: $relative"

        continue
    }

    # --------------------------------------------------------
    # Validate authoritative BTI pairing.
    # --------------------------------------------------------

    $logicalBTIRelative =
        Get-LogicalBTIRelativePath `
            -RelativeTGA $relative

    $btiKey =
        $logicalBTIRelative.ToLowerInvariant()

    if (-not $SHAMap.ContainsKey($key)) {
        throw `
            "PBRify SHA baseline missing: $relative"
    }

    if (-not $BTIIndex.ContainsKey($btiKey)) {
        throw `
            "Authoritative BTI missing for: $relative`n" +
            "Expected: $logicalBTIRelative"
    }

    $btiPath =
        $BTIIndex[$btiKey]

    # --------------------------------------------------------
    # Source hashes.
    # --------------------------------------------------------

    $expectedTgaSha =
        $SHAMap[$key]

    $actualTgaSha =
        (
            Get-FileHash `
                -LiteralPath $tga.FullName `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()

    if (
        $actualTgaSha -ne
        $expectedTgaSha.ToLowerInvariant()
    ) {
        throw `
            "Production TGA SHA-256 mismatch: $relative`n" +
            "Expected: $expectedTgaSha`n" +
            "Actual:   $actualTgaSha"
    }

    $sourceTgaSha =
        $actualTgaSha

    $sourceBtiSha =
        (
            Get-FileHash `
                -LiteralPath $btiPath `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()

    $originalFormat =
        Get-BTIFormat -Path $btiPath

    $compileFormat =
        $originalFormat

    $fallbackUsed = 'NO'
    $fallbackReason = ''

    $provisional = 'NO'
    $provisionalReason = ''

    if (
        $ProvisionalAssets.ContainsKey($key)
    ) {
        $provisional = 'YES'
        $provisionalReason =
            $ProvisionalAssets[$key]
    }

    # --------------------------------------------------------
    # Production output path.
    # --------------------------------------------------------

    $ddtRelative =
        $relative.Substring(
            0,
            $relative.Length - 4
        ) + '.ddt'

    $ddtPath =
        Join-Path `
            $DDTRoot `
            $ddtRelative

    $ddtDir =
        Split-Path -Parent $ddtPath

    $null = New-Item `
        -ItemType Directory `
        -Force `
        -Path $ddtDir

    # --------------------------------------------------------
    # Unique temporary staging.
    # --------------------------------------------------------

    $stageTga =
        Join-Path `
            $StageRoot `
            $relative

    $stageTgaDir =
        Split-Path -Parent $stageTga

    $null = New-Item `
        -ItemType Directory `
        -Force `
        -Path $stageTgaDir

    $stageBTI =
        [IO.Path]::ChangeExtension(
            $stageTga,
            '.bti'
        )

    Copy-Item `
        -LiteralPath $tga.FullName `
        -Destination $stageTga `
        -Force

    Copy-Item `
        -LiteralPath $btiPath `
        -Destination $stageBTI `
        -Force

    Write-Host `
        "[$Index/$ExpectedTotal] Compiling: $relative"

    try {

        # ----------------------------------------------------
        # Attempt 1: authoritative original format.
        # ----------------------------------------------------

        $attempt =
            Invoke-TextureCompiler `
                -InputTga $stageTga `
                -OutputDdt $ddtPath

        $exitCode =
            $attempt.ExitCode

        $outputLines =
            @(
                $attempt.Output
            )

        $warningLines =
            @(
                $outputLines |
                Where-Object {
                    $_ -match
                        'UNHANDLED token encountered'
                }
            )

        if ($warningLines.Count -gt 0) {

            $Warnings +=
                $warningLines.Count

            "[$relative]" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            $outputLines |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            "" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8
        }

        $success =
            (
                $exitCode -eq 0 -and
                (Test-DdtUsable -Path $ddtPath)
            )

        # ----------------------------------------------------
        # Remove invalid output before any fallback.
        # ----------------------------------------------------

        if (-not $success) {

            Remove-InvalidDdt `
                -Path $ddtPath
        }

        # ----------------------------------------------------
        # Explicit known fallback.
        #
        # Only run when:
        #   - original attempt failed
        #   - current texture has an allowlisted fallback
        #   - original format is BC1
        # ----------------------------------------------------

        if (
            -not $success -and
            $KnownFallbackFormats.ContainsKey($key) -and
            $originalFormat -eq 'BC1'
        ) {

            $fallbackFormat =
                $KnownFallbackFormats[$key]

            Write-Host `
                "[$Index/$ExpectedTotal] FALLBACK: " +
                "$relative  BC1 -> $fallbackFormat"

            "=== FALLBACK ===" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            "Texture: $relative" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            "Original format: $originalFormat" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            "Fallback format: $fallbackFormat" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            "Original exit code: $exitCode" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            $outputLines |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            "" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            # Change ONLY the staged BTI.
            Set-StagedBTIFormat `
                -Path $stageBTI `
                -NewFormat $fallbackFormat

            # Ensure no stale compiler output remains.
            Remove-InvalidDdt `
                -Path $ddtPath

            $fallbackAttempt =
                Invoke-TextureCompiler `
                    -InputTga $stageTga `
                    -OutputDdt $ddtPath

            $fallbackExitCode =
                $fallbackAttempt.ExitCode

            $fallbackOutputLines =
                @(
                    $fallbackAttempt.Output
                )

            $fallbackWarningLines =
                @(
                    $fallbackOutputLines |
                    Where-Object {
                        $_ -match
                            'UNHANDLED token encountered'
                    }
                )

            if (
                $fallbackWarningLines.Count -gt 0
            ) {
                $Warnings +=
                    $fallbackWarningLines.Count
            }

            $fallbackSuccess =
                (
                    $fallbackExitCode -eq 0 -and
                    (Test-DdtUsable -Path $ddtPath)
                )

            if ($fallbackSuccess) {

                $success = $true
                $compileFormat =
                    $fallbackFormat

                $fallbackUsed = 'YES'

                $fallbackReason =
                    'Authoritative BC1 compile failed; ' +
                    "tested $fallbackFormat fallback succeeded."

                $Fallbacks++

                "Fallback exit code: $fallbackExitCode" |
                    Add-Content `
                        -LiteralPath $LogPath `
                        -Encoding UTF8

                $fallbackOutputLines |
                    Add-Content `
                        -LiteralPath $LogPath `
                        -Encoding UTF8

                "" |
                    Add-Content `
                        -LiteralPath $LogPath `
                        -Encoding UTF8
            }
        }

        # ----------------------------------------------------
        # Final success/failure handling.
        # ----------------------------------------------------

        if ($success) {

            $ddtInfo =
                Get-Item `
                    -LiteralPath $ddtPath

            $ddtSha =
                (
                    Get-FileHash `
                        -LiteralPath $ddtPath `
                        -Algorithm SHA256
                ).Hash.ToLowerInvariant()

            $Compiled++

            $Results.Add(
                [pscustomobject]@{
                    RelativePath       = $relative
                    SourceTgaSHA256    = $sourceTgaSha
                    SourceBtiSHA256    = $sourceBtiSha
                    OriginalBTIFormat = $originalFormat
                    CompileFormat      = $compileFormat
                    FallbackUsed       = $fallbackUsed
                    FallbackReason     = $fallbackReason
                    Provisional        = $provisional
                    ProvisionalReason  = $provisionalReason
                    DDTSHA256          = $ddtSha
                    DDTBytes           = $ddtInfo.Length
                    CompilerExitCode   =
                        if ($fallbackUsed -eq 'YES') {
                            $fallbackExitCode
                        }
                        else {
                            $exitCode
                        }
                    WarningCount       =
                        $warningLines.Count
                    Status              =
                        if ($fallbackUsed -eq 'YES') {
                            'FALLBACK'
                        }
                        else {
                            'OK'
                        }
                    ExcludedReason     = ''
                }
            )

        }
        else {

            $Failed++

            Remove-InvalidDdt `
                -Path $ddtPath

            "=== COMPILE FAILURE ===" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            "Texture: $relative" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            "Original format: $originalFormat" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            "Exit code: $exitCode" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            $outputLines |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            "" |
                Add-Content `
                    -LiteralPath $LogPath `
                    -Encoding UTF8

            $Results.Add(
                [pscustomobject]@{
                    RelativePath       = $relative
                    SourceTgaSHA256    = $sourceTgaSha
                    SourceBtiSHA256    = $sourceBtiSha
                    OriginalBTIFormat = $originalFormat
                    CompileFormat      = $compileFormat
                    FallbackUsed       = 'NO'
                    FallbackReason     = ''
                    Provisional        = $provisional
                    ProvisionalReason  = $provisionalReason
                    DDTSHA256          = ''
                    DDTBytes           = ''
                    CompilerExitCode   = $exitCode
                    WarningCount       =
                        $warningLines.Count
                    Status              = 'FAIL'
                    ExcludedReason     = ''
                }
            )
        }

    }
    finally {

        # Never delete source files.
        Remove-Item `
            -LiteralPath $stageTga `
            -Force `
            -ErrorAction SilentlyContinue

        Remove-Item `
            -LiteralPath $stageBTI `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------
# Remove temporary stage tree.
# ------------------------------------------------------------

if (Test-Path -LiteralPath $StageRoot) {
    Remove-Item `
        -LiteralPath $StageRoot `
        -Recurse `
        -Force
}

# ------------------------------------------------------------
# Final DDT inventory.
#
# Invalid/zero-byte outputs should never survive.
# ------------------------------------------------------------

$AllDDTs = @(
    Get-ChildItem `
        -LiteralPath $DDTRoot `
        -Filter '*.ddt' `
        -Recurse `
        -File
)

foreach ($ddt in $AllDDTs) {

    if (-not (Test-DdtUsable -Path $ddt.FullName)) {

        Remove-Item `
            -LiteralPath $ddt.FullName `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

$DDTs = @(
    Get-ChildItem `
        -LiteralPath $DDTRoot `
        -Filter '*.ddt' `
        -Recurse `
        -File
)

$ddtKeys = @{}

foreach ($ddt in $DDTs) {

    $rel =
        Normalize-RelativePath (
            $ddt.FullName.Substring(
                $DDTRoot.Length + 1
            )
        )

    $key =
        $rel.ToLowerInvariant()

    if ($ddtKeys.ContainsKey($key)) {
        throw `
            "Duplicate output DDT relative path: $rel"
    }

    $ddtKeys[$key] = $ddt
}

$expectedCompileKeys = @(
    $TGAs |
    ForEach-Object {
        Normalize-RelativePath (
            $_.FullName.Substring(
                $PBRifyRoot.Length + 1
            )
        )
    } |
    Where-Object {
        $_.ToLowerInvariant() -ne
            $ExcludedRelative.ToLowerInvariant()
    } |
    ForEach-Object {
        $_.Substring(
            0,
            $_.Length - 4
        ) + '.ddt'
    } |
    ForEach-Object {
        $_.ToLowerInvariant()
    }
)

$missingDDTs = @(
    $expectedCompileKeys |
    Where-Object {
        -not $ddtKeys.ContainsKey($_)
    }
)

$unexpectedDDTs = @(
    $ddtKeys.Keys |
    Where-Object {
        $_ -notin $expectedCompileKeys
    }
)

# ------------------------------------------------------------
# Write manifest.
# ------------------------------------------------------------

$Results |
    Sort-Object RelativePath |
    Export-Csv `
        -LiteralPath $ManifestPath `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Final log summary.
# ------------------------------------------------------------

"" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Finished: $(Get-Date -Format o)" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Compiled: $Compiled" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Excluded: $SkippedExcluded" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Failed: $Failed" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Fallbacks: $Fallbacks" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Warnings: $Warnings" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"DDTs present: $($DDTs.Count)" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Missing DDTs: $($missingDDTs.Count)" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

"Unexpected DDTs: $($unexpectedDDTs.Count)" |
    Add-Content `
        -LiteralPath $LogPath `
        -Encoding UTF8

# ------------------------------------------------------------
# Console summary.
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================"
Write-Host "FULL CURRENT-BUILD COMPILE RESULT V2"
Write-Host "============================================"
Write-Host ""

Write-Host "Expected textures : $ExpectedCompile"
Write-Host "Compiled          : $Compiled"
Write-Host "DDTs present      : $($DDTs.Count)"
Write-Host "Excluded          : $SkippedExcluded"
Write-Host "Fallbacks         : $Fallbacks"
Write-Host "Failures          : $Failed"
Write-Host "Warning tokens    : $Warnings"
Write-Host "Missing DDTs      : $($missingDDTs.Count)"
Write-Host "Unexpected DDTs   : $($unexpectedDDTs.Count)"
Write-Host ""

if ($missingDDTs.Count -gt 0) {

    Write-Host "MISSING DDTs:"
    $missingDDTs |
        ForEach-Object {
            Write-Host "  $_"
        }

    Write-Host ""
}

if ($unexpectedDDTs.Count -gt 0) {

    Write-Host "UNEXPECTED DDTs:"
    $unexpectedDDTs |
        ForEach-Object {
            Write-Host "  $_"
        }

    Write-Host ""
}

$pass = (
    $Compiled -eq $ExpectedCompile -and
    $DDTs.Count -eq $ExpectedCompile -and
    $SkippedExcluded -eq 1 -and
    $Fallbacks -eq 1 -and
    $Failed -eq 0 -and
    $missingDDTs.Count -eq 0 -and
    $unexpectedDDTs.Count -eq 0
)

if ($pass) {

    Write-Host `
        "FULL CURRENT-BUILD PBRIFY V4 COMPILE: PASS"

    exit 0
}

Write-Host `
    "FULL CURRENT-BUILD PBRIFY V4 COMPILE: FAIL"

exit 1