$Root = 'D:\AI_upscaling\AoMEE\tests\remaster_benchmark'

$ManifestPath = Join-Path $Root 'remaster_benchmark_manifest.csv'
$QAV3Path     = Join-Path $Root 'benchmark_output_qa_v3.csv'
$InputRoot    = Join-Path $Root 'png_input'
$ReviewRoot   = Join-Path $Root 'visual_review'

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

if (-not (Test-Path -LiteralPath $QAV3Path)) {
    throw "QA v3 report not found: $QAV3Path"
}

if (-not (Test-Path -LiteralPath $InputRoot)) {
    throw "PNG benchmark input directory not found: $InputRoot"
}

$null = New-Item -ItemType Directory -Force -Path $ReviewRoot
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ReviewRoot 'by_category')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ReviewRoot 'recovered_exceptions')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ReviewRoot 'all')

py -c "import PIL" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Pillow is required but was not found."
}

$Python = @'
from pathlib import Path
import csv
import math
import re
from collections import defaultdict
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(r"""__ROOT__""")
MANIFEST_PATH = ROOT / "remaster_benchmark_manifest.csv"
QA_PATH = ROOT / "benchmark_output_qa_v3.csv"
INPUT_ROOT = ROOT / "png_input"
REVIEW_ROOT = ROOT / "visual_review"

CATEGORY_ROOT = REVIEW_ROOT / "by_category"
RECOVERED_ROOT = REVIEW_ROOT / "recovered_exceptions"
ALL_ROOT = REVIEW_ROOT / "all"

for d in (CATEGORY_ROOT, RECOVERED_ROOT, ALL_ROOT):
    d.mkdir(parents=True, exist_ok=True)

# ------------------------------------------------------------
# Load manifest + validated output paths from QA v3.
# ------------------------------------------------------------

with MANIFEST_PATH.open("r", encoding="utf-8-sig", newline="") as f:
    manifest = list(csv.DictReader(f))

with QA_PATH.open("r", encoding="utf-8-sig", newline="") as f:
    qa = list(csv.DictReader(f))

if len(manifest) != 115:
    raise RuntimeError(f"Expected 115 manifest entries, found {len(manifest)}")

if len(qa) != 115:
    raise RuntimeError(f"Expected 115 QA entries, found {len(qa)}")

qa_by_rel = {
    row["RelativePath"].replace("\\", "/").lower(): row
    for row in qa
}

# ------------------------------------------------------------
# Index benchmark input PNGs.
# ------------------------------------------------------------

input_files = [
    p for p in INPUT_ROOT.rglob("*")
    if p.is_file()
]

def norm(s):
    return str(s).replace("\\", "/").strip("/").lower()

def without_ext(s):
    p = Path(s)
    return norm(p.with_suffix(""))

def find_input(original_rel):

    target = without_ext(original_rel)
    parts = target.split("/")

    # Longest matching suffix first.
    for n in range(len(parts), 1, -1):
        suffix = "/".join(parts[-n:])

        matches = [
            p for p in input_files
            if without_ext(
                str(p.relative_to(INPUT_ROOT))
            ).endswith(suffix)
        ]

        if len(matches) == 1:
            return matches[0]

    # Unique filename fallback.
    name = Path(original_rel).name.lower()

    matches = [
        p for p in input_files
        if p.name.lower() == name
    ]

    if len(matches) == 1:
        return matches[0]

    return None

# ------------------------------------------------------------
# Fonts.
# ------------------------------------------------------------

try:
    FONT = ImageFont.truetype("arial.ttf", 18)
    SMALL_FONT = ImageFont.truetype("arial.ttf", 15)
    TITLE_FONT = ImageFont.truetype("arial.ttf", 22)
except Exception:
    FONT = ImageFont.load_default()
    SMALL_FONT = FONT
    TITLE_FONT = FONT

# ------------------------------------------------------------
# Neutral checkerboard background for transparency.
# ------------------------------------------------------------

