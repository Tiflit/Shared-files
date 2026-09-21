$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE\tests\greek_model_comparison'
$ManifestPath = Join-Path $Root 'greek_model_comparison_manifest.csv'

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Manifest not found: $ManifestPath"
}

# Pillow is sufficient for this analysis. NumPy is intentionally not required.
py -c "import PIL; print('Pillow OK')" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'This script requires Pillow in the active Python environment.'
}

$python = @'
from pathlib import Path
import csv
import math
import statistics

from PIL import Image

ROOT = Path(r"""__ROOT__""")
MANIFEST_PATH = ROOT / "greek_model_comparison_manifest.csv"

MODELS = ["HAT", "SwinIR", "DRCT", "DAT"]

with MANIFEST_PATH.open("r", encoding="utf-8-sig", newline="") as f:
    manifest = list(csv.DictReader(f))

if len(manifest) != 24:
    raise RuntimeError(f"Expected 24 manifest entries, found {len(manifest)}")


def load_rgb(path):
    with Image.open(path) as img:
        return img.convert("RGB")


def resize_to_source(img4x, source_size):
    # BOX averages the 4x4 output samples back onto the original pixel grid.
    # This avoids treating nearest-neighbour replication as added detail.
    return img4x.resize(source_size, Image.Resampling.BOX)


def rgb_stats(img):
    pixels = list(img.getdata())
    n = len(pixels)
    if n == 0:
        raise RuntimeError("Encountered an empty image")

    sum_r = sum_g = sum_b = 0.0
    for r, g, b in pixels:
        sum_r += r
        sum_g += g
        sum_b += b

    return (sum_r / n, sum_g / n, sum_b / n)


def luminance_pixel(pixel):
    r, g, b = pixel
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def gradient_energy(img):
    width, height = img.size
    if width < 2 and height < 2:
        return 0.0

    # Work directly from RGB pixels. This is slower than NumPy but keeps the
    # analysis dependency-free apart from Pillow.
    px = img.load()
    total_x = 0.0
    count_x = 0
    total_y = 0.0
    count_y = 0

    if width >= 2:
        for y in range(height):
            prev = luminance_pixel(px[0, y])
            for x in range(1, width):
                cur = luminance_pixel(px[x, y])
                total_x += abs(cur - prev)
                count_x += 1
                prev = cur

    if height >= 2:
        for y in range(1, height):
            for x in range(width):
                total_y += abs(
                    luminance_pixel(px[x, y]) - luminance_pixel(px[x, y - 1])
                )
                count_y += 1

    mean_x = total_x / count_x if count_x else 0.0
    mean_y = total_y / count_y if count_y else 0.0
    return (mean_x + mean_y) / 2.0


def pair_pixel_metrics(a, b):
    """Metrics for equal-size RGB images using only the Python standard library."""
    pa = a.load()
    pb = b.load()
    width, height = a.size
    n = width * height

    sum_dr = sum_dg = sum_db = 0.0
    sum_abs = 0.0
    sum_euclidean = 0.0
    sum_euclidean_sq = 0.0
    sum_abs_luma = 0.0
    sum_signed_luma = 0.0
    sum_chroma = 0.0
    strong_color_count = 0

    for y in range(height):
        for x in range(width):
            ar, ag, ab = pa[x, y]
            br, bg, bb = pb[x, y]

            dr = br - ar
            dg = bg - ag
            db = bb - ab

            sum_dr += dr
            sum_dg += dg
            sum_db += db

            sum_abs += abs(dr) + abs(dg) + abs(db)

            eu_sq = dr * dr + dg * dg + db * db
            eu = math.sqrt(eu_sq)
            sum_euclidean += eu
            sum_euclidean_sq += eu_sq

            ay = 0.2126 * ar + 0.7152 * ag + 0.0722 * ab
            by = 0.2126 * br + 0.7152 * bg + 0.0722 * bb
            dy = by - ay
            sum_abs_luma += abs(dy)
            sum_signed_luma += dy

            # Cb = B-Y, Cr = R-Y, matching the original NumPy script.
            acb = ab - ay
            acr = ar - ay
            bcb = bb - by
            bcr = br - by
            cdr = bcb - acb
            cdg = bcr - acr
            sum_chroma += math.sqrt(cdr * cdr + cdg * cdg)

            if eu > 12.0:
                strong_color_count += 1

    return {
        "SignedDeltaR": sum_dr / n,
        "SignedDeltaG": sum_dg / n,
        "SignedDeltaB": sum_db / n,
        "MeanAbsRGB": (sum_abs / n) / 3.0,
        "MeanRGBEuclidean": sum_euclidean / n,
        "P95RGBEuclidean": None,
        "MeanAbsLuma": sum_abs_luma / n,
        "SignedLuma": sum_signed_luma / n,
        "MeanChromaDelta": sum_chroma / n,
        "StrongColorShiftPct_gt12": strong_color_count * 100.0 / n,
        "EuclideanSquares": sum_euclidean_sq,
    }


