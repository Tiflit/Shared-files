$ErrorActionPreference = 'Stop'

# ============================================================
# AoM:EE Greek Model Comparison — Large Side-by-Side Viewer
#
# Generates:
#   Original | HAT | SwinIR | DRCT | DAT
#
# Original = native source texture, NOT AI-upscaled.
#
# Requirements:
#   Python
#   Pillow
#
# Existing directory layout:
#
# D:\AI_upscaling\AoMEE\tests\greek_model_comparison\
#     original\
#     HAT\
#     SwinIR\
#     DRCT\
#     DAT\
#
# Output:
#     visual_review_side_by_side\
#         individual\
#         overview\
# ============================================================

$Root = 'D:\AI_upscaling\AoMEE\tests\greek_model_comparison'
$OutputRoot = Join-Path $Root 'visual_review_side_by_side'
$IndividualOutput = Join-Path $OutputRoot 'individual'
$OverviewOutput = Join-Path $OutputRoot 'overview'

# ------------------------------------------------------------
# Verify paths
# ------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Comparison root not found: $Root"
}

foreach ($dir in @('original', 'HAT', 'SwinIR', 'DRCT', 'DAT')) {
    $path = Join-Path $Root $dir

    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Required folder not found: $path"
    }
}

# ------------------------------------------------------------
# Verify Pillow
# ------------------------------------------------------------

py -c "import PIL; print('Pillow OK')" 2>$null

if ($LASTEXITCODE -ne 0) {
    throw 'Pillow is required.'
}

# ------------------------------------------------------------
# Create output directories
# ------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $IndividualOutput | Out-Null
New-Item -ItemType Directory -Force -Path $OverviewOutput | Out-Null

# ------------------------------------------------------------
# Embedded Python
# ------------------------------------------------------------

$python = @'
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import re

ROOT = Path(r"""__ROOT__""")
INDIVIDUAL = Path(r"""__INDIVIDUAL__""")
OVERVIEW = Path(r"""__OVERVIEW__""")

MODELS = ["Original", "HAT", "SwinIR", "DRCT", "DAT"]

MODEL_DIRS = {
    "Original": ROOT / "original",
    "HAT": ROOT / "HAT",
    "SwinIR": ROOT / "SwinIR",
    "DRCT": ROOT / "DRCT",
    "DAT": ROOT / "DAT",
}

# ============================================================
# Configuration
# ============================================================

PANEL_W = 560
PANEL_H = 560

LEFT_MARGIN = 24
RIGHT_MARGIN = 24
TOP_MARGIN = 28

HEADER_H = 78
FOOTER_H = 48

PANEL_GAP = 18

BG_COLOR = (248, 248, 248)
TEXT_COLOR = (20, 20, 20)
SECONDARY_TEXT = (65, 65, 65)
BORDER_COLOR = (145, 145, 145)

# ============================================================
# Helpers
# ============================================================

def norm(s):
    return str(s).replace("\\", "/").strip("/").lower()


def files_in(folder):
    result = {}

    for p in folder.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".tga", ".png"}:
            rel = p.relative_to(folder)
            result[norm(rel)] = p

    return result


def load_fonts():
    candidates = [
        ("arial.ttf", "arialbd.ttf"),
        ("Arial.ttf", "Arial Bold.ttf"),
    ]

    for regular_name, bold_name in candidates:
        try:
            regular = ImageFont.truetype(regular_name, 24)
            small = ImageFont.truetype(regular_name, 18)
            bold = ImageFont.truetype(bold_name, 30)
            title = ImageFont.truetype(bold_name, 34)
            return regular, small, bold, title
        except Exception:
            pass

    default = ImageFont.load_default()
    return default, default, default, default


FONT, SMALL_FONT, BOLD_FONT, TITLE_FONT = load_fonts()


def text_size(draw, text, font):
    box = draw.textbbox((0, 0), text, font=font)
    return box[2] - box[0], box[3] - box[1]


def centered_text(draw, x0, y0, x1, y1, text, font, fill=TEXT_COLOR):
    tw, th = text_size(draw, text, font)

    x = x0 + (x1 - x0 - tw) / 2
    y = y0 + (y1 - y0 - th) / 2

    draw.text((x, y), text, font=font, fill=fill)


