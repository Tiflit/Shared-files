from __future__ import annotations

import csv
import shutil
import struct
import subprocess
from pathlib import Path

from PIL import Image


ROOT = Path(r"D:\AI_upscaling\AoMEE")

COMPILER = ROOT / "tools" / "TextureCompiler.exe"

OUT_ROOT = ROOT / (
    r"tests\production_compile_diagnostic"
    r"\blue_lagoon_bc1_limit"
)


def write_solid_tga(
    path: Path,
    width: int,
    height: int,
    rgba: tuple[int, int, int, int] = (0, 0, 0, 255),
) -> None:

    if width < 1 or height < 1:
        raise ValueError("Invalid dimensions")

    if width > 65535 or height > 65535:
        raise ValueError("TGA dimensions exceed 16-bit limits")

    r, g, b, a = rgba

    header = bytearray(18)

    # TGA 2
    header[2] = 2

    # Width / height
    header[12:14] = struct.pack("<H", width)
    header[14:16] = struct.pack("<H", height)

    # 32-bit BGRA
    header[16] = 32

    # 8 alpha bits, bottom-left origin
    header[17] = 8

    pixel = bytes((b, g, r, a))

    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("wb") as f:
        f.write(header)

        row = pixel * width

        for _ in range(height):
            f.write(row)


def compile_bc1(
    name: str,
    width: int,
    height: int,
) -> dict:

    directory = OUT_ROOT / name
    directory.mkdir(parents=True, exist_ok=True)

    tga = directory / "test.tga"
    bti = directory / "test.bti"
    ddt = directory / "test.ddt"
    log = directory / "compiler_output.txt"

    write_solid_tga(
        tga,
        width,
        height,
    )

    bti.write_text(
        "alpha=0 fmt=BC1",
        encoding="ascii",
    )

    completed = subprocess.run(
        [
            str(COMPILER),
            "-i",
            str(tga),
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

    ddt_size = (
        ddt.stat().st_size
        if ddt.exists()
        else 0
    )

    return {
        "variant": name,
        "width": width,
        "height": height,
        "pixels": width * height,
        "blocks_x": (width + 3) // 4,
        "blocks_y": (height + 3) // 4,
        "blocks": ((width + 3) // 4) * ((height + 3) // 4),
        "exit_code": completed.returncode,
        "ddt_bytes": ddt_size,
        "success": (
            completed.returncode == 0
            and ddt_size > 0
        ),
    }


def main() -> None:

    if not COMPILER.exists():
        raise SystemExit(
            f"Compiler not found:\n{COMPILER}"
        )

    if OUT_ROOT.exists():
        shutil.rmtree(OUT_ROOT)

    OUT_ROOT.mkdir(parents=True)

    print("============================================")
    print("BLUE LAGOON BC1 LIMIT DIAGNOSTIC")
    print("============================================")
    print()
    print(f"Compiler: {COMPILER}")
    print()

    # ---------------------------------------------------------
    # Test exact values around the observed 768 -> 896 boundary.
    #
    # These tell us whether 769 is already invalid.
    # ---------------------------------------------------------

    tests = [
        ("01_768x768", 768, 768),

        ("02_769x768", 769, 768),
        ("03_768x769", 768, 769),

        ("04_800x768", 800, 768),
        ("05_768x800", 768, 800),

        ("06_832x768", 832, 768),
        ("07_768x832", 768, 832),

        ("08_896x768", 896, 768),
        ("09_768x896", 768, 896),

        # -----------------------------------------------------
        # Same / lower dimensions but different total areas.
        # -----------------------------------------------------

        ("10_896x512", 896, 512),
        ("11_512x896", 512, 896),

        ("12_1024x512", 1024, 512),
        ("13_512x1024", 512, 1024),

        ("14_1024x640", 1024, 640),
        ("15_640x1024", 640, 1024),

        ("16_1024x768", 1024, 768),
        ("17_768x1024", 768, 1024),

        # -----------------------------------------------------
        # Area-focused controls around 768^2.
        # -----------------------------------------------------

        ("18_768x768", 768, 768),
        ("19_800x720", 800, 720),
        ("20_720x800", 720, 800),
        ("21_896x640", 896, 640),
        ("22_640x896", 640, 896),

        # -----------------------------------------------------
        # A few common square boundaries.
        # -----------------------------------------------------

        ("23_800x800", 800, 800),
        ("24_832x832", 832, 832),
        ("25_864x864", 864, 864),
        ("26_896x896", 896, 896),
    ]

    results = []

    print(
        f"{'Dimensions':>12} "
        f"{'Pixels':>10} "
        f"{'Blocks':>10} "
        f"{'Exit':>12} "
        f"{'DDT':>10} "
        f"{'Success'}"
    )

    print("-" * 74)

    for name, width, height in tests:

        result = compile_bc1(
            name,
            width,
            height,
        )

        results.append(result)

        print(
            f"{width:4}x{height:<4} "
            f"{result['pixels']:10,} "
            f"{result['blocks']:10,} "
            f"{result['exit_code']:12} "
            f"{result['ddt_bytes']:10,} "
            f"{result['success']}"
        )

    # ---------------------------------------------------------
    # CSV report
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
                "pixels",
                "blocks_x",
                "blocks_y",
                "blocks",
                "exit_code",
                "ddt_bytes",
                "success",
            ],
        )

        writer.writeheader()
        writer.writerows(results)

    print()
    print("============================================")
    print("RESULT INTERPRETATION")
    print("============================================")
    print()
    print(
        "The key distinction is whether dimensions above 768 "
        "fail regardless of the other dimension."
    )
    print()
    print(f"Report: {report}")


if __name__ == "__main__":
    main()