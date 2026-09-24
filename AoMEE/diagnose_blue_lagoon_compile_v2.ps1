param(
    [string]$Root = 'D:\AI_upscaling\AoMEE'
)

$ErrorActionPreference = 'Continue'

$Compiler = Join-Path $Root 'tools\TextureCompiler.exe'
$OriginalTGA = Join-Path $Root 'extracted\textures\ui\ui map blue lagoon.tga'
$GeneratedTGA = Join-Path $Root 'processed\PBRify_V4\textures\ui\ui map blue lagoon.tga'
$OriginalBTI = Join-Path $Root 'extracted\textures\ui\ui map blue lagoon.bti'
$DiagRoot = Join-Path $Root 'tests\production_compile_diagnostic\blue_lagoon_v2'

foreach ($p in @($Compiler,$OriginalTGA,$GeneratedTGA,$OriginalBTI)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Required path not found: $p"
    }
}

if (Test-Path -LiteralPath $DiagRoot) {
    Remove-Item -LiteralPath $DiagRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $DiagRoot | Out-Null

function Get-TgaInfo {
    param([Parameter(Mandatory)][string]$Path)

    $data = [IO.File]::ReadAllBytes($Path)

    if ($data.Length -lt 18) {
        throw "TGA is shorter than 18-byte header: $Path"
    }

    $width = [BitConverter]::ToUInt16($data,12)
    $height = [BitConverter]::ToUInt16($data,14)
    $bpp = [int]$data[16]
    $descriptor = [int]$data[17]
    $idLength = [int]$data[0]
    $imageType = [int]$data[2]

    $bytesPerPixel = [int]($bpp / 8)
    $expectedPixelBytes = $width * $height * $bytesPerPixel
    $expectedPayloadLength = 18 + $idLength + $expectedPixelBytes
    $trailingBytes = $data.Length - $expectedPayloadLength

    $footerPresent = $false
    $footerSignature = ''

    if ($data.Length -ge 26) {
        $footerSignature = [Text.Encoding]::ASCII.GetString($data,$data.Length - 18,18)
        $footerPresent = $footerSignature -eq ("TRUEVISION-XFILE." + [char]0)
    }

    [pscustomobject]@{
        Path = $Path
        Bytes = $data.Length
        ImageType = $imageType
        Width = $width
        Height = $height
        BitsPerPixel = $bpp
        BytesPerPixel = $bytesPerPixel
        Descriptor = $descriptor
        AlphaBits = ($descriptor -band 0x0F)
        IdLength = $idLength
        ExpectedUncompressedPayloadBytes = $expectedPixelBytes
        ExpectedFileBytesWithoutFooter = $expectedPayloadLength
        TrailingBytesAfterExpectedPayload = $trailingBytes
        FooterPresent = $footerPresent
        FooterSignature = if ($footerPresent) { $footerSignature.Replace([char]0,'<NUL>') } else { '' }
    }
}

function New-Tga20Footer {
    $footer = New-Object byte[] 26

    # Extension area offset = 0
    # Developer directory offset = 0
    # Signature = TRUEVISION-XFILE. + NUL
    $signature = [Text.Encoding]::ASCII.GetBytes('TRUEVISION-XFILE.')
    [Array]::Copy($signature,0,$footer,8,$signature.Length)
    $footer[25] = 0

    return $footer
}

function Strip-Tga20Footer {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $data = [IO.File]::ReadAllBytes($Source)
    $info = Get-TgaInfo -Path $Source

    if (-not $info.FooterPresent) {
        throw "No TGA 2.0 footer detected in $Source"
    }

    $out = New-Object byte[] ($data.Length - 26)
    [Array]::Copy($data,0,$out,0,$out.Length)
    [IO.File]::WriteAllBytes($Destination,$out)
}

function Append-Tga20Footer {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $data = [IO.File]::ReadAllBytes($Source)
    $footer = New-Tga20Footer
    $out = New-Object byte[] ($data.Length + 26)

    [Array]::Copy($data,0,$out,0,$data.Length)
    [Array]::Copy($footer,0,$out,$data.Length,$footer.Length)
    [IO.File]::WriteAllBytes($Destination,$out)
}

function Test-Compile {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TGA,
        [Parameter(Mandatory)][string]$BTIText
    )

    $dir = Join-Path $DiagRoot $Name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $testTGA = Join-Path $dir 'test.tga'
    $testBTI = Join-Path $dir 'test.bti'
    $testDDT = Join-Path $dir 'test.ddt'
    $testLog = Join-Path $dir 'compiler_output.txt'

    Copy-Item -LiteralPath $TGA -Destination $testTGA -Force
    [IO.File]::WriteAllText($testBTI,$BTIText,[Text.Encoding]::ASCII)

    Write-Host ''
    Write-Host '============================================'
    Write-Host $Name
    Write-Host '============================================'
    Write-Host "BTI: $BTIText"
    Write-Host "TGA: $TGA"

    $output = @(
        & $Compiler -i $testTGA -o $testDDT 2>&1
    )
    $exitCode = $LASTEXITCODE

    $output | ForEach-Object { [string]$_ } |
        Set-Content -LiteralPath $testLog -Encoding UTF8

    $exists = Test-Path -LiteralPath $testDDT
    $size = if ($exists) { (Get-Item -LiteralPath $testDDT).Length } else { 0 }

    $success = ($exitCode -eq 0 -and $exists -and $size -gt 0)

    $output |
        Where-Object { [string]$_ -match 'UNHANDLED|Running Texture Compiler|Processed:|texture\(s\)|FAIL|ERROR' } |
        ForEach-Object { Write-Host "  $_" }

    Write-Host "Exit code: $exitCode"
    Write-Host "DDT size : $size"
    Write-Host "Result   : $(if($success){'SUCCESS'}else{'FAILED'})"

    [pscustomobject]@{
        Variant = $Name
        BTI = $BTIText
        ExitCode = $exitCode
        DDTBytes = $size
        Success = $success
    }
}

