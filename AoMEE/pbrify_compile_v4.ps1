$ErrorActionPreference = 'Stop'

# ============================================================
# AoM:EE PBRIFY V4 - FULL EXPLICIT-FORMAT DDT COMPILE V4
#
# Production strategy proven by the 10/10 explicit canary:
#
#   BC1             32-bit TGA + -c BC1
#   BC2             32-bit TGA + -c BC2
#   BC3             32-bit TGA + -c BC3
#   DeflatedRGBA8   32-bit TGA + -c DeflatedRGBA8
#   DeflatedRGB8    TRUE 24-bit temporary TGA + -c DeflatedRGB8
#
# Compiler hygiene:
#   * Authoritative BTI files are never modified.
#   * Staged BTIs are UTF-8 without BOM.
#   * Exact compiler CLI spellings are preserved.
#   * Every successful DDT is checked immediately against its
#     expected DDT header format, alpha and dimensions.
#   * Only Blue Lagoon has an allowlisted BC1 -> BC2 fallback.
#
# Output:
#   processed\DDT_PBRify_V4_explicit
#   processed\PBRify_V4_explicit_compile_manifest.csv
#   processed\PBRify_V4_explicit_compile.log
#
# Source roots never modified:
#   Age of Mythology\
#   extracted\
#   processed\PBRify_V4\
# ============================================================

$Root = 'D:\AI_upscaling\AoMEE'

$PBRifyRoot = Join-Path $Root 'processed\PBRify_V4'
$PBRifyShaPath = Join-Path $Root 'processed\PBRify_V4_sha256.csv'
$ExtractedRoot = Join-Path $Root 'extracted'
$Compiler = Join-Path $Root 'tools\TextureCompiler.exe'

$DDTRoot = Join-Path $Root 'processed\DDT_PBRify_V4_explicit'
$ManifestPath = Join-Path $Root 'processed\PBRify_V4_explicit_compile_manifest.csv'
$LogPath = Join-Path $Root 'processed\PBRify_V4_explicit_compile.log'
$StageRoot = Join-Path $Root 'tests\production_explicit_compile_stage'

$ExpectedTotal = 7487
$ExpectedCompile = 7486

$ExcludedRelative = 'textures\icons\special c black tortoise icon.tga'
$BlueLagoon = 'textures\ui\ui map blue lagoon.tga'

$CLIFormats = @{
    'BC1' = 'BC1'
    'BC2' = 'BC2'
    'BC3' = 'BC3'
    'DEFLATEDRGBA8' = 'DeflatedRGBA8'
    'DEFLATEDRGB8' = 'DeflatedRGB8'
}

$ExpectedFormatBytes = @{
    'BC1' = 4
    'BC2' = 8
    'BC3' = 9
    'DEFLATEDRGBA8' = 10
    'DEFLATEDRGB8' = 11
}

$KnownFallbackFormats = @{
    $BlueLagoon = 'BC2'
}

$ProvisionalAssets = @{
    'textures\special g griffon map.tga' =
        'Recovered exception asset; bundled Gryphon family exists in the clean game; runtime usage not yet established.'
}

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

    return $relative + '.bti'
}

