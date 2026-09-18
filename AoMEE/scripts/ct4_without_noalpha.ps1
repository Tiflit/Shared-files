$Project = "D:\AI_upscaling\AoMEE"

$Input = "$Project\reports\ct4_texture_analysis.csv"
$Output = "$Project\reports\ct4_without_noalphatest.txt"

if (-not (Test-Path $Input)) {
    Write-Host "ERROR: Missing:"
    Write-Host $Input
    exit
}

$rows = Import-Csv -LiteralPath $Input

$exceptions = @(
    $rows |
        Where-Object {
            $_.NoAlphaTest -ne "True"
        } |
        Sort-Object Texture
)

$out = @()

$out += "AoM:EE CT4 Textures Without noalphatest"
$out += "======================================"
$out += ""
$out += "Count: $($exceptions.Count)"
$out += ""

foreach ($row in $exceptions) {

    $out += (
        "{0,-55} AlphaBits={1,-2} Alpha={2,-10} Coverage={3}" -f `
        $row.Texture,
        $row.BTI_AlphaBits,
        $row.TGA_AlphaType,
        $row.OpaqueCoveragePct
    )
}

$out += ""
$out += "OUTPUT"
$out += "------"
$out += $Output

$out |
    Set-Content -LiteralPath $Output -Encoding UTF8

Write-Host ""
Write-Host "DONE"
Write-Host ""
Write-Host "CT4 without noalphatest: $($exceptions.Count)"
Write-Host ""
Write-Host $Output