$ErrorActionPreference = 'Stop'

# ============================================================
# AoM:EE PBRIFY V4 — FULL EXPLICIT-FORMAT DDT COMPILE V3
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

$DDTRoot       = Join-Path $Root 'processed\DDT_PBRify_V4_explicit'
$ManifestPath  = Join-Path $Root 'processed\PBRify_V4_explicit_compile_manifest.csv'
$LogPath       = Join-Path $Root 'processed\PBRify_V4_explicit_compile.log'

$StageRoot     = Join-Path $Root 'tests\production_explicit_compile_stage'

$ExpectedTotal = 7487

$ExcludedRelative = 'textures\icons\special c black tortoise icon.tga'
$ExpectedCompile  = 7486

# Exact compiler CLI spellings. Do not uppercase these strings.
$CLIFormats = @{
    'BC1'           = 'BC1'
    'BC2'           = 'BC2'
    'BC3'           = 'BC3'
    'DEFLATEDRGBA8' = 'DeflatedRGBA8'
    'DEFLATEDRGB8'  = 'DeflatedRGB8'
}

$ExpectedFormatBytes = @{
    'BC1'           = 4
    'BC2'           = 8
    'BC3'           = 9
    'DEFLATEDRGBA8' = 10
    'DEFLATEDRGB8'  = 11
}


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


function Write-StagedBTI {
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Destination,
          [Parameter(Mandatory)][string]$ForcedFormat)

    $raw = [IO.File]::ReadAllBytes($Source)
    $hadBom = $raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF
    $text = [Text.Encoding]::UTF8.GetString($raw)

    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) {
        $text = $text.Substring(1)
    }

    $text = [regex]::Replace(
        $text,
        '(fmts*=s*)[A-Za-z0-9_]+',
        { param($m) $m.Groups[1].Value + $ForcedFormat },
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $dir = Split-Path -Parent $Destination
    $null = New-Item -ItemType Directory -Force -Path $dir
    [IO.File]::WriteAllText($Destination,$text,(New-Object System.Text.UTF8Encoding($false)))

    return [pscustomobject]@{ HadBom = $hadBom }
}

function Read-TgaBasic {
    param([Parameter(Mandatory)][string]$Path)

    $data = [IO.File]::ReadAllBytes($Path)
    if ($data.Length -lt 18) { throw "TGA shorter than 18 bytes: $Path" }

    return [pscustomobject]@{
        ImageType = [int]$data[2]
        Width = [int][BitConverter]::ToUInt16($data,12)
        Height = [int][BitConverter]::ToUInt16($data,14)
        Bits = [int]$data[16]
        Descriptor = [int]$data[17]
    }
}

function Convert-Tga32To24 {
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Destination)

    $src = [IO.File]::ReadAllBytes($Source)
    if ($src.Length -lt 18) { throw "TGA shorter than 18 bytes: $Source" }
    if ($src[1] -ne 0 -or $src[2] -ne 2 -or $src[16] -ne 32) {
        throw "DeflatedRGB8 staging requires uncompressed 32-bit true-color TGA type 2: $Source"
    }

    $width = [int][BitConverter]::ToUInt16($src,12)
    $height = [int][BitConverter]::ToUInt16($src,14)
    $imageStart = 18 + [int]$src[0]
    $pixelCount = [int64]$width * [int64]$height
    $sourcePixels = $pixelCount * 4
    $destPixels = $pixelCount * 3

    if ($imageStart + $sourcePixels -gt $src.Length) {
        throw "TGA pixel payload exceeds file bounds: $Source"
    }

    $destLength = [int]($src.Length - $pixelCount)
    $dst = New-Object byte[] $destLength
    [Array]::Copy($src,0,$dst,0,$imageStart)

    $dst[16] = 24
    $dst[17] = $src[17] -band 0xF0

    $srcPos = $imageStart
    $dstPos = $imageStart

    for ($i=[int64]0; $i -lt $pixelCount; $i++) {
        $dst[$dstPos] = $src[$srcPos]
        $dst[$dstPos+1] = $src[$srcPos+1]
        $dst[$dstPos+2] = $src[$srcPos+2]
        $srcPos += 4
        $dstPos += 3
    }

    $srcTail = $imageStart + [int]$sourcePixels
    $dstTail = $imageStart + [int]$destPixels
    $tailLength = $src.Length - $srcTail

    if ($tailLength -gt 0) {
        [Array]::Copy($src,$srcTail,$dst,$dstTail,$tailLength)
    }

    $dir = Split-Path -Parent $Destination
    $null = New-Item -ItemType Directory -Force -Path $dir
    [IO.File]::WriteAllBytes($Destination,$dst)

    $check = Read-TgaBasic -Path $Destination
    if ($check.Width -ne $width -or $check.Height -ne $height -or $check.Bits -ne 24) {
        throw "24-bit TGA validation failed: $Destination"
    }
}