function Get-LogicalRelativeFromExtracted {
    param([Parameter(Mandatory)][string]$FullPath)

    $relative = Normalize-RelativePath $FullPath.Substring($ExtractedRoot.Length + 1)

    if ($relative.StartsWith('patched_to_verify\', [StringComparison]::OrdinalIgnoreCase)) {
        $relative = $relative.Substring('patched_to_verify\'.Length)
    }

    return $relative
}

function Read-BTIInfo {
    param([Parameter(Mandatory)][string]$Path)

    $raw = [IO.File]::ReadAllBytes($Path)
    $hadBom = $raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF
    $text = [Text.Encoding]::UTF8.GetString($raw)

    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) {
        $text = $text.Substring(1)
    }

    $fmtMatch = [regex]::Match(
        $text,
        '\bfmt\s*=\s*([A-Za-z0-9_]+)',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $alphaMatch = [regex]::Match(
        $text,
        '\balpha\s*=\s*(\d+)',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if (-not $fmtMatch.Success) {
        throw "BTI missing fmt=: $Path"
    }

    if (-not $alphaMatch.Success) {
        throw "BTI missing alpha=: $Path"
    }

    return [pscustomobject]@{
        Text = $text
        Format = $fmtMatch.Groups[1].Value.ToUpperInvariant()
        AlphaBits = [int]$alphaMatch.Groups[1].Value
        HadBom = $hadBom
    }
}

function Write-StagedBTI {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$ForcedFormat
    )

    $info = Read-BTIInfo -Path $Source

    $text = [regex]::Replace(
        $info.Text,
        '(\bfmt\s*=\s*)[A-Za-z0-9_]+',
        { param($m) $m.Groups[1].Value + $ForcedFormat },
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $dir = Split-Path -Parent $Destination
    $null = New-Item -ItemType Directory -Force -Path $dir

    [IO.File]::WriteAllText(
        $Destination,
        $text,
        (New-Object System.Text.UTF8Encoding($false))
    )

    return $info
}

function Read-TgaBasic {
    param([Parameter(Mandatory)][string]$Path)

    $data = [IO.File]::ReadAllBytes($Path)

    if ($data.Length -lt 18) {
        throw "TGA shorter than 18 bytes: $Path"
    }

    return [pscustomobject]@{
        ImageType = [int]$data[2]
        Width = [int][BitConverter]::ToUInt16($data, 12)
        Height = [int][BitConverter]::ToUInt16($data, 14)
        Bits = [int]$data[16]
        Descriptor = [int]$data[17]
        IdLength = [int]$data[0]
    }
}

function Convert-Tga32To24 {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $src = [IO.File]::ReadAllBytes($Source)

    if ($src.Length -lt 18) {
        throw "TGA shorter than 18 bytes: $Source"
    }

    if ($src[1] -ne 0 -or $src[2] -ne 2 -or $src[16] -ne 32) {
        throw "DeflatedRGB8 staging requires uncompressed 32-bit true-color TGA type 2: $Source"
    }

    $width = [int][BitConverter]::ToUInt16($src, 12)
    $height = [int][BitConverter]::ToUInt16($src, 14)
    $imageStart = 18 + [int]$src[0]
    $pixelCount = [int64]$width * [int64]$height
    $sourcePixels = $pixelCount * 4
    $destPixels = $pixelCount * 3

    if ($imageStart + $sourcePixels -gt $src.Length) {
        throw "TGA pixel payload exceeds file bounds: $Source"
    }

    # The temporary 24-bit TGA intentionally contains only the header,
    # image ID and pixel data. Dropping the original footer/extension data
    # avoids leaving stale file offsets after removing one byte per pixel.
    $destLength = [int]($imageStart + $destPixels)
    $dst = New-Object byte[] $destLength

    [Array]::Copy($src, 0, $dst, 0, $imageStart)

    $dst[16] = 24
    $dst[17] = $src[17] -band 0xF0

    $srcPos = $imageStart
    $dstPos = $imageStart

    for ($i = [int64]0; $i -lt $pixelCount; $i++) {
        $dst[$dstPos] = $src[$srcPos]
        $dst[$dstPos + 1] = $src[$srcPos + 1]
        $dst[$dstPos + 2] = $src[$srcPos + 2]

        $srcPos += 4
        $dstPos += 3
    }

    $dir = Split-Path -Parent $Destination
    $null = New-Item -ItemType Directory -Force -Path $dir
    [IO.File]::WriteAllBytes($Destination, $dst)

    $check = Read-TgaBasic -Path $Destination

    if ($check.Width -ne $width -or $check.Height -ne $height -or $check.Bits -ne 24) {
        throw "24-bit TGA validation failed: $Destination"
    }
}

function Read-DDTHeader {
    param([Parameter(Mandatory)][string]$Path)

    $data = [IO.File]::ReadAllBytes($Path)

    if ($data.Length -lt 16) {
        throw "DDT shorter than 16-byte fixed header: $Path"
    }

    return [pscustomobject]@{
        Magic = [Text.Encoding]::ASCII.GetString($data, 0, 4)
        Properties = [int]$data[4]
        AlphaBits = [int]$data[5]
        Format = [int]$data[6]
        Mips = [int]$data[7]
        Width = [int][BitConverter]::ToUInt32($data, 8)
        Height = [int][BitConverter]::ToUInt32($data, 12)
        Bytes = (Get-Item -LiteralPath $Path).Length
    }
}

function Invoke-TextureCompiler {
    param(
        [Parameter(Mandatory)][string]$InputTga,
        [Parameter(Mandatory)][string]$OutputDdt,
        [Parameter(Mandatory)][string]$CliFormat
    )

    $output = @(& $Compiler -c $CliFormat -i $InputTga -o $OutputDdt 2>&1)

    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

foreach ($required in @($PBRifyRoot, $PBRifyShaPath, $ExtractedRoot, $Compiler)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path not found: $required"
    }
}

foreach ($path in @($DDTRoot, $StageRoot)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

foreach ($path in @($ManifestPath, $LogPath)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

$null = New-Item -ItemType Directory -Force -Path $DDTRoot
$null = New-Item -ItemType Directory -Force -Path $StageRoot

$shaRows = @(Import-Csv -LiteralPath $PBRifyShaPath)

if ($shaRows.Count -ne $ExpectedTotal) {
    throw "Expected $ExpectedTotal PBRify SHA rows, found $($shaRows.Count)"
}

$shaMap = @{}

foreach ($row in $shaRows) {
    $key = (Normalize-RelativePath $row.RelativePath).ToLowerInvariant()

    if ($shaMap.ContainsKey($key)) {
        throw "Duplicate PBRify SHA entry: $($row.RelativePath)"
    }

    $shaMap[$key] = $row.SHA256.ToLowerInvariant()
}

$allTga = @(Get-ChildItem -LiteralPath $PBRifyRoot -Filter '*.tga' -Recurse -File)

if ($allTga.Count -ne $ExpectedTotal) {
    throw "Expected $ExpectedTotal PBRify TGAs, found $($allTga.Count)"
}

$tgaMap = @{}

foreach ($tga in $allTga) {
    $relative = Normalize-RelativePath $tga.FullName.Substring($PBRifyRoot.Length + 1)
    $key = $relative.ToLowerInvariant()

    if ($tgaMap.ContainsKey($key)) {
        throw "Duplicate PBRify TGA relative path: $relative"
    }

    $tgaMap[$key] = $tga
}

if (-not $tgaMap.ContainsKey($ExcludedRelative.ToLowerInvariant())) {
    throw "Expected Black Tortoise exclusion not found: $ExcludedRelative"
}

$btiMap = @{}
$allBti = @(Get-ChildItem -LiteralPath $ExtractedRoot -Filter '*.bti' -Recurse -File)

foreach ($bti in $allBti) {
    $logical = Get-LogicalRelativeFromExtracted $bti.FullName
    $key = $logical.ToLowerInvariant()

    if ($btiMap.ContainsKey($key)) {
        throw "Duplicate authoritative BTI logical path: $logical"
    }

    $btiMap[$key] = $bti.FullName
}

Write-Host "============================================"
Write-Host "AoM:EE PBRIFY V4 FULL EXPLICIT COMPILE V4"
Write-Host "============================================"
Write-Host ""
Write-Host "Production TGAs      : $($allTga.Count)"
Write-Host "Expected total       : $ExpectedTotal"
Write-Host "Expected compilation : $ExpectedCompile"
Write-Host "Excluded             : $ExcludedRelative"
Write-Host "Compiler              : $Compiler"
Write-Host "DDT output            : $DDTRoot"
Write-Host "RGB8 staging          : TRUE 24-bit temporary TGA"
Write-Host "BTI staging           : UTF-8 without BOM"
Write-Host ""

"=== AoM:EE PBRify V4 full explicit compile V4 ===" | Set-Content -LiteralPath $LogPath -Encoding UTF8
"Started: $(Get-Date -Format o)" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Expected compilation count: $ExpectedCompile" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Explicit formats: BC1, BC2, BC3, DeflatedRGBA8, DeflatedRGB8" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"DeflatedRGB8 input staging: true 24-bit TGA" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Known fallback: Blue Lagoon BC1 -> BC2" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"" | Add-Content -LiteralPath $LogPath -Encoding UTF8

$Results = [System.Collections.Generic.List[object]]::new()

$compiled = 0
$excluded = 0
$failed = 0
$fallbacks = 0
$warnings = 0
$index = 0

foreach ($tga in ($allTga | Sort-Object FullName)) {
    $index++

    $relative = Normalize-RelativePath $tga.FullName.Substring($PBRifyRoot.Length + 1)
    $key = $relative.ToLowerInvariant()

    if ($key -eq $ExcludedRelative.ToLowerInvariant()) {
        $excluded++

        $Results.Add([pscustomobject]@{
            RelativePath = $relative
            SourceTgaSHA256 = $shaMap[$key]
            SourceBtiSHA256 = ''
            OriginalBTIFormat = ''
            RequestedCLIFormat = ''
            ActualCompileFormat = ''
            CompilerInputBits = ''
            AuthoritativeAlphaBits = ''
            ActualDDTFormatByte = ''
            ExpectedDDTFormatByte = ''
            ActualDDTAlphaBits = ''
            DDTWidth = ''
            DDTHeight = ''
            DDTMipLevels = ''
            DDTSHA256 = ''
            DDTBytes = ''
            CompilerExitCode = ''
            WarningCount = ''
            StagedBTIBomRemoved = ''
            FallbackUsed = 'NO'
            FallbackReason = ''
            Provisional = 'NO'
            ProvisionalReason = ''
            Status = 'EXCLUDED'
            FailureReason = ''
        })

        Write-Host "[$index/$ExpectedTotal] EXCLUDED: $relative"
        continue
    }

    if (-not $shaMap.ContainsKey($key)) {
        throw "PBRify SHA baseline missing: $relative"
    }

    $logicalBti = Get-LogicalBTIRelativePath $relative
    $btiKey = $logicalBti.ToLowerInvariant()

    if (-not $btiMap.ContainsKey($btiKey)) {
        throw "Authoritative BTI missing: $logicalBti"
    }

    $btiPath = $btiMap[$btiKey]
    $btiInfo = Read-BTIInfo -Path $btiPath
    $originalFormat = $btiInfo.Format

    if (-not $CLIFormats.ContainsKey($originalFormat)) {
        throw "Unsupported production BTI format '$originalFormat': $relative"
    }

    $sourceInfo = Read-TgaBasic -Path $tga.FullName

    if ($sourceInfo.Bits -ne 32) {
        throw "PBRify source is not 32-bit: $relative (bpp=$($sourceInfo.Bits))"
    }

    $compileTga = $tga.FullName
    $compileBits = 32

    $caseRoot = Join-Path $StageRoot ('{0:D5}' -f $index)
    $null = New-Item -ItemType Directory -Force -Path $caseRoot

    $stageTga = Join-Path $caseRoot ([IO.Path]::GetFileName($relative))
    $stageBti = [IO.Path]::ChangeExtension($stageTga, '.bti')

    Copy-Item -LiteralPath $tga.FullName -Destination $stageTga -Force
    $null = Write-StagedBTI -Source $btiPath -Destination $stageBti -ForcedFormat $originalFormat

    if ($originalFormat -eq 'DEFLATEDRGB8') {
        $compileTga = Join-Path $caseRoot 'rgb24_input.tga'
        Convert-Tga32To24 -Source $stageTga -Destination $compileTga
        $compileBits = 24
    }

    $cliFormat = $CLIFormats[$originalFormat]
    $ddtRelative = $relative.Substring(0, $relative.Length - 4) + '.ddt'
    $ddtPath = Join-Path $DDTRoot $ddtRelative
    $ddtDir = Split-Path -Parent $ddtPath
    $null = New-Item -ItemType Directory -Force -Path $ddtDir

    Write-Host "[$index/$ExpectedTotal] Compiling: $relative -> $cliFormat (input $compileBits-bit)"

    $attempt = Invoke-TextureCompiler -InputTga $compileTga -OutputDdt $ddtPath -CliFormat $cliFormat

    $attemptOutput = @($attempt.Output)
    $attemptWarnings = @($attemptOutput | Where-Object { $_ -match 'UNHANDLED token encountered' }).Count
    $warnings += $attemptWarnings

    $success = $false
    $header = $null
    $usedCliFormat = $cliFormat
    $usedExitCode = $attempt.ExitCode
    $compileFormat = $originalFormat
    $fallbackUsed = 'NO'
    $fallbackReason = ''

    if ($attempt.ExitCode -eq 0 -and (Test-Path -LiteralPath $ddtPath) -and (Get-Item -LiteralPath $ddtPath).Length -gt 24) {
        $header = Read-DDTHeader -Path $ddtPath
        $expectedByte = $ExpectedFormatBytes[$originalFormat]

        $success = (
            $header.Magic -eq 'RTS3' -and
            $header.Format -eq $expectedByte -and
            $header.AlphaBits -eq $btiInfo.AlphaBits -and
            $header.Width -eq $sourceInfo.Width -and
            $header.Height -eq $sourceInfo.Height
        )
    }

    if (-not $success -and $relative.ToLowerInvariant() -eq $BlueLagoon.ToLowerInvariant() -and $originalFormat -eq 'BC1') {
        Remove-Item -LiteralPath $ddtPath -Force -ErrorAction SilentlyContinue

        $fallbackFormat = $KnownFallbackFormats[$BlueLagoon]
        $fallbackCli = $CLIFormats[$fallbackFormat]

        $null = Write-StagedBTI -Source $btiPath -Destination $stageBti -ForcedFormat $fallbackFormat

        $fallbackAttempt = Invoke-TextureCompiler -InputTga $compileTga -OutputDdt $ddtPath -CliFormat $fallbackCli
        $fallbackOutput = @($fallbackAttempt.Output)
        $warnings += @($fallbackOutput | Where-Object { $_ -match 'UNHANDLED token encountered' }).Count

        $attemptOutput += $fallbackOutput
        $usedCliFormat = $fallbackCli
        $usedExitCode = $fallbackAttempt.ExitCode

        if ($fallbackAttempt.ExitCode -eq 0 -and (Test-Path -LiteralPath $ddtPath) -and (Get-Item -LiteralPath $ddtPath).Length -gt 24) {
            $header = Read-DDTHeader -Path $ddtPath

            $success = (
                $header.Magic -eq 'RTS3' -and
                $header.Format -eq $ExpectedFormatBytes[$fallbackFormat] -and
                $header.AlphaBits -eq $btiInfo.AlphaBits -and
                $header.Width -eq $sourceInfo.Width -and
                $header.Height -eq $sourceInfo.Height
            )
        }

        if ($success) {
            $compileFormat = $fallbackFormat
            $fallbackUsed = 'YES'
            $fallbackReason = 'Confirmed legacy BC1 compiler failure; explicit BC2 fallback succeeded.'
            $fallbacks++
        }
    }

    "[$relative]" | Add-Content -LiteralPath $LogPath -Encoding UTF8
    $attemptOutput | Add-Content -LiteralPath $LogPath -Encoding UTF8
    "" | Add-Content -LiteralPath $LogPath -Encoding UTF8

    $provisional = 'NO'
    $provisionalReason = ''

    if ($ProvisionalAssets.ContainsKey($key)) {
        $provisional = 'YES'
        $provisionalReason = $ProvisionalAssets[$key]
    }

    if ($success) {
        $ddtInfo = Get-Item -LiteralPath $ddtPath
        $ddtSha = (Get-FileHash -LiteralPath $ddtPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $compiled++

        $Results.Add([pscustomobject]@{
            RelativePath = $relative
            SourceTgaSHA256 = $shaMap[$key]
            SourceBtiSHA256 = (Get-FileHash -LiteralPath $btiPath -Algorithm SHA256).Hash.ToLowerInvariant()
            OriginalBTIFormat = $originalFormat
            RequestedCLIFormat = $cliFormat
            ActualCompileFormat = $compileFormat
            CompilerInputBits = $compileBits
            AuthoritativeAlphaBits = $btiInfo.AlphaBits
            ActualDDTFormatByte = $header.Format
            ExpectedDDTFormatByte = $ExpectedFormatBytes[$compileFormat]
            ActualDDTAlphaBits = $header.AlphaBits
            DDTWidth = $header.Width
            DDTHeight = $header.Height
            DDTMipLevels = $header.Mips
            DDTSHA256 = $ddtSha
            DDTBytes = $ddtInfo.Length
            CompilerExitCode = $usedExitCode
            WarningCount = $attemptWarnings
            StagedBTIBomRemoved = if ($btiInfo.HadBom) { 'YES' } else { 'NO' }
            FallbackUsed = $fallbackUsed
            FallbackReason = $fallbackReason
            Provisional = $provisional
            ProvisionalReason = $provisionalReason
            Status = if ($fallbackUsed -eq 'YES') { 'FALLBACK' } else { 'OK' }
            FailureReason = ''
        })
    }
    else {
        $failed++
        Remove-Item -LiteralPath $ddtPath -Force -ErrorAction SilentlyContinue

        $failureReason = "RequestedCLI=$cliFormat; exit=$usedExitCode"
        if ($header) {
            $failureReason += "; actualFormat=$($header.Format); alpha=$($header.AlphaBits); dimensions=$($header.Width)x$($header.Height)"
        }

        "=== COMPILE FAILURE ===" | Add-Content -LiteralPath $LogPath -Encoding UTF8
        "Texture: $relative" | Add-Content -LiteralPath $LogPath -Encoding UTF8
        $failureReason | Add-Content -LiteralPath $LogPath -Encoding UTF8
        "" | Add-Content -LiteralPath $LogPath -Encoding UTF8

        $Results.Add([pscustomobject]@{
            RelativePath = $relative
            SourceTgaSHA256 = $shaMap[$key]
            SourceBtiSHA256 = (Get-FileHash -LiteralPath $btiPath -Algorithm SHA256).Hash.ToLowerInvariant()
            OriginalBTIFormat = $originalFormat
            RequestedCLIFormat = $cliFormat
            ActualCompileFormat = $compileFormat
            CompilerInputBits = $compileBits
            AuthoritativeAlphaBits = $btiInfo.AlphaBits
            ActualDDTFormatByte = if ($header) { $header.Format } else { '' }
            ExpectedDDTFormatByte = $ExpectedFormatBytes[$compileFormat]
            ActualDDTAlphaBits = if ($header) { $header.AlphaBits } else { '' }
            DDTWidth = if ($header) { $header.Width } else { '' }
            DDTHeight = if ($header) { $header.Height } else { '' }
            DDTMipLevels = if ($header) { $header.Mips } else { '' }
            DDTSHA256 = ''
            DDTBytes = ''
            CompilerExitCode = $usedExitCode
            WarningCount = $attemptWarnings
            StagedBTIBomRemoved = if ($btiInfo.HadBom) { 'YES' } else { 'NO' }
            FallbackUsed = $fallbackUsed
            FallbackReason = $fallbackReason
            Provisional = $provisional
            ProvisionalReason = $provisionalReason
            Status = 'FAIL'
            FailureReason = $failureReason
        })
    }

    Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $StageRoot -Recurse -Force -ErrorAction SilentlyContinue

$ddts = @(Get-ChildItem -LiteralPath $DDTRoot -Filter '*.ddt' -Recurse -File)

$expectedKeys = @(
    $allTga |
    ForEach-Object {
        $r = Normalize-RelativePath $_.FullName.Substring($PBRifyRoot.Length + 1)
        if ($r.ToLowerInvariant() -ne $ExcludedRelative.ToLowerInvariant()) {
            ($r.Substring(0, $r.Length - 4) + '.ddt').ToLowerInvariant()
        }
    }
)

$actualKeys = @{}
foreach ($ddt in $ddts) {
    $r = Normalize-RelativePath $ddt.FullName.Substring($DDTRoot.Length + 1)
    $actualKeys[$r.ToLowerInvariant()] = $ddt
}

$missing = @($expectedKeys | Where-Object { -not $actualKeys.ContainsKey($_) })
$unexpected = @($actualKeys.Keys | Where-Object { $_ -notin $expectedKeys })

$Results | Sort-Object RelativePath | Export-Csv -LiteralPath $ManifestPath -NoTypeInformation -Encoding UTF8

"" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Finished: $(Get-Date -Format o)" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Compiled: $compiled" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Excluded: $excluded" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Fallbacks: $fallbacks" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Failed: $failed" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Warning tokens: $warnings" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"DDTs present: $($ddts.Count)" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Missing DDTs: $($missing.Count)" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"Unexpected DDTs: $($unexpected.Count)" | Add-Content -LiteralPath $LogPath -Encoding UTF8

$formatSummary = @(
    $Results |
    Where-Object { $_.Status -ne 'EXCLUDED' } |
    Group-Object ActualDDTFormatByte |
    Sort-Object Name |
    ForEach-Object { "Actual DDT format byte $($_.Name): $($_.Count)" }
)

$formatSummary | Add-Content -LiteralPath $LogPath -Encoding UTF8

Write-Host ""
Write-Host "============================================"
Write-Host "FULL EXPLICIT COMPILE V4 RESULT"
Write-Host "============================================"
Write-Host ""
Write-Host "Expected textures : $ExpectedCompile"
Write-Host "Compiled          : $compiled"
Write-Host "DDTs present      : $($ddts.Count)"
Write-Host "Excluded          : $excluded"
Write-Host "Fallbacks         : $fallbacks"
Write-Host "Failures          : $failed"
Write-Host "Warning tokens    : $warnings"
Write-Host "Missing DDTs      : $($missing.Count)"
Write-Host "Unexpected DDTs   : $($unexpected.Count)"
Write-Host ""

$formatSummary | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "Manifest          : $ManifestPath"
Write-Host "Compiler log      : $LogPath"
Write-Host "DDT output        : $DDTRoot"
Write-Host ""

$pass = (
    $compiled -eq $ExpectedCompile -and
    $ddts.Count -eq $ExpectedCompile -and
    $excluded -eq 1 -and
    $fallbacks -eq 1 -and
    $failed -eq 0 -and
    $missing.Count -eq 0 -and
    $unexpected.Count -eq 0
)

if ($pass) {
    Write-Host "FULL EXPLICIT PBRIFY V4 COMPILE V4: PASS"
    exit 0
}

Write-Host "FULL EXPLICIT PBRIFY V4 COMPILE V4: FAIL"
exit 1
