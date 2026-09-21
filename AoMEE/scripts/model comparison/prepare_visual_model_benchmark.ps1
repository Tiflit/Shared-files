$ErrorActionPreference = 'Stop'

# ============================================================
# AoM:EE VISUAL MODEL-SELECTION BENCHMARK PREPARATION
#
# Temporary benchmark.
#
# PURPOSE
# -------
# Build a human-friendly model comparison set dominated by
# recognizable complete images:
#
#   40 Icons
#   25 UI
#   10 Portrait / Artwork
#    5 Effects / Misc
#
# Total target: 80 textures
#
# This script ONLY selects and copies source textures.
# It does NOT run any AI upscaling.
#
# ============================================================

$Root = 'D:\AI_upscaling\AoMEE'
$Extracted = Join-Path $Root 'extracted'
$BenchmarkRoot = Join-Path $Root 'tests\visual_model_comparison'
$Originals = Join-Path $BenchmarkRoot 'original'
$Reports = Join-Path $BenchmarkRoot 'selection'

if (-not (Test-Path -LiteralPath $Extracted -PathType Container)) {
    throw "Extracted texture directory not found: $Extracted"
}

New-Item -ItemType Directory -Force -Path $BenchmarkRoot | Out-Null
New-Item -ItemType Directory -Force -Path $Originals | Out-Null
New-Item -ItemType Directory -Force -Path $Reports | Out-Null

# ------------------------------------------------------------
# Pillow check
# ------------------------------------------------------------

py -c "import PIL; print('Pillow OK')" 2>$null

if ($LASTEXITCODE -ne 0) {
    throw 'Pillow is required.'
}

# ------------------------------------------------------------
# Embedded Python selector
# ------------------------------------------------------------

$python = @'
from pathlib import Path
from PIL import Image
import csv
import math
import random
import shutil
import re

ROOT = Path(r"""__ROOT__""")
EXTRACTED = Path(r"""__EXTRACTED__""")
BENCHMARK = Path(r"""__BENCHMARK__""")
ORIGINALS = Path(r"""__ORIGINALS__""")
REPORTS = Path(r"""__REPORTS__""")

TARGETS = {
    "Icon": 40,
    "UI": 25,
    "Portrait/Artwork": 10,
    "Effect/Misc": 5,
}

TOTAL_TARGET = sum(TARGETS.values())

# Deterministic selection so rerunning the script gives the same set
# unless the source inventory changes.
RANDOM_SEED = 20260919
random.seed(RANDOM_SEED)

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

def norm(s):
    return str(s).replace("\\", "/").strip("/").lower()


def path_text(path):
    return norm(path.relative_to(EXTRACTED))


def is_squareish(width, height):
    ratio = width / height if height else 999
    return 0.75 <= ratio <= 1.333


def size_score(width, height):
    """
    Prefer dimensions that are large enough to show meaningful detail,
    but avoid enormous atlas-like textures.
    """
    area = width * height

    score = 0.0

    if width >= 64 and height >= 64:
        score += 3.0

    if width >= 128 and height >= 128:
        score += 2.0

    if width >= 256 and height >= 256:
        score += 1.0

    if min(width, height) >= 64:
        score += 1.0

    # Penalize extremely large textures, which are less useful for this
    # particular visual benchmark.
    if area > 1024 * 1024:
        score -= 1.0

    return score


def technical_penalty(text):
    """
    Strongly reject maps whose primary purpose is technical shading/data.
    """
    patterns = [
        r"(^|[/ _-])normal([/ _.-]|$)",
        r"(^|[/ _-])_nm([/ _.-]|$)",
        r"(^|[/ _-])nm([/ _.-]|$)",
        r"(^|[/ _-])spec([/ _.-]|$)",
        r"(^|[/ _-])_spec([/ _.-]|$)",
        r"(^|[/ _-])gloss([/ _.-]|$)",
        r"(^|[/ _-])_gloss([/ _.-]|$)",
        r"(^|[/ _-])bump([/ _.-]|$)",
        r"(^|[/ _-])mask([/ _.-]|$)",
        r"(^|[/ _-])shadow([/ _.-]|$)",
        r"(^|[/ _-])alpha([/ _.-]|$)",
        r"(^|[/ _-])depth([/ _.-]|$)",
        r"(^|[/ _-])height([/ _.-]|$)",
        r"(^|[/ _-])roughness([/ _.-]|$)",
    ]

    for pattern in patterns:
        if re.search(pattern, text):
            return 8.0

    return 0.0