$originalInfo = Get-TgaInfo -Path $OriginalTGA
$generatedInfo = Get-TgaInfo -Path $GeneratedTGA

Write-Host '============================================'
Write-Host 'BLUE LAGOON FINAL COMPILER DIAGNOSTIC V2'
Write-Host '============================================'
Write-Host ''
Write-Host 'ORIGINAL TGA:'
$originalInfo | Format-List | Out-String | Write-Host
Write-Host 'GENERATED PBRIFY TGA:'
$generatedInfo | Format-List | Out-String | Write-Host

# Preserve exact diagnostic copies of the two structural variants.
$generatedNoFooter = Join-Path $DiagRoot 'generated_no_footer.tga'
$originalWithFooter = Join-Path $DiagRoot 'original_with_footer.tga'

if ($generatedInfo.FooterPresent) {
    Strip-Tga20Footer -Source $GeneratedTGA -Destination $generatedNoFooter
} else {
    Write-Host 'NOTE: Generated TGA has no detected TGA 2.0 footer; footer-removal tests will be skipped.'
    $generatedNoFooter = $null
}

Append-Tga20Footer -Source $OriginalTGA -Destination $originalWithFooter

$results = @()

$results += Test-Compile -Name '01_generated_bc1_alpha4' -TGA $GeneratedTGA -BTIText 'alpha=4 fmt=BC1'
$results += Test-Compile -Name '02_generated_bc2_alpha4' -TGA $GeneratedTGA -BTIText 'alpha=4 fmt=BC2'
$results += Test-Compile -Name '03_generated_bc1_alpha0' -TGA $GeneratedTGA -BTIText 'alpha=0 fmt=BC1'

if ($generatedNoFooter) {
    $results += Test-Compile -Name '04_generated_no_footer_bc1_alpha0' -TGA $generatedNoFooter -BTIText 'alpha=0 fmt=BC1'
    $results += Test-Compile -Name '05_generated_no_footer_bc1_alpha4' -TGA $generatedNoFooter -BTIText 'alpha=4 fmt=BC1'
}

$results += Test-Compile -Name '06_original_bc1_alpha0' -TGA $OriginalTGA -BTIText 'alpha=0 fmt=BC1'
$results += Test-Compile -Name '07_original_with_footer_bc1_alpha0' -TGA $originalWithFooter -BTIText 'alpha=0 fmt=BC1'
$results += Test-Compile -Name '08_original_with_footer_bc1_alpha4' -TGA $originalWithFooter -BTIText 'alpha=4 fmt=BC1'

$report = Join-Path $DiagRoot 'variant_results.csv'
$results | Export-Csv -LiteralPath $report -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host '============================================'
Write-Host 'DIAGNOSTIC SUMMARY'
Write-Host '============================================'
$results | Format-Table Variant,ExitCode,DDTBytes,Success -AutoSize
Write-Host ''
Write-Host "Results: $report"
Write-Host "Diagnostic root: $DiagRoot"