def checkerboard(width, height, square=28):
    img = Image.new("RGB", (width, height), (224, 224, 224))
    draw = ImageDraw.Draw(img)

    for y in range(0, height, square):
        for x in range(0, width, square):
            if ((x // square) + (y // square)) % 2:
                draw.rectangle(
                    [x, y, x + square - 1, y + square - 1],
                    fill=(192, 192, 192)
                )

    return img


def open_rgba(path):
    with Image.open(path) as src:
        return src.convert("RGBA")


def display_image(path, is_original):
    if path is None:
        return Image.new("RGB", (PANEL_W, PANEL_H), (235, 235, 235))

    img = open_rgba(path)

    width, height = img.size

    # For the ORIGINAL we deliberately enlarge using nearest-neighbour.
    #
    # This does NOT modify the actual source file.
    # It simply makes the original texture easy to inspect at the same
    # physical viewing size as the 4x model outputs.
    #
    # For the upscaled outputs, use Lanczos to fit them into the
    # viewing panel without adding another artificial sharpening step.
    scale = min(
        PANEL_W / width,
        PANEL_H / height
    )

    new_w = max(1, round(width * scale))
    new_h = max(1, round(height * scale))

    if is_original and scale > 1.0:
        resample = Image.Resampling.NEAREST
    else:
        resample = Image.Resampling.LANCZOS

    img = img.resize((new_w, new_h), resample)

    # Checkerboard behind transparency.
    bg = checkerboard(PANEL_W, PANEL_H).convert("RGBA")

    x = (PANEL_W - new_w) // 2
    y = (PANEL_H - new_h) // 2

    bg.alpha_composite(img, (x, y))

    return bg.convert("RGB")


def find_variant(model, relative_path):
    """
    Find candidate output using the same relative path as the original,
    allowing either .tga or .png.
    """

    stem = str(Path(relative_path).with_suffix(""))

    for extension in (".tga", ".png"):
        candidate = indexes[model].get(
            norm(stem + extension)
        )

        if candidate is not None:
            return candidate

    return None


def safe_filename(relative_path):
    name = str(Path(relative_path).with_suffix(""))

    name = name.replace("\\", "_")
    name = name.replace("/", "_")

    name = re.sub(
        r"[^A-Za-z0-9._ -]+",
        "_",
        name
    )

    name = name.strip(" ._")

    return name or "texture"


def image_dimensions(path):
    if path is None:
        return "MISSING"

    try:
        with Image.open(path) as img:
            return f"{img.width}×{img.height}"
    except Exception:
        return "?"


# ============================================================
# Index files
# ============================================================

indexes = {
    model: files_in(MODEL_DIRS[model])
    for model in MODELS
}

originals = sorted(indexes["Original"])

print("")
print("============================================")
print("AoM:EE LARGE SIDE-BY-SIDE COMPARISON")
print("============================================")
print("")
print(f"Original textures found: {len(originals)}")

# ============================================================
# Individual comparison
# ============================================================

TOTAL_W = (
    LEFT_MARGIN
    + len(MODELS) * PANEL_W
    + (len(MODELS) - 1) * PANEL_GAP
    + RIGHT_MARGIN
)

TOTAL_H = (
    TOP_MARGIN
    + HEADER_H
    + PANEL_H
    + FOOTER_H
    + 24
)


def make_individual(relative_path):
    paths = {}

    for model in MODELS:
        if model == "Original":
            paths[model] = indexes["Original"].get(
                norm(relative_path)
            )
        else:
            paths[model] = find_variant(
                model,
                relative_path
            )

    sheet = Image.new(
        "RGB",
        (TOTAL_W, TOTAL_H),
        BG_COLOR
    )

    draw = ImageDraw.Draw(sheet)

    # --------------------------------------------------------
    # Title
    # --------------------------------------------------------

    title = "AoM:EE Greek Model Comparison"

    draw.text(
        (LEFT_MARGIN, TOP_MARGIN),
        title,
        font=TITLE_FONT,
        fill=TEXT_COLOR
    )

    relative_display = str(relative_path).replace("\\", "/")

    draw.text(
        (LEFT_MARGIN, TOP_MARGIN + 44),
        relative_display,
        font=SMALL_FONT,
        fill=SECONDARY_TEXT
    )

    # --------------------------------------------------------
    # Panels
    # --------------------------------------------------------

    panel_y = TOP_MARGIN + HEADER_H

    for index, model in enumerate(MODELS):

        panel_x = (
            LEFT_MARGIN
            + index * (PANEL_W + PANEL_GAP)
        )

        # Model name
        centered_text(
            draw,
            panel_x,
            TOP_MARGIN + HEADER_H - 48,
            panel_x + PANEL_W,
            TOP_MARGIN + HEADER_H - 8,
            model,
            BOLD_FONT
        )

        # Image
        image = display_image(
            paths[model],
            is_original=(model == "Original")
        )

        sheet.paste(
            image,
            (panel_x, panel_y)
        )

        # Border
        draw.rectangle(
            [
                panel_x,
                panel_y,
                panel_x + PANEL_W - 1,
                panel_y + PANEL_H - 1
            ],
            outline=BORDER_COLOR,
            width=2
        )

        # Native dimensions
        dims = image_dimensions(paths[model])

        centered_text(
            draw,
            panel_x,
            panel_y + PANEL_H + 8,
            panel_x + PANEL_W,
            panel_y + PANEL_H + 36,
            dims,
            SMALL_FONT,
            SECONDARY_TEXT
        )

    # --------------------------------------------------------
    # Footer
    # --------------------------------------------------------

    footer_y = (
        TOP_MARGIN
        + HEADER_H
        + PANEL_H
        + FOOTER_H
    )

    footer = (
        "Original = native source texture. "
        "Model panels = 4× outputs. "
        "Transparency shown over checkerboard."
    )

    draw.text(
        (LEFT_MARGIN, footer_y),
        footer,
        font=SMALL_FONT,
        fill=SECONDARY_TEXT
    )

    output_name = (
        safe_filename(relative_path)
        + "__side_by_side.png"
    )

    output_path = INDIVIDUAL / output_name

    sheet.save(
        output_path,
        format="PNG",
        optimize=True
    )

    return output_path


# ============================================================
# Generate all individual images
# ============================================================

generated = 0
missing = []

for relative_path in originals:

    for model in ("HAT", "SwinIR", "DRCT", "DAT"):

        if find_variant(model, relative_path) is None:
            missing.append(
                (relative_path, model)
            )

    make_individual(relative_path)
    generated += 1


# ============================================================
# Overview sheets
#
# Four textures per overview.
# Each texture uses the same five-column layout:
#
# Original | HAT | SwinIR | DRCT | DAT
#
# The individual files remain the preferred detailed view.
# ============================================================

OVERVIEW_PANEL_W = 330
OVERVIEW_PANEL_H = 330

OVERVIEW_LABEL_H = 46
OVERVIEW_TITLE_H = 68

OVERVIEW_COLS = 5
OVERVIEW_ROWS = 4

OVERVIEW_GAP = 12
OVERVIEW_MARGIN = 18

OVERVIEW_W = (
    OVERVIEW_MARGIN * 2
    + OVERVIEW_COLS * OVERVIEW_PANEL_W
    + (OVERVIEW_COLS - 1) * OVERVIEW_GAP
)

OVERVIEW_ROW_H = (
    OVERVIEW_LABEL_H
    + OVERVIEW_PANEL_H
    + 32
)

OVERVIEW_H = (
    OVERVIEW_MARGIN * 2
    + OVERVIEW_TITLE_H
    + OVERVIEW_ROWS * OVERVIEW_ROW_H
)


def overview_preview(path, is_original):
    if path is None:
        return Image.new(
            "RGB",
            (OVERVIEW_PANEL_W, OVERVIEW_PANEL_H),
            (235, 235, 235)
        )

    img = open_rgba(path)

    width, height = img.size

    scale = min(
        OVERVIEW_PANEL_W / width,
        OVERVIEW_PANEL_H / height
    )

    new_w = max(1, round(width * scale))
    new_h = max(1, round(height * scale))

    if is_original and scale > 1.0:
        resample = Image.Resampling.NEAREST
    else:
        resample = Image.Resampling.LANCZOS

    img = img.resize(
        (new_w, new_h),
        resample
    )

    bg = checkerboard(
        OVERVIEW_PANEL_W,
        OVERVIEW_PANEL_H,
        square=18
    ).convert("RGBA")

    x = (OVERVIEW_PANEL_W - new_w) // 2
    y = (OVERVIEW_PANEL_H - new_h) // 2

    bg.alpha_composite(
        img,
        (x, y)
    )

    return bg.convert("RGB")


def make_overview(chunk, sheet_number):
    sheet = Image.new(
        "RGB",
        (OVERVIEW_W, OVERVIEW_H),
        BG_COLOR
    )

    draw = ImageDraw.Draw(sheet)

    draw.text(
        (OVERVIEW_MARGIN, OVERVIEW_MARGIN),
        f"AoM:EE Greek Model Comparison — Overview {sheet_number}",
        font=BOLD_FONT,
        fill=TEXT_COLOR
    )

    for row, relative_path in enumerate(chunk):

        row_y = (
            OVERVIEW_MARGIN
            + OVERVIEW_TITLE_H
            + row * OVERVIEW_ROW_H
        )

        # Texture filename
        draw.text(
            (
                OVERVIEW_MARGIN,
                row_y
            ),
            str(relative_path).replace("\\", "/"),
            font=SMALL_FONT,
            fill=SECONDARY_TEXT
        )

        image_y = row_y + OVERVIEW_LABEL_H

        paths = {}

        for model in MODELS:

            if model == "Original":
                paths[model] = indexes["Original"].get(
                    norm(relative_path)
                )
            else:
                paths[model] = find_variant(
                    model,
                    relative_path
                )

        for col, model in enumerate(MODELS):

            image_x = (
                OVERVIEW_MARGIN
                + col * (
                    OVERVIEW_PANEL_W
                    + OVERVIEW_GAP
                )
            )

            centered_text(
                draw,
                image_x,
                image_y - 28,
                image_x + OVERVIEW_PANEL_W,
                image_y - 4,
                model,
                SMALL_FONT
            )

            image = overview_preview(
                paths[model],
                is_original=(model == "Original")
            )

            sheet.paste(
                image,
                (image_x, image_y)
            )

            draw.rectangle(
                [
                    image_x,
                    image_y,
                    image_x + OVERVIEW_PANEL_W - 1,
                    image_y + OVERVIEW_PANEL_H - 1
                ],
                outline=BORDER_COLOR,
                width=1
            )

    output_path = (
        OVERVIEW
        / f"greek_comparison_overview_{sheet_number:02d}.png"
    )

    sheet.save(
        output_path,
        format="PNG",
        optimize=True
    )


# Generate overview sheets.
for index in range(
    0,
    len(originals),
    OVERVIEW_ROWS
):
    chunk = originals[
        index:index + OVERVIEW_ROWS
    ]

    make_overview(
        chunk,
        index // OVERVIEW_ROWS + 1
    )


# ============================================================
# Missing output report
# ============================================================

if missing:

    missing_path = (
        OVERVIEW
        / "missing_outputs.txt"
    )

    with open(
        missing_path,
        "w",
        encoding="utf-8"
    ) as f:

        f.write(
            "AoM:EE Greek Model Comparison\n"
            "Missing model outputs\n"
            "=========================\n\n"
        )

        for relative_path, model in missing:

            f.write(
                f"{model}: "
                f"{str(relative_path).replace(chr(92), '/')}\n"
            )


# ============================================================
# Final report
# ============================================================

print("")
print("Generated:")
print(f"  Individual comparisons: {generated}")
print(f"  Individual folder:      {INDIVIDUAL}")
print(f"  Overview folder:        {OVERVIEW}")

if missing:
    print("")
    print(f"Missing model outputs: {len(missing)}")
else:
    print("Missing model outputs: 0")

print("")
print("Panel order:")
print("  Original | HAT | SwinIR | DRCT | DAT")
print("")
print("IMPORTANT:")
print("  Original is displayed from the untouched native source texture.")
print("  Nearest-neighbour enlargement is used ONLY for visual presentation.")
print("  No source texture is modified.")
print("")
'@

# ------------------------------------------------------------
# Substitute paths
# ------------------------------------------------------------

$python = $python.Replace('__ROOT__', $Root)
$python = $python.Replace('__INDIVIDUAL__', $IndividualOutput)
$python = $python.Replace('__OVERVIEW__', $OverviewOutput)

# ------------------------------------------------------------
# Run Python
# ------------------------------------------------------------

$temp = Join-Path $env:TEMP 'aom_make_greek_side_by_side.py'

$python | Set-Content `
    -LiteralPath $temp `
    -Encoding UTF8

py $temp

$code = $LASTEXITCODE

Remove-Item `
    -LiteralPath $temp `
    -Force `
    -ErrorAction SilentlyContinue

if ($code -ne 0) {
    throw "Side-by-side generation failed with exit code $code."
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "SIDE-BY-SIDE COMPARISON COMPLETE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Individual comparisons:"
Write-Host "  $IndividualOutput"
Write-Host ""
Write-Host "Overview sheets:"
Write-Host "  $OverviewOutput"