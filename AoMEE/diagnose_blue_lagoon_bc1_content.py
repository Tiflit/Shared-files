from __future__ import annotations

import csv
import struct
import subprocess
from pathlib import Path


ROOT = Path(r"D:\AI_upscaling\AoMEE")

COMPILER = ROOT / "tools" / "TextureCompiler.exe"
SOURCE = ROOT / r"processed\PBRify_V4\textures\ui\ui map blue lagoon.tga"
OUT_ROOT = ROOT / r"tests\production_compile_diagnostic\blue_lagoon_bc1_content"


def read_tga(path: Path) -> tuple[bytearray, int, int, int]:
    data = bytearray(path.read_bytes())

    if len(data) < 18:
        raise ValueError("TGA too small")

    image_type = data[2]
    width = struct.unpack_from("<H", data, 12)[0]
    height = struct.unpack_from("<H", data, 14)[0]
    bpp = data[16]
    id_length = data[0]

    if image_type != 2:
        raise ValueError(f"Expected uncompressed TGA type 2, got {image_type}")

    if bpp != 32:
        raise ValueError(f"Expected 32-bit TGA, got {bpp}")

    pixel_offset = 18 + id_length
    pixel_bytes = width * height * 4

    if pixel_offset + pixel_bytes > len(data):
        raise ValueError("TGA pixel payload exceeds file length")

    return data, width, height, pixel_offset


def alpha_stats(data: bytearray, width: int, height: int, pixel_offset: int):
    alphas = data[pixel_offset + 3:pixel_offset + width * height * 4:4]

    unique = sorted(set(alphas))

    zero = sum(a == 0 for a in alphas)
    full = sum(a == 255 for a in alphas)

    partial = len(alphas) - zero - full

    return {
        "pixels": len(alphas),
        "alpha_unique_count": len(unique),
        "alpha_min": min(alphas),
        "alpha_max": max(alphas),
        "alpha_zero_pixels": zero,
        "alpha_255_pixels": full,
        "alpha_partial_pixels": partial,
        "alpha_zero_percent": zero * 100.0 / len(alphas),
        "alpha_255_percent": full * 100.0 / len(alphas),
        "alpha_partial_percent": partial * 100.0 / len(alphas),
        "alpha_unique_values": ",".join(map(str, unique[:64])),
    }


def count_uniform_4x4_blocks(
    data: bytearray,
    width: int,
    height: int,
    pixel_offset: int,
):
    blocks_x = width // 4
    blocks_y = height // 4

    uniform_alpha = 0
    transparent = 0
    uniform_rgba = 0
    transparent_uniform_rgb = 0

    for by in range(blocks_y):
        for bx in range(blocks_x):
            first = None
            same_alpha = True
            same_rgba = True

            all_alpha_zero = True
            first_rgb = None
            same_rgb = True

            for yy in range(4):
                for xx in range(4):
                    x = bx * 4 + xx
                    y = by * 4 + yy

                    p = pixel_offset + (y * width + x) * 4
                    b, g, r, a = data[p:p + 4]

                    rgba = (r, g, b, a)
                    rgb = (r, g, b)

                    if first is None:
                        first = rgba
                        first_rgb = rgb
                    else:
                        if rgba != first:
                            same_rgba = False
                        if rgb != first_rgb:
                            same_rgb = False

                    if a != 0:
                        all_alpha_zero = False

                    if first is not None and a != first[3]:
                        same_alpha = False

            if same_alpha:
                uniform_alpha += 1

            if all_alpha_zero:
                transparent += 1

                if same_rgb:
                    transparent_uniform_rgb += 1

            if same_rgba:
                uniform_rgba += 1

    total = blocks_x * blocks_y

    return {
        "blocks_4x4": total,
        "uniform_alpha_blocks": uniform_alpha,
        "uniform_alpha_percent": uniform_alpha * 100.0 / total,
        "fully_transparent_blocks": transparent,
        "fully_transparent_percent": transparent * 100.0 / total,
        "uniform_rgba_blocks": uniform_rgba,
        "uniform_rgba_percent": uniform_rgba * 100.0 / total,
        "transparent_uniform_rgb_blocks": transparent_uniform_rgb,
    }


def write_variant(
    name: str,
    original: bytearray,
    width: int,
    height: int,
    pixel_offset: int,
    transform,
) -> Path:
    data = bytearray(original)

    for y in range(height):
        for x in range(width):
            p = pixel_offset + (y * width + x) * 4

            b = data[p]
            g = data[p + 1]
            r = data[p + 2]
            a = data[p + 3]

            b, g, r, a = transform(b, g, r, a)

            data[p] = b
            data[p + 1] = g
            data[p + 2] = r
            data[p + 3] = a

    path = OUT_ROOT / name / "test.tga"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)

    return path


