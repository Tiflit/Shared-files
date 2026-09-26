$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE'

$BadBTI = Join-Path `
    $Root `
    'extracted\patched_to_verify\textures\icons\special c black tortoise icon.bti'

$StageRoot = Join-Path `
    $Root `
    'tests\remaster_benchmark\compile_sharper'

if (-not (Test-Path -LiteralPath $BadBTI)) {
    throw "Black Tortoise BTI not found: $BadBTI"
}

Write-Host ""
Write-Host "============================================"
Write-Host "BLACK TORTOISE BTI INSPECTION"
Write-Host "============================================"
Write-Host ""

function Show-BTI {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $bytes = [IO.File]::ReadAllBytes($Path)

    Write-Host "FILE:"
    Write-Host $Path
    Write-Host ""

    Write-Host "SIZE:"
    Write-Host "$($bytes.Count) bytes"
    Write-Host ""

    Write-Host "HEX:"
    Write-Host (
        ($bytes | ForEach-Object {
            $_.ToString('X2')
        }) -join ' '
    )

    Write-Host ""
    Write-Host "UTF-8 TEXT:"
    Write-Host "------------"

    try {

        $utf8 = New-Object System.Text.UTF8Encoding(
            $false,
            $true
        )

        $text = $utf8.GetString($bytes)

        # Display escaped control characters as well.
        $display = $text `
            -replace "`r", '<CR>' `
            -replace "`n", '<LF>' `
            -replace "`t", '<TAB>'

        Write-Host $display

    }
    catch {
        Write-Host "UTF-8 decode failed: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "CHARACTERS:"
    Write-Host "------------"

    foreach ($b in $bytes) {

        if ($b -ge 32 -and $b -le 126) {
            $c = [char]$b
        }
        else {
            $c = '.'
        }

        Write-Host -NoNewline $c
    }

    Write-Host ""
    Write-Host ""
}

# ------------------------------------------------------------
# Problem BTI
# ------------------------------------------------------------

Show-BTI $BadBTI

# ------------------------------------------------------------
# Find successful benchmark BTIs of the same size.
# These are BTIs copied into compile_sharper during the
# previous successful staging/compilation run.
# ------------------------------------------------------------

$BadSize = (Get-Item -LiteralPath $BadBTI).Length

$Candidates = @(
    Get-ChildItem `
        -LiteralPath $StageRoot `
        -Filter '*.bti' `
        -Recurse `
        -File |
    Where-Object {
        $_.Length -eq $BadSize -and
        $_.FullName -ne $BadBTI
    } |
    Select-Object -First 5
)

Write-Host ""
Write-Host "============================================"
Write-Host "COMPARISON BTIs"
Write-Host "============================================"
Write-Host ""

Write-Host "Problem BTI size: $BadSize bytes"
Write-Host "Successful same-size candidates: $($Candidates.Count)"
Write-Host ""

foreach ($candidate in $Candidates) {
    Show-BTI $candidate.FullName
}

# ------------------------------------------------------------
# Specifically detect UTF-8 BOM.
# ------------------------------------------------------------

$bytes = [IO.File]::ReadAllBytes($BadBTI)

Write-Host ""
Write-Host "============================================"
Write-Host "BOM / SYNTAX CHECK"
Write-Host "============================================"
Write-Host ""

if (
    $bytes.Count -ge 3 -and
    $bytes[0] -eq 0xEF -and
    $bytes[1] -eq 0xBB -and
    $bytes[2] -eq 0xBF
) {
    Write-Host "UTF-8 BOM: PRESENT"
} else {
    Write-Host "UTF-8 BOM: NOT PRESENT"
}

$text = [Text.Encoding]::UTF8.GetString($bytes)

Write-Host ""

if ($text -match 'alpha\s*=\s*[0-9]+') {
    Write-Host "Detected alpha= syntax: YES"
}
elseif ($text -match 'alpha\s+[0-9]+') {
    Write-Host "Detected alpha<space> syntax: YES"
}
else {
    Write-Host "Detected alpha syntax: NO"
}

if ($text -match 'fmt\s*=') {
    Write-Host "Detected fmt= syntax: YES"
}
elseif ($text -match 'fmt\s+') {
    Write-Host "Detected fmt<space> syntax: YES"
}
else {
    Write-Host "Detected fmt syntax: NO"
}

if ($text -match 'format\s*=') {
    Write-Host "Detected format= syntax: YES"
}
elseif ($text -match 'format\s+') {
    Write-Host "Detected format<space> syntax: YES"
}
else {
    Write-Host "Detected format syntax: NO"
}

Write-Host ""