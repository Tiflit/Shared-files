$ErrorActionPreference = 'Stop'

$Root      = 'D:\AI_upscaling\AoMEE'
$Benchmark = Join-Path $Root 'tests\remaster_benchmark'
$Manifest  = Join-Path $Benchmark 'remaster_benchmark_manifest.csv'
$PngRoot   = Join-Path $Benchmark 'png_input'
$Report    = Join-Path $Benchmark 'png_conversion_report.csv'

if (-not (Test-Path -LiteralPath $Manifest)) {
    throw "Benchmark manifest not found: $Manifest"
}

New-Item -ItemType Directory -Force -Path $PngRoot | Out-Null

# Check Pillow only for PNG WRITING.
py -c "import PIL" 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Pillow is not installed. Installing it..." -ForegroundColor Yellow
    py -m pip install --user Pillow

    if ($LASTEXITCODE -ne 0) {
        throw "Could not install Pillow."
    }
}

$Python = @'
from pathlib import Path
import csv
import struct
from PIL import Image

manifest_path = Path(r"""__MANIFEST__""")
png_root = Path(r"""__PNGROOT__""")
report_path = Path(r"""__REPORT__""")

with manifest_path.open("r", encoding="utf-8-sig", newline="") as f:
    rows = list(csv.DictReader(f))

if len(rows) != 115:
    raise RuntimeError(
        f"Expected 115 benchmark files, found {len(rows)}"
    )

def decode_tga(path):
    data = path.read_bytes()

    if len(data) < 18:
        raise ValueError("TGA file is smaller than the 18-byte header")

    image_id_length = data[0]
    color_map_type = data[1]
    image_type = data[2]

    color_map_length = int.from_bytes(data[5:7], "little")
    color_map_bits = data[7]

    width = int.from_bytes(data[12:14], "little")
    height = int.from_bytes(data[14:16], "little")
    bpp = data[16]
    descriptor = data[17]

    if color_map_type != 0:
        raise ValueError("Color-mapped TGAs are not supported by this benchmark converter")

    if image_type not in (2, 10):
        raise ValueError(f"Unsupported TGA image type {image_type}")

    if bpp not in (24, 32):
        raise ValueError(f"Unsupported TGA bit depth {bpp}")

    if width <= 0 or height <= 0:
        raise ValueError(f"Invalid dimensions {width}x{height}")

    bytes_per_pixel = bpp // 8

    # TGA origin:
    # bit 4 = horizontal direction
    # bit 5 = vertical direction
    left_to_right = not bool(descriptor & 0x10)
    top_to_bottom = bool(descriptor & 0x20)

    offset = 18 + image_id_length

    if color_map_type != 0:
        color_map_entry_bytes = (color_map_bits + 7) // 8
        offset += color_map_length * color_map_entry_bytes

    if offset > len(data):
        raise ValueError("Image data starts beyond end of file")

    expected_pixels = width * height

    # Output is always top-left-origin RGBA.
    output = bytearray(expected_pixels * 4)

    def write_pixel(file_index, pixel):
        row = file_index // width
        col = file_index % width

        x = col if left_to_right else width - 1 - col
        y = row if top_to_bottom else height - 1 - row

        out_index = (y * width + x) * 4

        if bpp == 32:
            b, g, r, a = pixel
        else:
            b, g, r = pixel
            a = 255

        output[out_index:out_index + 4] = bytes((r, g, b, a))

    pixels_read = 0
    pos = offset

    if image_type == 2:

        total_bytes = expected_pixels * bytes_per_pixel

        if pos + total_bytes > len(data):
            raise ValueError("Uncompressed TGA data is truncated")

        for i in range(expected_pixels):
            pixel = data[
                pos + i * bytes_per_pixel:
                pos + (i + 1) * bytes_per_pixel
            ]

            write_pixel(i, pixel)

        pixels_read = expected_pixels

    else:

        while pixels_read < expected_pixels:

            if pos >= len(data):
                raise ValueError("RLE data ended before all pixels were decoded")

            packet_header = data[pos]
            pos += 1

            count = (packet_header & 0x7F) + 1

            if pixels_read + count > expected_pixels:
                raise ValueError("RLE packet exceeds expected pixel count")

            if packet_header & 0x80:
                # RLE packet
                if pos + bytes_per_pixel > len(data):
                    raise ValueError("RLE pixel data is truncated")

                pixel = data[pos:pos + bytes_per_pixel]
                pos += bytes_per_pixel

                for _ in range(count):
                    write_pixel(pixels_read, pixel)
                    pixels_read += 1

            else:
                # Raw packet
                required = count * bytes_per_pixel

                if pos + required > len(data):
                    raise ValueError("Raw TGA packet is truncated")

                for i in range(count):
                    pixel_start = pos + i * bytes_per_pixel
                    pixel = data[
                        pixel_start:
                        pixel_start + bytes_per_pixel
                    ]

                    write_pixel(pixels_read, pixel)
                    pixels_read += 1

                pos += required

    if pixels_read != expected_pixels:
        raise ValueError(
            f"Decoded {pixels_read} pixels, expected {expected_pixels}"
        )

    return Image.frombytes(
        "RGBA",
        (width, height),
        bytes(output)
    ), {
        "Width": width,
        "Height": height,
        "ImageType": image_type,
        "BitsPerPixel": bpp,
        "DecodedPixels": pixels_read,
    }

