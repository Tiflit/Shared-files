from __future__ import annotations

import argparse
import csv
import hashlib
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(r"D:\AI_upscaling\AoMEE")
PBRIFY_ROOT = ROOT / r"processed\PBRify_V4"
DDT_ROOT = ROOT / r"processed\DDT_PBRify_V4"
MANIFEST_PATH = ROOT / r"processed\PBRify_V4_compile_manifest.csv"
EXTRACTED_ROOT = ROOT / r"extracted"
EXTRACTOR = ROOT / r"tools\TextureExtractor.exe"

OUT_ROOT = ROOT / r"reports\ddt_full_verification_v2"
FINAL_REPORT = OUT_ROOT / "ddt_full_verification_v2.csv"
PARTIAL_REPORT = OUT_ROOT / "ddt_full_verification_v2.partial.csv"
CHECKPOINT = OUT_ROOT / "ddt_full_verification_v2_checkpoint.txt"
SUMMARY = OUT_ROOT / "ddt_full_verification_v2_summary.txt"
SCRATCH_ROOT = ROOT / r"tests\ddt_full_verification_v2_stage"

EXPECTED_TGAS = 7487
EXPECTED_DDTS = 7486
EXCLUDED_TGA = r"textures\icons\special c black tortoise icon.tga"

FIELDS = [
    "RelativePath", "DDTRelativePath", "ManifestStatus",
    "OriginalBTIFormat", "CompileFormat", "FallbackUsed", "Provisional",
    "ExpectedTgaSHA256", "ActualTgaSHA256",
    "ExpectedDDTSHA256", "ActualDDTSHA256",
    "ExpectedDDTBytes", "ActualDDTBytes",
    "TgaExists", "DDTExists", "DDTMagic", "DDTWidth", "DDTHeight",
    "DDTHeaderSize", "ExpectedWidth", "ExpectedHeight",
    "ExtractorExitCode", "ExtractorExitHex", "ExtractorTimedOut",
    "ExtractedTgaExists", "ExtractedBTIExists",
    "ExtractedTgaWidth", "ExtractedTgaHeight", "ExtractedTgaBPP",
    "ExtractedTgaDescriptor", "ExtractedBTIFormat", "ExtractedBTIAlpha",
    "ExtractedBTINoAlphaTest", "ExtractedBTINoMip", "ExtractedBTIClamp",
    "AuthoritativeBTIFormat", "AuthoritativeBTIAlpha",
    "AuthoritativeBTINoAlphaTest", "AuthoritativeBTINoMip", "AuthoritativeBTIClamp",
    "SourceTGAShaPASS", "DDTHashPASS", "DDTSizePASS", "MagicPASS",
    "DDTDimensionsPASS", "ExtractDimensionsPASS", "ExtractFormatPASS",
    "ExtractMetadataPASS", "OVERALLPASS", "FailureStage", "FailureReason",
    "ExtractorOutput", "ElapsedSeconds",
]


def norm(p: str) -> str:
    return p.replace("/", "\\").strip().lstrip("\\")


def key(p: str) -> str:
    return norm(p).lower()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().lower()


