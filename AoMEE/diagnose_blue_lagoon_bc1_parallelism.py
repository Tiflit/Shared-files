from __future__ import annotations

import csv
import shutil
import struct
import subprocess
from pathlib import Path


ROOT = Path(r"D:\AI_upscaling\AoMEE")

COMPILER = ROOT / "tools" / "TextureCompiler.exe"

OUT_ROOT = ROOT / (
    r"tests\production_compile_diagnostic"
    r"\blue_lagoon_bc1_parallelism"
)


def write_solid_tga(
    path: Path,
    width: int,
    height: int,
) -> None:

    header = bytearray(18)

    # TGA true-color, uncompressed.
    header[2] = 2

    header[12:14] = struct.pack("<H", width)
    header[14:16] = struct.pack("<H", height)

    # 32-bit BGRA.
    header[16] = 32

    # 8 alpha bits, bottom-left origin.
    header[17] = 8

    # Solid opaque black.
    pixel = bytes((0, 0, 0, 255))

    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("wb") as f:
        f.write(header)

        row = pixel * width

        for _ in range(height):
            f.write(row)


def run_compiler(
    tga: Path,
    ddt: Path,
    single_core: bool,
) -> tuple[int, str]:

    if single_core:

        # Windows START /AFFINITY 1 launches the compiler with only
        # logical CPU 0 available.
        command = [
            "cmd.exe",
            "/c",
            "start",
            "",
            "/b",
            "/wait",
            "/affinity",
            "1",
            str(COMPILER),
            "-i",
            str(tga),
            "-o",
            str(ddt),
        ]

    else:

        command = [
            str(COMPILER),
            "-i",
            str(tga),
            "-o",
            str(ddt),
        ]

    completed = subprocess.run(
        command,
        cwd=str(tga.parent),
        capture_output=True,
        text=True,
        errors="replace",
    )

    output = ""

    if completed.stdout:
        output += completed.stdout

    if completed.stderr:
        output += "\n" + completed.stderr

    return completed.returncode, output


def test_variant(
    name: str,
    width: int,
    height: int,
    single_core: bool,
) -> dict:

    mode = "single_core" if single_core else "normal"

    directory = OUT_ROOT / name / mode
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

    exit_code, output = run_compiler(
        tga,
        ddt,
        single_core,
    )

    log.write_text(
        output,
        encoding="utf-8",
    )

    ddt_bytes = (
        ddt.stat().st_size
        if ddt.exists()
        else 0
    )

    return {
        "variant": name,
        "width": width,
        "height": height,
        "pixels": width * height,
        "blocks": ((width + 3) // 4) * ((height + 3) // 4),
        "mode": mode,
        "exit_code": exit_code,
        "ddt_bytes": ddt_bytes,
        "success": (
            exit_code == 0
            and ddt_bytes > 0
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

    tests = [
        ("01_832x832", 832, 832),
        ("02_896x896", 896, 896),
        ("03_1024x768", 1024, 768),
        ("04_768x1024", 768, 1024),
        ("05_896x768", 896, 768),
        ("06_768x896", 768, 896),
        ("07_768x832", 768, 832),
        ("08_832x768", 832, 768),
        ("09_768x769", 768, 769),
        ("10_769x768", 769, 768),
        ("11_1024x1024", 1024, 1024),
    ]

    results = []

    print("============================================")
    print("BLUE LAGOON BC1 PARALLELISM DIAGNOSTIC")
    print("============================================")
    print()
    print(f"Compiler: {COMPILER}")
    print()

    for name, width, height in tests:

        print(
            f"{width}x{height}: "
            f"normal...",
            end=" ",
            flush=True,
        )

        normal = test_variant(
            name,
            width,
            height,
            single_core=False,
        )

        print(
            f"exit={normal['exit_code']} "
            f"ddt={normal['ddt_bytes']} "
            f"success={normal['success']}"
        )

        results.append(normal)

        print(
            f"{width}x{height}: "
            f"single-core...",
            end=" ",
            flush=True,
        )

        single = test_variant(
            name,
            width,
            height,
            single_core=True,
        )

        print(
            f"exit={single['exit_code']} "
            f"ddt={single['ddt_bytes']} "
            f"success={single['success']}"
        )

        results.append(single)

        print()

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
                "blocks",
                "mode",
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

    print(
        f"{'Dimensions':>12} "
        f"{'Normal':>12} "
        f"{'Single-core':>12}"
    )

    print("-" * 40)

    for name, width, height in tests:

        normal = next(
            r for r in results
            if r["variant"] == name
            and r["mode"] == "normal"
        )

        single = next(
            r for r in results
            if r["variant"] == name
            and r["mode"] == "single_core"
        )

        print(
            f"{width:4}x{height:<4} "
            f"{str(normal['success']):>12} "
            f"{str(single['success']):>12}"
        )

    print()
    print(f"Results: {report}")


if __name__ == "__main__":
    main()