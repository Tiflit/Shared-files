$ErrorActionPreference = 'Stop'

$Source = 'D:\AI_upscaling\AoMEE\tests\production_canary\original'
$Output = 'D:\AI_upscaling\AoMEE\tests\production_canary\PBRify_V4'
$Verifier = 'D:\AI_upscaling\AoMEE\verify_pbrify_output_v2.py'
$Report = 'D:\AI_upscaling\AoMEE\tests\production_canary\pbrify_output_qa.csv'

if (-not (Test-Path -LiteralPath $Source)) { throw "Missing canary source: $Source" }
if (-not (Test-Path -LiteralPath $Output)) { throw "Missing canary output: $Output" }
if (-not (Test-Path -LiteralPath $Verifier)) { throw "Missing verifier: $Verifier" }

& python $Verifier --source $Source --output $Output --report $Report
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
