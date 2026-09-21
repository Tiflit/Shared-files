$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE\tests\final_model_comparison'
$Output = Join-Path $Root 'visual_review'
$ManifestPath = Join-Path $Root 'final_model_comparison_manifest.csv'

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Final comparison root not found: $Root"
}
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
import re

ROOT = Path(r"""__ROOT__""")
OUT = ROOT / "visual_review"
MANIFEST_PATH = ROOT / "final_model_comparison_manifest.csv"

MODELS = ["Original", "PBRify V4", "UltraSharp V2"]
FOLDERS = {
    "Original": ROOT / "original",
    "PBRify V4": ROOT / "PBRify_V4",
    "UltraSharp V2": ROOT / "UltraSharp_V2",
}

# The same presentation dimensions used by the earlier model comparisons.
CELL_W = 470
IMAGE_W = 440
IMAGE_H = 340
ROW_H = 410
TOP = 105
COLS = 3
ROWS_PER_SHEET = 3

INDIVIDUAL_W = COLS * CELL_W
INDIVIDUAL_IMAGE_H = 470
INDIVIDUAL_TOP = 125

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
    raise RuntimeError("The final comparison manifest is empty.")

# The final manifest uses the Path column. Fall back to RelativePath for compatibility.
def get_rel(row):
    return row.get("Path") or row.get("RelativePath")

originals = [get_rel(row) for row in manifest]

if any(not x for x in originals):
    raise RuntimeError("Manifest contains an entry without Path/RelativePath.")

