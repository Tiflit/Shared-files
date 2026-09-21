$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE\tests\visual_model_comparison'

$OutputRoot = Join-Path $Root 'visual_review'
$Individual = Join-Path $OutputRoot 'individual'
$Overview = Join-Path $OutputRoot 'overview'

foreach ($dir in @($Individual,$Overview)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

py -c "import PIL; print('Pillow OK')" 2>$null

if ($LASTEXITCODE -ne 0) {
    throw 'Pillow is required.'
}

$python = @'
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import re

ROOT = Path(r"""__ROOT__""")
INDIVIDUAL = Path(r"""__INDIVIDUAL__""")
OVERVIEW = Path(r"""__OVERVIEW__""")

MODELS = ["Original", "HAT", "SwinIR", "DRCT", "DAT"]

DIRS = {
    "Original": ROOT / "original",
    "HAT": ROOT / "HAT",
    "SwinIR": ROOT / "SwinIR",
    "DRCT": ROOT / "DRCT",
    "DAT": ROOT / "DAT",
}

def norm(s):
    return str(s).replace("\\", "/").strip("/").lower()

def index(folder):
    result = {}

    for p in folder.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".tga", ".png"}:
            result[norm(p.relative_to(folder))] = p

    return result

indexes = {
    model: index(DIRS[model])
    for model in MODELS
}

originals = sorted(indexes["Original"])

print(f"Original textures found: {len(originals)}")

def find_output(model, rel):
    stem = str(Path(rel).with_suffix(""))

    for ext in (".tga", ".png"):
        key = norm(stem + ext)

        if key in indexes[model]:
            return indexes[model][key]

    return None

def load_font(size, bold=False):
    names = (
        ["arialbd.ttf", "Arial Bold.ttf"]
        if bold
        else ["arial.ttf", "Arial.ttf"]
    )

    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except Exception:
            pass

    return ImageFont.load_default()

FONT = load_font(24)
SMALL = load_font(18)
BOLD = load_font(28, True)
TITLE = load_font(34, True)

PANEL_W = 560
PANEL_H = 560
GAP = 18
MARGIN = 24
HEADER = 82
FOOTER = 45

WIDTH = (
    MARGIN * 2
    + PANEL_W * 5
    + GAP * 4
)

HEIGHT = (
    MARGIN
    + HEADER
    + PANEL_H
    + FOOTER
    + MARGIN
)