results = []

for index, row in enumerate(rows, 1):

    source = Path(row["BenchmarkPath"])

    if not source.exists():
        raise RuntimeError(
            f"Benchmark source does not exist: {source}"
        )

    # Preserve benchmark directory structure beneath png_input.
    benchmark_root = manifest_path.parent
    relative = source.relative_to(benchmark_root)

    destination = png_root / relative.with_suffix(".png")
    destination.parent.mkdir(parents=True, exist_ok=True)

    try:
        image, info = decode_tga(source)

        image.save(
            destination,
            format="PNG",
            optimize=False
        )

        results.append({
            "Source": str(source),
            "Destination": str(destination),
            "Width": info["Width"],
            "Height": info["Height"],
            "TgaImageType": info["ImageType"],
            "BitsPerPixel": info["BitsPerPixel"],
            "DecodedPixels": info["DecodedPixels"],
            "Status": "OK",
            "Error": ""
        })

        print(
            f"[{index:3}/{len(rows)}] OK  {relative}"
        )

    except Exception as exc:

        results.append({
            "Source": str(source),
            "Destination": str(destination),
            "Width": "",
            "Height": "",
            "TgaImageType": "",
            "BitsPerPixel": "",
            "DecodedPixels": "",
            "Status": "FAILED",
            "Error": str(exc)
        })

        print(
            f"[{index:3}/{len(rows)}] FAILED  {relative}"
        )

fieldnames = [
    "Source",
    "Destination",
    "Width",
    "Height",
    "TgaImageType",
    "BitsPerPixel",
    "DecodedPixels",
    "Status",
    "Error",
]

with report_path.open(
    "w",
    newline="",
    encoding="utf-8-sig"
) as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(results)

failed = [r for r in results if r["Status"] != "OK"]

print()
print("========================================")
print("PNG benchmark conversion complete")
print("========================================")
print(f"Input files:     {len(rows)}")
print(f"Converted:       {len(rows) - len(failed)}")
print(f"Failed:          {len(failed)}")
print(f"Output root:     {png_root}")
print(f"Report:          {report_path}")

if failed:
    print()
    print("FAILED FILES")
    print("------------")
    for r in failed:
        print(r["Source"])
        print(f"  {r['Error']}")

    raise SystemExit(1)
'@

$Python = $Python.Replace('__MANIFEST__', $Manifest)
$Python = $Python.Replace('__PNGROOT__', $PngRoot)
$Python = $Python.Replace('__REPORT__', $Report)

$Temp = Join-Path $env:TEMP 'aom_benchmark_tga_to_png.py'

$Python |
    Set-Content `
        -LiteralPath $Temp `
        -Encoding UTF8

py $Temp

$ExitCode = $LASTEXITCODE

Remove-Item `
    -LiteralPath $Temp `
    -Force `
    -ErrorAction SilentlyContinue

if ($ExitCode -ne 0) {
    throw "Benchmark PNG conversion failed."
}

Write-Host ""
Write-Host "PNG benchmark ready:" -ForegroundColor Green
Write-Host $PngRoot
Write-Host ""
Write-Host "Now point chaiNNer's LOAD IMAGES node to:" -ForegroundColor Cyan
Write-Host $PngRoot -ForegroundColor Yellow