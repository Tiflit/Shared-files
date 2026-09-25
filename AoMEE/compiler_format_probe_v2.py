from __future__ import annotations

import csv
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(r"D:\AI_upscaling\AoMEE")
COMPILER = ROOT / r"tools\TextureCompiler.exe"
PBRIFY = ROOT / r"processed\PBRify_V4"
MANIFEST = ROOT / r"processed\PBRify_V4_compile_manifest.csv"
OUT_ROOT = ROOT / r"tests\compiler_format_probe_v2"

FORMATS = [
    "BC1",
    "BC2",
    "BC3",
    "DeflatedRGBA8",
    "DeflatedRGB8",
]


def norm(p: str) -> str:
    return p.replace("/", "\").strip().lstrip("\")


def read_csv(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def find_sample(rows: list[dict], fmt: str) -> str:
    for row in rows:
        if row.get("OriginalBTIFormat", "").upper() == fmt.upper():
            return norm(row["RelativePath"])
    return ""


def read_ddt_header(path: Path) -> dict:
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


def run_case(name: str, rel: str, fmt: str, alpha: int) -> dict:
    source = PBRIFY / rel
    case = OUT_ROOT / name
    case.mkdir(parents=True, exist_ok=True)
    tga = case / "test.tga"
    bti = case / "test.bti"
    ddt = case / "test.ddt"
    log = case / "compiler_output.txt"

    shutil.copy2(source, tga)
    # ASCII intentionally: no BOM.
    bti.write_text(f"alpha={alpha} fmt={fmt}", encoding="ascii")

    attempts = [
        ("bti_only", [str(COMPILER), "-i", str(tga), "-o", str(ddt)]),
        ("explicit_c", [str(COMPILER), "-c", fmt, "-i", str(tga), "-o", str(ddt)]),
    ]

    outputs = []
    for mode, cmd in attempts:
        try:
            ddt.unlink()
        except FileNotFoundError:
            pass

        cp = subprocess.run(
            cmd,
            cwd=str(case),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

        output = (cp.stdout or "") + ("\n" + cp.stderr if cp.stderr else "")
        outputs.append(f"=== {mode} ===\n{output}")

        hdr = read_ddt_header(ddt) if ddt.exists() else {}
        outputs[-1] += (
            f"DDT_BYTES={ddt.stat().st_size if ddt.exists() else 0}\n"
            f"DDT_HEADER={hdr}\n"
        )

        # Save the explicit result for the CSV.
        if mode == "explicit_c":
            result = {
                "sample": rel,
                "format_requested": fmt,
                "alpha_requested": alpha,
                "bti_only_exit": "",
                "bti_only_header_format": "",
                "bti_only_bytes": "",
                "explicit_exit": cp.returncode,
                "explicit_header_format": hdr.get("format", ""),
                "explicit_header_alpha": hdr.get("alpha", ""),
                "explicit_header_mips": hdr.get("mips", ""),
                "explicit_width": hdr.get("width", ""),
                "explicit_height": hdr.get("height", ""),
                "explicit_bytes": ddt.stat().st_size if ddt.exists() else 0,
            }

    # Re-run BTI-only to capture its result separately.
    try:
        ddt.unlink()
    except FileNotFoundError:
        pass
    cp0 = subprocess.run(
        [str(COMPILER), "-i", str(tga), "-o", str(ddt)],
        cwd=str(case),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    h0 = read_ddt_header(ddt) if ddt.exists() else {}
    result["bti_only_exit"] = cp0.returncode
    result["bti_only_header_format"] = h0.get("format", "")
    result["bti_only_bytes"] = ddt.stat().st_size if ddt.exists() else 0

    log.write_text("\n".join(outputs), encoding="utf-8")
    return result


def main() -> None:
    if not COMPILER.exists():
        raise SystemExit(f"Compiler not found: {COMPILER}")
    if not PBRIFY.exists():
        raise SystemExit(f"PBRify root not found: {PBRIFY}")
    if not MANIFEST.exists():
        raise SystemExit(f"Manifest not found: {MANIFEST}")

    rows = read_csv(MANIFEST)
    samples = {fmt: find_sample(rows, fmt) for fmt in FORMATS}

    if OUT_ROOT.exists():
        shutil.rmtree(OUT_ROOT)
    OUT_ROOT.mkdir(parents=True)

    print("============================================")
    print("AoM:EE TEXTURE COMPILER FORMAT PROBE V2")
    print("============================================")
    print()

    results = []

    for fmt in FORMATS:
        rel = samples[fmt]
        if not rel:
            print(f"{fmt:18}: NO SAMPLE IN PRODUCTION SET")
            continue

        # Use the alpha directive actually present in the manifest only when available;
        # otherwise use the common expected value.
        alpha = {
            "BC1": 0,
            "BC2": 4,
            "BC3": 8,
            "DeflatedRGBA8": 8,
            "DeflatedRGB8": 0,
        }[fmt]

        result = run_case(fmt, rel, fmt, alpha)
        results.append(result)

        print(f"{fmt:18} sample={rel}")
        print(
            f"  BTI-only : exit={result['bti_only_exit']:>12} "
            f"header_fmt={str(result['bti_only_header_format']):>2} "
            f"bytes={result['bti_only_bytes']}"
        )
        print(
            f"  explicit : exit={result['explicit_exit']:>12} "
            f"header_fmt={str(result['explicit_header_format']):>2} "
            f"bytes={result['explicit_bytes']}"
        )

    report = OUT_ROOT / "compiler_format_probe_v2.csv"
    if results:
        with report.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(results[0].keys()))
            w.writeheader()
            w.writerows(results)

    print()
    print(f"Report: {report}")
    print()
    print("Expected DDT format bytes:")
    print("  BC1 = 4")
    print("  BC2 = 8")
    print("  BC3 = 9")
    print("  DeflatedRGBA8 = 10")
    print("  DeflatedRGB8 = 11")


if __name__ == "__main__":
    main()