function Read-DDTHeader {
    param([Parameter(Mandatory)][string]$Path)

    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 16) { throw "DDT shorter than fixed header: $Path" }

    return [pscustomobject]@{
        Magic = [Text.Encoding]::ASCII.GetString($b,0,4)
        Properties = [int]$b[4]
        AlphaBits = [int]$b[5]
        Format = [int]$b[6]
        Mips = [int]$b[7]
        Width = [int][BitConverter]::ToUInt32($b,8)
        Height = [int][BitConverter]::ToUInt32($b,12)
        Bytes = (Get-Item -LiteralPath $Path).Length
    }
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
    param([Parameter(Mandatory)][string]$InputTga,
          [Parameter(Mandatory)][string]$OutputDdt,
          [Parameter(Mandatory)][string]$CliFormat)

    $output = @(& $Compiler -c $CliFormat -i $InputTga -o $OutputDdt 2>&1)

    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = @($output | ForEach-Object { [string]$_ })
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

"Expected compile count: $ExpectedCompile"
"Explicit formats: BC1, BC2, BC3, DeflatedRGBA8, DeflatedRGB8" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"DeflatedRGB8 input staging: true 24-bit TGA" | Add-Content -LiteralPath $LogPath -Encoding UTF8 |
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

    $btiInfo = Write-StagedBTI -Source $btiPath -Destination $stageBTI -ForcedFormat $originalFormat

    $sourceInfo = Read-TgaBasic -Path $tga.FullName
    $compileTga = $stageTga
    $compileBits = $sourceInfo.Bits

    if ($originalFormat -eq 'DEFLATEDRGB8') {
        $rgb24Path = Join-Path $caseRoot 'rgb24_input.tga'
        Convert-Tga32To24 -Source $stageTga -Destination $rgb24Path
        $compileTga = $rgb24Path
        $compileBits = 24
    }

    Write-Host "[$Index/$ExpectedTotal] Compiling: $relative -> $cliFormat (input $compileBits-bit)"

    try {

        # ----------------------------------------------------
        # Explicit compile using canonical CLI spelling.
        # ----------------------------------------------------

        $cliFormat = $CLIFormats[$originalFormat]
        if (-not $cliFormat) {
            throw "No CLI format mapping for $originalFormat"
        }

        $attempt = Invoke-TextureCompiler -InputTga $compileTga -OutputDdt $ddtPath -CliFormat $cliFormat
        $exitCode = $attempt.ExitCode
        $outputLines = @($attempt.Output)

        $warningLines = @($outputLines | Where-Object { $_ -match 'UNHANDLED token encountered' })
        if ($warningLines.Count -gt 0) { $Warnings += $warningLines.Count }

        $success = $false
        $hdr = $null
        $usedExitCode = $exitCode
        $usedCliFormat = $cliFormat

        if ($exitCode -eq 0 -and (Test-Path -LiteralPath $ddtPath) -and (Get-Item -LiteralPath $ddtPath).Length -gt 24) {
            $hdr = Read-DDTHeader -Path $ddtPath
            $expectedByte = $ExpectedFormatBytes[$originalFormat]

            $success = (
                $hdr.Magic -eq 'RTS3' -and
                $hdr.Format -eq $expectedByte -and
                $hdr.AlphaBits -eq $btiInfo.AlphaBits -and
                $hdr.Width -eq $sourceInfo.Width -and
                $hdr.Height -eq $sourceInfo.Height
            )
        }

        # ----------------------------------------------------
        # Only the known Blue Lagoon BC1 fallback is allowed.
        # ----------------------------------------------------

        if (-not $success -and $KnownFallbackFormats.ContainsKey($key) -and $originalFormat -eq 'BC1') {
            Remove-Item -LiteralPath $ddtPath -Force -ErrorAction SilentlyContinue

            $fallbackFormat = $KnownFallbackFormats[$key]
            $fallbackCli = $CLIFormats[$fallbackFormat]

            $null = Write-StagedBTI -Source $btiPath -Destination $stageBTI -ForcedFormat $fallbackFormat

            $fallbackAttempt = Invoke-TextureCompiler -InputTga $compileTga -OutputDdt $ddtPath -CliFormat $fallbackCli
            $fallbackOutput = @($fallbackAttempt.Output)
            $Warnings += @($fallbackOutput | Where-Object { $_ -match 'UNHANDLED token encountered' }).Count

            $usedExitCode = $fallbackAttempt.ExitCode
            $usedCliFormat = $fallbackCli
            $outputLines += $fallbackOutput

            if ($fallbackAttempt.ExitCode -eq 0 -and (Test-Path -LiteralPath $ddtPath) -and (Get-Item -LiteralPath $ddtPath).Length -gt 24) {
                $hdr = Read-DDTHeader -Path $ddtPath
                $success = (
                    $hdr.Magic -eq 'RTS3' -and
                    $hdr.Format -eq $ExpectedFormatBytes[$fallbackFormat] -and
                    $hdr.AlphaBits -eq $btiInfo.AlphaBits -and
                    $hdr.Width -eq $sourceInfo.Width -and
                    $hdr.Height -eq $sourceInfo.Height
                )
            }

            if ($success) {
                $compileFormat = $fallbackFormat
                $fallbackUsed = 'YES'
                $fallbackReason = 'Confirmed legacy BC1 compiler failure; explicit BC2 fallback succeeded.'
                $Fallbacks++
            }
        }

        if (-not $success) {
            $compileFormat = $originalFormat
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
                    WarningCount       = $warningLines.Count
                    RequestedCLIFormat = $cliFormat
                    CompilerInputBits = $compileBits
                    ActualDDTFormatByte = $hdr.Format
                    ActualDDTAlphaBits = $hdr.AlphaBits
                    DDTWidth = $hdr.Width
                    DDTHeight = $hdr.Height
                    StagedBTIBomRemoved = if ($btiInfo.HadBom) { 'YES' } else { 'NO' }
                    Status              =
                        if ($fallbackUsed -eq 'YES') { 'FALLBACK' } else { 'OK' }
                    RequestedCLIFormat = $cliFormat
                    CompilerInputBits = $compileBits
                    ActualDDTFormatByte = $hdr.Format
                    ActualDDTAlphaBits = $hdr.AlphaBits
                    DDTWidth = $hdr.Width
                    DDTHeight = $hdr.Height
                    StagedBTIBomRemoved = if ($btiInfo.HadBom) { 'YES' } else { 'NO' }
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
                    RequestedCLIFormat = $cliFormat
                    CompilerInputBits = $compileBits
                    ActualDDTFormatByte = if ($hdr) { $hdr.Format } else { '' }
                    ActualDDTAlphaBits = if ($hdr) { $hdr.AlphaBits } else { '' }
                    DDTWidth = if ($hdr) { $hdr.Width } else { '' }
                    DDTHeight = if ($hdr) { $hdr.Height } else { '' }
                    StagedBTIBomRemoved = if ($btiInfo.HadBom) { 'YES' } else { 'NO' }
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
Write-Host "FULL EXPLICIT COMPILE RESULT V3 V2"
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
        "FULL EXPLICIT PBRIFY V4 COMPILE V3: PASS"

    exit 0
}

Write-Host `
    "FULL EXPLICIT PBRIFY V4 COMPILE V3: FAIL"

exit 1