def classify(text, width, height):
    """
    Classify into benchmark-oriented visual groups.

    Priority is intentional:
        Icon -> UI -> Portrait/Artwork -> Effect/Misc
    """

    basename = Path(text).name
    stem = Path(text).stem

    # --------------------------------------------------------
    # ICON
    # --------------------------------------------------------

    icon_score = 0.0

    icon_terms = [
        " icon",
        "icons",
        "icon ",
        " icon.",
        "portrait",
        "minor icon",
        "major icon",
        "power icon",
        "improvement icon",
        "unit icon",
        "building icon",
        "god icon",
        "scenario icon",
    ]

    for term in icon_terms:
        if term in text:
            icon_score += 3.0

    # Explicit icon directories are very strong evidence.
    if "/icons/" in "/" + text + "/":
        icon_score += 8.0

    if basename.startswith("icon "):
        icon_score += 5.0

    # Icons are usually square-ish.
    if is_squareish(width, height):
        icon_score += 3.0

    # Prefer common practical icon dimensions.
    if (width, height) in {
        (32, 32),
        (64, 64),
        (128, 128),
        (256, 256),
    }:
        icon_score += 4.0

    # --------------------------------------------------------
    # UI
    # --------------------------------------------------------

    ui_score = 0.0

    if "/ui/" in "/" + text + "/":
        ui_score += 10.0

    ui_terms = [
        "button",
        "arrow",
        "border",
        "boarder",
        "corner",
        "scroll",
        "checkbox",
        "check box",
        "radio",
        "cursor",
        "uparrow",
        "downarrow",
        "leftarrow",
        "rightarrow",
        "titlebar",
        "bottom bar",
        "bottombar",
        "progress bar",
        "status",
        "panel",
        "frame",
        "slider",
        "techtree",
        "tech tree",
        "campmap",
        "start up",
    ]

    for term in ui_terms:
        if term in text:
            ui_score += 3.0

    # Files with explicit UI naming conventions.
    if text.startswith("ui_") or "/ui_" in text:
        ui_score += 5.0

    # Larger UI artwork deserves preference.
    if width >= 128 or height >= 128:
        ui_score += 2.0

    # --------------------------------------------------------
    # PORTRAIT / ARTWORK
    # --------------------------------------------------------

    portrait_score = 0.0

    portrait_terms = [
        "portrait",
        "head",
        "face",
        "hero",
        "god minor",
        "god major",
        "scenario",
        "cinematic",
        "cine ",
        "campmap",
        "loading",
        "title",
    ]

    for term in portrait_terms:
        if term in text:
            portrait_score += 3.0

    if is_squareish(width, height):
        portrait_score += 2.0

    if width >= 128 and height >= 128:
        portrait_score += 3.0

    # --------------------------------------------------------
    # EFFECT / MISC
    # --------------------------------------------------------

    effect_score = 0.0

    effect_terms = [
        "sfx ",
        "effect",
        "fx ",
        "particle",
        "glow",
        "streak",
        "spark",
        "flame",
        "smoke",
        "shockwave",
        "recreation",
        "steak",
        "meteor",
        "overlay",
    ]

    for term in effect_terms:
        if term in text:
            effect_score += 3.0

    # --------------------------------------------------------
    # Final class
    # --------------------------------------------------------

    scores = {
        "Icon": icon_score,
        "UI": ui_score,
        "Portrait/Artwork": portrait_score,
        "Effect/Misc": effect_score,
    }

    category = max(scores, key=scores.get)
    score = scores[category]

    if score < 3.0:
        return "Effect/Misc", 0.0

    return category, score


