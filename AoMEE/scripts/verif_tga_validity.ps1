$Root = 'D:\AI_upscaling\AoMEE'

$Inventory  = Import-Csv "$Root\reports\tga_inventory.csv"
$Benchmark  = Import-Csv "$Root\tests\remaster_benchmark\remaster_benchmark_manifest.csv"

$Paths = @(
    $Benchmark |
    Select-Object -ExpandProperty OriginalRelativePath
)

$Rle = @(
    $Inventory |
    Where-Object {
        $Paths -contains $_.Path -and
        $_.ImageType -eq '10'
    } |
    Sort-Object Path
)

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Benchmark TGA format check" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Benchmark files: $($Paths.Count)"
Write-Host "RLE type-10 files: $($Rle.Count)"
Write-Host ""

$Rle |
    Select-Object Path, Width, Height, ImageType, BitsPerPixel, AlphaBits |
    Format-Table -AutoSize

Write-Host ""
Write-Host "RLE files by benchmark selection:"
Write-Host ""

$RlePaths = @($Rle | Select-Object -ExpandProperty Path)

$Benchmark |
    Where-Object {
        $RlePaths -contains $_.OriginalRelativePath
    } |
    Group-Object Selection |
    Sort-Object Name |
    Format-Table Name, Count -AutoSize