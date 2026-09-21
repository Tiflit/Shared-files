$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE\tests\greek_model_comparison'
$Output = Join-Path $Root 'visual_review'

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Comparison root not found: $Root"
}

py -c "import PIL" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Pillow is required.'
}

$python = @'
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import csv
import math

ROOT = Path(r"""__ROOT__""")
OUT = ROOT / "visual_review"
OUT.mkdir(parents=True, exist_ok=True)

MODELS = ["Original", "HAT", "SwinIR", "DRCT", "DAT"]

try:
    FONT = ImageFont.truetype("arial.ttf", 18)
    SMALL = ImageFont.truetype("arial.ttf", 14)
    TITLE = ImageFont.truetype("arial.ttf", 22)
except Exception:
    FONT = ImageFont.load_default()
    SMALL = FONT
    TITLE = FONT

def norm(s):
    return str(s).replace("\\", "/").strip("/").lower()

def files_in(folder):
    if not folder.exists():
        return {}
    d = {}
    for p in folder.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".png", ".tga"}:
            d[norm(p.relative_to(folder))] = p
    return d

indexes = {m: files_in(ROOT / ("original" if m == "Original" else m)) for m in MODELS}

# The original filenames are authoritative. Output files are expected
# to have the same relative path, with a PNG or TGA extension.
originals = sorted(indexes["Original"])

def find_variant(model, original_rel):
    stem = str(Path(original_rel).with_suffix(""))
    for ext in (".png", ".tga"):
        hit = indexes[model].get(norm(stem + ext))
        if hit:
            return hit
    return None

def checker(w, h, size=16):
    out = Image.new("RGB", (w, h), (220, 220, 220))
    d = ImageDraw.Draw(out)
    for y in range(0, h, size):
        for x in range(0, w, size):
            if ((x // size) + (y // size)) % 2:
                d.rectangle([x, y, x + size - 1, y + size - 1], fill=(190, 190, 190))
    return out

def preview(path, box_w=300, box_h=260):
    if path is None:
        return Image.new("RGB", (box_w, box_h), (235, 235, 235))

    with Image.open(path) as src:
        img = src.convert("RGBA")

    scale = min(box_w / img.width, box_h / img.height)
    nw = max(1, round(img.width * scale))
    nh = max(1, round(img.height * scale))

    img = img.resize((nw, nh), Image.Resampling.LANCZOS)

    bg = checker(box_w, box_h)
    x = (box_w - nw) // 2
    y = (box_h - nh) // 2
    bg_rgba = bg.convert("RGBA")
    bg_rgba.alpha_composite(img, (x, y))
    return bg_rgba.convert("RGB")

CELL_W = 320
CELL_H = 310
TOP = 70
COLS = 5
ROWS_PER_SHEET = 4

def make_sheet(chunk, output_path, title):
    sheet = Image.new("RGB", (COLS * CELL_W, TOP + ROWS_PER_SHEET * CELL_H), (245, 245, 245))
    d = ImageDraw.Draw(sheet)

    d.text((18, 18), title, fill=(20, 20, 20), font=TITLE)

    # Each input texture occupies one row of five model cells.
    # Use a 5-column sheet, one texture per row.
    sheet = Image.new("RGB", (COLS * CELL_W, TOP + len(chunk) * CELL_H), (245, 245, 245))
    d = ImageDraw.Draw(sheet)
    d.text((18, 18), title, fill=(20, 20, 20), font=TITLE)

    labels = ["Original", "HAT", "SwinIR", "DRCT", "DAT"]

    for r, rel in enumerate(chunk):
        y = TOP + r * CELL_H
        base = Path(rel).stem

        for c, model in enumerate(MODELS):
            x = c * CELL_W
            path_in = rel if model == "Original" else rel

            image_path = indexes[model].get(norm(path_in)) if model == "Original" else find_variant(model, rel)
            img = preview(image_path)

            sheet.paste(img, (x + 10, y + 10))
            d.text((x + 12, y + 274), labels[c], fill=(20, 20, 20), font=FONT)

        d.text((12, y + 294), str(rel).replace("\\", "/"), fill=(30, 30, 30), font=SMALL)

    sheet.save(output_path)

# Main sheets, 4 textures per sheet.
for start in range(0, len(originals), ROWS_PER_SHEET):
    chunk = originals[start:start + ROWS_PER_SHEET]
    make_sheet(
        chunk,
        OUT / f"greek_comparison_{start // ROWS_PER_SHEET + 1:02d}.png",
        f"AoM:EE Greek model comparison — {start + 1}-{start + len(chunk)}"
    )

# A compact contact sheet containing only the 10 building textures.
building = [r for r in originals if r.lower().startswith("textures/building g ")]
if building:
    for start in range(0, len(building), ROWS_PER_SHEET):
        chunk = building[start:start + ROWS_PER_SHEET]
        make_sheet(
            chunk,
            OUT / f"buildings_{start // ROWS_PER_SHEET + 1:02d}.png",
            f"Greek buildings — {start + 1}-{start + len(chunk)}"
        )

print("")
print("============================================")
print("AoM:EE GREEK COMPARISON CONTACT SHEETS")
print("============================================")
print("")
print(f"Original textures: {len(originals)}")
print(f"Review folder:     {OUT}")
print("")
'@

$python = $python.Replace('__ROOT__', $Root)
$temp = Join-Path $env:TEMP 'aom_make_greek_comparison_sheets.py'
$python | Set-Content -LiteralPath $temp -Encoding UTF8

py $temp
$code = $LASTEXITCODE
Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue

if ($code -ne 0) {
    throw "Contact-sheet generation failed with exit code $code."
}
