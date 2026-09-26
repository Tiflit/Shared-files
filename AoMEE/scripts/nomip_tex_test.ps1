$ErrorActionPreference = 'Continue'

$Root = 'D:\AI_upscaling\AoMEE'

$StageRoot = Join-Path `
    $Root `
    'tests\remaster_benchmark\compile_sharper'

$Compiler = Join-Path `
    $Root `
    'tools\TextureCompiler.exe'

$DiagRoot = Join-Path `
    $Root `
    'tests\remaster_benchmark\nomip_diagnostic_all_v2'

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

# ============================================================
# FIND STAGED NOMIP BTIs
# ============================================================

$AllBTIs = @(
    Get-ChildItem `
        -LiteralPath $StageRoot `
        -Filter '*.bti' `
        -Recurse `
        -File
)

$Candidates = @()

foreach ($bti in $AllBTIs) {

    # Read BTI text, ignoring optional UTF-8 BOM.
    $bytes = [IO.File]::ReadAllBytes($bti.FullName)

    $offset = 0

    if (
        $bytes.Count -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    ) {
        $offset = 3
    }

    $text = [Text.Encoding]::UTF8.GetString(
        $bytes,
        $offset,
        $bytes.Count - $offset
    ).Trim()

    if ($text -notmatch '(^|\s)nomip(\s|$)') {
        continue
    }

    # Derive matching TGA directly from the BTI's directory.
    $tga = Join-Path `
        $bti.DirectoryName `
        ($bti.BaseName + '.tga')

    if (-not (Test-Path -LiteralPath $tga)) {
        Write-Host "WARNING: TGA missing for:"
        Write-Host "  $($bti.FullName)"
        continue
    }

    $relative = $tga.Substring(
        $StageRoot.Length + 1
    )

    $Candidates += [PSCustomObject]@{
        Relative = $relative
        BTI      = $bti.FullName
        TGA      = $tga
        Settings = $text
    }
}

# Remove accidental duplicate full paths, just in case.
$Candidates = @(
    $Candidates |
        Sort-Object BTI -Unique
)

Write-Host ""
Write-Host "============================================"
Write-Host "NOMIP DIAGNOSTIC v2"
Write-Host "============================================"
Write-Host ""

Write-Host "Nomip BTIs found: $($Candidates.Count)"
Write-Host ""

# ============================================================
# SHOW EXACT CANDIDATES
# ============================================================

$Candidates |
    Sort-Object Relative |
    Format-Table `
        Relative,
        Settings `
        -AutoSize

Write-Host ""

if ($Candidates.Count -eq 0) {
    throw "No staged nomip BTIs were found."
}

# ============================================================
# TEST EVERY NOMIP TEXTURE
# ============================================================

$Results = @()

$index = 0

foreach ($item in $Candidates) {

    $index++

    Write-Host ""
    Write-Host "============================================"
    Write-Host "[$index/$($Candidates.Count)]"
    Write-Host $item.Relative
    Write-Host "============================================"
    Write-Host ""

    Write-Host "BTI: $($item.Settings)"
    Write-Host "TGA: $($item.TGA)"
    Write-Host ""

    $safeName = (
        $item.Relative `
        -replace '[\\/:*?"<>|]', '_' `
        -replace '\.tga$', ''
    )

    $testDir = Join-Path `
        $DiagRoot `
        ('{0:D3}_{1}' -f $index, $safeName)

    $null = New-Item `
        -ItemType Directory `
        -Force `
        -Path $testDir

    $testTGA = Join-Path $testDir 'test.tga'
    $testBTI = Join-Path $testDir 'test.bti'
    $testDDT = Join-Path $testDir 'test.ddt'

    Copy-Item `
        -LiteralPath $item.TGA `
        -Destination $testTGA `
        -Force

    Copy-Item `
        -LiteralPath $item.BTI `
        -Destination $testBTI `
        -Force

    if (
        -not (Test-Path -LiteralPath $testTGA) -or
        -not (Test-Path -LiteralPath $testBTI)
    ) {
        Write-Host "STAGING ERROR"

        $Results += [PSCustomObject]@{
            Relative = $item.Relative
            Settings = $item.Settings
            ExitCode = 'STAGING'
            DDTBytes = 0
            Success  = $false
        }

        continue
    }

    & $Compiler `
        -i $testTGA `
        -o $testDDT

    $exit = $LASTEXITCODE

    $ddtBytes = 0

    if (Test-Path -LiteralPath $testDDT) {
        $ddtBytes = (
            Get-Item -LiteralPath $testDDT
        ).Length
    }

    $success = (
        $exit -eq 0 -and
        $ddtBytes -gt 0
    )

    if ($success) {
        Write-Host "RESULT: SUCCESS"
        Write-Host "DDT size: $ddtBytes bytes"
    }
    else {
        Write-Host "RESULT: FAILED"
        Write-Host "Exit code: $exit"
        Write-Host "DDT size: $ddtBytes bytes"
    }

    $Results += [PSCustomObject]@{
        Relative = $item.Relative
        Settings = $item.Settings
        ExitCode = $exit
        DDTBytes = $ddtBytes
        Success  = $success
    }
}

# ============================================================
# SAVE REPORT
# ============================================================

$Report = Join-Path `
    $DiagRoot `
    'nomip_results_v2.csv'

$Results |
    Export-Csv `
        -LiteralPath $Report `
        -NoTypeInformation `
        -Encoding UTF8

# ============================================================
# SUMMARY BY BTI CONFIGURATION
# ============================================================

Write-Host ""
Write-Host "============================================"
Write-Host "SUMMARY BY BTI CONFIGURATION"
Write-Host "============================================"
Write-Host ""

$Groups = @(
    $Results |
        Group-Object Settings |
        Sort-Object Name
)

foreach ($g in $Groups) {

    $pass = @(
        $g.Group |
            Where-Object { $_.Success }
    ).Count

    $fail = $g.Count - $pass

    Write-Host $g.Name
    Write-Host "    Total: $($g.Count)"
    Write-Host "    Pass:  $pass"
    Write-Host "    Fail:  $fail"
    Write-Host ""
}

# ============================================================
# OVERALL
# ============================================================

$passTotal = @(
    $Results |
        Where-Object { $_.Success }
).Count

$failTotal = $Results.Count - $passTotal

Write-Host "============================================"
Write-Host "OVERALL"
Write-Host "============================================"
Write-Host ""

Write-Host "Nomip textures tested: $($Results.Count)"
Write-Host "Successful:            $passTotal"
Write-Host "Failed:                $failTotal"
Write-Host ""

if ($failTotal -eq 0) {

    Write-Host "ALL NOMIP TEXTURES COMPILED SUCCESSFULLY."

}
else {

    Write-Host "FAILURES:"
    Write-Host ""

    $Results |
        Where-Object { -not $_.Success } |
        Format-Table `
            Relative,
            Settings,
            ExitCode,
            DDTBytes `
            -AutoSize
}

Write-Host ""
Write-Host "Report:"
Write-Host $Report

Write-Host ""
Write-Host "Diagnostic folder:"
Write-Host $DiagRoot