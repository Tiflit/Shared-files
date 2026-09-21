$ErrorActionPreference = 'Stop'

$Root     = 'D:\AI_upscaling\AoMEE'
$TestRoot = Join-Path $Root 'tests\greek_model_comparison'
$Manifest = Join-Path $TestRoot 'greek_model_comparison_manifest.csv'

if (-not (Test-Path -LiteralPath $Manifest)) {
    throw "Manifest not found: $Manifest"
}

py -c "import PIL" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Pillow is required in the Python environment used by this script.'
}

$python = @'
from pathlib import Path
import csv
import hashlib
from PIL import Image

ROOT = Path(r"""__ROOT__""")
MANIFEST = ROOT / "greek_model_comparison_manifest.csv"
MODEL_NAMES = ["HAT", "SwinIR", "DRCT", "DAT"]

with MANIFEST.open("r", encoding="utf-8-sig", newline="") as f:
    rows = list(csv.DictReader(f))

def norm(p):
    return str(p).replace("\\", "/").lower().strip("/")

def image_index(folder):
    result = {}
    if not folder.exists():
        return result
    for p in folder.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".png", ".tga"}:
            result[norm(p.relative_to(folder))] = p
    return result

def expected_alpha(original_path, size):
    with Image.open(original_path) as img:
        rgba = img.convert("RGBA")
        alpha = rgba.getchannel("A")
        return alpha.resize(size, Image.Resampling.NEAREST)

def alpha_hash(img):
    return hashlib.sha256(img.tobytes()).hexdigest()

results = []

for model in MODEL_NAMES:
    folder = ROOT / model
    outputs = image_index(folder)

    for row in rows:
        rel = norm(row["RelativePath"])
        # Outputs should retain the same relative path, but accept a .png/.tga extension.
        stem = str(Path(rel).with_suffix(""))
        candidates = [
            outputs.get(stem + ".png"),
            outputs.get(stem + ".tga"),
        ]
        out = next((p for p in candidates if p is not None), None)

        original = ROOT / "original" / Path(row["RelativePath"])

        record = {
            "Model": model,
            "RelativePath": row["RelativePath"],
            "Found": False,
            "Correct4x": False,
            "AlphaExactNN4x": False,
            "OutputWidth": "",
            "OutputHeight": "",
            "OriginalWidth": "",
            "OriginalHeight": "",
            "OutputSHA256": "",
            "Status": ""
        }

        if not original.exists():
            record["Status"] = "MISSING_ORIGINAL"
            results.append(record)
            continue

        with Image.open(original) as src:
            src_rgba = src.convert("RGBA")
            ow, oh = src_rgba.size

        record["OriginalWidth"] = ow
        record["OriginalHeight"] = oh

        if out is None:
            record["Status"] = "MISSING_OUTPUT"
            results.append(record)
            continue

        record["Found"] = True

        with Image.open(out) as dst:
            dst_rgba = dst.convert("RGBA")
            dw, dh = dst_rgba.size
            record["OutputWidth"] = dw
            record["OutputHeight"] = dh
            record["OutputSHA256"] = hashlib.sha256(out.read_bytes()).hexdigest()

            record["Correct4x"] = (dw == ow * 4 and dh == oh * 4)

            if record["Correct4x"]:
                expected = expected_alpha(original, (dw, dh))
                actual = dst_rgba.getchannel("A")
                record["AlphaExactNN4x"] = (actual.tobytes() == expected.tobytes())

        if not record["Correct4x"]:
            record["Status"] = "BAD_DIMENSIONS"
        elif not record["AlphaExactNN4x"]:
            record["Status"] = "ALPHA_MISMATCH"
        else:
            record["Status"] = "PASS"

        results.append(record)

out_csv = ROOT / "greek_model_comparison_qa.csv"
with out_csv.open("w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
    writer.writeheader()
    writer.writerows(results)

print("")
print("============================================")
print("AoM:EE GREEK MODEL COMPARISON QA")
print("============================================")
print("")

for model in MODEL_NAMES:
    subset = [r for r in results if r["Model"] == model]
    print(model)
    print(f"  Found:            {sum(r['Found'] for r in subset)}/{len(subset)}")
    print(f"  Correct 4x:       {sum(r['Correct4x'] for r in subset)}/{len(subset)}")
    print(f"  Alpha exact NN:   {sum(r['AlphaExactNN4x'] for r in subset)}/{len(subset)}")
    print(f"  PASS:             {sum(r['Status'] == 'PASS' for r in subset)}/{len(subset)}")
    print("")

print(f"QA report: {out_csv}")
'@

$python = $python.Replace('__ROOT__', $TestRoot)
$temp = Join-Path $env:TEMP 'aom_greek_model_comparison_qa.py'
$python | Set-Content -LiteralPath $temp -Encoding UTF8

py $temp
$code = $LASTEXITCODE

Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue

if ($code -ne 0) {
    throw "QA script failed with exit code $code."
}
