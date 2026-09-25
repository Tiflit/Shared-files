from __future__ import annotations

import csv
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(r"D:\AI_upscaling\AoMEE")
COMPILER = ROOT / r"tools\TextureCompiler.exe"
PBRIFY = ROOT / r"processed\PBRify_V4"
EXTRACTED = ROOT / r"extracted"
OUT = ROOT / r"tests\compiler_format_validation"

SAMPLES = {
    "BC1": r"textures\animal elephant indian.tga",
    "BC2": r"textures\animal dog a map.tga",
    "BC3": r"textures\_missingtexture.tga",
    "DeflatedRGBA8": r"dlc-frontend\textures\ui\screen shot a_01.tga",
    "DeflatedRGB8": r"textures\icons\building storage pit icon.tga",
}

EXPECTED = {"BC1": 4, "BC2": 8, "BC3": 9, "DeflatedRGBA8": 10, "DeflatedRGB8": 11}

def bti_info(path: Path) -> tuple[str, int]:
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    fmt = re.search(r"\bfmt\s*=\s*([A-Za-z0-9_]+)", text, re.I)
    alpha = re.search(r"\balpha\s*=\s*(\d+)", text, re.I)
    if not fmt or not alpha:
        raise ValueError(f"Invalid BTI metadata: {path}")
    return fmt.group(1), int(alpha.group(1))

def tga_header(path: Path) -> dict[str, int]:
    data = path.read_bytes()
    if len(data) < 18:
        raise ValueError(f"TGA too short: {path}")
    return {"type": data[2], "bits": data[16], "width": int.from_bytes(data[12:14], "little"), "height": int.from_bytes(data[14:16], "little"), "id": data[0]}

def stage_bti(source: Path, dest: Path, fmt: str) -> None:
    text = source.read_text(encoding="utf-8-sig", errors="replace")
    text = re.sub(r"(\bfmt\s*=\s*)[A-Za-z0-9_]+", lambda m: m.group(1) + fmt, text, flags=re.I)
    dest.write_text(text, encoding="utf-8")

def convert_32_to_24(source: Path, dest: Path) -> None:
    data = source.read_bytes()
    h = tga_header(source)
    if data[1] != 0 or data[2] != 2 or h["bits"] != 32:
        raise ValueError(f"Expected uncompressed 32-bit TGA: {source}")
    start = 18 + h["id"]
    count = h["width"] * h["height"]
    need = start + count * 4
    if need > len(data):
        raise ValueError(f"TGA payload truncated: {source}")
    out = bytearray(start + count * 3)
    out[:start] = data[:start]
    out[16] = 24
    out[17] = data[17] & 0xF0
    s = d = start
    for _ in range(count):
        out[d:d + 3] = data[s:s + 3]
        s += 4
        d += 3
    dest.write_bytes(out)
    check = tga_header(dest)
    if check["bits"] != 24 or check["width"] != h["width"] or check["height"] != h["height"]:
        raise ValueError(f"24-bit TGA validation failed: {dest}")

def ddt_header(path: Path) -> dict[str, int | str]:
    data = path.read_bytes()
    if len(data) < 16:
        raise ValueError(f"DDT too short: {path}")
    return {"magic": data[:4].decode("ascii", "replace"), "properties": data[4], "alpha": data[5], "format": data[6], "mips": data[7], "width": int.from_bytes(data[8:12], "little"), "height": int.from_bytes(data[12:16], "little"), "bytes": path.stat().st_size}

def compile_case(label: str, source: Path, bti: Path, fmt: str, alpha: int) -> dict:
    case = OUT / label
    case.mkdir(parents=True)
    input_tga = case / "input.tga"
    input_bti = case / "input.bti"
    compile_tga = input_tga
    shutil.copy2(source, input_tga)
    stage_bti(bti, input_bti, fmt)
    input_bits = tga_header(input_tga)["bits"]
    if fmt == "DeflatedRGB8":
        compile_tga = case / "input_rgb24.tga"
        compile_bti = case / "input_rgb24.bti"
        convert_32_to_24(input_tga, compile_tga)
        stage_bti(bti, compile_bti, fmt)
        input_bits = 24
    ddt = case / "output.ddt"
    cp = subprocess.run([str(COMPILER), "-c", fmt, "-i", str(compile_tga), "-o", str(ddt)], cwd=str(case), capture_output=True, text=True, encoding="utf-8", errors="replace")
    header = ddt_header(ddt) if ddt.exists() and ddt.stat().st_size >= 16 else {}
    ok = cp.returncode == 0 and header.get("magic") == "RTS3" and header.get("format") == EXPECTED[fmt] and header.get("alpha") == alpha
    return {"format": fmt, "input_bits": input_bits, "exit": cp.returncode, "header_format": header.get("format", ""), "alpha": header.get("alpha", ""), "width": header.get("width", ""), "height": header.get("height", ""), "mips": header.get("mips", ""), "bytes": header.get("bytes", ""), "pass": ok}

def main() -> int:
    for path in (COMPILER, PBRIFY, EXTRACTED):
        if not path.exists():
            raise SystemExit(f"Required path missing: {path}")
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    results = []
    for fmt, rel in SAMPLES.items():
        source = PBRIFY / rel
        bti = EXTRACTED / Path(rel).with_suffix(".bti")
        if not bti.exists():
            bti = EXTRACTED / "patched_to_verify" / Path(rel).with_suffix(".bti")
        if not source.exists() or not bti.exists():
            raise SystemExit(f"Missing sample pair for {fmt}: {rel}")
        original, alpha = bti_info(bti)
        if original.lower() != fmt.lower():
            raise SystemExit(f"Sample metadata mismatch: {fmt} vs {original}")
        r = compile_case(fmt, source, bti, fmt, alpha)
        results.append(r)
        status = "PASS" if r["pass"] else "FAIL"
        print(f"{fmt:18} {status} input={r['input_bits']}-bit DDT={r['header_format']} bytes={r['bytes']}")
    report = OUT / "compiler_format_validation.csv"
    with report.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)
    failed = [r for r in results if not r["pass"]]
    print(f"\nReport: {report}\nPASS: {len(results) - len(failed)}/{len(results)}")
    return 1 if failed else 0

if __name__ == "__main__":
    raise SystemExit(main())
