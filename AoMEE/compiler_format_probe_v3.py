from __future__ import annotations

import csv
import shutil
import subprocess
from pathlib import Path

try:
    from PIL import Image
except ImportError as exc:
    raise SystemExit("Pillow is required. Install it with: python -m pip install pillow") from exc

ROOT = Path(r"D:\AI_upscaling\AoMEE")
COMPILER = ROOT / r"tools\TextureCompiler.exe"
PBRIFY = ROOT / r"processed\PBRify_V4"
EXTRACTED = ROOT / r"extracted"
MANIFEST = ROOT / r"processed\PBRify_V4_compile_manifest.csv"
OUT_ROOT = ROOT / r"tests\compiler_format_probe_v3"

# Real production texture known to be classified DeflatedRGB8 by the current
# production manifest. We use a discovered sample when possible.
FALLBACK_SAMPLE = r"textures\icons\building storage pit icon.tga"


def norm(p: str) -> str:
    return p.replace("/", "\\").strip().lstrip("\\").strip('"')


def read_csv(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def find_sample(rows: list[dict], fmt: str) -> str:
    for row in rows:
        if row.get("OriginalBTIFormat", "").strip().upper() == fmt.upper():
            rel = row.get("RelativePath", "").strip()
            if rel:
                return norm(rel)
    return FALLBACK_SAMPLE


def read_bti(rel: str) -> dict:
    path = EXTRACTED / Path(rel).with_suffix(".bti")
    data = path.read_text(encoding="utf-8-sig").strip().split()
    values = {}
    i = 0
    while i < len(data):
        token = data[i]
        if "=" in token:
            k, v = token.split("=", 1)
            values[k.lower()] = v
            i += 1
        elif token.lower() in {"alpha", "fmt"} and i + 1 < len(data):
            values[token.lower()] = data[i + 1]
            i += 2
        else:
            values[token.lower()] = True
            i += 1
    return values


def read_ddt_header(path: Path) -> dict:
    if not path.exists():
        return {}
    raw = path.read_bytes()
    if len(raw) < 16:
        return {}
    return {
        "magic": raw[0:4].decode("ascii", errors="replace"),
        "properties": raw[4],
        "alpha": raw[5],
        "format": raw[6],
        "mips": raw[7],
        "width": int.from_bytes(raw[8:12], "little"),
        "height": int.from_bytes(raw[12:16], "little"),
    }


def run_compiler(case: Path, source: Path, requested_format: str, label: str) -> dict:
    ddt = case / f"{label}.ddt"
    log = case / f"{label}.txt"
    try:
        ddt.unlink()
    except FileNotFoundError:
        pass

    cmd = [
        str(COMPILER),
        "-c",
        requested_format,
        "-i",
        str(source),
        "-o",
        str(ddt),
    ]
    cp = subprocess.run(
        cmd,
        cwd=str(case),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    output = (cp.stdout or "") + ("\n" + cp.stderr if cp.stderr else "")
    log.write_text(output, encoding="utf-8")
    hdr = read_ddt_header(ddt)
    return {
        "label": label,
        "requested_format": requested_format,
        "exit_code": cp.returncode,
        "header_format": hdr.get("format", ""),
        "header_alpha": hdr.get("alpha", ""),
        "mips": hdr.get("mips", ""),
        "width": hdr.get("width", ""),
        "height": hdr.get("height", ""),
        "bytes": ddt.stat().st_size if ddt.exists() else 0,
    }


def main() -> None:
    if not COMPILER.exists():
        raise SystemExit(f"Compiler not found: {COMPILER}")
    if not PBRIFY.exists():
        raise SystemExit(f"PBRify root not found: {PBRIFY}")
    if not EXTRACTED.exists():
        raise SystemExit(f"Extracted root not found: {EXTRACTED}")
    if not MANIFEST.exists():
        raise SystemExit(f"Manifest not found: {MANIFEST}")

    rows = read_csv(MANIFEST)
    rel = find_sample(rows, "DeflatedRGB8")
    source = PBRIFY / rel
    if not source.exists():
        raise SystemExit(f"Sample TGA not found: {source}")

    bti = read_bti(rel)
    print("============================================")
    print("AoM:EE TEXTURE COMPILER FORMAT PROBE V3")
    print("============================================")
    print(f"Sample: {rel}")
    print(f"Authoritative BTI: fmt={bti.get('fmt')} alpha={bti.get('alpha')}")
    print()

    if OUT_ROOT.exists():
        shutil.rmtree(OUT_ROOT)
    OUT_ROOT.mkdir(parents=True)

    case = OUT_ROOT / "rgb8"
    case.mkdir()

    rgba_source = case / "source_rgba32.tga"
    rgb_source = case / "source_rgb24.tga"
    shutil.copy2(source, rgba_source)

    # Convert only the temporary diagnostic copy to a true 24-bit TGA.
    with Image.open(source) as im:
        im.convert("RGB").save(rgb_source, format="TGA")

    # Test both the documented enum name and the GUI's short display alias.
    cases = [
        ("rgba32_DeflatedRGB8", rgba_source, "DeflatedRGB8"),
        ("rgba32_RGB8", rgba_source, "RGB8"),
        ("rgb24_DeflatedRGB8", rgb_source, "DeflatedRGB8"),
        ("rgb24_RGB8", rgb_source, "RGB8"),
    ]

    results = []
    for label, src, fmt in cases:
        result = run_compiler(case, src, fmt, label)
        results.append(result)
        print(
            f"{label:24} exit={result['exit_code']:>12} "
            f"header_fmt={str(result['header_format']):>2} "
            f"bytes={result['bytes']}"
        )

    report = OUT_ROOT / "compiler_format_probe_v3.csv"
    with report.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(results[0].keys()))
        w.writeheader()
        w.writerows(results)

    print()
    print(f"Report: {report}")
    print()
    print("Expected: DeflatedRGB8 -> DDT format byte 11")
    print("          DeflatedRGBA8 -> DDT format byte 10")


if __name__ == "__main__":
    main()
