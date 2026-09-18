$ErrorActionPreference = 'Stop'

$Root      = 'D:\AI_upscaling\AoMEE'
$Extracted = Join-Path $Root 'extracted'
$Reports   = Join-Path $Root 'reports'

$Output = Join-Path $Reports 'tga_inventory.csv'

New-Item -ItemType Directory -Force -Path $Reports | Out-Null

$Python = @'
from pathlib import Path
from collections import Counter
import csv
import struct
import sys

root = Path(r"""__EXTRACTED__""")
output = Path(r"""__OUTPUT__""")

files = sorted(
    root.rglob("*.tga"),
    key=lambda p: str(p).lower()
)

print(f"Found {len(files)} TGA files.")
print()

rows = []
errors = []

def read_tga(path):
    data = path.read_bytes()

    if len(data) < 18:
        raise ValueError("File smaller than TGA header")

    image_id_length = data[0]
    color_map_type  = data[1]
    image_type      = data[2]

    color_map_first = int.from_bytes(data[3:5], "little")
    color_map_len   = int.from_bytes(data[5:7], "little")
    color_map_bits  = data[7]

    x_origin = int.from_bytes(data[8:10], "little")
    y_origin = int.from_bytes(data[10:12], "little")
    width    = int.from_bytes(data[12:14], "little")
    height   = int.from_bytes(data[14:16], "little")
    bpp      = data[16]
    descriptor = data[17]

    alpha_bits = descriptor & 0x0F

    if width <= 0 or height <= 0:
        raise ValueError(f"Invalid dimensions {width}x{height}")

    if image_type not in (2, 10):
        raise ValueError(f"Unsupported TGA image type {image_type}")

    if bpp not in (24, 32):
        raise ValueError(f"Unsupported pixel depth {bpp}")

    bytes_per_pixel = bpp // 8

    offset = 18

    # Image identification field
    offset += image_id_length

    # Color map, if present
    if color_map_type != 0:
        color_map_entry_bytes = (color_map_bits + 7) // 8
        offset += color_map_len * color_map_entry_bytes

    if offset > len(data):
        raise ValueError("TGA image data begins beyond end of file")

    expected_pixels = width * height

    transparent = 0
    partial = 0
    opaque = 0

    alpha_counter = Counter()

    pixels_read = 0

    def consume_pixel(pixel):
        nonlocal transparent, partial, opaque

        if len(pixel) < 4:
            alpha = 255
        else:
            # TGA 32-bit true-color is BGRA
            alpha = pixel[3]

        alpha_counter[alpha] += 1

        if alpha == 0:
            transparent += 1
        elif alpha == 255:
            opaque += 1
        else:
            partial += 1

    if image_type == 2:
        # Uncompressed true-color
        total_bytes = expected_pixels * bytes_per_pixel

        end = offset + total_bytes

        if end > len(data):
            raise ValueError(
                f"Pixel data truncated: need {total_bytes} bytes, "
                f"have {len(data) - offset}"
            )

        for pos in range(offset, end, bytes_per_pixel):
            consume_pixel(data[pos:pos + bytes_per_pixel])
            pixels_read += 1

    else:
        # Type 10: RLE true-color
        pos = offset

        while pixels_read < expected_pixels:
            if pos >= len(data):
                raise ValueError("RLE data truncated before all pixels were read")

            packet = data[pos]
            pos += 1

            count = (packet & 0x7F) + 1

            if pixels_read + count > expected_pixels:
                raise ValueError("RLE packet exceeds expected pixel count")

            if packet & 0x80:
                # RLE packet: one pixel repeated
                if pos + bytes_per_pixel > len(data):
                    raise ValueError("RLE pixel data truncated")

                pixel = data[pos:pos + bytes_per_pixel]
                pos += bytes_per_pixel

                for _ in range(count):
                    consume_pixel(pixel)
                    pixels_read += 1

            else:
                # Raw packet
                total_packet_bytes = count * bytes_per_pixel

                if pos + total_packet_bytes > len(data):
                    raise ValueError("Raw packet data truncated")

                end = pos + total_packet_bytes

                for pixel_pos in range(pos, end, bytes_per_pixel):
                    consume_pixel(
                        data[pixel_pos:pixel_pos + bytes_per_pixel]
                    )
                    pixels_read += 1

                pos = end

    if pixels_read != expected_pixels:
        raise ValueError(
            f"Decoded {pixels_read} pixels, expected {expected_pixels}"
        )

    has_alpha = (bpp == 32 and alpha_bits > 0)

    if has_alpha:
        alpha_value_count = len(alpha_counter)
        transparent_pixels = transparent
        partial_pixels = partial
        opaque_pixels = opaque
    else:
        alpha_value_count = 0
        transparent_pixels = 0
        partial_pixels = 0
        opaque_pixels = expected_pixels

    return {
        "Width": width,
        "Height": height,
        "Pixels": expected_pixels,
        "Mode": "RGBA" if bpp == 32 else "RGB",
        "HasAlpha": has_alpha,
        "TransparentPixels": transparent_pixels,
        "PartialAlphaPixels": partial_pixels,
        "OpaquePixels": opaque_pixels,
        "AlphaValueCount": alpha_value_count,
        "ImageType": image_type,
        "BitsPerPixel": bpp,
        "AlphaBits": alpha_bits,
        "DecodedPixels": pixels_read,
        "FileSizeKB": round(len(data) / 1024, 1),
    }