def read_csv(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def read_tga_header(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 18:
        raise ValueError("TGA shorter than 18 bytes")
    return {
        "width": int.from_bytes(data[12:14], "little"),
        "height": int.from_bytes(data[14:16], "little"),
        "bpp": data[16],
        "descriptor": data[17],
    }


def read_ddt_header(path: Path) -> dict:
    with path.open("rb") as f:
        data = f.read(64)
    if len(data) < 20:
        raise ValueError("DDT shorter than 20 bytes")
    return {
        "magic": data[:4],
        "width": int.from_bytes(data[8:12], "little"),
        "height": int.from_bytes(data[12:16], "little"),
        "header_size": int.from_bytes(data[16:20], "little"),
    }


def parse_bti(path: Path) -> dict:
    raw = path.read_bytes()
    text = raw.decode("utf-8-sig", errors="replace")

    def mv(pattern: str) -> str:
        import re
        m = re.search(pattern, text, re.IGNORECASE)
        return m.group(1) if m else ""

    import re
    return {
        "format": mv(r"\bfmt\s*=\s*([A-Za-z0-9_]+)").upper(),
        "alpha": mv(r"\balpha\s*=\s*(\d+)"),
        "noalphatest": bool(re.search(r"(^|\s)noalphatest(\s|$)", text, re.I)),
        "nomip": bool(re.search(r"(^|\s)nomip(\s|$)", text, re.I)),
        "clamp": bool(re.search(r"(^|\s)clamp(\s|$)", text, re.I)),
    }


def bti_index() -> dict[str, Path]:
    idx: dict[str, Path] = {}
    for p in EXTRACTED_ROOT.rglob("*.bti"):
        rel = norm(str(p.relative_to(EXTRACTED_ROOT)))
        if rel.lower().startswith("patched_to_verify\\"):
            rel = rel[len("patched_to_verify\\"):]
        k = key(rel)
        if k in idx:
            raise RuntimeError(f"Duplicate logical BTI: {rel}")
        idx[k] = p
    return idx


def tga_index() -> dict[str, Path]:
    idx: dict[str, Path] = {}
    for p in PBRIFY_ROOT.rglob("*.tga"):
        rel = norm(str(p.relative_to(PBRIFY_ROOT)))
        k = key(rel)
        if k in idx:
            raise RuntimeError(f"Duplicate PBRify TGA: {rel}")
        idx[k] = p
    return idx


def ddt_index() -> dict[str, Path]:
    idx: dict[str, Path] = {}
    for p in DDT_ROOT.rglob("*.ddt"):
        rel = norm(str(p.relative_to(DDT_ROOT)))
        k = key(rel)
        if k in idx:
            raise RuntimeError(f"Duplicate DDT output: {rel}")
        idx[k] = p
    return idx


def manifest_index() -> dict[str, dict]:
    rows = read_csv(MANIFEST_PATH)
    if len(rows) != EXPECTED_TGAS:
        raise RuntimeError(f"Expected {EXPECTED_TGAS} compile manifest rows, found {len(rows)}")
    idx: dict[str, dict] = {}
    for row in rows:
        rel = norm(row.get("RelativePath", ""))
        if not rel:
            raise RuntimeError("Blank RelativePath in compile manifest")
        k = key(rel)
        if k in idx:
            raise RuntimeError(f"Duplicate compile-manifest path: {rel}")
        idx[k] = row
    return idx


def exit_hex(code: int | None) -> str:
    return "" if code is None else f"0x{code & 0xFFFFFFFF:08X}"


def extractor(ddt: Path, out_tga: Path, timeout: int) -> tuple[int | None, bool, str]:
    try:
        cp = subprocess.run(
            [str(EXTRACTOR), "-i", str(ddt), "-o", str(out_tga)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        return cp.returncode, False, cp.stdout or ""
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout
        if isinstance(out, bytes):
            out = out.decode("utf-8", errors="replace")
        return None, True, str(out or "")


def cleanup_scratch() -> None:
    shutil.rmtree(SCRATCH_ROOT, ignore_errors=True)
    SCRATCH_ROOT.mkdir(parents=True, exist_ok=True)


def write_partial_header() -> None:
    if not PARTIAL_REPORT.exists():
        with PARTIAL_REPORT.open("w", encoding="utf-8-sig", newline="") as f:
            csv.DictWriter(f, fieldnames=FIELDS).writeheader()


def append_partial(row: dict) -> None:
    with PARTIAL_REPORT.open("a", encoding="utf-8-sig", newline="") as f:
        csv.DictWriter(f, fieldnames=FIELDS).writerow({k: row.get(k, "") for k in FIELDS})


def load_completed_passes() -> set[str]:
    if not PARTIAL_REPORT.exists():
        return set()
    passes = set()
    try:
        for row in read_csv(PARTIAL_REPORT):
            if str(row.get("OVERALLPASS", "")).lower() == "true":
                passes.add(key(row.get("RelativePath", "")))
    except Exception:
        return set()
    return passes


def verify_one(index: int, rel: str, tga: Path, ddt: Path, manifest: dict, btis: dict[str, Path], timeout: int) -> dict:
    start = time.perf_counter()
    row = {f: "" for f in FIELDS}
    row.update({
        "RelativePath": rel,
        "DDTRelativePath": norm(str(Path(rel).with_suffix(".ddt"))),
        "ManifestStatus": manifest.get("Status", ""),
        "OriginalBTIFormat": manifest.get("OriginalBTIFormat", "").upper(),
        "CompileFormat": manifest.get("CompileFormat", "").upper(),
        "FallbackUsed": manifest.get("FallbackUsed", ""),
        "Provisional": manifest.get("Provisional", ""),
        "ExpectedTgaSHA256": manifest.get("SourceTgaSHA256", "").lower(),
        "ExpectedDDTSHA256": manifest.get("DDTSHA256", "").lower(),
        "ExpectedDDTBytes": manifest.get("DDTBytes", ""),
        "TgaExists": str(tga.is_file()),
        "DDTExists": str(ddt.is_file()),
    })

    try:
        if not tga.is_file():
            raise VerificationError("INPUT", "PBRify TGA missing")
        if not ddt.is_file():
            raise VerificationError("INPUT", "Production DDT missing")

        tga_h = read_tga_header(tga)
        row["ExpectedWidth"] = tga_h["width"]
        row["ExpectedHeight"] = tga_h["height"]

        actual_tga_sha = sha256_file(tga)
        row["ActualTgaSHA256"] = actual_tga_sha
        row["SourceTGAShaPASS"] = str(actual_tga_sha == row["ExpectedTgaSHA256"] and actual_tga_sha != "")
        if row["SourceTGAShaPASS"] != "True":
            raise VerificationError("SOURCE_TGA_HASH", "PBRify TGA SHA-256 does not match compile manifest")

        actual_ddt_size = ddt.stat().st_size
        actual_ddt_sha = sha256_file(ddt)
        row["ActualDDTBytes"] = actual_ddt_size
        row["ActualDDTSHA256"] = actual_ddt_sha
        row["DDTSizePASS"] = str(actual_ddt_size > 24 and actual_ddt_size == int(float(row["ExpectedDDTBytes"] or 0)))
        row["DDTHashPASS"] = str(actual_ddt_sha == row["ExpectedDDTSHA256"] and actual_ddt_sha != "")

        hdr = read_ddt_header(ddt)
        row["DDTMagic"] = hdr["magic"].decode("ascii", errors="replace")
        row["DDTWidth"] = hdr["width"]
        row["DDTHeight"] = hdr["height"]
        row["DDTHeaderSize"] = hdr["header_size"]
        row["MagicPASS"] = str(hdr["magic"] == b"RTS3")
        row["DDTDimensionsPASS"] = str(
            hdr["magic"] == b"RTS3"
            and hdr["width"] == tga_h["width"]
            and hdr["height"] == tga_h["height"]
            and 20 <= hdr["header_size"] < actual_ddt_size
        )

        rel_bti = norm(str(Path(rel).with_suffix(".bti")))
        auth_path = btis.get(key(rel_bti))
        if auth_path is None:
            raise VerificationError("BTI_INPUT", f"Authoritative BTI missing: {rel_bti}")
        auth = parse_bti(auth_path)
        row["AuthoritativeBTIFormat"] = auth["format"]
        row["AuthoritativeBTIAlpha"] = auth["alpha"]
        row["AuthoritativeBTINoAlphaTest"] = str(auth["noalphatest"])
        row["AuthoritativeBTINoMip"] = str(auth["nomip"])
        row["AuthoritativeBTIClamp"] = str(auth["clamp"])

        out_tga = SCRATCH_ROOT / f"{index:05d}.tga"
        out_bti = SCRATCH_ROOT / f"{index:05d}.bti"
        out_tga.parent.mkdir(parents=True, exist_ok=True)
        for p in (out_tga, out_bti):
            if p.exists():
                p.unlink()

        code, timed_out, output = extractor(ddt, out_tga, timeout)
        row["ExtractorExitCode"] = "" if code is None else str(code)
        row["ExtractorExitHex"] = exit_hex(code)
        row["ExtractorTimedOut"] = str(timed_out)
        row["ExtractorOutput"] = output[-4000:]
        row["ExtractedTgaExists"] = str(out_tga.is_file())
        row["ExtractedBTIExists"] = str(out_bti.is_file())

        if timed_out:
            raise VerificationError("EXTRACTOR", f"TextureExtractor exceeded {timeout}s")
        if code != 0:
            raise VerificationError("EXTRACTOR", f"TextureExtractor exit code {code} ({exit_hex(code)})")
        if not out_tga.is_file() or not out_bti.is_file():
            raise VerificationError("EXTRACTOR_OUTPUT", "TextureExtractor did not produce both TGA and BTI")

        ext_tga = read_tga_header(out_tga)
        row["ExtractedTgaWidth"] = ext_tga["width"]
        row["ExtractedTgaHeight"] = ext_tga["height"]
        row["ExtractedTgaBPP"] = ext_tga["bpp"]
        row["ExtractedTgaDescriptor"] = ext_tga["descriptor"]
        row["ExtractDimensionsPASS"] = str(
            ext_tga["width"] == tga_h["width"]
            and ext_tga["height"] == tga_h["height"]
            and ext_tga["bpp"] == 32
        )
        if row["ExtractDimensionsPASS"] != "True":
            raise VerificationError("EXTRACTED_TGA", "Decoded TGA dimensions/BPP mismatch")

        ext_bti = parse_bti(out_bti)
        row["ExtractedBTIFormat"] = ext_bti["format"]
        row["ExtractedBTIAlpha"] = ext_bti["alpha"]
        row["ExtractedBTINoAlphaTest"] = str(ext_bti["noalphatest"])
        row["ExtractedBTINoMip"] = str(ext_bti["nomip"])
        row["ExtractedBTIClamp"] = str(ext_bti["clamp"])

        expected_fmt = row["CompileFormat"]
        row["ExtractFormatPASS"] = str(expected_fmt != "" and ext_bti["format"] == expected_fmt)

        # Metadata is verified against the authoritative BTI where the extractor emitted a value.
        meta_ok = True
        if auth["format"] and expected_fmt:
            if expected_fmt != auth["format"]:
                if not (rel.lower() == key(EXCLUDED_TGA) and expected_fmt == "BC2" and auth["format"] == "BC1"):
                    meta_ok = False
        if auth["alpha"] and ext_bti["alpha"] and auth["alpha"] != ext_bti["alpha"]:
            meta_ok = False
        if auth["noalphatest"] != ext_bti["noalphatest"]:
            meta_ok = False
        if auth["nomip"] != ext_bti["nomip"]:
            meta_ok = False
        if auth["clamp"] != ext_bti["clamp"]:
            meta_ok = False
        row["ExtractMetadataPASS"] = str(meta_ok)
        if row["ExtractFormatPASS"] != "True":
            raise VerificationError("EXTRACTED_BTI_FORMAT", f"Expected compiled format {expected_fmt}, extracted {ext_bti['format']}")
        if not meta_ok:
            raise VerificationError("EXTRACTED_BTI_METADATA", "Extracted BTI metadata differs from authoritative metadata")

        overall = all(row[x] == "True" for x in [
            "SourceTGAShaPASS", "DDTHashPASS", "DDTSizePASS", "MagicPASS",
            "DDTDimensionsPASS", "ExtractDimensionsPASS", "ExtractFormatPASS",
            "ExtractMetadataPASS",
        ])
        row["OVERALLPASS"] = str(overall)
        if not overall:
            raise VerificationError("VALIDATION", "One or more verification gates failed")

    except VerificationError as exc:
        row["FailureStage"] = exc.stage
        row["FailureReason"] = exc.reason
        row["OVERALLPASS"] = "False"
    except Exception as exc:
        row["FailureStage"] = "EXCEPTION"
        row["FailureReason"] = f"{type(exc).__name__}: {exc}"
        row["OVERALLPASS"] = "False"
    finally:
        for p in SCRATCH_ROOT.glob(f"{index:05d}.*"):
            try:
                p.unlink()
            except Exception:
                pass
        row["ElapsedSeconds"] = f"{time.perf_counter() - start:.3f}"

    return row


class VerificationError(Exception):
    def __init__(self, stage: str, reason: str):
        super().__init__(reason)
        self.stage = stage
        self.reason = reason


def consolidate_partial() -> dict[str, dict]:
    rows: dict[str, dict] = {}
    if PARTIAL_REPORT.exists():
        for row in read_csv(PARTIAL_REPORT):
            rel = key(row.get("RelativePath", ""))
            if rel:
                rows[rel] = row
    return rows


def write_final(rows: dict[str, dict]) -> None:
    ordered = [rows[k] for k in sorted(rows)]
    with FINAL_REPORT.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for row in ordered:
            w.writerow({k: row.get(k, "") for k in FIELDS})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--timeout", type=int, default=300)
    args = ap.parse_args()

    for p in [PBRIFY_ROOT, DDT_ROOT, MANIFEST_PATH, EXTRACTED_ROOT, EXTRACTOR]:
        if not p.exists():
            print(f"Required path not found: {p}")
            return 2
    if args.timeout <= 0:
        print("--timeout must be > 0")
        return 2

    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    cleanup_scratch()

    mi = manifest_index()
    ti = tga_index()
    di = ddt_index()
    bi = bti_index()

    print("============================================")
    print("AoM:EE FULL DDT VERIFICATION V2")
    print("============================================")
    print(f"PBRify TGAs       : {len(ti)}")
    print(f"Compile manifest  : {len(mi)}")
    print(f"Production DDTs   : {len(di)}")
    print(f"Authoritative BTIs: {len(bi)}")
    print()

    expected_tga_keys = set(ti)
    excluded_key = key(EXCLUDED_TGA)
    expected_ddt_keys = {
        key(norm(str(Path(rel).with_suffix(".ddt"))))
        for rel in expected_tga_keys
        if rel != excluded_key
    }
    if len(ti) != EXPECTED_TGAS or len(expected_ddt_keys) != EXPECTED_DDTS:
        print("INVENTORY BASELINE: FAIL")
        return 2

    missing = sorted(expected_ddt_keys - set(di))
    unexpected = sorted(set(di) - expected_ddt_keys)
    if missing or unexpected:
        print(f"Missing DDTs   : {len(missing)}")
        print(f"Unexpected DDTs: {len(unexpected)}")
        return 2
    print("Inventory/path gate: PASS")

    partial = PARTIAL_REPORT.exists()
    if not partial:
        write_partial_header()
    completed_passes = load_completed_passes() if args.resume else set()

    total = 0
    passed_now = 0
    failed_now = 0
    skipped = 0
    started = time.perf_counter()

    try:
        for i, tga_key in enumerate(sorted(ti), start=1):
            if tga_key == excluded_key:
                continue

            rel = norm(str(ti[tga_key].relative_to(PBRIFY_ROOT)))
            ddt_rel = norm(str(Path(rel).with_suffix(".ddt")))
            manifest = mi[tga_key]

            if args.resume and tga_key in completed_passes:
                skipped += 1
                total += 1
                if skipped == 1 or skipped % 250 == 0:
                    print(f"[{total}/{EXPECTED_DDTS}] RESUME SKIP: {rel}")
                continue

            print(f"[{total + 1}/{EXPECTED_DDTS}] VERIFY: {rel}")
            row = verify_one(i, rel, ti[tga_key], di[key(ddt_rel)], manifest, bi, args.timeout)
            append_partial(row)
            total += 1

            if row["OVERALLPASS"] == "True":
                passed_now += 1
            else:
                failed_now += 1
                print(f"    >>> FAIL: {row['FailureStage']} — {row['FailureReason']}")

            if total % 100 == 0:
                print(f"    Progress: {total}/{EXPECTED_DDTS} | PASS now {passed_now} | FAIL now {failed_now} | skipped {skipped}")
    finally:
        cleanup_scratch()

    rows = consolidate_partial()
    write_final(rows)
    CHECKPOINT.write_text(
        f"last_run_completed={time.strftime('%Y-%m-%dT%H:%M:%S')}\n"
        f"rows_in_final={len(rows)}\n",
        encoding="utf-8",
    )

    final_pass = len(rows) == EXPECTED_DDTS and all(
        str(r.get("OVERALLPASS", "")).lower() == "true"
        for r in rows.values()
    )

    failed_rows = [r for r in rows.values() if str(r.get("OVERALLPASS", "")).lower() != "true"]
    elapsed = time.perf_counter() - started

    summary = [
        "AoM:EE FULL DDT VERIFICATION V2",
        "================================",
        "",
        f"Expected production DDTs: {EXPECTED_DDTS}",
        f"Final report rows:        {len(rows)}",
        f"Verified this run:        {passed_now + failed_now}",
        f"Skipped prior PASS:       {skipped}",
        f"PASS in final report:     {EXPECTED_DDTS - len(failed_rows) if len(rows) == EXPECTED_DDTS else 'n/a'}",
        f"FAIL in final report:     {len(failed_rows)}",
        f"Elapsed seconds:          {elapsed:.3f}",
        "",
        "INDEPENDENT GATES",
        "-----------------",
        "Production path completeness",
        "Compile-manifest coverage",
        "PBRify TGA SHA-256",
        "Generated DDT SHA-256",
        "Generated DDT byte size",
        "RTS3 DDT signature",
        "DDT embedded dimensions",
        "DDT dimensions vs PBRify TGA",
        "Official AoM TextureExtractor decode",
        "Decoded TGA dimensions and 32-bit format",
        "Regenerated BTI existence",
        "Regenerated BTI compile format",
        "Regenerated BTI metadata vs authoritative BTI",
        "",
        "A DDT is PASS only when every gate above passes.",
        "",
        "FULL DDT VERIFICATION: PASS" if final_pass else "FULL DDT VERIFICATION: FAIL",
    ]
    SUMMARY.write_text("\n".join(summary) + "\n", encoding="utf-8")

    print()
    print("============================================")
    print("FULL DDT VERIFICATION RESULT")
    print("============================================")
    print(f"Expected DDTs : {EXPECTED_DDTS}")
    print(f"Final rows    : {len(rows)}")
    print(f"PASS          : {EXPECTED_DDTS - len(failed_rows) if len(rows) == EXPECTED_DDTS else 0}")
    print(f"FAIL          : {len(failed_rows)}")
    print(f"Report        : {FINAL_REPORT}")
    print(f"Summary       : {SUMMARY}")
    print()
    print("FULL DDT VERIFICATION: PASS" if final_pass else "FULL DDT VERIFICATION: FAIL")
    return 0 if final_pass else 1


if __name__ == "__main__":
    sys.exit(main())