def selection_score(category, category_score, width, height, text):
    score = category_score

    score += size_score(width, height)

    if is_squareish(width, height):
        score += 2.5

    # Strong preference for images that are visually inspectable.
    if min(width, height) >= 64:
        score += 2.0

    # Avoid extremely tiny assets even if classified as icons.
    if min(width, height) < 32:
        score -= 6.0

    # Mild preference for alpha-bearing visual assets where possible.
    # We don't make alpha a hard requirement.
    try:
        with Image.open(EXTRACTED / text) as img:
            if "A" in img.getbands():
                extrema = img.getchannel("A").getextrema()

                if extrema != (255, 255):
                    score += 1.5
    except Exception:
        pass

    # Penalize obvious technical textures.
    score -= technical_penalty(text)

    return score


# ------------------------------------------------------------
# Scan inventory
# ------------------------------------------------------------

files = []

for path in EXTRACTED.rglob("*.tga"):

    if not path.is_file():
        continue

    relative = path.relative_to(EXTRACTED)
    text = norm(relative)

    try:
        with Image.open(path) as img:
            width, height = img.size
    except Exception:
        continue

    # Hard exclusion of very tiny textures.
    if width < 32 or height < 32:
        continue

    if technical_penalty(text) >= 8.0:
        continue

    category, category_score = classify(
        text,
        width,
        height
    )

    score = selection_score(
        category,
        category_score,
        width,
        height,
        text
    )

    files.append({
        "Path": path,
        "RelativePath": str(relative),
        "Width": width,
        "Height": height,
        "Category": category,
        "CategoryScore": category_score,
        "SelectionScore": score,
    })

print("")
print("Scanned usable textures:", len(files))

# ------------------------------------------------------------
# Build category pools
# ------------------------------------------------------------

pools = {
    category: [
        item for item in files
        if item["Category"] == category
    ]
    for category in TARGETS
}

# Sort primarily by score and secondarily by path for deterministic
# behavior.
for category in pools:
    pools[category].sort(
        key=lambda x: (
            -x["SelectionScore"],
            x["RelativePath"].lower()
        )
    )

# ------------------------------------------------------------
# Select targets
# ------------------------------------------------------------

selected = []
selected_paths = set()

for category, target in TARGETS.items():

    pool = pools[category]

    if len(pool) < target:
        print(
            f"WARNING: only {len(pool)} candidates available "
            f"for {category}; target was {target}."
        )

    # Take considerably more than target from the strongest candidates,
    # then add deterministic diversity by selecting across the pool.
    take = min(target, len(pool))

    if len(pool) <= take:
        choices = pool[:take]
    else:
        # First 70% based on score.
        strong_count = max(
            take,
            int(len(pool) * 0.20)
        )

        strong = pool[:strong_count]

        remaining = pool[strong_count:]

        random.shuffle(remaining)

        # Most selections remain score-driven, but this prevents the
        # benchmark from containing 40 nearly identical icon assets.
        random_count = max(
            0,
            take // 5
        )

        random_count = min(
            random_count,
            len(remaining)
        )

        choices = (
            strong[:take - random_count]
            + remaining[:random_count]
        )

        choices.sort(
            key=lambda x: (
                -x["SelectionScore"],
                x["RelativePath"].lower()
            )
        )

    for item in choices:

        key = norm(item["RelativePath"])

        if key in selected_paths:
            continue

        selected.append(item)
        selected_paths.add(key)

# ------------------------------------------------------------
# If category overlap or shortages prevent 80 textures,
# fill remaining places from the best unused candidates.
# ------------------------------------------------------------

if len(selected) < TOTAL_TARGET:

    remaining = [
        item
        for item in files
        if norm(item["RelativePath"]) not in selected_paths
    ]

    remaining.sort(
        key=lambda x: (
            -x["SelectionScore"],
            x["RelativePath"].lower()
        )
    )

    for item in remaining:

        selected.append(item)
        selected_paths.add(
            norm(item["RelativePath"])
        )

        if len(selected) >= TOTAL_TARGET:
            break

