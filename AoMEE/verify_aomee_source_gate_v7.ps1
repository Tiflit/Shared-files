$ErrorActionPreference = 'Stop'

$scriptPath = 'D:\AI_upscaling\AoMEE\verify_aomee_source_gate_v7.py'

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing Python verifier: $scriptPath"
}

& python $scriptPath
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host ''
    Write-Host "SOURCE GATE FAILED (exit code $exitCode)." -ForegroundColor Red
    exit $exitCode
}