def find_variant(model, original_rel):
    rel = Path(original_rel)
    stem = str(rel.with_suffix(""))
    for ext in (".tga", ".png"):
        hit = indexes[model].get(norm(stem + ext))
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
        ImageDraw.Draw(bg).text((12, 12), "MISSING", fill=(120, 0, 0), font=FONT)
        return bg

    img = open_rgba(path)
    scale = min(box_w / img.width, box_h / img.height)
    nw = max(1, round(img.width * scale))
    nh = max(1, round(img.height * scale))
    img = img.resize((nw, nh), Image.Resampling.LANCZOS)

    bg = checker(box_w, box_h).convert("RGBA")
    bg.alpha_composite(img, ((box_w - nw) // 2, (box_h - nh) // 2))
    return bg.convert("RGB")

def safe_name(rel):
    name = str(rel).replace("\\", "__").replace("/", "__")
    return re.sub(r'[^A-Za-z0-9._ -]', '_', name)

def get_path(model, rel):
    return indexes["Original"].get(norm(rel)) if model == "Original" else find_variant(model, rel)

def make_overview_sheet(chunk, output_path, title):
    height = TOP + len(chunk) * ROW_H
    width = COLS * CELL_W
    sheet = Image.new("RGB", (width, height), (245, 245, 245))
    d = ImageDraw.Draw(sheet)
    d.text((18, 18), title, fill=(20, 20, 20), font=TITLE)

    for r, rel in enumerate(chunk):
        y = TOP + r * ROW_H
        d.text((12, y + IMAGE_H + 50), str(rel).replace("\\", "/"),
               fill=(35, 35, 35), font=SMALL)

        for c, model in enumerate(MODELS):
            draw_x = c * CELL_W
            path = get_path(model, rel)
            sheet.paste(fit_preview(path), (draw_x + 15, y + 10))
            d.text((draw_x + 17, y + IMAGE_H + 18),
                   model, fill=(20, 20, 20), font=HEADER)

    sheet.save(output_path)

def make_individual(rel, index):
    sheet = Image.new(
        "RGB",
        (INDIVIDUAL_W, INDIVIDUAL_TOP + INDIVIDUAL_IMAGE_H),
        (245, 245, 245)
    )
    d = ImageDraw.Draw(sheet)

    d.text((18, 18), f"AoM:EE final model comparison — #{index:02d}",
           fill=(20, 20, 20), font=TITLE)
    d.text((18, 57), str(rel).replace("\\", "/"),
           fill=(35, 35, 35), font=SMALL)

    for c, model in enumerate(MODELS):
        x = c * CELL_W
        path = get_path(model, rel)
        sheet.paste(fit_preview(path), (x + 15, INDIVIDUAL_TOP + 10))
        d.text((x + 17, INDIVIDUAL_TOP + IMAGE_H + 20),
               model, fill=(20, 20, 20), font=HEADER)

        if path is not None:
            try:
                with Image.open(path) as img:
                    size_text = f"{img.width} × {img.height}"
            except Exception:
                size_text = "unreadable"
        else:
            size_text = "missing"

        d.text((x + 17, INDIVIDUAL_TOP + IMAGE_H + 53),
               size_text, fill=(70, 70, 70), font=SMALL)

    sheet.save(OUT / "individual" / f"{index:02d}_{safe_name(rel)}.png")

# Individual 3-way sheets.
for i, rel in enumerate(originals, 1):
    make_individual(rel, i)

# Overview sheets: 3 textures per sheet, 3 model columns.
for start in range(0, len(originals), ROWS_PER_SHEET):
    chunk = originals[start:start + ROWS_PER_SHEET]
    n = start // ROWS_PER_SHEET + 1
    make_overview_sheet(
        chunk,
        OUT / "overview" / f"final_comparison_{n:02d}.png",
        f"AoM:EE final comparison — {start + 1}-{start + len(chunk)}"
    )

# Category overview sheets, preserving manifest order within each category.
categories = {}
for row in manifest:
    categories.setdefault(row.get("Category", "Uncategorized"), []).append(get_rel(row))

for category, rels in categories.items():
    safe_cat = re.sub(r'[^A-Za-z0-9._ -]', '_', str(category).replace("/", "_"))
    for start in range(0, len(rels), ROWS_PER_SHEET):
        chunk = rels[start:start + ROWS_PER_SHEET]
        n = start // ROWS_PER_SHEET + 1
        make_overview_sheet(
            chunk,
            OUT / "overview" / f"{safe_cat}_{n:02d}.png",
            f"AoM:EE {category} — {start + 1}-{start + len(chunk)}"
        )

# Final availability report.
report_path = OUT / "comparison_availability.txt"
with report_path.open("w", encoding="utf-8") as f:
    f.write("AoM:EE FINAL MODEL COMPARISON AVAILABILITY\n")
    f.write("=" * 48 + "\n\n")
    f.write(f"Manifest textures: {len(originals)}\n\n")

    for model in MODELS:
        found = sum(1 for rel in originals if get_path(model, rel) is not None)
        f.write(f"{model}: {found}/{len(originals)} found\n")

    f.write("\nMissing outputs:\n")
    for model in MODELS:
        missing = [rel for rel in originals if get_path(model, rel) is None]
        if missing:
            f.write(f"\n{model} ({len(missing)} missing)\n")
            for rel in missing:
                f.write(f"  {rel}\n")

print("")
print("============================================")
print("AoM:EE FINAL MODEL COMPARISON SHEETS")
print("============================================")
print("")
print(f"Textures: {len(originals)}")

for model in MODELS:
    found = sum(1 for rel in originals if get_path(model, rel) is not None)
    print(f"{model:20s} {found}/{len(originals)} found")

print("")
print(f"Individual sheets: {OUT / 'individual'}")
print(f"Overview sheets:   {OUT / 'overview'}")
print(f"Availability:      {OUT / 'comparison_availability.txt'}")
print("")
'@

$python = $python.Replace('__ROOT__', $Root)
$temp = Join-Path $env:TEMP 'aom_make_final_model_comparison.py'
$python | Set-Content -LiteralPath $temp -Encoding UTF8

py $temp
$code = $LASTEXITCODE

Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue

if ($code -ne 0) {
    throw "Final comparison sheet generation failed with exit code $code."
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host 'FINAL MODEL COMPARISON SHEETS COMPLETE' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "Review folder: $Output"
Write-Host "Individual:    $(Join-Path $Output 'individual')"
Write-Host "Overview:      $(Join-Path $Output 'overview')"
Write-Host ''
