$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE\tests\pbrify_model_comparison'
$Output = Join-Path $Root 'visual_review'

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Comparison root not found: $Root`nRun prepare_pbrify_model_comparison.ps1 and process the three models first."
}

$ManifestPath = Join-Path $Root 'pbrify_model_comparison_manifest.csv'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Manifest not found: $ManifestPath"
}

py -c "import PIL" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Pillow is required in the active Python environment.'
}

New-Item -ItemType Directory -Force -Path $Output | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Output 'individual') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Output 'overview') | Out-Null

$python = @'
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import csv
import math
import re

ROOT = Path(r"""__ROOT__""")
OUT = ROOT / "visual_review"
MANIFEST_PATH = ROOT / "pbrify_model_comparison_manifest.csv"

MODELS = ["Original", "HAT", "PBRify V4", "PBRify RPLKSRd V3"]
FOLDERS = {
    "Original": ROOT / "original",
    "HAT": ROOT / "HAT",
    "PBRify V4": ROOT / "PBRify_V4",
    "PBRify RPLKSRd V3": ROOT / "PBRify_RPLKSRd_V3",
}

# Display settings. The actual image files are never modified.
CELL_W = 360
IMAGE_W = 340
IMAGE_H = 300
ROW_H = 355
TOP = 92
COLS = 4
ROWS_PER_SHEET = 3

INDIVIDUAL_W = COLS * CELL_W
INDIVIDUAL_IMAGE_H = 430
INDIVIDUAL_TOP = 115

try:
    FONT = ImageFont.truetype("arial.ttf", 20)
    SMALL = ImageFont.truetype("arial.ttf", 16)
    TITLE = ImageFont.truetype("arial.ttf", 28)
    HEADER = ImageFont.truetype("arialbd.ttf", 22)
except Exception:
    FONT = ImageFont.load_default()
    SMALL = FONT
    TITLE = FONT
    HEADER = FONT

def norm(s):
    return str(s).replace("\\", "/").strip("/").lower()

def load_index(folder):
    result = {}
    if not folder.exists():
        return result
    for p in folder.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".tga", ".png"}:
            result[norm(p.relative_to(folder))] = p
    return result

indexes = {model: load_index(folder) for model, folder in FOLDERS.items()}

with MANIFEST_PATH.open("r", encoding="utf-8-sig", newline="") as f:
    manifest = list(csv.DictReader(f))

if not manifest:
    raise RuntimeError("The comparison manifest is empty.")

# Manifest order is authoritative. This preserves the exact previous selection.
originals = [row["RelativePath"] for row in manifest]

def find_variant(model, original_rel):
    rel = Path(original_rel)
    stem = str(rel.with_suffix(""))
    for ext in (".tga", ".png"):
        candidate = norm(stem + ext)
        hit = indexes[model].get(candidate)
        if hit:
            return hit
    return None

def checker(w, h, size=20):
    out = Image.new("RGB", (w, h), (225, 225, 225))
    d = ImageDraw.Draw(out)
    for y in range(0, h, size):
        for x in range(0, w, size):
            if ((x // size) + (y // size)) % 2:
                d.rectangle([x, y, x + size - 1, y + size - 1], fill=(195, 195, 195))
    return out

def open_rgba(path):
    with Image.open(path) as src:
        img = src.convert("RGBA")
        img.load()
        return img.copy()

def fit_preview(path, box_w=IMAGE_W, box_h=IMAGE_H):
    if path is None:
        bg = Image.new("RGB", (box_w, box_h), (238, 238, 238))
        d = ImageDraw.Draw(bg)
        d.text((12, 12), "MISSING", fill=(120, 0, 0), font=FONT)
        return bg

    img = open_rgba(path)

    scale = min(box_w / img.width, box_h / img.height)
    nw = max(1, round(img.width * scale))
    nh = max(1, round(img.height * scale))
    img = img.resize((nw, nh), Image.Resampling.LANCZOS)

    bg = checker(box_w, box_h).convert("RGBA")
    x = (box_w - nw) // 2
    y = (box_h - nh) // 2
    bg.alpha_composite(img, (x, y))
    return bg.convert("RGB")

def safe_name(rel):
    name = str(rel).replace("\\", "__").replace("/", "__")
    return re.sub(r'[^A-Za-z0-9._ -]', '_', name)

def draw_model_cell(sheet, draw, x, y, model, path):
    preview = fit_preview(path)
    sheet.paste(preview, (x + 10, y + 10))
    draw.text((x + 12, y + IMAGE_H + 18), model, fill=(20, 20, 20), font=HEADER)

def make_overview_sheet(chunk, output_path, title):
    height = TOP + len(chunk) * ROW_H
    width = COLS * CELL_W
    sheet = Image.new("RGB", (width, height), (245, 245, 245))
    d = ImageDraw.Draw(sheet)
    d.text((18, 18), title, fill=(20, 20, 20), font=TITLE)

    for r, rel in enumerate(chunk):
        y = TOP + r * ROW_H
        d.text((12, y + IMAGE_H + 48), str(rel).replace("\\", "/"),
               fill=(35, 35, 35), font=SMALL)

        for c, model in enumerate(MODELS):
            path = (
                indexes["Original"].get(norm(rel))
                if model == "Original"
                else find_variant(model, rel)
            )
            draw_model_cell(sheet, d, c * CELL_W, y, model, path)

    sheet.save(output_path)

def make_individual(rel, index):
    width = INDIVIDUAL_W
    height = INDIVIDUAL_TOP + INDIVIDUAL_IMAGE_H
    sheet = Image.new("RGB", (width, height), (245, 245, 245))
    d = ImageDraw.Draw(sheet)

    d.text((18, 18), f"AoM:EE model comparison — #{index:02d}", fill=(20, 20, 20), font=TITLE)
    d.text((18, 54), str(rel).replace("\\", "/"), fill=(35, 35, 35), font=SMALL)

    for c, model in enumerate(MODELS):
        x = c * CELL_W
        path = (
            indexes["Original"].get(norm(rel))
            if model == "Original"
            else find_variant(model, rel)
        )
        preview = fit_preview(path, IMAGE_W, IMAGE_H)
        sheet.paste(preview, (x + 10, INDIVIDUAL_TOP + 10))
        d.text((x + 12, INDIVIDUAL_TOP + IMAGE_H + 20),
               model, fill=(20, 20, 20), font=HEADER)

        if path is not None:
            try:
                with Image.open(path) as img:
                    size_text = f"{img.width} × {img.height}"
            except Exception:
                size_text = "unreadable"
        else:
            size_text = "missing"

        d.text((x + 12, INDIVIDUAL_TOP + IMAGE_H + 52),
               size_text, fill=(70, 70, 70), font=SMALL)

    sheet.save(OUT / "individual" / f"{index:02d}_{safe_name(rel)}.png")

# Generate individual four-way comparisons.
for i, rel in enumerate(originals, 1):
    make_individual(rel, i)

# Generate overview sheets, three textures per sheet.
for start in range(0, len(originals), ROWS_PER_SHEET):
    chunk = originals[start:start + ROWS_PER_SHEET]
    n = start // ROWS_PER_SHEET + 1
    make_overview_sheet(
        chunk,
        OUT / "overview" / f"pbrify_comparison_{n:02d}.png",
        f"AoM:EE HAT vs PBRify comparison — {start + 1}-{start + len(chunk)}"
    )

# Category overview sheets using the manifest's category field.
categories = {}
for row in manifest:
    categories.setdefault(row["Category"], []).append(row["RelativePath"])

for category, rels in categories.items():
    safe_cat = re.sub(r'[^A-Za-z0-9._ -]', '_', category.replace("/", "_"))
    for start in range(0, len(rels), ROWS_PER_SHEET):
        chunk = rels[start:start + ROWS_PER_SHEET]
        n = start // ROWS_PER_SHEET + 1
        make_overview_sheet(
            chunk,
            OUT / "overview" / f"{safe_cat}_{n:02d}.png",
            f"AoM:EE {category} — {start + 1}-{start + len(chunk)}"
        )

# Create a simple availability report.
report_path = OUT / "comparison_availability.txt"
with report_path.open("w", encoding="utf-8") as f:
    f.write("AoM:EE PBRify model comparison availability\n")
    f.write("=" * 52 + "\n\n")
    f.write(f"Manifest entries: {len(originals)}\n\n")

    totals = {}
    for model in MODELS:
        found = 0
        for rel in originals:
            path = indexes["Original"].get(norm(rel)) if model == "Original" else find_variant(model, rel)
            found += 1 if path is not None else 0
        totals[model] = found
        f.write(f"{model}: {found}/{len(originals)} found\n")

    f.write("\nMissing outputs:\n")
    for model in MODELS[1:]:
        missing = [
            rel for rel in originals
            if find_variant(model, rel) is None
        ]
        if missing:
            f.write(f"\n{model} ({len(missing)} missing)\n")
            for rel in missing:
                f.write(f"  {rel}\n")

print("")
print("============================================")
print("AoM:EE PBRIFY MODEL COMPARISON SHEETS")
print("============================================")
print("")
print(f"Textures:         {len(originals)}")
for model in MODELS:
    found = sum(
        1
        for rel in originals
        if (indexes["Original"].get(norm(rel)) if model == "Original" else find_variant(model, rel)) is not None
    )
    print(f"{model:20s} {found}/{len(originals)} found")
print("")
print(f"Individual sheets: {OUT / 'individual'}")
print(f"Overview sheets:   {OUT / 'overview'}")
print(f"Availability:      {OUT / 'comparison_availability.txt'}")
print("")
'@

$python = $python.Replace('__ROOT__', $Root)
$temp = Join-Path $env:TEMP 'aom_make_pbrify_model_comparison.py'
$python | Set-Content -LiteralPath $temp -Encoding UTF8

py $temp
$code = $LASTEXITCODE

Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue

if ($code -ne 0) {
    throw "PBRify comparison sheet generation failed with exit code $code."
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host 'PBRIFY COMPARISON SHEETS COMPLETE' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "Review folder: $Output"
Write-Host "Individual:    $(Join-Path $Output 'individual')"
Write-Host "Overview:      $(Join-Path $Output 'overview')"
Write-Host ''
