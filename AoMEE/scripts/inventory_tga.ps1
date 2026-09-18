$Root = "D:\AI_upscaling\AoMEE"
$Extracted = Join-Path $Root "extracted"
$Reports = Join-Path $Root "reports"
$Output = Join-Path $Reports "tga_inventory.csv"

New-Item -ItemType Directory -Force -Path $Reports | Out-Null

# Check Pillow
py -c "import PIL" 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Pillow not found. Installing..." -ForegroundColor Yellow
    py -m pip install --user Pillow

    if ($LASTEXITCODE -ne 0) {
        throw "Could not install Pillow."
    }
}

$Python = @'
from PIL import Image
from pathlib import Path
import csv

root = Path(r"""__ROOT__""")
output = Path(r"""__OUTPUT__""")

rows = []

files = list(root.rglob("*.tga"))

print(f"Found {len(files)} TGA files.")
print()

for index, path in enumerate(files, 1):

    try:
        with Image.open(path) as img:
            width, height = img.size
            mode = img.mode

            has_alpha = "A" in img.getbands()

            transparent = 0
            opaque = 0
            partial = 0
            alpha_values = 0

            if has_alpha:
                alpha = img.getchannel("A")
                values = list(alpha.getdata())

                transparent = sum(1 for v in values if v == 0)
                opaque = sum(1 for v in values if v == 255)
                partial = len(values) - transparent - opaque
                alpha_values = len(set(values))
            else:
                total_pixels = width * height
                opaque = total_pixels

            relative = path.relative_to(root)

            rows.append({
                "Path": str(relative),
                "Filename": path.name,
                "Width": width,
                "Height": height,
                "Pixels": width * height,
                "Mode": mode,
                "HasAlpha": has_alpha,
                "TransparentPixels": transparent,
                "PartialAlphaPixels": partial,
                "OpaquePixels": opaque,
                "AlphaValueCount": alpha_values,
                "FileSizeKB": round(path.stat().st_size / 1024, 1),
            })

    except Exception as e:
        rows.append({
            "Path": str(path.relative_to(root)),
            "Filename": path.name,
            "Width": "",
            "Height": "",
            "Pixels": "",
            "Mode": "",
            "HasAlpha": "",
            "TransparentPixels": "",
            "PartialAlphaPixels": "",
            "OpaquePixels": "",
            "AlphaValueCount": "",
            "FileSizeKB": round(path.stat().st_size / 1024, 1),
        })

    if index % 500 == 0:
        print(f"Processed {index}/{len(files)}")

fieldnames = [
    "Path",
    "Filename",
    "Width",
    "Height",
    "Pixels",
    "Mode",
    "HasAlpha",
    "TransparentPixels",
    "PartialAlphaPixels",
    "OpaquePixels",
    "AlphaValueCount",
    "FileSizeKB",
]

with output.open("w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

print()
print("========================================")
print("TGA inventory complete")
print("========================================")
print(f"Files:  {len(files)}")
print(f"Output: {output}")
'@

$Python = $Python.Replace("__ROOT__", $Extracted)
$Python = $Python.Replace("__OUTPUT__", $Output)

$Temp = Join-Path $env:TEMP "aom_inventory_tga.py"
$Python | Set-Content -LiteralPath $Temp -Encoding UTF8

py $Temp

Remove-Item $Temp -Force

Write-Host ""
Write-Host "Inventory written to:" -ForegroundColor Green
Write-Host $Output