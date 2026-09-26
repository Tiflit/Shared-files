$ErrorActionPreference = 'Stop'

$Root = 'D:\AI_upscaling\AoMEE\tests\remaster_benchmark'

$ManifestPath = Join-Path $Root 'remaster_benchmark_manifest.csv'
$SharperRoot  = Join-Path $Root 'HAT_sharper'
$SRx4Root     = Join-Path $Root 'HAT_SRx4'
$ReportPath   = Join-Path $Root 'benchmark_output_qa_v2.csv'

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

if (-not (Test-Path -LiteralPath $SharperRoot)) {
    throw "Sharper output directory not found: $SharperRoot"
}

if (-not (Test-Path -LiteralPath $SRx4Root)) {
    throw "SRx4 output directory not found: $SRx4Root"
}

# ------------------------------------------------------------
# Verify Pillow is available for reading HAT outputs.
# ------------------------------------------------------------

py -c "import PIL" 2>$null

if ($LASTEXITCODE -ne 0) {
    throw "Pillow is required but was not found."
}

$Python = @'
from pathlib import Path
import csv
import json
from PIL import Image

root = Path(r"""__ROOT__""")
manifest_path = root / "remaster_benchmark_manifest.csv"
sharp_root = root / "HAT_sharper"
sr_root = root / "HAT_SRx4"
report_path = root / "benchmark_output_qa_v2.csv"

with manifest_path.open("r", encoding="utf-8-sig", newline="") as f:
    manifest = list(csv.DictReader(f))

if len(manifest) != 115:
    raise RuntimeError(
        f"Expected 115 manifest entries, found {len(manifest)}"
    )

# ------------------------------------------------------------
# Index every output file by normalized relative path.
# ------------------------------------------------------------

def build_index(root_dir):
    index = {}

    for p in root_dir.rglob("*"):
        if not p.is_file():
            continue

        rel = str(p.relative_to(root_dir)).replace("\\", "/").lower()

        index[rel] = p

    return index

sharp_index = build_index(sharp_root)
sr_index = build_index(sr_root)

print(f"Sharper files indexed: {len(sharp_index)}")
print(f"SRx4 files indexed:    {len(sr_index)}")
print()

# ------------------------------------------------------------
# Helper to find an output.
#
# First: exact relative path ignoring extension.
# Second: unique basename fallback.
# ------------------------------------------------------------

def find_output(index, original_rel):

    original = Path(original_rel)
    stem_rel = str(original.with_suffix("")).replace("\\", "/").lower()

    exact = []

    for rel, path in index.items():

        p = Path(rel)
        candidate_stem = str(p.with_suffix("")).replace("\\", "/").lower()

        if candidate_stem == stem_rel:
            exact.append(path)

    if len(exact) == 1:
        return "ExactRelativePath", exact[0]

    if len(exact) > 1:
        return "AmbiguousRelativePath", None

    # Filename fallback
    basename = original.name.lower()
    matches = [
        path for rel, path in index.items()
        if Path(rel).name.lower() == basename
    ]

    if len(matches) == 1:
        return "FilenameUnique", matches[0]

    if len(matches) > 1:
        return "AmbiguousFilename", None

    return "Missing", None

# ------------------------------------------------------------
# Read output dimensions using Pillow.
# ------------------------------------------------------------

def read_dimensions(path):

    try:
        with Image.open(path) as img:

            return {
                "width": img.width,
                "height": img.height,
                "mode": img.mode,
                "format": img.format,
                "error": ""
            }

    except Exception as exc:

        return {
            "width": None,
            "height": None,
            "mode": "",
            "format": "",
            "error": str(exc)
        }

results = []

