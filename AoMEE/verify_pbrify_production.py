from __future__ import annotations

import argparse
import csv
import hashlib
import sys
from pathlib import Path

from PIL import Image


def decode_tga(path: Path):
    data = path.read_bytes()

    if len(data) < 18:
        raise ValueError("TGA header truncated")

    h = data[:18]

    id_length = h[0]
    color_map_type = h[1]
    image_type = h[2]
    width = int.from_bytes(h[12:14], "little")
    height = int.from_bytes(h[14:16], "little")
    bpp = h[16]
    descriptor = h[17]

    if color_map_type != 0:
        raise ValueError("Color-mapped TGA unsupported")

    if image_type not in (2, 10):
        raise ValueError(f"Unsupported TGA image type {image_type}")

    if bpp not in (24, 32):
        raise ValueError(f"Unsupported TGA bit depth {bpp}")

    if width <= 0 or height <= 0:
        raise ValueError(f"Invalid dimensions {width}x{height}")

    bytes_per_pixel = bpp // 8
    pixel_count = width * height
    pos = 18 + id_length

    if pos > len(data):
        raise ValueError("TGA image data starts beyond EOF")

    raw = bytearray()

    def read_pixel():
        nonlocal pos

        end = pos + bytes_per_pixel
        if end > len(data):
            raise ValueError("TGA pixel data truncated")

        px = data[pos:end]
        pos = end
        return px

    if image_type == 2:
        required = pixel_count * bytes_per_pixel

        if pos + required > len(data):
            raise ValueError("TGA uncompressed payload truncated")

        raw.extend(data[pos:pos + required])

    else:
        while len(raw) < pixel_count * bytes_per_pixel:
            if pos >= len(data):
                raise ValueError("TGA RLE stream ended early")

            packet = data[pos]
            pos += 1

            count = (packet & 0x7F) + 1

            if len(raw) + count * bytes_per_pixel > pixel_count * bytes_per_pixel:
                raise ValueError("TGA RLE packet exceeds declared image size")

            if packet & 0x80:
                px = read_pixel()
                raw.extend(px * count)
            else:
                for _ in range(count):
                    raw.extend(read_pixel())

    top_origin = bool(descriptor & 0x20)
    right_origin = bool(descriptor & 0x10)

    rgba = bytearray(pixel_count * 4)

    for i in range(pixel_count):
        s = i * bytes_per_pixel

        b = raw[s]
        g = raw[s + 1]
        r = raw[s + 2]

        if bytes_per_pixel == 4:
            a = raw[s + 3]
        else:
            a = 255

        row = i // width
        col = i % width

        x = col if not right_origin else (width - 1 - col)
        y = row if top_origin else (height - 1 - row)

        d = (y * width + x) * 4
        rgba[d:d + 4] = bytes((r, g, b, a))

    return width, height, bytes(rgba)


def alpha_4x_exact(source_alpha: bytes, sw: int, sh: int,
                    output_alpha: bytes, ow: int, oh: int) -> bool:

    if ow != sw * 4 or oh != sh * 4:
        return False

    for y in range(sh):
        for x in range(sw):
            a = source_alpha[y * sw + x]

            for yy in range(4):
                out_row = (y * 4 + yy) * ow
                start = out_row + x * 4
                end = start + 4

                if output_alpha[start:end] != bytes((a, a, a, a)):
                    return False

    return True


def rel_key(path: Path, root: Path, suffix: str) -> str:
    return str(path.relative_to(root).with_suffix(suffix)).replace("\\", "/").lower()