def euclidean_values(a, b):
    pa = a.load()
    pb = b.load()
    width, height = a.size
    values = []

    for y in range(height):
        for x in range(width):
            ar, ag, ab = pa[x, y]
            br, bg, bb = pb[x, y]
            dr = br - ar
            dg = bg - ag
            db = bb - ab
            values.append(math.sqrt(dr * dr + dg * dg + db * db))

    return values


def hf_rms(output4x, source):
    baseline = source.resize(output4x.size, Image.Resampling.BICUBIC)
    stats = pair_pixel_metrics(baseline, output4x)
    return math.sqrt(stats["EuclideanSquares"] / (output4x.size[0] * output4x.size[1]))


def row_for(model, src_rel):
    return ROOT / model / Path(src_rel)


rows = []
summary_values = {m: [] for m in MODELS}
reduced_cache = {m: {} for m in MODELS}

for item in manifest:
    rel = item["RelativePath"]
    category = item.get("Category", "")

    original_path = ROOT / "original" / Path(rel)

    if not original_path.is_file():
        raise RuntimeError(f"Original missing: {original_path}")

    source = load_rgb(original_path)
    source_size = source.size
    source_mean = rgb_stats(source)
    source_grad = gradient_energy(source)

    for model in MODELS:
        out_path = row_for(model, rel)

        if not out_path.is_file():
            raise RuntimeError(f"Output missing: {out_path}")

        output = load_rgb(out_path)

        if output.size != (source.size[0] * 4, source.size[1] * 4):
            raise RuntimeError(
                f"Bad dimensions for {model} / {rel}: "
                f"{output.size[0]}x{output.size[1]}"
            )

        reduced = resize_to_source(output, source_size)
        reduced_cache[model][rel] = reduced.copy()

        stats = pair_pixel_metrics(source, reduced)
        eu_values = euclidean_values(source, reduced)
        eu_values.sort()
        p95_index = max(0, min(len(eu_values) - 1, math.ceil(0.95 * len(eu_values)) - 1))
        p95_rgb_euclidean = eu_values[p95_index]

        reduced_mean = rgb_stats(reduced)
        out_grad = gradient_energy(reduced)
        gradient_ratio = out_grad / source_grad if source_grad > 1e-9 else float("nan")

        record = {
            "Model": model,
            "RelativePath": rel,
            "Category": category,
            "OriginalWidth": source.size[0],
            "OriginalHeight": source.size[1],
            "SourceMeanR": source_mean[0],
            "SourceMeanG": source_mean[1],
            "SourceMeanB": source_mean[2],
            "OutputMeanR_Reduced": reduced_mean[0],
            "OutputMeanG_Reduced": reduced_mean[1],
            "OutputMeanB_Reduced": reduced_mean[2],
            "SignedDeltaR": stats["SignedDeltaR"],
            "SignedDeltaG": stats["SignedDeltaG"],
            "SignedDeltaB": stats["SignedDeltaB"],
            "MeanAbsRGB": stats["MeanAbsRGB"],
            "MeanRGBEuclidean": stats["MeanRGBEuclidean"],
            "P95RGBEuclidean": p95_rgb_euclidean,
            "MeanAbsLuma": stats["MeanAbsLuma"],
            "SignedLuma": stats["SignedLuma"],
            "MeanChromaDelta": stats["MeanChromaDelta"],
            "StrongColorShiftPct_gt12": stats["StrongColorShiftPct_gt12"],
            "SourceGradientEnergy": source_grad,
            "ReducedOutputGradientEnergy": out_grad,
            "GradientEnergyRatio": gradient_ratio,
            "HighFrequencyRMS_vs_Bicubic": hf_rms(output, source),
        }

        rows.append(record)
        summary_values[model].append(record)


