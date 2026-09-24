from __future__ import annotations

import csv
import shutil
import struct
import subprocess
import time
from pathlib import Path


ROOT = Path(r"D:\AI_upscaling\AoMEE")

COMPILER = ROOT / "tools" / "TextureCompiler.exe"

OUT_ROOT = ROOT / (
    r"tests\production_compile_diagnostic"
    r"\blue_lagoon_bc1_repeatability"
)

REPEATS = 20


def write_solid_tga(
    path: Path,
    width: int,
    height: int,
) -> None:
    header = bytearray(18)

    # Uncompressed true-color TGA.
    header[2] = 2

    # Dimensions.
    header[12:14] = struct.pack("<H", width)
    header[14:16] = struct.pack("<H", height)

    # 32-bit BGRA.
    header[16] = 32

    # 8 alpha bits, bottom-left origin.
    header[17] = 8

    # Solid opaque black.
    pixel = bytes((0, 0, 0, 255))

    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("wb") as f:
        f.write(header)

        row = pixel * width

        for _ in range(height):
            f.write(row)


def compile_once(
    width: int,
    height: int,
    fmt: str,
    attempt_dir: Path,
) -> dict:

    attempt_dir.mkdir(parents=True, exist_ok=True)

    tga = attempt_dir / "test.tga"
    bti = attempt_dir / "test.bti"
    ddt = attempt_dir / "test.ddt"
    log = attempt_dir / "compiler_output.txt"

    write_solid_tga(
        tga,
        width,
        height,
    )

    bti.write_text(
        f"alpha=0 fmt={fmt}",
        encoding="ascii",
    )

    started = time.perf_counter()

    try:
        completed = subprocess.run(
            [
                str(COMPILER),
                "-i",
                str(tga),
                "-o",
                str(ddt),
            ],
            cwd=str(attempt_dir),
            capture_output=True,
            text=True,
            errors="replace",
        )

        exit_code = completed.returncode

        output = ""

        if completed.stdout:
            output += completed.stdout

        if completed.stderr:
            output += "\n" + completed.stderr

    except Exception as exc:
        exit_code = -1
        output = (
            f"Python failed to launch compiler:\n"
            f"{type(exc).__name__}: {exc}"
        )

    elapsed = time.perf_counter() - started

    log.write_text(
        output,
        encoding="utf-8",
    )

    ddt_bytes = (
        ddt.stat().st_size
        if ddt.exists()
        else 0
    )

    success = (
        exit_code == 0
        and ddt_bytes > 0
    )

    return {
        "width": width,
        "height": height,
        "fmt": fmt,
        "exit_code": exit_code,
        "ddt_bytes": ddt_bytes,
        "success": success,
        "elapsed_seconds": round(elapsed, 3),
    }


def run_series(
    label: str,
    width: int,
    height: int,
    fmt: str,
) -> list[dict]:

    series_root = OUT_ROOT / label

    results = []

    successes = 0
    failures = 0

    print()
    print(
        f"=== {label}: "
        f"{width}x{height}, {fmt}, "
        f"{REPEATS} fresh processes ==="
    )

    for run in range(1, REPEATS + 1):

        result = compile_once(
            width,
            height,
            fmt,
            series_root / f"run_{run:02d}",
        )

        result["series"] = label
        result["run"] = run

        results.append(result)

        if result["success"]:
            successes += 1
        else:
            failures += 1

        print(
            f"run {run:02d}: "
            f"exit={result['exit_code']:>12} "
            f"ddt={result['ddt_bytes']:>8} "
            f"time={result['elapsed_seconds']:>6.2f}s "
            f"{'PASS' if result['success'] else 'FAIL'}"
        )

    print(
        f"TOTAL: {successes} PASS / {failures} FAIL"
    )

    return results


def main() -> None:

    if not COMPILER.exists():
        raise SystemExit(
            f"Compiler not found:\n{COMPILER}"
        )

    if OUT_ROOT.exists():
        shutil.rmtree(OUT_ROOT)

    OUT_ROOT.mkdir(parents=True)

    print("============================================")
    print("BLUE LAGOON BC1 REPEATABILITY DIAGNOSTIC")
    print("============================================")
    print()
    print(f"Compiler: {COMPILER}")
    print(f"Repeats : {REPEATS} per series")

    results = []

    # Known-good BC1 control.
    results += run_series(
        "01_768x768_BC1",
        768,
        768,
        "BC1",
    )

    # This dimension has produced both PASS and FAIL in previous testing.
    results += run_series(
        "02_1024x768_BC1",
        1024,
        768,
        "BC1",
    )

    results += run_series(
        "03_768x1024_BC1",
        768,
        1024,
        "BC1",
    )

    # Known problematic square size.
    results += run_series(
        "04_832x832_BC1",
        832,
        832,
        "BC1",
    )

    # Known working format at the actual Blue Lagoon dimensions.
    results += run_series(
        "05_1024x1024_BC2",
        1024,
        1024,
        "BC2",
    )

    report = OUT_ROOT / "results.csv"

    with report.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as f:

        writer = csv.DictWriter(
            f,
            fieldnames=[
                "series",
                "run",
                "width",
                "height",
                "fmt",
                "exit_code",
                "ddt_bytes",
                "success",
                "elapsed_seconds",
            ],
        )

        writer.writeheader()
        writer.writerows(results)

    print()
    print("============================================")
    print("SUMMARY")
    print("============================================")

    seen = []

    for row in results:
        series = row["series"]

        if series not in seen:
            seen.append(series)

    for series in seen:

        rows = [
            row
            for row in results
            if row["series"] == series
        ]

        passed = sum(
            1
            for row in rows
            if row["success"]
        )

        failed = len(rows) - passed

        print(
            f"{series:25} "
            f"{passed:2} PASS / "
            f"{failed:2} FAIL"
        )

    print()
    print(f"Results: {report}")


if __name__ == "__main__":
    main()