def checkerboard(w, h, size=16):
    img = Image.new("RGB", (w, h), (220, 220, 220))
    draw = ImageDraw.Draw(img)

    for y in range(0, h, size):
        for x in range(0, w, size):
            if ((x // size) + (y // size)) % 2:
                draw.rectangle(
                    [x, y, x + size - 1, y + size - 1],
                    fill=(190, 190, 190)
                )

    return img

# ------------------------------------------------------------
# Composite RGBA onto checkerboard.
# ------------------------------------------------------------

def preview_image(path, box_w=300, box_h=300):

    with Image.open(path) as src:
        img = src.convert("RGBA")

    # Fit while preserving aspect ratio.
    scale = min(box_w / img.width, box_h / img.height)

    new_w = max(1, round(img.width * scale))
    new_h = max(1, round(img.height * scale))

    img = img.resize(
        (new_w, new_h),
        Image.Resampling.LANCZOS
    )

    bg = checkerboard(box_w, box_h)

    x = (box_w - new_w) // 2
    y = (box_h - new_h) // 2

    bg_rgba = bg.convert("RGBA")
    bg_rgba.alpha_composite(img, (x, y))

    return bg_rgba.convert("RGB")

# ------------------------------------------------------------
# Text wrapping.
# ------------------------------------------------------------

def wrap_text(text, width=46):
    words = text.replace("\\", "/").split("/")
    lines = []
    current = ""

    for word in words:

        candidate = word if not current else current + "/" + word

        if len(candidate) <= width:
            current = candidate
        else:
            if current:
                lines.append(current)

            current = word

    if current:
        lines.append(current)

    return lines

# ------------------------------------------------------------
# Build one sheet from records.
# ------------------------------------------------------------

CELL_W = 320
IMAGE_W = 300
IMAGE_H = 300
LABEL_H = 58
CELL_H = IMAGE_H + LABEL_H

SHEET_COLS = 3
SHEET_ROWS = 6

SHEET_W = SHEET_COLS * CELL_W
SHEET_H = 75 + SHEET_ROWS * CELL_H

def make_sheet(records, output_path, title):

    sheet = Image.new(
        "RGB",
        (SHEET_W, SHEET_H),
        (245, 245, 245)
    )

    draw = ImageDraw.Draw(sheet)

    draw.text(
        (12, 12),
        title,
        fill=(20, 20, 20),
        font=TITLE_FONT
    )

    for i, record in enumerate(records):

        row = i // SHEET_COLS
        col = i % SHEET_COLS

        x = col * CELL_W + 10
        y = 50 + row * CELL_H

        originals = [
            ("Original", record["input"]),
            ("HAT Sharper", record["sharp"]),
            ("HAT SRx4", record["sr"])
        ]

        # Each record occupies one horizontal row:
        # Original / Sharper / SRx4
        for panel, (label, path) in enumerate(originals):

            px = x + panel * 100
            py = y

            # Since the three previews share the row, place them
            # across the whole sheet instead below.
            # This block is replaced below.
            pass

    # Redesign sheet: one texture per row, three panels.
    sheet = Image.new(
        "RGB",
        (SHEET_COLS * CELL_W, SHEET_ROWS * 370 + 50),
        (245, 245, 245)
    )

    draw = ImageDraw.Draw(sheet)

    draw.text(
        (12, 10),
        title,
        fill=(20, 20, 20),
        font=TITLE_FONT
    )

    for i, record in enumerate(records):

        row = i

        y = 45 + row * 370

        panels = [
            ("Original", record["input"]),
            ("HAT Sharper", record["sharp"]),
            ("HAT SRx4", record["sr"])
        ]

        for panel, (label, path) in enumerate(panels):

            x = panel * 320 + 10

            preview = preview_image(
                path,
                IMAGE_W,
                IMAGE_H
            )

            sheet.paste(preview, (x, y))

            draw.text(
                (x + 4, y + 302),
                label,
                fill=(20, 20, 20),
                font=FONT
            )

        # Path label spanning the bottom of the row.
        path_text = record["relative"]
        lines = wrap_text(path_text, 105)

        label_y = y + 325

        for line in lines[:2]:
            draw.text(
                (10, label_y),
                line,
                fill=(70, 70, 70),
                font=SMALL_FONT
            )
            label_y += 16

    sheet.save(
        output_path,
        format="PNG",
        optimize=True
    )

# ------------------------------------------------------------
# Build records + exact alpha validation.
# ------------------------------------------------------------

records = []

alpha_results = []

for m in manifest:

    relative = m["OriginalRelativePath"]
    key = norm(relative)

    qa_row = qa_by_rel.get(key)

    if qa_row is None:
        raise RuntimeError(
            f"Missing QA row for {relative}"
        )

    input_path = find_input(relative)

    if input_path is None:
        raise RuntimeError(
            f"Could not locate benchmark input PNG for {relative}"
        )

    sharp_path = Path(qa_row["SharperOutput"])
    sr_path = Path(qa_row["SRx4Output"])

    if not sharp_path.exists():
        raise RuntimeError(
            f"Sharper output missing: {sharp_path}"
        )

    if not sr_path.exists():
        raise RuntimeError(
            f"SRx4 output missing: {sr_path}"
        )

    input_img = Image.open(input_path).convert("RGBA")
    sharp_img = Image.open(sharp_path).convert("RGBA")
    sr_img = Image.open(sr_path).convert("RGBA")

    expected_size = (
        input_img.width * 4,
        input_img.height * 4
    )

    if sharp_img.size != expected_size:
        raise RuntimeError(
            f"Unexpected Sharper size for {relative}: "
            f"{sharp_img.size}, expected {expected_size}"
        )

    if sr_img.size != expected_size:
        raise RuntimeError(
            f"Unexpected SRx4 size for {relative}: "
            f"{sr_img.size}, expected {expected_size}"
        )

    # --------------------------------------------------------
    # Exact alpha validation.
    # --------------------------------------------------------

    original_alpha = input_img.getchannel("A")

    expected_alpha = original_alpha.resize(
        expected_size,
        Image.Resampling.NEAREST
    )

    sharp_alpha = sharp_img.getchannel("A")
    sr_alpha = sr_img.getchannel("A")

    sharp_alpha_ok = (
        sharp_alpha.tobytes() ==
        expected_alpha.tobytes()
    )

    sr_alpha_ok = (
        sr_alpha.tobytes() ==
        expected_alpha.tobytes()
    )

    alpha_results.append({
        "RelativePath": relative,
        "SharperAlphaExact": sharp_alpha_ok,
        "SRx4AlphaExact": sr_alpha_ok
    })

    records.append({
        "relative": relative,
        "category": m.get("Category", "Unknown"),
        "input": input_path,
        "sharp": sharp_path,
        "sr": sr_path,
        "selection": m.get("Selection", ""),
        "alpha_band": m.get("AlphaBand", "")
    })

# ------------------------------------------------------------
# Alpha report.
# ------------------------------------------------------------

alpha_report = REVIEW_ROOT / "alpha_integrity.csv"

with alpha_report.open(
    "w",
    encoding="utf-8-sig",
    newline=""
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=[
            "RelativePath",
            "SharperAlphaExact",
            "SRx4AlphaExact"
        ]
    )

    writer.writeheader()
    writer.writerows(alpha_results)

sharp_alpha_pass = sum(
    1 for r in alpha_results
    if r["SharperAlphaExact"]
)

sr_alpha_pass = sum(
    1 for r in alpha_results
    if r["SRx4AlphaExact"]
)

# ------------------------------------------------------------
# Group by category.
# ------------------------------------------------------------

groups = defaultdict(list)

for record in records:
    groups[record["category"]].append(record)

for category, items in sorted(groups.items()):

    safe = re.sub(
        r"[^A-Za-z0-9._-]+",
        "_",
        category
    ).strip("_")

    if not safe:
        safe = "Unknown"

    for start in range(0, len(items), SHEET_ROWS):

        chunk = items[start:start + SHEET_ROWS]

        part = start // SHEET_ROWS + 1

        filename = (
            f"{safe}_part_{part:02d}.png"
        )

        make_sheet(
            chunk,
            CATEGORY_ROOT / filename,
            f"{category} — {part:02d}"
        )

# ------------------------------------------------------------
# All-texture sheets.
# ------------------------------------------------------------

for start in range(0, len(records), SHEET_ROWS):

    chunk = records[start:start + SHEET_ROWS]

    part = start // SHEET_ROWS + 1

    make_sheet(
        chunk,
        ALL_ROOT / f"all_part_{part:02d}.png",
        f"All benchmark textures — {part:02d}"
    )

# ------------------------------------------------------------
# Recovered-exception sheets.
# ------------------------------------------------------------

recovered = [
    r for r in records
    if norm(r["relative"]).startswith(
        "patched_to_verify/"
    )
]

for start in range(0, len(recovered), SHEET_ROWS):

    chunk = recovered[start:start + SHEET_ROWS]

    part = start // SHEET_ROWS + 1

    make_sheet(
        chunk,
        RECOVERED_ROOT / f"recovered_part_{part:02d}.png",
        f"Recovered exceptions — {part:02d}"
    )

# ------------------------------------------------------------
# Summary.
# ------------------------------------------------------------

summary = REVIEW_ROOT / "visual_review_summary.txt"

with summary.open(
    "w",
    encoding="utf-8"
) as f:

    f.write("============================================\n")
    f.write("AoM:EE HAT BENCHMARK VISUAL REVIEW\n")
    f.write("============================================\n\n")

    f.write(f"Benchmark textures: {len(records)}\n\n")

    f.write("ALPHA INTEGRITY\n")
    f.write("--------------------------------------------\n")
    f.write(
        f"Sharper exact alpha: {sharp_alpha_pass}/"
        f"{len(alpha_results)}\n"
    )
    f.write(
        f"SRx4 exact alpha:    {sr_alpha_pass}/"
        f"{len(alpha_results)}\n"
    )
    f.write("\n")

    if sharp_alpha_pass == len(alpha_results):
        f.write("Sharper alpha: PASS\n")
    else:
        f.write("Sharper alpha: PROBLEMS FOUND\n")

    if sr_alpha_pass == len(alpha_results):
        f.write("SRx4 alpha: PASS\n")
    else:
        f.write("SRx4 alpha: PROBLEMS FOUND\n")

    f.write("\n")
    f.write("Visual sheets:\n")
    f.write(f"{CATEGORY_ROOT}\n")
    f.write(f"{ALL_ROOT}\n")
    f.write(f"{RECOVERED_ROOT}\n")

print()
print("============================================")
print("AoM:EE HAT VISUAL REVIEW BUILD")
print("============================================")
print()

print(f"Benchmark textures: {len(records)}")
print()
print(
    f"Sharper exact alpha: {sharp_alpha_pass}/"
    f"{len(alpha_results)}"
)
print(
    f"SRx4 exact alpha:    {sr_alpha_pass}/"
    f"{len(alpha_results)}"
)

print()

if (
    sharp_alpha_pass == len(alpha_results)
    and sr_alpha_pass == len(alpha_results)
):
    print("ALPHA INTEGRITY: PASS — 115/115 for both models")
else:
    print("ALPHA INTEGRITY: PROBLEMS FOUND")

print()
print(f"Visual review folder:")
print(REVIEW_ROOT)
print()
print(f"Summary:")
print(summary)
print()
print(f"Alpha report:")
print(alpha_report)
'@

$Python = $Python.Replace('__ROOT__', $Root)

$Temp = Join-Path $env:TEMP 'aom_hat_visual_review.py'

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
    throw "Visual review generation failed with exit code $ExitCode."
}