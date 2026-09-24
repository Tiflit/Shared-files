from __future__ import annotations

import csv
import shutil
import struct
import subprocess
from pathlib import Path

from PIL import Image


ROOT = Path(r"D:\AI_upscaling\AoMEE")

COMPILER = ROOT / "tools" / "TextureCompiler.exe"
ORIGINAL = ROOT / r"extracted\textures\ui\ui map blue lagoon.tga"

OUT_ROOT = ROOT / r"tests\production_compile_diagnostic\blue_lagoon_bc1_dimensions"


def write_tga_rgba(path: Path, image: Image.Image) -> None:
    """
    Write a minimal uncompressed 32-bit TGA matching the style of the
    original AoMEE extracted TGA:

        type       = 2
        bpp        = 32
        descriptor= 8  (8 alpha bits, bottom-left origin)
        no ID
        no color map
        no footer
    """

    image = image.convert("RGBA")

    width, height = image.size

    if width > 65535 or height > 65535:
        raise ValueError("TGA dimensions exceed 16-bit field")

    rgba = image.tobytes()

    # TGA stores BGR(A), and descriptor bit 5 = 0 means bottom-left origin.
    rows = []

    row_bytes = width * 4

    for y in range(height - 1, -1, -1):
        row = rgba[y * row_bytes:(y + 1) * row_bytes]

        bgra = bytearray(len(row))

        for x in range(width):
            i = x * 4

            r = row[i]
            g = row[i + 1]
            b = row[i + 2]
            a = row[i + 3]

            bgra[i] = b
            bgra[i + 1] = g
            bgra[i + 2] = r
            bgra[i + 3] = a

        rows.append(bgra)

    header = bytearray(18)

    header[0] = 0                         # ID length
    header[1] = 0                         # No color map
    header[2] = 2                         # Uncompressed true-color
    header[12:14] = struct.pack("<H", width)
    header[14:16] = struct.pack("<H", height)
    header[16] = 32                       # 32-bit
    header[17] = 8                        # 8 alpha bits, bottom-left

    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("wb") as f:
        f.write(header)

        for row in rows:
            f.write(row)


def compile_bc1(name: str, tga_path: Path) -> dict:
    directory = tga_path.parent

    bti = directory / "test.bti"
    ddt = directory / "test.ddt"
    log = directory / "compiler_output.txt"

    bti.write_text(
        "alpha=0 fmt=BC1",
        encoding="ascii",
    )

    completed = subprocess.run(
        [
            str(COMPILER),
            "-i",
            str(tga_path),
            "-o",
            str(ddt),
        ],
        cwd=str(directory),
        capture_output=True,
        text=True,
        errors="replace",
    )

    output = ""

    if completed.stdout:
        output += completed.stdout

    if completed.stderr:
        output += "\n" + completed.stderr

    log.write_text(
        output,
        encoding="utf-8",
    )

    ddt_size = ddt.stat().st_size if ddt.exists() else 0

    return {
        "variant": name,
        "width": Image.open(tga_path).size[0],
        "height": Image.open(tga_path).size[1],
        "exit_code": completed.returncode,
        "ddt_bytes": ddt_size,
        "success": completed.returncode == 0 and ddt_size > 0,
    }


def make_solid_variant(
    name: str,
    size: int,
    rgba: tuple[int, int, int, int],
) -> Path:

    directory = OUT_ROOT / name
    directory.mkdir(parents=True, exist_ok=True)

    image = Image.new(
        "RGBA",
        (size, size),
        rgba,
    )

    path = directory / "test.tga"

    write_tga_rgba(path, image)

    return path


def make_original_scaled_variant(
    name: str,
    size: int,
) -> Path:

    directory = OUT_ROOT / name
    directory.mkdir(parents=True, exist_ok=True)

    with Image.open(ORIGINAL) as source:
        image = source.convert("RGBA")

        image = image.resize(
            (size, size),
            Image.Resampling.NEAREST,
        )

    path = directory / "test.tga"

    write_tga_rgba(path, image)

    return path


def main() -> None:

    if not COMPILER.exists():
        raise SystemExit(f"Compiler not found:\n{COMPILER}")

    if not ORIGINAL.exists():
        raise SystemExit(f"Original TGA not found:\n{ORIGINAL}")

    if OUT_ROOT.exists():
        shutil.rmtree(OUT_ROOT)

    OUT_ROOT.mkdir(parents=True)

    print("============================================")
    print("BLUE LAGOON BC1 DIMENSION DIAGNOSTIC")
    print("============================================")
    print()
    print("Compiler :", COMPILER)
    print("Original :", ORIGINAL)
    print()

    # ---------------------------------------------------------
    # Series A:
    # Completely opaque solid black.
    #
    # This deliberately removes image content and alpha as
    # variables. Only TGA dimensions change.
    # ---------------------------------------------------------

    solid_sizes = [
        64,
        128,
        256,
        384,
        512,
        640,
        768,
        896,
        1024,
        1280,
        1536,
        2048,
    ]

    results = []

    print("SOLID BLACK / OPAQUE")
    print("--------------------------------------------")

    for size in solid_sizes:

        name = f"solid_{size}x{size}"

        tga = make_solid_variant(
            name,
            size,
            (0, 0, 0, 255),
        )

        result = compile_bc1(name, tga)
        results.append(result)

        print(
            f"{size:4}x{size:<4} "
            f"exit={result['exit_code']:>12} "
            f"ddt={result['ddt_bytes']:>10} "
            f"success={result['success']}"
        )

    print()

    # ---------------------------------------------------------
    # Series B:
    # Real Blue Lagoon pixels, nearest-neighbour scaled.
    #
    # This checks whether the dimension result reproduces on
    # the actual texture rather than only the synthetic test.
    # ---------------------------------------------------------

    source_sizes = [
        256,
        512,
        768,
        1024,
    ]

    print("REAL BLUE LAGOON / NEAREST-NEIGHBOUR")
    print("--------------------------------------------")

    for size in source_sizes:

        name = f"original_scaled_{size}x{size}"

        tga = make_original_scaled_variant(
            name,
            size,
        )

        result = compile_bc1(name, tga)
        results.append(result)

        print(
            f"{size:4}x{size:<4} "
            f"exit={result['exit_code']:>12} "
            f"ddt={result['ddt_bytes']:>10} "
            f"success={result['success']}"
        )

    print()

    # ---------------------------------------------------------
    # CSV
    # ---------------------------------------------------------

    report = OUT_ROOT / "results.csv"

    with report.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as f:

        writer = csv.DictWriter(
            f,
            fieldnames=[
                "variant",
                "width",
                "height",
                "exit_code",
                "ddt_bytes",
                "success",
            ],
        )

        writer.writeheader()
        writer.writerows(results)

    print("============================================")
    print("SUMMARY")
    print("============================================")

    for row in results:
        print(
            f"{row['variant']:28} "
            f"exit={row['exit_code']:>12} "
            f"ddt={row['ddt_bytes']:>10} "
            f"success={row['success']}"
        )

    print()
    print(f"Results: {report}")


if __name__ == "__main__":
    main()