# Trim in the extremely unlikely event of overshoot.
selected = selected[:TOTAL_TARGET]

# Stable ordering for the final manifest.
category_order = {
    "Icon": 1,
    "UI": 2,
    "Portrait/Artwork": 3,
    "Effect/Misc": 4,
}

selected.sort(
    key=lambda x: (
        category_order.get(x["Category"], 99),
        -x["SelectionScore"],
        x["RelativePath"].lower()
    )
)

# ------------------------------------------------------------
# Validate selected textures before copying
#
# Image.open() can successfully read a TGA header while the
# actual pixel decoder later fails. Force a full pixel load here.
# Unreadable files are excluded and replaced from the candidate
# pools.
# ------------------------------------------------------------

validation_cache = {}
invalid_candidates = {}

def is_readable(item):
    key = norm(item["RelativePath"])

    if key in validation_cache:
        return validation_cache[key]

    try:
        with Image.open(item["Path"]) as img:
            img.load()

        validation_cache[key] = True
        return True

    except Exception as exc:
        invalid_candidates[key] = (
            f"{type(exc).__name__}: {exc}"
        )

        validation_cache[key] = False
        return False


# Remove unreadable textures from the current selection.
validated = []

for item in selected:

    if is_readable(item):
        validated.append(item)

selected = validated

selected_paths = {
    norm(item["RelativePath"])
    for item in selected
}


# ------------------------------------------------------------
# Restore category quotas after removing invalid files
# ------------------------------------------------------------

for category, target in TARGETS.items():

    current_count = sum(
        1
        for item in selected
        if item["Category"] == category
    )

    if current_count >= target:
        continue

    for item in pools[category]:

        key = norm(item["RelativePath"])

        if key in selected_paths:
            continue

        if not is_readable(item):
            continue

        selected.append(item)
        selected_paths.add(key)
        current_count += 1

        if current_count >= target:
            break


# ------------------------------------------------------------
# Fill any remaining slots globally
# ------------------------------------------------------------

if len(selected) < TOTAL_TARGET:

    remaining = [
        item
        for item in files
        if norm(item["RelativePath"])
        not in selected_paths
    ]

    remaining.sort(
        key=lambda x: (
            -x["SelectionScore"],
            x["RelativePath"].lower()
        )
    )

    for item in remaining:

        if len(selected) >= TOTAL_TARGET:
            break

        key = norm(item["RelativePath"])

        if key in selected_paths:
            continue

        if not is_readable(item):
            continue

        selected.append(item)
        selected_paths.add(key)


# Stable final ordering.
category_order = {
    "Icon": 1,
    "UI": 2,
    "Portrait/Artwork": 3,
    "Effect/Misc": 4,
}

selected.sort(
    key=lambda x: (
        category_order.get(x["Category"], 99),
        -x["SelectionScore"],
        x["RelativePath"].lower()
    )
)

selected = selected[:TOTAL_TARGET]


# ------------------------------------------------------------
# Report unreadable source textures
# ------------------------------------------------------------

invalid_path = (
    REPORTS / "unreadable_candidates.txt"
)

with open(
    invalid_path,
    "w",
    encoding="utf-8"
) as f:

    f.write(
        "AoM:EE Visual Model Comparison\n"
        "Unreadable candidate textures\n"
        "==============================\n\n"
    )

    if invalid_candidates:

        for key in sorted(invalid_candidates):

            f.write(
                f"{key}\n"
                f"  {invalid_candidates[key]}\n\n"
            )

    else:

        f.write(
            "No unreadable candidate textures were encountered.\n"
        )

# ------------------------------------------------------------
# Copy selected originals
# ------------------------------------------------------------

for item in selected:

    source = item["Path"]

    destination = (
        ORIGINALS
        / item["RelativePath"]
    )

    destination.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    shutil.copy2(
        source,
        destination
    )

# ------------------------------------------------------------
# Write manifest
# ------------------------------------------------------------

manifest_path = (
    BENCHMARK
    / "visual_model_comparison_manifest.csv"
)