def main():
    parser = argparse.ArgumentParser(
        description="Verify AoM EE PBRify V4 production output."
    )

    parser.add_argument(
        "--source",
        required=True,
        help="PNG source directory"
    )

    parser.add_argument(
        "--output",
        required=True,
        help="TGA output directory"
    )

    parser.add_argument(
        "--report",
        required=True,
        help="CSV QA report"
    )

    parser.add_argument(
        "--expected-count",
        type=int,
        required=True,
        help="Expected number of source/output textures"
    )

    args = parser.parse_args()

    source = Path(args.source).resolve()
    output = Path(args.output).resolve()
    report = Path(args.report).resolve()

    if not source.is_dir():
        raise SystemExit(f"ERROR: source directory missing: {source}")

    if not output.is_dir():
        raise SystemExit(f"ERROR: output directory missing: {output}")

    pngs = sorted(
        p for p in source.rglob("*.png")
        if p.is_file()
    )

    tgas = sorted(
        p for p in output.rglob("*.tga")
        if p.is_file()
    )

    source_map = {
        rel_key(p, source, ".tga"): p
        for p in pngs
    }

    output_map = {
        rel_key(p, output, ".tga"): p
        for p in tgas
    }

    missing = sorted(set(source_map) - set(output_map))
    unexpected = sorted(set(output_map) - set(source_map))

    rows = []

    dimension_pass = 0
    alpha_pass = 0
    decode_pass = 0

    for key in sorted(set(source_map) & set(output_map)):

        src_path = source_map[key]
        out_path = output_map[key]

        row = {
            "relative_path": key,
            "source_width": "",
            "source_height": "",
            "output_width": "",
            "output_height": "",
            "dimension_ok": False,
            "alpha_ok": False,
            "output_decode_ok": False,
            "source_rgba_sha256": "",
            "output_rgba_sha256": "",
            "error": "",
        }

        try:
            with Image.open(src_path) as img:
                img.load()
                rgba = img.convert("RGBA")

                sw, sh = rgba.size
                src_pixels = rgba.tobytes()
                src_alpha = rgba.getchannel("A").tobytes()

            ow, oh, out_pixels = decode_tga(out_path)
            out_alpha = out_pixels[3::4]

            row["source_width"] = sw
            row["source_height"] = sh
            row["output_width"] = ow
            row["output_height"] = oh

            row["source_rgba_sha256"] = hashlib.sha256(
                src_pixels
            ).hexdigest()

            row["output_rgba_sha256"] = hashlib.sha256(
                out_pixels
            ).hexdigest()

            row["output_decode_ok"] = True
            decode_pass += 1

            row["dimension_ok"] = (
                ow == sw * 4 and
                oh == sh * 4
            )

            if row["dimension_ok"]:
                dimension_pass += 1

            row["alpha_ok"] = alpha_4x_exact(
                src_alpha,
                sw,
                sh,
                out_alpha,
                ow,
                oh,
            )

            if row["alpha_ok"]:
                alpha_pass += 1

        except Exception as exc:
            row["error"] = f"{type(exc).__name__}: {exc}"

        rows.append(row)

    report.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "relative_path",
        "source_width",
        "source_height",
        "output_width",
        "output_height",
        "dimension_ok",
        "alpha_ok",
        "output_decode_ok",
        "source_rgba_sha256",
        "output_rgba_sha256",
        "error",
    ]

    with report.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    paired = len(set(source_map) & set(output_map))

    expected = args.expected_count

    passed = (
        len(pngs) == expected and
        len(tgas) == expected and
        paired == expected and
        len(missing) == 0 and
        len(unexpected) == 0 and
        decode_pass == expected and
        dimension_pass == expected and
        alpha_pass == expected
    )

    print("==============================================")
    print("AoM EE PBRIFY V4 PRODUCTION OUTPUT QA")
    print("==============================================")
    print(f"Source PNGs        : {len(pngs)}")
    print(f"Output TGAs        : {len(tgas)}")
    print(f"Paired files       : {paired}")
    print(f"Missing outputs    : {len(missing)}")
    print(f"Unexpected outputs : {len(unexpected)}")
    print(f"TGA decode PASS    : {decode_pass}/{paired}")
    print(f"Dimension PASS     : {dimension_pass}/{paired}")
    print(f"Alpha PASS         : {alpha_pass}/{paired}")
    print(f"Report             : {report}")

    if missing:
        print("\nMISSING:")
        for x in missing:
            print(f"  {x}")

    if unexpected:
        print("\nUNEXPECTED:")
        for x in unexpected:
            print(f"  {x}")

    errors = [r for r in rows if r["error"]]
    if errors:
        print("\nERRORS:")
        for r in errors:
            print(f"  {r['relative_path']} :: {r['error']}")

    print()

    if passed:
        print("PBRIFY V4 PRODUCTION QA: PASS")
        return 0

    print("PBRIFY V4 PRODUCTION QA: FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())

