from __future__ import annotations

import csv
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(r"D:\AI_upscaling\AoMEE")
MANIFEST = ROOT / "reports" / "master_texture_manifest.csv"

SOURCE_ROOT = ROOT / "input" / "production_source_png"
OUTPUT_ROOT = ROOT / "processed" / "PBRify_V4"

REVIEW_ROOT = ROOT / "tests" / "production_visual_review"
PAIR_ROOT = REVIEW_ROOT / "pairs"
SEAM_ROOT = REVIEW_ROOT / "tile_boundary_review"

MAX_PANEL_W = 520
MAX_PANEL_H = 390

FONT = ImageFont.load_default()


def load_rgba(path: Path) -> Image.Image:
    with Image.open(path) as img:
        img.load()
        return img.convert("RGBA")


def checkerboard(size: tuple[int, int], cell: int = 16) -> Image.Image:
    w, h = size
    bg = Image.new("RGBA", (w, h), (220, 220, 220, 255))
    d = ImageDraw.Draw(bg)

    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if ((x // cell) + (y // cell)) % 2:
                d.rectangle(
                    [x, y, min(x + cell - 1, w - 1), min(y + cell - 1, h - 1)],
                    fill=(190, 190, 190, 255),
                )

    return bg


def composite_checker(img: Image.Image) -> Image.Image:
    if img.mode != "RGBA":
        img = img.convert("RGBA")

    bg = checkerboard(img.size)
    return Image.alpha_composite(bg, img)


def enlarge_source(img: Image.Image) -> Image.Image:
    """
    Enlarge source by exactly 4x for side-by-side visual inspection.
    This is a review-only representation and never modifies the source.
    """
    return img.resize((img.width * 4, img.height * 4), Image.Resampling.NEAREST)


def fit_panel(img: Image.Image) -> Image.Image:
    return ImageOps.contain(
        img,
        (MAX_PANEL_W, MAX_PANEL_H),
        method=Image.Resampling.LANCZOS,
    )


def safe_name(rel: str) -> str:
    return (
        rel.replace("\\", "__")
        .replace("/", "__")
        .replace(":", "_")
        .replace(" ", "_")
    )


def make_pair(
    source: Path,
    output: Path,
    destination: Path,
    relative_path: str,
):
    src = load_rgba(source)
    out = load_rgba(output)

    # Make source visually comparable at 4x.
    src_display = enlarge_source(src)

    src_display = fit_panel(composite_checker(src_display))
    out_display = fit_panel(composite_checker(out))

    panel_w = max(src_display.width, out_display.width)
    panel_h = max(src_display.height, out_display.height)

    canvas_w = panel_w * 2
    canvas_h = panel_h + 54

    canvas = Image.new("RGB", (canvas_w, canvas_h), "white")
    draw = ImageDraw.Draw(canvas)

    left_x = (panel_w - src_display.width) // 2
    right_x = panel_w + (panel_w - out_display.width) // 2

    canvas.paste(src_display.convert("RGB"), (left_x, 42))
    canvas.paste(out_display.convert("RGB"), (right_x, 42))

    draw.text((8, 8), "Original (4x nearest display)", fill="black", font=FONT)
    draw.text((panel_w + 8, 8), "PBRify V4", fill="black", font=FONT)

    label = (
        f"{relative_path}   "
        f"{src.width}x{src.height} -> {out.width}x{out.height}"
    )

    # Put the path at the bottom; truncate only for the image label.
    draw.text(
        (8, canvas_h - 12),
        label[:180],
        fill="black",
        font=FONT,
        anchor="ls",
    )

    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, "PNG", optimize=False)


def tile_boundaries(width: int, height: int, max_tile: int = 256):
    """
    Reproduce ChaiNNer's tile partition math for the 256 px configuration.
    ChaiNNer computes a tile count from the maximum tile size and then
    distributes the image evenly among that number of tiles.
    """
    nx = math.ceil(width / max_tile)
    ny = math.ceil(height / max_tile)

    tile_w = math.ceil(width / nx)
    tile_h = math.ceil(height / ny)

    xs = [i * tile_w for i in range(1, nx)]
    ys = [i * tile_h for i in range(1, ny)]

    return xs, ys, tile_w, tile_h


def save_seam_crops(
    output_path: Path,
    relative_path: str,
    source_width: int,
    source_height: int,
):
    img = load_rgba(output_path)

    # Output is 4x the source.
    scale = 4

    xs, ys, _, _ = tile_boundaries(
        source_width,
        source_height,
        256,
    )

    centers = []

    for x in xs:
        centers.append(("vertical", x * scale))

    for y in ys:
        centers.append(("horizontal", y * scale))

    base = SEAM_ROOT / safe_name(relative_path)
    base.mkdir(parents=True, exist_ok=True)

    crops = []

    for index, (orientation, center) in enumerate(centers, 1):
        margin = 128

        if orientation == "vertical":
            x0 = max(0, center - margin)
            x1 = min(img.width, center + margin)
            crop = img.crop((x0, 0, x1, img.height))

        else:
            y0 = max(0, center - margin)
            y1 = min(img.height, center + margin)
            crop = img.crop((0, y0, img.width, y1))

        # Fit to a convenient review size while retaining enough detail.
        display = ImageOps.contain(
            composite_checker(crop),
            (1400, 900),
            method=Image.Resampling.LANCZOS,
        ).convert("RGB")

        fname = (
            f"{index:02d}_{orientation}_"
            f"{center}px_output.png"
        )

        dest = base / fname
        display.save(dest, "PNG", optimize=False)
        crops.append(str(dest.relative_to(REVIEW_ROOT)))

    return crops, xs, ys


def deterministic_even_sample(rows, count):
    if not rows or count <= 0:
        return []

    if len(rows) <= count:
        return rows[:]

    result = []
    used = set()

    for i in range(count):
        pos = round(i * (len(rows) - 1) / (count - 1))
        if pos not in used:
            used.add(pos)
            result.append(rows[pos])

    return result


def main():
    if not MANIFEST.is_file():
        raise SystemExit(f"Missing manifest: {MANIFEST}")

    if not SOURCE_ROOT.is_dir():
        raise SystemExit(f"Missing PNG source root: {SOURCE_ROOT}")

    if not OUTPUT_ROOT.is_dir():
        raise SystemExit(f"Missing production output root: {OUTPUT_ROOT}")

    rows = []
    with MANIFEST.open("r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))

    if len(rows) != 7487:
        raise SystemExit(
            f"Expected 7,487 manifest rows, found {len(rows)}."
        )

    for row in rows:
        row["_width"] = int(row["Width"])
        row["_height"] = int(row["Height"])
        row["_area"] = row["_width"] * row["_height"]

    rows.sort(key=lambda r: r["RelativePath"].lower())

    selected = {}
    order = []

    def add(row, group):
        key = row["RelativePath"].lower()
        if key not in selected:
            selected[key] = group
            order.append(row)

    # 1. All recovered exceptions.
    for r in rows:
        if r["SourceType"] == "RecoveredException":
            add(r, "recovered_all")

    # 2. All very large images.
    for r in rows:
        if r["_width"] >= 1024 or r["_height"] >= 1024:
            add(r, "large_all")

    # 3. Additional multi-tile samples.
    remaining_multi = [
        r for r in rows
        if (r["_width"] > 256 or r["_height"] > 256)
        and r["RelativePath"].lower() not in selected
    ]

    remaining_multi.sort(
        key=lambda r: (
            r["_area"],
            r["RelativePath"].lower(),
        )
    )

    for r in deterministic_even_sample(remaining_multi, 20):
        add(r, "multi_tile")

    # 4. Smallest remaining textures.
    remaining_small = [
        r for r in rows
        if r["RelativePath"].lower() not in selected
    ]

    remaining_small.sort(
        key=lambda r: (
            r["_area"],
            r["RelativePath"].lower(),
        )
    )

    for r in remaining_small[:20]:
        add(r, "smallest")

    # 5. Evenly distributed coverage sample.
    remaining_coverage = [
        r for r in rows
        if r["RelativePath"].lower() not in selected
    ]

    for r in deterministic_even_sample(remaining_coverage, 60):
        add(r, "coverage")

    # Rebuild review tree.
    if REVIEW_ROOT.exists():
        import shutil
        shutil.rmtree(REVIEW_ROOT)

    PAIR_ROOT.mkdir(parents=True, exist_ok=True)
    SEAM_ROOT.mkdir(parents=True, exist_ok=True)

    manifest_out = REVIEW_ROOT / "review_selection.csv"

    fields = [
        "SelectionGroup",
        "RelativePath",
        "SourceType",
        "TgaImageType",
        "BitsPerPixel",
        "Width",
        "Height",
        "Area",
        "OriginalPNG",
        "PBRifyTGA",
        "PairPNG",
    ]

    manifest_rows = []

    for row in order:
        rel = Path(row["RelativePath"])
        source = SOURCE_ROOT / rel.with_suffix(".png")
        output = OUTPUT_ROOT / rel

        if not source.is_file():
            raise RuntimeError(f"Missing review source: {source}")

        if not output.is_file():
            raise RuntimeError(f"Missing review output: {output}")

        group = selected[row["RelativePath"].lower()]

        pair = (
            PAIR_ROOT
            / group
            / f"{safe_name(row['RelativePath'])}__pair.png"
        )

        make_pair(
            source,
            output,
            pair,
            row["RelativePath"],
        )

        pair_rel = pair.relative_to(REVIEW_ROOT)

        manifest_rows.append({
            "SelectionGroup": group,
            "RelativePath": row["RelativePath"],
            "SourceType": row["SourceType"],
            "TgaImageType": row["TgaImageType"],
            "BitsPerPixel": row["BitsPerPixel"],
            "Width": row["Width"],
            "Height": row["Height"],
            "Area": row["_area"],
            "OriginalPNG": str(source),
            "PBRifyTGA": str(output),
            "PairPNG": str(pair_rel),
        })

        if group == "large_all":
            save_seam_crops(
                output,
                row["RelativePath"],
                row["_width"],
                row["_height"],
            )

    with manifest_out.open(
        "w",
        encoding="utf-8-sig",
        newline=""
    ) as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(manifest_rows)

    summary = REVIEW_ROOT / "README.txt"

    counts = {}
    for r in manifest_rows:
        counts[r["SelectionGroup"]] = counts.get(
            r["SelectionGroup"], 0
        ) + 1

    with summary.open("w", encoding="utf-8") as f:
        f.write("AoM:EE PBRify V4 production visual review\n")
        f.write("==========================================\n\n")
        f.write(f"Manifest rows: {len(rows)}\n")
        f.write(f"Review textures: {len(manifest_rows)}\n\n")

        for group in [
            "recovered_all",
            "large_all",
            "multi_tile",
            "smallest",
            "coverage",
        ]:
            f.write(f"{group}: {counts.get(group, 0)}\n")

        f.write("\n")
        f.write(
            "All production files are READ-ONLY inputs to this review.\n"
        )
        f.write(
            "The review does not modify processed\\PBRify_V4.\n"
        )
        f.write(
            "Source PNGs are enlarged 4x nearest-neighbour for display only.\n"
        )
        f.write(
            "large_all additionally receives crops around predicted "
            "256px-input tile boundaries.\n"
        )

    print("============================================")
    print("AoM EE PBRIFY V4 VISUAL REVIEW PREPARATION")
    print("============================================")
    print(f"Manifest rows : {len(rows)}")
    print(f"Review files  : {len(manifest_rows)}")

    for group in [
        "recovered_all",
        "large_all",
        "multi_tile",
        "smallest",
        "coverage",
    ]:
        print(f"{group:18}: {counts.get(group, 0)}")

    print(f"Review root   : {REVIEW_ROOT}")
    print(f"Selection CSV : {manifest_out}")
    print("\nVISUAL REVIEW PACK: PASS")


if __name__ == "__main__":
    main()