for m in manifest:

    original_rel = m["OriginalRelativePath"]

    input_width = int(m["Width"])
    input_height = int(m["Height"])

    expected_width = input_width * 4
    expected_height = input_height * 4

    sharp_status, sharp_path = find_output(
        sharp_index,
        original_rel
    )

    sr_status, sr_path = find_output(
        sr_index,
        original_rel
    )

    sharp_info = (
        read_dimensions(sharp_path)
        if sharp_path is not None
        else {
            "width": None,
            "height": None,
            "mode": "",
            "format": "",
            "error": ""
        }
    )

    sr_info = (
        read_dimensions(sr_path)
        if sr_path is not None
        else {
            "width": None,
            "height": None,
            "mode": "",
            "format": "",
            "error": ""
        }
    )

    sharp_correct = (
        sharp_path is not None
        and sharp_info["width"] == expected_width
        and sharp_info["height"] == expected_height
    )

    sr_correct = (
        sr_path is not None
        and sr_info["width"] == expected_width
        and sr_info["height"] == expected_height
    )

    results.append({
        "RelativePath": original_rel,
        "Category": m["Category"],
        "Selection": m["Selection"],
        "AlphaBand": m["AlphaBand"],

        "InputWidth": input_width,
        "InputHeight": input_height,

        "ExpectedWidth4x": expected_width,
        "ExpectedHeight4x": expected_height,

        "SharperStatus": sharp_status,
        "SharperPath": str(sharp_path) if sharp_path else "",
        "SharperWidth": sharp_info["width"] or "",
        "SharperHeight": sharp_info["height"] or "",
        "SharperMode": sharp_info["mode"],
        "SharperFormat": sharp_info["format"],
        "SharperCorrect4x": sharp_correct,
        "SharperReadError": sharp_info["error"],

        "SRx4Status": sr_status,
        "SRx4Path": str(sr_path) if sr_path else "",
        "SRx4Width": sr_info["width"] or "",
        "SRx4Height": sr_info["height"] or "",
        "SRx4Mode": sr_info["mode"],
        "SRx4Format": sr_info["format"],
        "SRx4Correct4x": sr_correct,
        "SRx4ReadError": sr_info["error"]
    })

fields = list(results[0].keys())

with report_path.open(
    "w",
    newline="",
    encoding="utf-8-sig"
) as f:

    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(results)

sharp_found = sum(
    1 for r in results
    if r["SharperStatus"] not in (
        "Missing",
        "AmbiguousRelativePath",
        "AmbiguousFilename"
    )
)

sr_found = sum(
    1 for r in results
    if r["SRx4Status"] not in (
        "Missing",
        "AmbiguousRelativePath",
        "AmbiguousFilename"
    )
)

sharp_correct = sum(
    1 for r in results
    if r["SharperCorrect4x"]
)

sr_correct = sum(
    1 for r in results
    if r["SRx4Correct4x"]
)

sharp_read_errors = sum(
    1 for r in results
    if r["SharperReadError"]
)

sr_read_errors = sum(
    1 for r in results
    if r["SRx4ReadError"]
)

print()
print("============================================")
print("HAT BENCHMARK OUTPUT QA v2")
print("============================================")
print()

print(f"Benchmark entries:       {len(results)}")
print(f"Sharper outputs found:  {sharp_found}")
print(f"SRx4 outputs found:     {sr_found}")
print(f"Sharper correct 4x:     {sharp_correct}")
print(f"SRx4 correct 4x:        {sr_correct}")
print(f"Sharper read errors:    {sharp_read_errors}")
print(f"SRx4 read errors:       {sr_read_errors}")
print()

problems = [
    r for r in results
    if not r["SharperCorrect4x"]
    or not r["SRx4Correct4x"]
]

if not problems:

    print("ALL 115 HAT OUTPUTS PASSED 4x DIMENSION QA.")

else:

    print(f"PROBLEMS FOUND: {len(problems)}")
    print()

    for r in problems:

        print(r["RelativePath"])
        print(
            f"  Sharper: {r['SharperStatus']} "
            f"{r['SharperWidth']}x{r['SharperHeight']} "
            f"{r['SharperFormat']} "
            f"{r['SharperReadError']}"
        )

        print(
            f"  SRx4:   {r['SRx4Status']} "
            f"{r['SRx4Width']}x{r['SRx4Height']} "
            f"{r['SRx4Format']} "
            f"{r['SRx4ReadError']}"
        )

        print()

print(f"QA report: {report_path}")
'@

$Python = $Python.Replace('__ROOT__', $Root)

$Temp = Join-Path $env:TEMP 'aom_hat_benchmark_qa_v2.py'

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
    throw "QA script failed with exit code $ExitCode."
}