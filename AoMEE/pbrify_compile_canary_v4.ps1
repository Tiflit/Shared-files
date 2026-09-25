$ErrorActionPreference = 'Stop'

# AoM:EE PBRify V4 - explicit-format compile canary V3
# Tests two real samples for every production format and always tests Blue Lagoon.
# DeflatedRGB8 is staged as a true 24-bit TGA.
# Authoritative source files are never modified.

$Root = 'D:\AI_upscaling\AoMEE'
$PBRifyRoot = Join-Path $Root 'processed\PBRify_V4'
$ExtractedRoot = Join-Path $Root 'extracted'
$Compiler = Join-Path $Root 'tools\TextureCompiler.exe'

$OutRoot = Join-Path $Root 'tests\PBRify_V4_explicit_canary'
$StageRoot = Join-Path $OutRoot 'stage'
$DDTRoot = Join-Path $OutRoot 'ddt'
$ReportPath = Join-Path $OutRoot 'canary_report.csv'
$LogPath = Join-Path $OutRoot 'canary_log.txt'

$BlueLagoon = 'textures\ui\ui map blue lagoon.tga'

$CanonicalCompilerFormat = @{
    'BC1'           = 'BC1'
    'BC2'           = 'BC2'
    'BC3'           = 'BC3'
    'DEFLATEDRGBA8' = 'DeflatedRGBA8'
    'DEFLATEDRGB8'  = 'DeflatedRGB8'
}

$ExpectedBytes = @{
    'BC1' = 4
    'BC2' = 8
    'BC3' = 9
    'DEFLATEDRGBA8' = 10
    'DEFLATEDRGB8' = 11
}