def compile_variant(
    name: str,
    tga_path: Path,
) -> dict:

    directory = tga_path.parent

    bti_path = directory / "test.bti"
    ddt_path = directory / "test.ddt"
    log_path = directory / "compiler_output.txt"

    bti_path.write_text(
        "alpha=0 fmt=BC1",
        encoding="ascii",
    )

    completed = subprocess.run(
        [
            str(COMPILER),
            "-i",
            str(tga_path),
            "-o",
            str(ddt_path),
        ],
        cwd=str(directory),
        capture_output=True,
        text=True,
        errors="replace",
    )

    log_text = ""
    if completed.stdout:
        log_text += completed.stdout

    if completed.stderr:
        log_text += "\n" + completed.stderr

    log_path.write_text(
        log_text,
        encoding="utf-8",
    )

    size = ddt_path.stat().st_size if ddt_path.exists() else 0

    return {
        "variant": name,
        "exit_code": completed.returncode,
        "ddt_bytes": size,
        "success": (
            completed.returncode == 0
            and size > 0
        ),
    }


def main():
    if not COMPILER.exists():
        raise SystemExit(f"Compiler not found: {COMPILER}")

    if not SOURCE.exists():
        raise SystemExit(f"Source TGA not found: {SOURCE}")

    if OUT_ROOT.exists():
        import shutil
        shutil.rmtree(OUT_ROOT)

    OUT_ROOT.mkdir(parents=True)

    original, width, height, pixel_offset = read_tga(SOURCE)

    print("============================================")
    print("BLUE LAGOON BC1 PIXEL-CONTENT DIAGNOSTIC")
    print("============================================")
    print()
    print(f"Dimensions : {width} x {height}")
    print(f"Pixel data : offset {pixel_offset}")
    print(f"File bytes : {len(original)}")
    print()

    stats = {}
    stats.update(alpha_stats(original, width, height, pixel_offset))
    stats.update(
        count_uniform_4x4_blocks(
            original,
            width,
            height,
            pixel_offset,
        )
    )

    print("ALPHA / BLOCK STATISTICS")
    print("--------------------------------------------")

    for key, value in stats.items():
        print(f"{key}: {value}")

    print()

    variants = []

    # 1. Exact original control.
    original_path = OUT_ROOT / "01_original" / "test.tga"
    original_path.parent.mkdir(parents=True, exist_ok=True)
    original_path.write_bytes(original)

    variants.append(("01_original", original_path))

    # 2. Same RGB, completely opaque.
    variants.append(
        (
            "02_alpha_255",
            write_variant(
                "02_alpha_255",
                original,
                width,
                height,
                pixel_offset,
                lambda b, g, r, a: (b, g, r, 255),
            ),
        )
    )

    # 3. Same RGB, completely transparent.
    variants.append(
        (
            "03_alpha_0",
            write_variant(
                "03_alpha_0",
                original,
                width,
                height,
                pixel_offset,
                lambda b, g, r, a: (b, g, r, 0),
            ),
        )
    )

    # 4. Same alpha, completely black RGB.
    variants.append(
        (
            "04_rgb_black",
            write_variant(
                "04_rgb_black",
                original,
                width,
                height,
                pixel_offset,
                lambda b, g, r, a: (0, 0, 0, a),
            ),
        )
    )

    # 5. Same alpha, completely white RGB.
    variants.append(
        (
            "05_rgb_white",
            write_variant(
                "05_rgb_white",
                original,
                width,
                height,
                pixel_offset,
                lambda b, g, r, a: (255, 255, 255, a),
            ),
        )
    )

    # 6. Completely black and opaque.
    variants.append(
        (
            "06_black_opaque",
            write_variant(
                "06_black_opaque",
                original,
                width,
                height,
                pixel_offset,
                lambda b, g, r, a: (0, 0, 0, 255),
            ),
        )
    )

    # 7. Completely white and opaque.
    variants.append(
        (
            "07_white_opaque",
            write_variant(
                "07_white_opaque",
                original,
                width,
                height,
                pixel_offset,
                lambda b, g, r, a: (255, 255, 255, 255),
            ),
        )
    )

    results = []

    print("COMPILER TESTS")
    print("--------------------------------------------")

    for name, path in variants:
        result = compile_variant(name, path)
        results.append(result)

        print(
            f"{name:22} "
            f"exit={result['exit_code']:>12} "
            f"ddt={result['ddt_bytes']:>10} "
            f"success={result['success']}"
        )

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
                "exit_code",
                "ddt_bytes",
                "success",
            ],
        )
        writer.writeheader()
        writer.writerows(results)

    print()
    print(f"Results: {report}")


if __name__ == "__main__":
    main()