fields = list(rows[0].keys())
metrics_path = ROOT / "greek_model_comparison_metrics.csv"
with metrics_path.open("w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)


numeric_fields = [
    "MeanAbsRGB",
    "MeanRGBEuclidean",
    "P95RGBEuclidean",
    "MeanAbsLuma",
    "SignedLuma",
    "MeanChromaDelta",
    "StrongColorShiftPct_gt12",
    "GradientEnergyRatio",
    "HighFrequencyRMS_vs_Bicubic",
]

summary_rows = []
for model in MODELS:
    subset = summary_values[model]
    record = {"Model": model, "Textures": len(subset)}

    for field in numeric_fields:
        values = [float(r[field]) for r in subset if math.isfinite(float(r[field]))]
        record[field + "_Mean"] = statistics.mean(values)
        record[field + "_Median"] = statistics.median(values)
        record[field + "_Min"] = min(values)
        record[field + "_Max"] = max(values)

    summary_rows.append(record)

summary_path = ROOT / "greek_model_comparison_summary.csv"
with summary_path.open("w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(summary_rows[0].keys()))
    writer.writeheader()
    writer.writerows(summary_rows)


category_rows = []
categories = sorted(set(r["Category"] for r in rows))
for category in categories:
    for model in MODELS:
        subset = [r for r in rows if r["Category"] == category and r["Model"] == model]
        if not subset:
            continue

        record = {"Category": category, "Model": model, "Textures": len(subset)}
        for field in numeric_fields:
            values = [float(r[field]) for r in subset if math.isfinite(float(r[field]))]
            record[field + "_Mean"] = statistics.mean(values)
            record[field + "_Median"] = statistics.median(values)
        category_rows.append(record)

category_path = ROOT / "greek_model_comparison_category_summary.csv"
with category_path.open("w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(category_rows[0].keys()))
    writer.writeheader()
    writer.writerows(category_rows)


variation_rows = []
for item in manifest:
    rel = item["RelativePath"]
    category = item.get("Category", "")
    reduced_models = {model: reduced_cache[model][rel] for model in MODELS}
    pair_diffs = []

    for i, model_a in enumerate(MODELS):
        for model_b in MODELS[i + 1:]:
            a = reduced_models[model_a]
            b = reduced_models[model_b]
            stats = pair_pixel_metrics(a, b)
            pair_diffs.append({
                "A": model_a,
                "B": model_b,
                "MeanAbsRGB": stats["MeanAbsRGB"],
                "MeanRGBEuclidean": stats["MeanRGBEuclidean"],
            })

    largest = max(pair_diffs, key=lambda x: x["MeanAbsRGB"])
    means = {model: rgb_stats(reduced_models[model]) for model in MODELS}

    mean_colour_spread = 0.0
    for i, a in enumerate(MODELS):
        for b in MODELS[i + 1:]:
            dr = means[a][0] - means[b][0]
            dg = means[a][1] - means[b][1]
            db = means[a][2] - means[b][2]
            mean_colour_spread = max(mean_colour_spread, math.sqrt(dr * dr + dg * dg + db * db))

    variation_rows.append({
        "RelativePath": rel,
        "Category": category,
        "LargestPairMeanAbsRGB": largest["MeanAbsRGB"],
        "LargestPairMeanRGBEuclidean": largest["MeanRGBEuclidean"],
        "LargestPairA": largest["A"],
        "LargestPairB": largest["B"],
        "ModelMeanColourSpread": mean_colour_spread,
    })

variation_rows.sort(
    key=lambda r: (r["LargestPairMeanAbsRGB"], r["ModelMeanColourSpread"]),
    reverse=True,
)

variation_path = ROOT / "greek_model_cross_model_variation.csv"
with variation_path.open("w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(variation_rows[0].keys()))
    writer.writeheader()
    writer.writerows(variation_rows)


queue_path = ROOT / "greek_model_manual_review_queue.txt"
with queue_path.open("w", encoding="utf-8") as f:
    f.write("AoM:EE Greek Model Comparison — Manual Review Queue\n")
    f.write("=" * 56 + "\n\n")
    f.write("Textures are ordered by largest cross-model mean RGB disagreement.\n")
    f.write("This is a triage list, not a quality ranking.\n\n")

    for i, row in enumerate(variation_rows, 1):
        f.write(
            f"{i:02d}. {row['RelativePath']}\n"
            f"    Category: {row['Category']}\n"
            f"    Largest pair: {row['LargestPairA']} vs {row['LargestPairB']}\n"
            f"    MeanAbsRGB: {row['LargestPairMeanAbsRGB']:.4f}\n"
            f"    MeanRGBEuclidean: {row['LargestPairMeanRGBEuclidean']:.4f}\n"
            f"    Mean-colour spread: {row['ModelMeanColourSpread']:.4f}\n\n"
        )


report_path = ROOT / "greek_model_comparison_analysis.txt"
with report_path.open("w", encoding="utf-8") as f:
    f.write("AoM:EE Greek Model Comparison — Diagnostic Analysis\n")
    f.write("=" * 58 + "\n\n")
    f.write("Inputs: 24 Greek textures\n")
    f.write("Models: HAT, SwinIR-M Classical, DRCT-L, DAT\n")
    f.write("RGB comparison: model output reduced 4x to source dimensions using BOX\n")
    f.write("Alpha: excluded from RGB metrics; separately verified exact NN 4x\n\n")
    f.write("IMPORTANT INTERPRETATION\n")
    f.write("- These are diagnostics, not a quality score or model ranking.\n")
    f.write("- RGB differences measure how much a model changed the image after reduction.\n")
    f.write("- HighFrequencyRMS measures change relative to bicubic, not correctness.\n")
    f.write("- StrongColorShiftPct_gt12 is a repeatable flag for manual inspection.\n")
    f.write("- Visual inspection remains necessary for judging invented detail, texture plausibility,\n")
    f.write("  ringing, and faithfulness to the original artwork.\n\n")

    for record in summary_rows:
        model = record["Model"]
        f.write(f"{model}\n")
        f.write("-" * len(model) + "\n")
        for field in numeric_fields:
            f.write(
                f"  {field}: mean={record[field + '_Mean']:.4f}, "
                f"median={record[field + '_Median']:.4f}, "
                f"min={record[field + '_Min']:.4f}, "
                f"max={record[field + '_Max']:.4f}\n"
            )
        f.write("\n")

print("")
print("============================================")
print("AoM:EE GREEK MODEL COMPARISON ANALYSIS")
print("============================================")
print("")
print(f"Textures: {len(manifest)}")
print(f"Models:   {len(MODELS)}")
print("")
print("Generated:")
print(f"  {metrics_path}")
print(f"  {summary_path}")
print(f"  {category_path}")
print(f"  {variation_path}")
print(f"  {queue_path}")
print(f"  {report_path}")
print("")
print("No composite score or ranking was produced.")
'@

$python = $python.Replace('__ROOT__', $Root)
$temp = Join-Path $env:TEMP 'aom_analyze_greek_model_comparison.py'
$python | Set-Content -LiteralPath $temp -Encoding UTF8

py $temp
$code = $LASTEXITCODE

Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue

if ($code -ne 0) {
    throw "Greek model comparison analysis failed with exit code $code."
}
