$script = "D:\AI_upscaling\AoMEE\scripts\verify_pbrify_output.py"

@'
import csv
import sys
from pathlib import Path
from PIL import Image

SOURCE = Path(r"D:\AI_upscaling\AoMEE\tests\production_canary\png_input")
OUTPUT = Path(r"D:\AI_upscaling\AoMEE\tests\production_canary\PBRify_V4")
REPORT = Path(r"D:\AI_upscaling\AoMEE\tests\production_canary\PBRify_V4_QA.csv")


def png_files(root):
    return sorted(
        p for p in root.rglob("*.png")
        if p.is_file()
    )


def tga_files(root):
    return sorted(
        p for p in root.rglob("*.tga")
        if p.is_file()
    )


def rel_without_ext(path, root):
    return path.relative_to(root).with_suffix("").as_posix().lower()


def alpha_bytes_from_image(img):
    img = img.convert("RGBA")
    return img.getchannel("A").tobytes(), img.size


def decode_tga(path):
    """
    Supports the TGA formats relevant to this project:
      - type 2: uncompressed true-color
      - type 10: RLE true-color
      - 24/32 bpp
    Returns RGBA pixels in top-left row-major order.
    """
    data = path.read_bytes()

    if len(data) < 18:
        raise ValueError("TGA header truncated")

    h = data[:18]
    id_len = h[0]
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
        raise ValueError("Invalid TGA dimensions")

    pos = 18 + id_len
    bytes_per_pixel = bpp // 8
    pixel_count = width * height
    raw = bytearray()

    def need(n):
        if pos + n > len(data):
            raise ValueError("TGA pixel data truncated")

    while len(raw) < pixel_count * bytes_per_pixel:
        if image_type == 2:
            need(bytes_per_pixel)
            raw.extend(data[pos:pos + bytes_per_pixel])
            pos += bytes_per_pixel
        else:
            need(1)
            packet = data[pos]
            pos += 1
            count = (packet & 0x7F) + 1

            if packet & 0x80:
                need(bytes_per_pixel)
                px = data[pos:pos + bytes_per_pixel]
                pos += bytes_per_pixel
                raw.extend(px * count)
            else:
                need(bytes_per_pixel * count)
                raw.extend(data[pos:pos + bytes_per_pixel * count])
                pos += bytes_per_pixel * count

        if len(raw) > pixel_count * bytes_per_pixel:
            raise ValueError("TGA pixel data overruns declared image size")

    # TGA stores BGR(A); convert to RGBA.
    pixels = bytearray(pixel_count * 4)

    for i in range(pixel_count):
        s = i * bytes_per_pixel
        d = i * 4

        b = raw[s]
        g = raw[s + 1]
        r = raw[s + 2]
        a = raw[s + 3] if bytes_per_pixel == 4 else 255

        pixels[d:d + 4] = bytes((r, g, b, a))

    # Bit 5 controls vertical origin.
    top_origin = bool(descriptor & 0x20)

    # Bit 4 controls horizontal origin.
    right_origin = bool(descriptor & 0x10)

    src = bytes(pixels)
    fixed = bytearray(len(src))

    for y in range(height):
        sy = y if top_origin else (height - 1 - y)
        for x in range(width):
            sx = x if not right_origin else (width - 1 - x)

            s = (sy * width + sx) * 4
            d = (y * width + x) * 4
            fixed[d:d + 4] = src[s:s + 4]

    return width, height, bytes(fixed)


def alpha_replication_ok(source_alpha, source_size, output_alpha, output_size):
    sw, sh = source_size
    ow, oh = output_size

    if ow != sw * 4 or oh != sh * 4:
        return False

    src = source_alpha
    out = output_alpha

    for y in range(sh):
        for x in range(sw):
            a = src[y * sw + x]
            base = (y * 4) * ow + (x * 4)

            for yy in range(4):
                row = base + yy * ow
                if out[row:row + 4] != bytes((a, a, a, a)):
                    return False

    return True


def main():
    sources = png_files(SOURCE)
    outputs = tga_files(OUTPUT)

    source_keys = {rel_without_ext(p, SOURCE): p for p in sources}
    output_keys = {rel_without_ext(p, OUTPUT): p for p in outputs}

    rows = []

    missing = sorted(set(source_keys) - set(output_keys))
    unexpected = sorted(set(output_keys) - set(source_keys))

    if missing:
        print("MISSING OUTPUTS:")
        for x in missing:
            print("  ", x)

    if unexpected:
        print("UNEXPECTED OUTPUTS:")
        for x in unexpected:
            print("  ", x)

    for key in sorted(set(source_keys) & set(output_keys)):
        src_path = source_keys[key]
        out_path = output_keys[key]

        row = {
            "relative_path": key,
            "source_width": "",
            "source_height": "",
            "output_width": "",
            "output_height": "",
            "dimension_ok": False,
            "alpha_ok": False,
            "error": "",
        }

        try:
            with Image.open(src_path) as img:
                src_alpha, src_size = alpha_bytes_from_image(img)

            ow, oh, rgba = decode_tga(out_path)
            out_alpha = bytes(rgba[3::4])

            row["source_width"] = src_size[0]
            row["source_height"] = src_size[1]
            row["output_width"] = ow
            row["output_height"] = oh
            row["dimension_ok"] = (
                ow == src_size[0] * 4 and
                oh == src_size[1] * 4
            )

            row["alpha_ok"] = alpha_replication_ok(
                src_alpha,
                src_size,
                out_alpha,
                (ow, oh),
            )

        except Exception as exc:
            row["error"] = str(exc)

        rows.append(row)

    REPORT.parent.mkdir(parents=True, exist_ok=True)

    with REPORT.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys() if rows else [
            "relative_path",
            "source_width",
            "source_height",
            "output_width",
            "output_height",
            "dimension_ok",
            "alpha_ok",
            "error",
        ])
        writer.writeheader()
        writer.writerows(rows)

    paired = len(set(source_keys) & set(output_keys))
    dimensions = sum(bool(r["dimension_ok"]) for r in rows)
    alpha = sum(bool(r["alpha_ok"]) for r in rows)
    errors = sum(bool(r["error"]) for r in rows)

    print("========================================")
    print("PBRIFY V4 CANARY OUTPUT QA")
    print("========================================")
    print(f"Source PNGs       : {len(sources)}")
    print(f"Output TGAs       : {len(outputs)}")
    print(f"Paired files      : {paired}")
    print(f"Missing outputs   : {len(missing)}")
    print(f"Unexpected outputs: {len(unexpected)}")
    print(f"Dimension PASS    : {dimensions}/{paired}")
    print(f"Alpha PASS        : {alpha}/{paired}")
    print(f"Decode errors     : {errors}")
    print(f"Report            : {REPORT}")

    passed = (
        len(sources) == 44 and
        len(outputs) == 44 and
        paired == 44 and
        not missing and
        not unexpected and
        dimensions == 44 and
        alpha == 44 and
        errors == 0
    )

    print()
    print("PBRIFY V4 CANARY QA:", "PASS" if passed else "FAIL")

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
'@ | Set-Content -LiteralPath $script -Encoding UTF8

"Created: $script"