with open(
    manifest_path,
    "w",
    newline="",
    encoding="utf-8-sig"
) as f:

    writer = csv.writer(f)

    writer.writerow([
        "Index",
        "RelativePath",
        "Category",
        "Width",
        "Height",
        "CategoryScore",
        "SelectionScore",
    ])

    for index, item in enumerate(selected, 1):

        writer.writerow([
            index,
            item["RelativePath"],
            item["Category"],
            item["Width"],
            item["Height"],
            f'{item["CategoryScore"]:.3f}',
            f'{item["SelectionScore"]:.3f}',
        ])

# ------------------------------------------------------------
# Write category summary
# ------------------------------------------------------------

summary_path = (
    REPORTS
    / "selection_summary.txt"
)

counts = {}

for item in selected:
    counts[item["Category"]] = (
        counts.get(item["Category"], 0)
        + 1
    )

with open(
    summary_path,
    "w",
    encoding="utf-8"
) as f:

    f.write(
        "AoM:EE Visual Model Comparison Benchmark\n"
        "========================================\n\n"
    )

    f.write(
        f"Selected textures: {len(selected)}\n\n"
    )

    f.write("CATEGORY COUNTS\n")
    f.write("---------------\n")

    for category in TARGETS:
        f.write(
            f"{category:<20} "
            f"{counts.get(category, 0):>3}\n"
        )

    f.write("\n")
    f.write("TARGETS\n")
    f.write("-------\n")

    for category, target in TARGETS.items():
        f.write(
            f"{category:<20} "
            f"{target:>3}\n"
        )

    f.write("\n")
    f.write("Excluded technical textures include normal/spec/gloss/\n")
    f.write("shadow/mask/alpha/depth/height-style assets.\n")

    f.write("\n")
    f.write("This is a visual-selection benchmark, not a production\n")
    f.write("classification of the entire AoM:EE texture inventory.\n")

# ------------------------------------------------------------
# Create an original-only contact sheet
# ------------------------------------------------------------

SHEET_DIR = REPORTS / "original_review"
SHEET_DIR.mkdir(
    parents=True,
    exist_ok=True
)

PANEL_W = 240
PANEL_H = 240
LABEL_H = 52

COLS = 8
ROWS = 5

MARGIN = 20
GAP = 10

SHEET_W = (
    MARGIN * 2
    + COLS * PANEL_W
    + (COLS - 1) * GAP
)

SHEET_H = (
    MARGIN * 2
    + ROWS * (PANEL_H + LABEL_H)
    + (ROWS - 1) * GAP
)