function Norm([string]$p) {
    return ($p -replace '/', '\').TrimStart('\')
}

function BtiRel([string]$tga) {
    $r = Norm $tga
    if ($r.EndsWith('.tga', [StringComparison]::OrdinalIgnoreCase)) {
        $r = $r.Substring(0, $r.Length - 4)
    }
    return $r + '.bti'
}

function LogicalFromExtracted([string]$path) {
    $r = Norm ($path.Substring($ExtractedRoot.Length + 1))
    if ($r.StartsWith('patched_to_verify\', [StringComparison]::OrdinalIgnoreCase)) {
        $r = $r.Substring('patched_to_verify\'.Length)
    }
    return $r
}

function GetBtiValue([string]$path, [string]$name) {
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path))
    $m = [regex]::Match($text, ('\b' + [regex]::Escape($name) + '\s*=\s*([A-Za-z0-9_]+)'), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $m.Success) { throw "Missing $name in BTI: $path" }
    return $m.Groups[1].Value
}

function NormalizeBti([string]$source, [string]$dest, [string]$format) {
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($source))
    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) {
        $text = $text.Substring(1)
    }
    $text = [regex]::Replace($text, '(\bfmt\s*=\s*)[A-Za-z0-9_]+', { param($m) $m.Groups[1].Value + $format }, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $dir = Split-Path -Parent $dest
    $null = New-Item -ItemType Directory -Force -Path $dir
    [IO.File]::WriteAllText($dest, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function TgaInfo([string]$path) {
    $b = [IO.File]::ReadAllBytes($path)
    if ($b.Length -lt 18) { throw "TGA too short: $path" }
    return [pscustomobject]@{
        Id = $b[0]
        Type = $b[2]
        Width = [BitConverter]::ToUInt16($b, 12)
        Height = [BitConverter]::ToUInt16($b, 14)
        Bits = $b[16]
    }
}

function Convert32To24([string]$source, [string]$dest) {
    $src = [IO.File]::ReadAllBytes($source)
    if ($src.Length -lt 18) { throw "TGA too short: $source" }
    if ($src[1] -ne 0 -or $src[2] -ne 2 -or $src[16] -ne 32) {
        throw "Expected uncompressed 32-bit true-color TGA: $source"
    }

    $w = [int][BitConverter]::ToUInt16($src, 12)
    $h = [int][BitConverter]::ToUInt16($src, 14)
    $start = 18 + [int]$src[0]
    $count = [int64]$w * [int64]$h
    $srcPixels = $count * 4
    $dstPixels = $count * 3

    if ($start + $srcPixels -gt $src.Length) {
        throw "TGA pixel data outside file: $source"
    }

    $dst = New-Object byte[] ([int64]$src.Length - $count)
    [Array]::Copy($src, 0, $dst, 0, $start)
    $dst[16] = 24

    $s = $start
    $d = $start
    for ($i = [int64]0; $i -lt $count; $i++) {
        $dst[$d] = $src[$s]
        $dst[$d + 1] = $src[$s + 1]
        $dst[$d + 2] = $src[$s + 2]
        $s += 4
        $d += 3
    }

    $srcTail = $start + [int]$srcPixels
    $dstTail = $start + [int]$dstPixels
    $tail = $src.Length - $srcTail
    if ($tail -gt 0) {
        [Array]::Copy($src, $srcTail, $dst, $dstTail, $tail)
    }

    $dir = Split-Path -Parent $dest
    $null = New-Item -ItemType Directory -Force -Path $dir
    [IO.File]::WriteAllBytes($dest, $dst)

    $check = TgaInfo $dest
    if ($check.Bits -ne 24 -or $check.Width -ne $w -or $check.Height -ne $h) {
        throw "24-bit staged TGA validation failed: $dest"
    }
}

function RunCompiler([string]$inputTga, [string]$outputDdt, [string]$format) {
    $out = @(& $Compiler -c $format -i $inputTga -o $outputDdt 2>&1)
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = @($out | ForEach-Object { [string]$_ })
    }
}

function ReadDdt([string]$path) {
    $b = [IO.File]::ReadAllBytes($path)
    if ($b.Length -lt 16) { throw "DDT too short: $path" }
    return [pscustomobject]@{
        Magic = [Text.Encoding]::ASCII.GetString($b, 0, 4)
        Properties = $b[4]
        Alpha = $b[5]
        Format = $b[6]
        Mips = $b[7]
        Width = [BitConverter]::ToUInt32($b, 8)
        Height = [BitConverter]::ToUInt32($b, 12)
        Bytes = (Get-Item -LiteralPath $path).Length
    }
}

foreach ($p in @($PBRifyRoot, $ExtractedRoot, $ManifestPath, $Compiler)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Required path not found: $p" }
}

if (Test-Path -LiteralPath $OutRoot) {
    Remove-Item -LiteralPath $OutRoot -Recurse -Force
}

$null = New-Item -ItemType Directory -Force -Path $StageRoot
$null = New-Item -ItemType Directory -Force -Path $DDTRoot

$selected = @(
    [pscustomobject]@{ RelativePath = 'textures\animal elephant indian.tga'; ExpectedFormat = 'BC1' }
    [pscustomobject]@{ RelativePath = 'textures\ui\ui map blue lagoon.tga'; ExpectedFormat = 'BC1' }
    [pscustomobject]@{ RelativePath = 'textures\animal dog a map.tga'; ExpectedFormat = 'BC2' }
    [pscustomobject]@{ RelativePath = 'textures\animal dog b map.tga'; ExpectedFormat = 'BC2' }
    [pscustomobject]@{ RelativePath = 'textures\_missingtexture.tga'; ExpectedFormat = 'BC3' }
    [pscustomobject]@{ RelativePath = 'textures\agamemnon map.tga'; ExpectedFormat = 'BC3' }
    [pscustomobject]@{ RelativePath = 'dlc-frontend\textures\ui\screen shot a_01.tga'; ExpectedFormat = 'DeflatedRGBA8' }
    [pscustomobject]@{ RelativePath = 'dlc-frontend\textures\ui\screen shot a_02.tga'; ExpectedFormat = 'DeflatedRGBA8' }
    [pscustomobject]@{ RelativePath = 'textures\icons\building storage pit icon.tga'; ExpectedFormat = 'DeflatedRGB8' }
    [pscustomobject]@{ RelativePath = 'textures\icons\improvement bone oracle script icon.tga'; ExpectedFormat = 'DeflatedRGB8' }
)

"=== AoM:EE PBRify V4 explicit format canary V4 ===" | Set-Content -LiteralPath $LogPath -Encoding UTF8
"Started: $(Get-Date -Format o)" | Add-Content -LiteralPath $LogPath -Encoding UTF8
"" | Add-Content -LiteralPath $LogPath -Encoding UTF8

$Results = [System.Collections.Generic.List[object]]::new()
$index = 0

foreach ($m in $selected) {
    $index++
    $relative = Norm $m.RelativePath
    $btiRel = BtiRel $relative

    $btiPath = Join-Path $ExtractedRoot $btiRel
    if (-not (Test-Path -LiteralPath $btiPath)) {
        $btiPath = Join-Path $ExtractedRoot ('patched_to_verify\' + $btiRel)
    }
    if (-not (Test-Path -LiteralPath $btiPath)) { throw "BTI missing: $btiRel" }

    $source = Join-Path $PBRifyRoot $relative
    if (-not (Test-Path -LiteralPath $source)) { throw "PBRify TGA missing: $relative" }

    $originalFormat = (GetBtiValue $btiPath 'fmt').ToUpperInvariant()
    $expectedFormat = $m.ExpectedFormat.ToUpperInvariant()
    if ($originalFormat -ne $expectedFormat) {
        throw "Sample metadata mismatch: $relative expected $expectedFormat but BTI says $originalFormat"
    }
    $alpha = [int](GetBtiValue $btiPath 'alpha')
    $tga = TgaInfo $source

    $case = Join-Path $StageRoot ('{0:D2}_{1}' -f $index, ($relative -replace '[\\/:*?"<>|]', '_'))
    $null = New-Item -ItemType Directory -Force -Path $case

    $stageTga = Join-Path $case ([IO.Path]::GetFileName($relative))
    $stageBti = [IO.Path]::ChangeExtension($stageTga, '.bti')
    Copy-Item -LiteralPath $source -Destination $stageTga -Force
    NormalizeBti $btiPath $stageBti $originalFormat

    $compileTga = $stageTga
    $compileBti = $stageBti
    $inputBits = $tga.Bits

    if ($originalFormat -eq 'DEFLATEDRGB8') {
        $compileTga = Join-Path $case 'rgb24_input.tga'
        $compileBti = Join-Path $case 'rgb24_input.bti'
        Convert32To24 $stageTga $compileTga
        NormalizeBti $btiPath $compileBti $originalFormat
        $inputBits = 24
    }

    $ddtRel = ($relative.Substring(0, $relative.Length - 4)) + '.ddt'
    $ddtPath = Join-Path $DDTRoot $ddtRel
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ddtPath)

    $cliFormat = $CanonicalCompilerFormat[$originalFormat]
    if (-not $cliFormat) { throw "Unsupported compiler format: $originalFormat" }

    $attempt = RunCompiler $compileTga $ddtPath $cliFormat
    $attempts = @([pscustomobject]@{ Format = $cliFormat; Result = $attempt })
    $usedFormat = $originalFormat
    $fallback = 'NO'
    $success = $false
    $hdr = $null

    if ($attempt.ExitCode -eq 0 -and (Test-Path -LiteralPath $ddtPath) -and (Get-Item -LiteralPath $ddtPath).Length -gt 24) {
        $hdr = ReadDdt $ddtPath
        $success = ($hdr.Magic -eq 'RTS3' -and $hdr.Format -eq $ExpectedBytes[$originalFormat])
    }

    if (-not $success -and $relative -eq $BlueLagoon -and $originalFormat -eq 'BC1') {
        Remove-Item -LiteralPath $ddtPath -Force -ErrorAction SilentlyContinue
        NormalizeBti $btiPath $stageBti 'BC2'
        $a2 = RunCompiler $compileTga $ddtPath 'BC2'
        $attempts += $a2
        $usedFormat = 'BC2'
        $hdr = if ($a2.ExitCode -eq 0 -and (Test-Path -LiteralPath $ddtPath)) { ReadDdt $ddtPath } else { $null }
        $success = ($null -ne $hdr -and $hdr.Magic -eq 'RTS3' -and $hdr.Format -eq 8 -and $hdr.Alpha -eq $alpha)
        if ($success) { $fallback = 'YES' }
    }

    $warnings = @($attempts | ForEach-Object { $_.Output } | Where-Object { $_ -match 'UNHANDLED token encountered' })

    $result = [pscustomobject]@{
        RelativePath = $relative
        OriginalBTIFormat = $originalFormat
        RequestedFormat = $cliFormat
        UsedFormat = $usedFormat
        ExpectedDDTFormatByte = $ExpectedBytes[$usedFormat]
        ActualDDTFormatByte = if ($hdr) { $hdr.Format } else { '' }
        AuthoritativeAlphaBits = $alpha
        ActualDDTAlphaBits = if ($hdr) { $hdr.Alpha } else { '' }
        PBRifySourceBits = $tga.Bits
        CompilerInputBits = $inputBits
        DDTBytes = if ($hdr) { $hdr.Bytes } else { '' }
        DDTWidth = if ($hdr) { $hdr.Width } else { '' }
        DDTHeight = if ($hdr) { $hdr.Height } else { '' }
        DDTMips = if ($hdr) { $hdr.Mips } else { '' }
        CompilerExitCode = $usedAttempt.ExitCode
        FallbackUsed = $fallback
        WarningCount = $warnings.Count
        Status = if ($success) { 'PASS' } else { 'FAIL' }
    }

    $Results.Add($result)
    "[$relative]" | Add-Content -LiteralPath $LogPath -Encoding UTF8
    $attempts | ForEach-Object { $_.Output } | Add-Content -LiteralPath $LogPath -Encoding UTF8
    "" | Add-Content -LiteralPath $LogPath -Encoding UTF8

    if ($success) {
        Write-Host "[$index/$($selected.Count)] PASS $relative -> DDT fmt $($hdr.Format), input $inputBits-bit, $($hdr.Bytes) bytes"
    } else {
        $actual = if ($hdr) { $hdr.Format } else { '' }
        Write-Host "[$index/$($selected.Count)] FAIL $relative -> requested $cliFormat, actual $actual"
    }
}

$Results | Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding UTF8

$failed = @($Results | Where-Object Status -eq 'FAIL')
$passed = @($Results | Where-Object Status -eq 'PASS')

Write-Host ""
Write-Host "============================================"
Write-Host "EXPLICIT FORMAT CANARY V3 RESULT"
Write-Host "============================================"
Write-Host "Cases tested : $($Results.Count)"
Write-Host "Passed       : $($passed.Count)"
Write-Host "Failed       : $($failed.Count)"
Write-Host "Report       : $ReportPath"
Write-Host "Log          : $LogPath"
Write-Host "Output DDT   : $DDTRoot"
Write-Host ""

if ($failed.Count -eq 0) {
    Write-Host "EXPLICIT FORMAT CANARY V4: PASS"
    exit 0
}

Write-Host "EXPLICIT FORMAT CANARY V4: FAIL"
exit 1
