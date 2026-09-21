$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE\tests\greek_model_comparison'
$ManifestPath = Join-Path $Root 'greek_model_comparison_manifest.csv'

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Manifest not found: $ManifestPath"
}

py -c "import PIL" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Pillow is required in the active Python environment.'
}

$python = @'
from pathlib import Path
from PIL import Image
import csv
import hashlib

ROOT = Path(r"""__ROOT__""")
MANIFEST_PATH = ROOT / "greek_model_comparison_manifest.csv"
MODELS = ["HAT", "SwinIR", "DRCT", "DAT"]

with MANIFEST_PATH.open("r", encoding="utf-8-sig", newline="") as f:
    manifest = list(csv.DictReader(f))

if len(manifest) != 24:
    raise RuntimeError(f"Expected 24 manifest entries, found {len(manifest)}")

def nearest_alpha(original, size):
    with Image.open(original) as img:
        return img.convert("RGBA").getchannel("A").resize(
            size, Image.Resampling.NEAREST
        )

results = []

for model in MODELS:
    for row in manifest:
        rel = Path(row["RelativePath"])
        original = ROOT / "original" / rel
        output = ROOT / model / rel

        r = {
            "Model": model,
            "RelativePath": row["RelativePath"],
            "OriginalWidth": "",
            "OriginalHeight": "",
            "OutputWidth": "",
            "OutputHeight": "",
            "Found": output.is_file(),
            "Correct4x": False,
            "AlphaExactNN4x": False,
            "OutputSHA256": "",
            "Status": ""
        }

        if not original.is_file():
            r["Status"] = "MISSING_ORIGINAL"
            results.append(r)
            continue

        with Image.open(original) as src:
            src_rgba = src.convert("RGBA")
            ow, oh = src_rgba.size

        r["OriginalWidth"] = ow
        r["OriginalHeight"] = oh

        if not output.is_file():
            r["Status"] = "MISSING_OUTPUT"
            results.append(r)
            continue

        with Image.open(output) as dst:
            dst_rgba = dst.convert("RGBA")
            dw, dh = dst_rgba.size

            r["OutputWidth"] = dw
            r["OutputHeight"] = dh
            r["Correct4x"] = (dw == ow * 4 and dh == oh * 4)

            if r["Correct4x"]:
                expected = nearest_alpha(original, (dw, dh))
                actual = dst_rgba.getchannel("A")
                r["AlphaExactNN4x"] = (actual.tobytes() == expected.tobytes())

        r["OutputSHA256"] = hashlib.sha256(output.read_bytes()).hexdigest()

        if not r["Correct4x"]:
            r["Status"] = "BAD_DIMENSIONS"
        elif not r["AlphaExactNN4x"]:
            r["Status"] = "ALPHA_MISMATCH"
        else:
            r["Status"] = "PASS"

        results.append(r)

out_csv = ROOT / "greek_model_comparison_qa_v2.csv"

with out_csv.open("w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
    writer.writeheader()
    writer.writerows(results)

print("")
print("============================================")
print("AoM:EE GREEK MODEL COMPARISON QA v2")
print("============================================")
print("")

overall_pass = True

for model in MODELS:
    subset = [r for r in results if r["Model"] == model]
    found = sum(r["Found"] for r in subset)
    dims = sum(r["Correct4x"] for r in subset)
    alpha = sum(r["AlphaExactNN4x"] for r in subset)
    passed = sum(r["Status"] == "PASS" for r in subset)

    print(model)
    print(f"  Found:            {found}/24")
    print(f"  Correct 4x:       {dims}/24")
    print(f"  Alpha exact NN:   {alpha}/24")
    print(f"  PASS:             {passed}/24")
    print("")

    if passed != 24:
        overall_pass = False

problems = [r for r in results if r["Status"] != "PASS"]

if problems:
    print("PROBLEMS:")
    for r in problems:
        print(f"  {r['Model']} | {r['RelativePath']} | {r['Status']}")
else:
    print("ALL 96 MODEL OUTPUTS PASSED DIMENSION + ALPHA QA.")

print("")
print(f"QA report: {out_csv}")

if not overall_pass:
    raise SystemExit(2)
'@

$python = $python.Replace('__ROOT__', $Root)
$temp = Join-Path $env:TEMP 'aom_greek_model_comparison_qa_v2.py'
$python | Set-Content -LiteralPath $temp -Encoding UTF8

py $temp
$code = $LASTEXITCODE

Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue

if ($code -ne 0) {
    throw "Greek model comparison QA v2 failed with exit code $code."
}
