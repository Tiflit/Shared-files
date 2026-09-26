from __future__ import annotations

import csv
import shutil
import struct
import subprocess
from pathlib import Path

ROOT = Path(r"D:\AI_upscaling\AoMEE")
COMPILER = ROOT / r"tools\TextureCompiler.exe"
SOURCE = ROOT / r"processed\PBRify_V4\dlc-frontend\textures\ui\screen shot a_01.tga"
OUT_ROOT = ROOT / r"tests\compiler_format_probe"


CASES = [
    ("BTI_BC1_A0", "BC1", 0),
    ("BTI_BC1_A1", "BC1", 1),
    ("BTI_BC2_A4", "BC2", 4),
    ("BTI_BC3_A8", "BC3", 8),
    ("BTI_DEFLATEDRGB8_A0", "DeflatedRGB8", 0),
    ("BTI_DEFLATEDRGBA8_A8", "DeflatedRGBA8", 8),
]

EXPLICIT_CASES = [
    ("EXPLICIT_BC1_A0", "BC1", 0),
    ("EXPLICIT_BC2_A4", "BC2", 4),
    ("EXPLICIT_BC3_A8", "BC3", 8),
    ("EXPLICIT_DEFLATEDRGB8_A0", "DeflatedRGB8", 0),
    ("EXPLICIT_DEFLATEDRGBA8_A8", "DeflatedRGBA8", 8),
]


def read_ddt_header(path: Path) -> dict:
    with path.open("rb") as f:
        head = f.read(16)
        if len(head) < 16:
            raise ValueError("DDT shorter than fixed 16-byte header")

        magic = head[0:4]
        props = head[4]
        alpha = head[5]
        fmt = head[6]
        mips = head[7]
        width = int.from_bytes(head[8:12], "little")
        height = int.from_bytes(head[12:16], "little")

        entries = []
        for _ in range(max(1, mips)):
            b = f.read(8)
            if len(b) < 8:
                break
            off = int.from_bytes(b[0:4], "little")
            size = int.from_bytes(b[4:8], "little")
            entries.append((off, size))

    return {
        "magic": magic.decode("ascii", errors="replace"),
        "props": props,
        "alpha": alpha,
        "format": fmt,
        "mips": mips,
        "width": width,
        "height": height,
        "entries": entries,
    }


def expected_format_byte(name: str) -> int:
    return {
        "BC1": 4,
        "BC2": 8,
        "BC3": 9,
        "DeflatedRGBA8": 10,
        "DeflatedRGB8": 11,
    }[name]


def run_case(case_name: str, fmt: str, alpha: int, explicit: bool) -> dict:
    case_dir = OUT_ROOT / case_name
    case_dir.mkdir(parents=True, exist_ok=True)

    tga = case_dir / "test.tga"
    bti = case_dir / "test.bti"
    ddt = case_dir / "test.ddt"
    log = case_dir / "compiler_output.txt"

    shutil.copy2(SOURCE, tga)
    bti.write_text(f"alpha={alpha} fmt={fmt}", encoding="ascii")

    cmd = [
        str(COMPILER),
        "-i", str(tga),
        "-o", str(ddt),
    ]
    if explicit:
        cmd = [
            str(COMPILER),
            "-c", fmt,
            "-i", str(tga),
            "-o", str(ddt),
        ]

    cp = subprocess.run(
        cmd,
        cwd=str(case_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    output = (cp.stdout or "") + ("\n" + cp.stderr if cp.stderr else "")
    log.write_text(output, encoding="utf-8")

    result = {
        "case": case_name,
        "mode": "explicit_-c" if explicit else "bti_metadata",
        "requested_format": fmt,
        "requested_alpha": alpha,
        "exit_code": cp.returncode,
        "ddt_bytes": ddt.stat().st_size if ddt.exists() else 0,
        "ddt_magic": "",
        "ddt_properties": "",
        "ddt_alpha": "",
        "ddt_format_byte": "",
        "ddt_mips": "",
        "ddt_width": "",
        "ddt_height": "",
        "first_mip_offset": "",
        "first_mip_size": "",
        "expected_format_byte": expected_format_byte(fmt),
        "format_matches_requested": False,
    }

    if ddt.exists() and ddt.stat().st_size >= 16:
        hdr = read_ddt_header(ddt)
        result.update({
            "ddt_magic": hdr["magic"],
            "ddt_properties": hdr["props"],
            "ddt_alpha": hdr["alpha"],
            "ddt_format_byte": hdr["format"],
            "ddt_mips": hdr["mips"],
            "ddt_width": hdr["width"],
            "ddt_height": hdr["height"],
            "first_mip_offset": hdr["entries"][0][0] if hdr["entries"] else "",
            "first_mip_size": hdr["entries"][0][1] if hdr["entries"] else "",
            "format_matches_requested": hdr["format"] == expected_format_byte(fmt),
        })

    return result


def main() -> None:
    if not COMPILER.exists():
        raise SystemExit(f"Compiler not found: {COMPILER}")
    if not SOURCE.exists():
        raise SystemExit(f"Production TGA not found: {SOURCE}")

    if OUT_ROOT.exists():
        shutil.rmtree(OUT_ROOT)
    OUT_ROOT.mkdir(parents=True)

    print("============================================")
    print("AoM:EE TEXTURE COMPILER FORMAT PROBE")
    print("============================================")
    print(f"Compiler : {COMPILER}")
    print(f"Source   : {SOURCE}")
    print()

    results = []

    print("BTI METADATA ONLY")
    print("--------------------------------------------")
    for case_name, fmt, alpha in CASES:
        r = run_case(case_name, fmt, alpha, explicit=False)
        results.append(r)
        print(
            f"{case_name:28} "
            f"exit={r['exit_code']:>4} "
            f"bytes={r['ddt_bytes']:>8} "
            f"header_fmt={str(r['ddt_format_byte']):>2} "
            f"mips={str(r['ddt_mips']):>2} "
            f"match={r['format_matches_requested']}"
        )

    print()
    print("EXPLICIT -c")
    print("--------------------------------------------")
    for case_name, fmt, alpha in EXPLICIT_CASES:
        r = run_case(case_name, fmt, alpha, explicit=True)
        results.append(r)
        print(
            f"{case_name:34} "
            f"exit={r['exit_code']:>4} "
            f"bytes={r['ddt_bytes']:>8} "
            f"header_fmt={str(r['ddt_format_byte']):>2} "
            f"mips={str(r['ddt_mips']):>2} "
            f"match={r['format_matches_requested']}"
        )

    report = OUT_ROOT / "compiler_format_probe.csv"
    with report.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(results[0].keys()))
        w.writeheader()
        w.writerows(results)

    print()
    print("============================================")
    print("PROBE COMPLETE")
    print("============================================")
    print(f"Report: {report}")
    print()
    print("Interpretation:")
    print("  header_fmt 4  = BC1/DXT1")
    print("  header_fmt 8  = BC2/DXT3")
    print("  header_fmt 9  = BC3/DXT5")
    print("  header_fmt 10 = DeflatedRGBA8")
    print("  header_fmt 11 = DeflatedRGB8")


if __name__ == "__main__":
    main()