def checkerboard(w, h, square=16):
    image = Image.new(
        "RGB",
        (w, h),
        (225, 225, 225)
    )

    from PIL import ImageDraw

    draw = ImageDraw.Draw(image)

    for y in range(0, h, square):
        for x in range(0, w, square):
            if ((x // square) + (y // square)) % 2:
                draw.rectangle(
                    [
                        x,
                        y,
                        min(x + square - 1, w - 1),
                        min(y + square - 1, h - 1)
                    ],
                    fill=(195, 195, 195)
                )

    return image


try:
    from PIL import ImageFont, ImageDraw

    try:
        FONT = ImageFont.truetype(
            "arial.ttf",
            14
        )
    except Exception:
        FONT = ImageFont.load_default()

except Exception:
    FONT = None

from PIL import ImageDraw

for sheet_index in range(
    0,
    len(selected),
    COLS * ROWS
):

    chunk = selected[
        sheet_index:
        sheet_index + COLS * ROWS
    ]

    sheet = Image.new(
        "RGB",
        (SHEET_W, SHEET_H),
        (248, 248, 248)
    )

    draw = ImageDraw.Draw(sheet)

    for local_index, item in enumerate(chunk):

        col = local_index % COLS
        row = local_index // COLS

        x = (
            MARGIN
            + col * (
                PANEL_W + GAP
            )
        )

        y = (
            MARGIN
            + row * (
                PANEL_H + LABEL_H + GAP
            )
        )

        source = (
            ORIGINALS
            / item["RelativePath"]
        )

        with Image.open(source) as src:
            image = src.convert("RGBA")

        scale = min(
            PANEL_W / image.width,
            PANEL_H / image.height
        )

        nw = max(
            1,
            round(image.width * scale)
        )

        nh = max(
            1,
            round(image.height * scale)
        )

        image = image.resize(
            (nw, nh),
            Image.Resampling.NEAREST
            if scale > 1
            else Image.Resampling.LANCZOS
        )

        bg = checkerboard(
            PANEL_W,
            PANEL_H
        ).convert("RGBA")

        px = (
            PANEL_W - nw
        ) // 2

        py = (
            PANEL_H - nh
        ) // 2

        bg.alpha_composite(
            image,
            (px, py)
        )

        sheet.paste(
            bg.convert("RGB"),
            (x, y)
        )

        draw.rectangle(
            [
                x,
                y,
                x + PANEL_W - 1,
                y + PANEL_H - 1
            ],
            outline=(145, 145, 145),
            width=1
        )

        label = (
            f'{item["Category"]} | '
            f'{item["Width"]}×{item["Height"]}'
        )

        draw.text(
            (x + 5, y + PANEL_H + 4),
            label,
            fill=(25, 25, 25),
            font=FONT
        )

    output_path = (
        SHEET_DIR
        / f"original_selection_{sheet_index // (COLS * ROWS) + 1:02d}.png"
    )

    sheet.save(
        output_path,
        format="PNG",
        optimize=True
    )

# ------------------------------------------------------------
# Write README
# ------------------------------------------------------------

readme_path = (
    BENCHMARK
    / "README.txt"
)

with open(
    readme_path,
    "w",
    encoding="utf-8"
) as f:

    f.write(
        "AoM:EE Visual Model Comparison Benchmark\n"
        "=========================================\n\n"
        "Purpose:\n"
        "  Temporary human-visual comparison of SR models.\n\n"
        "Selected source images are stored under:\n"
        "  original\\\n\n"
        "Before running any AI model, inspect:\n"
        "  selection\\original_review\\\n\n"
        "Manifest:\n"
        "  visual_model_comparison_manifest.csv\n\n"
        "Selection targets:\n"
        "  40 Icons\n"
        "  25 UI\n"
        "  10 Portrait/Artwork\n"
        "   5 Effect/Misc\n\n"
        "The original source textures are copied without modification.\n"
        "No upscaling is performed by this preparation script.\n"
    )

# ------------------------------------------------------------
# Console output
# ------------------------------------------------------------

print("")
print("============================================")
print("AoM:EE VISUAL BENCHMARK PREPARATION")
print("============================================")
print("")

print(
    f"Selected: {len(selected)} / {TOTAL_TARGET}"
)

print("")
print("Category counts:")

for category in TARGETS:
    print(
        f"  {category:<20} "
        f"{counts.get(category, 0)}"
    )

print("")
print("Benchmark root:")
print(f"  {BENCHMARK}")

print("")
print("Original textures:")
print(f"  {ORIGINALS}")

print("")
print("Manifest:")
print(f"  {manifest_path}")

print("")
print("Original-only review sheets:")
print(f"  {SHEET_DIR}")

print("")
print("IMPORTANT:")
print("  No AI processing was performed.")
print("  No clean game/source files were modified.")
print("  Review the original selection before running models.")
print("")

'@

$python = $python.Replace('__ROOT__', $Root)
$python = $python.Replace('__EXTRACTED__', $Extracted)
$python = $python.Replace('__BENCHMARK__', $BenchmarkRoot)
$python = $python.Replace('__ORIGINALS__', $Originals)
$python = $python.Replace('__REPORTS__', $Reports)

$temp = Join-Path $env:TEMP 'aom_prepare_visual_model_benchmark.py'

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
    throw "Benchmark preparation failed with exit code $code."
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "VISUAL BENCHMARK PREPARATION COMPLETE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Review the original-only sheets before processing any models:"
Write-Host "  $Reports\original_review"
Write-Host ""