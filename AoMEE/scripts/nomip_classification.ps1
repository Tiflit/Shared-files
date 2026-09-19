$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE'

$StageRoot = Join-Path `
    $Root `
    'tests\remaster_benchmark\compile_sharper'

$Compiler = Join-Path `
    $Root `
    'tools\TextureCompiler.exe'

$DiagRoot = Join-Path `
    $Root `
    'tests\remaster_benchmark\nomip_diagnostic'

if (-not (Test-Path -LiteralPath $StageRoot)) {
    throw "Compile staging directory not found: $StageRoot"
}

if (-not (Test-Path -LiteralPath $Compiler)) {
    throw "TextureCompiler.exe not found: $Compiler"
}

if (Test-Path -LiteralPath $DiagRoot) {
    Remove-Item `
        -LiteralPath $DiagRoot `
        -Recurse `
        -Force
}

$null = New-Item `
    -ItemType Directory `
    -Force `
    -Path $DiagRoot

# ------------------------------------------------------------
# Locate staged BTIs containing the nomip token.
# ------------------------------------------------------------

$Candidates = @()

$BTIs = Get-ChildItem `
    -LiteralPath $StageRoot `
    -Filter '*.bti' `
    -Recurse `
    -File

foreach ($bti in $BTIs) {

    $bytes = [IO.File]::ReadAllBytes($bti.FullName)

    # Decode after removing a possible UTF-8 BOM.
    $start = 0

    if (
        $bytes.Count -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    ) {
        $start = 3
    }

    $text = [Text.Encoding]::UTF8.GetString(
        $bytes,
        $start,
        $bytes.Count - $start
    )

    if (
        $text -match '(^|\s)nomip(\s|$)'
    ) {

        $tga = [IO.Path]::ChangeExtension(
            $bti.FullName,
            '.tga'
        )

        if (Test-Path -LiteralPath $tga) {

            $Candidates += [PSCustomObject]@{
                BTI = $bti.FullName
                TGA = $tga
                Settings = $text.Trim()
            }
        }
    }
}

Write-Host ""
Write-Host "============================================"
Write-Host "NOMIP DIAGNOSTIC"
Write-Host "============================================"
Write-Host ""

Write-Host "Staged BTIs containing nomip: $($Candidates.Count)"
Write-Host ""

if ($Candidates.Count -eq 0) {
    Write-Host "No staged nomip BTIs were found."
    exit
}

# Do not test hundreds here.
# Five representative examples are enough.
$Tests = @(
    $Candidates | Select-Object -First 5
)

$Results = @()

foreach ($item in $Tests) {

    $name = [IO.Path]::GetFileNameWithoutExtension(
        $item.TGA
    )

    $safeName = $name -replace '[^A-Za-z0-9._-]', '_'

    $dir = Join-Path `
        $DiagRoot `
        $safeName

    $null = New-Item `
        -ItemType Directory `
        -Force `
        -Path $dir

    Copy-Item `
        -LiteralPath $item.TGA `
        -Destination (Join-Path $dir 'test.tga') `
        -Force

    Copy-Item `
        -LiteralPath $item.BTI `
        -Destination (Join-Path $dir 'test.bti') `
        -Force

    $ddt = Join-Path `
        $dir `
        'test.ddt'

    Write-Host ""
    Write-Host "--------------------------------------------"
    Write-Host $name
    Write-Host "--------------------------------------------"
    Write-Host ""
    Write-Host "BTI: $($item.Settings)"
    Write-Host ""

    & $Compiler `
        -i (Join-Path $dir 'test.tga') `
        -o $ddt

    $exit = $LASTEXITCODE

    $size = 0

    if (Test-Path -LiteralPath $ddt) {
        $size = (Get-Item -LiteralPath $ddt).Length
    }

    $success = (
        $exit -eq 0 -and
        $size -gt 0
    )

    if ($success) {
        Write-Host "RESULT: SUCCESS"
        Write-Host "DDT size: $size bytes"
    }
    else {
        Write-Host "RESULT: FAILED"
        Write-Host "Exit code: $exit"
        Write-Host "DDT size: $size bytes"
    }

    $Results += [PSCustomObject]@{
        Texture  = $name
        BTI      = $item.Settings
        ExitCode = $exit
        DDTBytes = $size
        Success  = $success
    }
}

$Report = Join-Path `
    $DiagRoot `
    'nomip_results.csv'

$Results |
    Export-Csv `
        -LiteralPath $Report `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host ""
Write-Host "============================================"
Write-Host "SUMMARY"
Write-Host "============================================"
Write-Host ""

$Results |
    Format-Table `
        Texture,
        BTI,
        ExitCode,
        DDTBytes,
        Success `
        -AutoSize

Write-Host ""
Write-Host "Results:"
Write-Host $Report