for index, path in enumerate(files, 1):

    relative = path.relative_to(root)

    try:
        info = read_tga(path)

        rows.append({
            "Path": str(relative),
            "Filename": path.name,
            **info,
            "ParseError": ""
        })

    except Exception as exc:

        errors.append(
            f"{relative}: {type(exc).__name__}: {exc}"
        )

        rows.append({
            "Path": str(relative),
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
            "ImageType": "",
            "BitsPerPixel": "",
            "AlphaBits": "",
            "DecodedPixels": "",
            "FileSizeKB": round(path.stat().st_size / 1024, 1),
            "ParseError": str(exc)
        })

    if index % 500 == 0:
        print(f"Processed {index}/{len(files)}")

fields = [
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
    "ImageType",
    "BitsPerPixel",
    "AlphaBits",
    "DecodedPixels",
    "FileSizeKB",
    "ParseError",
]

with output.open("w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)

print()
print("========================================")
print("Native TGA inventory complete")
print("========================================")
print(f"Files:        {len(files)}")
print(f"Parsed:       {len(files) - len(errors)}")
print(f"Parse errors: {len(errors)}")
print(f"Output:       {output}")

if errors:
    print()
    print("PARSE ERRORS")
    print("------------")
    for error in errors:
        print(error)

    error_file = output.with_name("tga_inventory_parse_errors.txt")
    error_file.write_text(
        "\n".join(errors) + "\n",
        encoding="utf-8"
    )

    print()
    print(f"Error report: {error_file}")
else:
    error_file = output.with_name("tga_inventory_parse_errors.txt")

    if error_file.exists():
        error_file.unlink()
'@

$Python = $Python.Replace('__EXTRACTED__', $Extracted)
$Python = $Python.Replace('__OUTPUT__', $Output)

$Temp = Join-Path $env:TEMP 'aom_native_tga_inventory.py'
$Python | Set-Content -LiteralPath $Temp -Encoding UTF8

py $Temp

$ExitCode = $LASTEXITCODE

Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue

if ($ExitCode -ne 0) {
    throw "Native TGA inventory failed with exit code $ExitCode."
}

Write-Host ""
Write-Host "Now rebuilding classification..." -ForegroundColor Cyan

$Classification = Join-Path $Root 'scripts\master_classification.ps1'

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Classification

if ($LASTEXITCODE -ne 0) {
    throw "Classification rebuild failed."
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "INVENTORY + CLASSIFICATION COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "TGA inventory:"
Write-Host $Output
Write-Host ""
Write-Host "Classification:"
Write-Host (Join-Path $Reports 'tga_classification.csv')
Write-Host ""
Write-Host "Classification summary:"
Write-Host (Join-Path $Reports 'tga_classification_summary.txt')
Write-Host ""

# Quick sanity check
$data = Import-Csv -LiteralPath $Output

$badDimensions = @(
    $data | Where-Object {
        [string]::IsNullOrWhiteSpace($_.Width) -or
        [string]::IsNullOrWhiteSpace($_.Height)
    }
)

$parseErrors = @(
    $data | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.ParseError)
    }
)

$type2 = @($data | Where-Object { $_.ImageType -eq '2' }).Count
$type10 = @($data | Where-Object { $_.ImageType -eq '10' }).Count
$rgba = @($data | Where-Object { $_.BitsPerPixel -eq '32' }).Count

Write-Host "SANITY CHECK" -ForegroundColor Cyan
Write-Host "-------------"
Write-Host "Total TGAs:       $($data.Count)"
Write-Host "Bad dimensions:   $($badDimensions.Count)"
Write-Host "Parse errors:     $($parseErrors.Count)"
Write-Host "Type 2 TGAs:      $type2"
Write-Host "Type 10 TGAs:     $type10"
Write-Host "32-bit TGAs:      $rgba"
Write-Host ""

if ($data.Count -ne 7487) {
    Write-Warning "Expected 7487 TGAs, found $($data.Count)."
}

if ($badDimensions.Count -ne 0) {
    Write-Warning "Some TGAs still have missing dimensions."
}

if ($parseErrors.Count -ne 0) {
    Write-Warning "Some TGAs still failed native parsing."
}

if (
    $data.Count -eq 7487 -and
    $badDimensions.Count -eq 0 -and
    $parseErrors.Count -eq 0 -and
    $rgba -eq 7487 -and
    $type2 -eq 7453 -and
    $type10 -eq 34
) {
    Write-Host "ALL TGA SANITY CHECKS PASSED." -ForegroundColor Green
}
else {
    Write-Host "Sanity checks did not all pass; inspect the numbers above." -ForegroundColor Yellow
}