def checker(w, h, size=28):
    img = Image.new("RGB", (w, h), (225,225,225))
    d = ImageDraw.Draw(img)

    for y in range(0,h,size):
        for x in range(0,w,size):

            if ((x // size) + (y // size)) % 2:
                d.rectangle(
                    [
                        x,
                        y,
                        min(x+size-1,w-1),
                        min(y+size-1,h-1)
                    ],
                    fill=(195,195,195)
                )

    return img

def render(path, original=False):

    if path is None:
        return Image.new(
            "RGB",
            (PANEL_W,PANEL_H),
            (235,235,235)
        )

    with Image.open(path) as src:
        img = src.convert("RGBA")
        native_w, native_h = img.size

    scale = min(
        PANEL_W/native_w,
        PANEL_H/native_h
    )

    nw = max(1, round(native_w*scale))
    nh = max(1, round(native_h*scale))

    # Native original is enlarged with nearest-neighbour ONLY
    # for display, preserving its original pixel structure.
    if original and scale > 1:
        resample = Image.Resampling.NEAREST
    else:
        resample = Image.Resampling.LANCZOS

    img = img.resize(
        (nw,nh),
        resample
    )

    bg = checker(
        PANEL_W,
        PANEL_H
    ).convert("RGBA")

    x = (PANEL_W-nw)//2
    y = (PANEL_H-nh)//2

    bg.alpha_composite(
        img,
        (x,y)
    )

    return bg.convert("RGB")

def dims(path):

    if path is None:
        return "MISSING"

    try:
        with Image.open(path) as img:
            return f"{img.width}×{img.height}"
    except Exception:
        return "ERROR"

def safe_name(rel):

    s = str(Path(rel).with_suffix(""))

    s = s.replace("\\","_")
    s = s.replace("/","_")

    s = re.sub(
        r"[^A-Za-z0-9._ -]+",
        "_",
        s
    )

    return s.strip(" ._")

def make_individual(rel):

    paths = {}

    for model in MODELS:

        if model == "Original":
            paths[model] = indexes["Original"].get(
                norm(rel)
            )
        else:
            paths[model] = find_output(
                model,
                rel
            )

    sheet = Image.new(
        "RGB",
        (WIDTH,HEIGHT),
        (248,248,248)
    )

    d = ImageDraw.Draw(sheet)

    title = str(rel).replace("\\","/")

    d.text(
        (MARGIN,MARGIN),
        "AoM:EE Visual Model Comparison",
        font=TITLE,
        fill=(15,15,15)
    )

    d.text(
        (MARGIN,MARGIN+44),
        title,
        font=SMALL,
        fill=(60,60,60)
    )

    y = MARGIN + HEADER

    for i,model in enumerate(MODELS):

        x = (
            MARGIN
            + i*(PANEL_W+GAP)
        )

        d.text(
            (x,y-36),
            model,
            font=BOLD,
            fill=(15,15,15)
        )

        img = render(
            paths[model],
            original=(model=="Original")
        )

        sheet.paste(
            img,
            (x,y)
        )

        d.rectangle(
            [
                x,
                y,
                x+PANEL_W-1,
                y+PANEL_H-1
            ],
            outline=(140,140,140),
            width=2
        )

        centered = dims(paths[model])

        d.text(
            (x+8,y+PANEL_H+8),
            centered,
            font=SMALL,
            fill=(65,65,65)
        )

    d.text(
        (
            MARGIN,
            HEIGHT-30
        ),
        "Original = native source. Model outputs = 4×. Transparency shown over checkerboard.",
        font=SMALL,
        fill=(70,70,70)
    )

    output = (
        INDIVIDUAL
        / (safe_name(rel) + "__comparison.png")
    )

    sheet.save(
        output,
        format="PNG",
        optimize=True
    )

    return output

# ------------------------------------------------------------
# Generate individual comparisons
# ------------------------------------------------------------

missing = []

for rel in originals:

    for model in MODELS[1:]:

        if find_output(model,rel) is None:
            missing.append(
                (model,rel)
            )

    make_individual(rel)

# ------------------------------------------------------------
# Generate compact overview sheets.
#
# 5 columns:
#   Original | HAT | SwinIR | DRCT | DAT
#
# 4 textures per sheet.
# ------------------------------------------------------------

OV_PANEL_W = 360
OV_PANEL_H = 300
OV_GAP = 12
OV_MARGIN = 18
OV_LABEL_H = 42
OV_ROWS = 4

OV_WIDTH = (
    OV_MARGIN*2
    + 5*OV_PANEL_W
    + 4*OV_GAP
)

OV_ROW_H = (
    OV_LABEL_H
    + OV_PANEL_H
    + 24
)

OV_HEIGHT = (
    OV_MARGIN*2
    + OV_ROWS*OV_ROW_H
)

def render_overview(path, original=False):

    if path is None:
        return Image.new(
            "RGB",
            (OV_PANEL_W,OV_PANEL_H),
            (235,235,235)
        )

    with Image.open(path) as src:
        img = src.convert("RGBA")

    scale = min(
        OV_PANEL_W/img.width,
        OV_PANEL_H/img.height
    )

    nw = max(
        1,
        round(img.width*scale)
    )

    nh = max(
        1,
        round(img.height*scale)
    )

    if original and scale > 1:
        method = Image.Resampling.NEAREST
    else:
        method = Image.Resampling.LANCZOS

    img = img.resize(
        (nw,nh),
        method
    )

    bg = checker(
        OV_PANEL_W,
        OV_PANEL_H,
        18
    ).convert("RGBA")

    x = (OV_PANEL_W-nw)//2
    y = (OV_PANEL_H-nh)//2

    bg.alpha_composite(
        img,
        (x,y)
    )

    return bg.convert("RGB")

for start in range(
    0,
    len(originals),
    OV_ROWS
):

    chunk = originals[
        start:start+OV_ROWS
    ]

    sheet = Image.new(
        "RGB",
        (OV_WIDTH,OV_HEIGHT),
        (248,248,248)
    )

    d = ImageDraw.Draw(sheet)

    d.text(
        (OV_MARGIN,OV_MARGIN),
        f"AoM:EE Visual Comparison — {start+1}-{start+len(chunk)}",
        font=BOLD,
        fill=(15,15,15)
    )

    for row,rel in enumerate(chunk):

        row_y = (
            OV_MARGIN
            + 55
            + row*OV_ROW_H
        )

        d.text(
            (OV_MARGIN,row_y),
            str(rel).replace("\\","/"),
            font=SMALL,
            fill=(65,65,65)
        )

        image_y = row_y + OV_LABEL_H

        for col,model in enumerate(MODELS):

            x = (
                OV_MARGIN
                + col*(OV_PANEL_W+OV_GAP)
            )

            d.text(
                (x,image_y-24),
                model,
                font=SMALL,
                fill=(20,20,20)
            )

            if model == "Original":
                path = indexes["Original"].get(
                    norm(rel)
                )
                original = True
            else:
                path = find_output(
                    model,
                    rel
                )
                original = False

            img = render_overview(
                path,
                original
            )

            sheet.paste(
                img,
                (x,image_y)
            )

            d.rectangle(
                [
                    x,
                    image_y,
                    x+OV_PANEL_W-1,
                    image_y+OV_PANEL_H-1
                ],
                outline=(145,145,145),
                width=1
            )

    output = (
        OVERVIEW
        / f"visual_comparison_{start//OV_ROWS+1:02d}.png"
    )

    sheet.save(
        output,
        format="PNG",
        optimize=True
    )

# ------------------------------------------------------------
# Final report
# ------------------------------------------------------------

print("")
print("============================================")
print("AoM:EE VISUAL MODEL COMPARISON COMPLETE")
print("============================================")
print("")
print(f"Textures:       {len(originals)}")
print(f"Individual:     {INDIVIDUAL}")
print(f"Overview:       {OVERVIEW}")
print("")
print(f"Missing outputs: {len(missing)}")

if missing:
    print("")
    for model,rel in missing[:30]:
        print(
            f"  {model}: "
            f"{str(rel).replace(chr(92),'/')}"
        )

print("")
print("Panel order:")
print("  Original | HAT | SwinIR | DRCT | DAT")
print("")
'@

$python = $python.Replace('__ROOT__',$Root)
$python = $python.Replace('__INDIVIDUAL__',$Individual)
$python = $python.Replace('__OVERVIEW__',$Overview)

$temp = Join-Path $env:TEMP 'aom_visual_model_comparisons.py'

$python |
    Set-Content `
        -LiteralPath $temp `
        -Encoding UTF8

py $temp

$code = $LASTEXITCODE

Remove-Item `
    -LiteralPath $temp `
    -Force `
    -ErrorAction SilentlyContinue

if ($code -ne 0) {
    throw "Comparison generation failed with exit code $code."
}

Write-Host ""
Write-Host "Comparison images generated:"
Write-Host "  $Individual"
Write-Host "  $Overview"