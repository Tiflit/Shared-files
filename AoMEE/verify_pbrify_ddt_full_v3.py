from __future__ import annotations

import argparse
import csv
import hashlib
import re
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

OUT_ROOT = ROOT / r"reports\ddt_full_verification_v3"
FINAL_REPORT = OUT_ROOT / "ddt_full_verification_v3.csv"
PARTIAL_REPORT = OUT_ROOT / "ddt_full_verification_v3.partial.csv"
CHECKPOINT = OUT_ROOT / "ddt_full_verification_v3_checkpoint.txt"
SUMMARY = OUT_ROOT / "ddt_full_verification_v3_summary.txt"
SCRATCH_ROOT = ROOT / r"tests\ddt_full_verification_v3_stage"

EXPECTED_TGAS = 7487
EXPECTED_DDTS = 7486
EXCLUDED_TGA = r"textures\icons\special c black tortoise icon.tga"

FIELDS = [
    "RelativePath", "DDTRelativePath", "ManifestStatus",
    "OriginalBTIFormat", "CompileFormat", "FallbackUsed", "Provisional",
    "ExpectedTgaSHA256", "ActualTgaSHA256",
    "ExpectedDDTSHA256", "ActualDDTSHA256",
    "ExpectedDDTBytes", "ActualDDTBytes",
    "SourceTgaWidth", "SourceTgaHeight", "SourceTgaBPP",
    "DDTMagic", "DDTProperties", "DDTAlphaBits", "DDTFormatByte", "DDTMipLevels",
    "DDTWidth", "DDTHeight", "DDTDataTableEnd", "DDTDataEntryCount",
    "DDTDataEntriesInBounds", "DDTDataEntriesNonOverlapping",
    "DDTExpectedFormatByte", "DDTExpectedAlphaBits",
    "AuthoritativeBTIFormat", "AuthoritativeBTIAlpha",
    "AuthoritativeBTINoAlphaTest", "AuthoritativeBTINoMip",
    "AuthoritativeBTINoLowDetail", "AuthoritativeBTIDisplacement",
    "SourceTGAShaPASS", "DDTHashPASS", "DDTSizePASS", "SourceTgaStructurePASS",
    "MagicPASS", "DDTFormatPASS", "DDTAlphaPASS", "DDTDimensionsPASS",
    "DDTDataTablePASS", "DDTPropertyPASS",
    "ExtractorExitCode", "ExtractorExitHex", "ExtractorTimedOut",
    "ExtractedTgaExists", "ExtractedBTIExists",
    "ExtractedTgaWidth", "ExtractedTgaHeight", "ExtractedTgaBPP",
    "ExtractedBTIFormat", "ExtractedBTIAlpha",
    "ExtractorDecodePASS", "CorePASS", "OVERALLPASS",
    "FailureStage", "FailureReason", "ExtractorOutput", "ElapsedSeconds",
]


class VerificationError(Exception):
    def __init__(self, stage: str, reason: str):
        super().__init__(reason)
        self.stage = stage
        self.reason = reason


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
        head = f.read(16)
        if len(head) < 16:
            raise ValueError("DDT shorter than 16-byte fixed header")
        magic = head[0:4]
        props = head[4]
        alpha = head[5]
        fmt = head[6]
        mips = head[7]
        width = int.from_bytes(head[8:12], "little")
        height = int.from_bytes(head[12:16], "little")

        faces = 6 if (props & 0x08) else 1
        entry_count = faces * mips
        entries = []
        for _ in range(entry_count):
            b = f.read(8)
            if len(b) < 8:
                raise ValueError("DDT truncated inside image-entry table")
            off = int.from_bytes(b[0:4], "little")
            size = int.from_bytes(b[4:8], "little")
            entries.append((off, size))

        return {
            "magic": magic,
            "properties": props,
            "alpha": alpha,
            "format": fmt,
            "mips": mips,
            "width": width,
            "height": height,
            "faces": faces,
            "entry_count": entry_count,
            "table_end": 16 + 8 * entry_count,
            "entries": entries,
        }


def parse_bti(path: Path) -> dict:
    text = path.read_text(encoding="utf-8-sig", errors="replace")

    def value(pattern: str) -> str:
        m = re.search(pattern, text, re.IGNORECASE)
        return m.group(1) if m else ""

    def flag(token: str) -> bool:
        return bool(re.search(r"(^|\s)" + re.escape(token) + r"(\s|$)", text, re.IGNORECASE))

    return {
        "format": value(r"\bfmt\s*=\s*([A-Za-z0-9_]+)").upper(),
        "alpha": value(r"\balpha\s*=\s*(\d+)"),
        "noalphatest": flag("noalphatest"),
        "nomip": flag("nomip"),
        "nolowdetail": flag("noLowDetail"),
        "displacement": flag("displacement"),
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
    out = set()
    try:
        for row in read_csv(PARTIAL_REPORT):
            if str(row.get("OVERALLPASS", "")).lower() == "true":
                out.add(key(row.get("RelativePath", "")))
    except Exception:
        return set()
    return out


def expected_ddt_format_byte(compile_format: str, alpha_bits: int) -> int:
    fmt = compile_format.upper()
    if fmt == "BC1":
        return 5 if alpha_bits == 1 else 4
    if fmt == "BC2":
        return 8
    if fmt == "BC3":
        return 9
    if fmt == "DEFLATEDRGBA8":
        return 10
    if fmt == "DEFLATEDRGB8":
        return 11
    if fmt == "DEFLATEDR8":
        return 12
    if fmt == "DEFLATEDRG8":
        return 13
    raise ValueError(f"Unsupported CompileFormat for DDT header mapping: {compile_format}")


def expected_compressed_mip_bytes(ddt_format: int, width: int, height: int) -> int | None:
    bw = max(1, (width + 3) // 4)
    bh = max(1, (height + 3) // 4)
    if ddt_format in (4, 5):
        return bw * bh * 8
    if ddt_format in (6, 8, 9):
        return bw * bh * 16
    if ddt_format == 1:
        return width * height * 4
    if ddt_format == 2:
        return width * height * 3
    return None


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
        row["SourceTgaWidth"] = tga_h["width"]
        row["SourceTgaHeight"] = tga_h["height"]
        row["SourceTgaBPP"] = tga_h["bpp"]
        row["SourceTgaStructurePASS"] = str(tga_h["bpp"] == 32 and tga_h["width"] > 0 and tga_h["height"] > 0)
        if row["SourceTgaStructurePASS"] != "True":
            raise VerificationError("SOURCE_TGA_STRUCTURE", "PBRify TGA is not a valid 32-bit texture")

        actual_tga_sha = sha256_file(tga)
        row["ActualTgaSHA256"] = actual_tga_sha
        row["SourceTGAShaPASS"] = str(actual_tga_sha == row["ExpectedTgaSHA256"] and actual_tga_sha != "")
        if row["SourceTGAShaPASS"] != "True":
            raise VerificationError("SOURCE_TGA_HASH", "PBRify TGA SHA-256 does not match compile manifest")

        actual_ddt_size = ddt.stat().st_size
        actual_ddt_sha = sha256_file(ddt)
        row["ActualDDTBytes"] = actual_ddt_size
        row["DDTSizePASS"] = str(actual_ddt_size > 16 and actual_ddt_size == int(float(row["ExpectedDDTBytes"] or 0)))
        row["DDTHashPASS"] = str(actual_ddt_sha == row["ExpectedDDTSHA256"] and actual_ddt_sha != "")
        row["ExpectedDDTBytes"] = row["ExpectedDDTBytes"]
        row["ActualDDTSHA256"] = actual_ddt_sha
        if row["DDTSizePASS"] != "True":
            raise VerificationError("DDT_SIZE", "Generated DDT size does not match compile manifest")
        if row["DDTHashPASS"] != "True":
            raise VerificationError("DDT_HASH", "Generated DDT SHA-256 does not match compile manifest")

        hdr = read_ddt_header(ddt)
        row["DDTMagic"] = hdr["magic"].decode("ascii", errors="replace")
        row["DDTProperties"] = hdr["properties"]
        row["DDTAlphaBits"] = hdr["alpha"]
        row["DDTFormatByte"] = hdr["format"]
        row["DDTMipLevels"] = hdr["mips"]
        row["DDTWidth"] = hdr["width"]
        row["DDTHeight"] = hdr["height"]
        row["DDTDataTableEnd"] = hdr["table_end"]
        row["DDTDataEntryCount"] = hdr["entry_count"]

        if hdr["alpha"] not in (0, 1, 4, 8):
            raise VerificationError("DDT_HEADER", f"Invalid alpha bit count {hdr['alpha']}")
        if hdr["mips"] < 1 or hdr["mips"] > 32:
            raise VerificationError("DDT_HEADER", f"Invalid mip level count {hdr['mips']}")
        row["MagicPASS"] = str(hdr["magic"] == b"RTS3")

        rel_bti = norm(str(Path(rel).with_suffix(".bti")))
        auth_path = btis.get(key(rel_bti))
        if auth_path is None:
            raise VerificationError("BTI_INPUT", f"Authoritative BTI missing: {rel_bti}")
        auth = parse_bti(auth_path)
        row["AuthoritativeBTIFormat"] = auth["format"]
        row["AuthoritativeBTIAlpha"] = auth["alpha"]
        row["AuthoritativeBTINoAlphaTest"] = str(auth["noalphatest"])
        row["AuthoritativeBTINoMip"] = str(auth["nomip"])
        row["AuthoritativeBTINoLowDetail"] = str(auth["nolowdetail"])
        row["AuthoritativeBTIDisplacement"] = str(auth["displacement"])

        auth_alpha = int(auth["alpha"]) if auth["alpha"] else None
        expected_fmt_byte = expected_ddt_format_byte(row["CompileFormat"], auth_alpha if auth_alpha is not None else 0)
        row["DDTExpectedFormatByte"] = expected_fmt_byte
        row["DDTExpectedAlphaBits"] = auth_alpha if auth_alpha is not None else ""

        format_ok = hdr["format"] == expected_fmt_byte
        alpha_ok = auth_alpha is not None and hdr["alpha"] == auth_alpha
        dims_ok = hdr["width"] == tga_h["width"] and hdr["height"] == tga_h["height"]

        entries_ok = hdr["table_end"] <= actual_ddt_size and hdr["entry_count"] == len(hdr["entries"])
        intervals = []
        for mip, (off, size) in enumerate(hdr["entries"]):
            mw = max(1, hdr["width"] >> (mip % hdr["mips"]))
            mh = max(1, hdr["height"] >> (mip % hdr["mips"]))
            if off < hdr["table_end"] or size <= 0 or off + size > actual_ddt_size:
                entries_ok = False
            expected_size = expected_compressed_mip_bytes(hdr["format"], mw, mh)
            if expected_size is not None and size != expected_size:
                entries_ok = False
            intervals.append((off, off + size))

        overlap_ok = True
        for i, (a0, a1) in enumerate(sorted(intervals)):
            if i and a0 < sorted(intervals)[i - 1][1]:
                overlap_ok = False
        row["DDTDataEntriesInBounds"] = str(entries_ok)
        row["DDTDataEntriesNonOverlapping"] = str(overlap_ok)

        props_ok = (
            ((bool(hdr["properties"] & 0x01)) == auth["noalphatest"])
            and ((bool(hdr["properties"] & 0x02)) == auth["nolowdetail"])
            and ((bool(hdr["properties"] & 0x04)) == auth["displacement"])
            and ((hdr["mips"] == 1) == auth["nomip"])
        )
        row["DDTFormatPASS"] = str(format_ok)
        row["DDTAlphaPASS"] = str(alpha_ok)
        row["DDTDimensionsPASS"] = str(dims_ok)
        row["DDTDataTablePASS"] = str(entries_ok)
        row["DDTPropertyPASS"] = str(props_ok)

        core = all(row[x] == "True" for x in [
            "SourceTGAShaPASS", "SourceTgaStructurePASS", "DDTHashPASS", "DDTSizePASS",
            "MagicPASS", "DDTFormatPASS", "DDTAlphaPASS", "DDTDimensionsPASS",
            "DDTDataTablePASS", "DDTDataEntriesNonOverlapping", "DDTPropertyPASS",
        ])
        row["CorePASS"] = str(core)

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

        decode_ok = (not timed_out) and code == 0 and out_tga.is_file() and out_bti.is_file()
        if decode_ok:
            ext_tga = read_tga_header(out_tga)
            row["ExtractedTgaWidth"] = ext_tga["width"]
            row["ExtractedTgaHeight"] = ext_tga["height"]
            row["ExtractedTgaBPP"] = ext_tga["bpp"]
            decode_ok = (
                ext_tga["width"] == tga_h["width"]
                and ext_tga["height"] == tga_h["height"]
                and ext_tga["bpp"] == 32
            )
            if out_bti.is_file():
                ext_bti = parse_bti(out_bti)
                row["ExtractedBTIFormat"] = ext_bti["format"]
                row["ExtractedBTIAlpha"] = ext_bti["alpha"]

        row["ExtractorDecodePASS"] = str(decode_ok)
        if not core:
            row["FailureStage"] = "CORE_DDT_INTEGRITY"
            row["FailureReason"] = "; ".join(
                [
                    f"format={hdr['format']}/{expected_fmt_byte}" if not format_ok else "",
                    f"alpha={hdr['alpha']}/{auth_alpha}" if not alpha_ok else "",
                    "dimensions" if not dims_ok else "",
                    "data_table" if not entries_ok or not overlap_ok else "",
                    "properties" if not props_ok else "",
                ]
            ).strip("; ")
        elif not decode_ok:
            if timed_out:
                row["FailureStage"] = "EXTRACTOR"
                row["FailureReason"] = f"TextureExtractor exceeded {timeout}s"
            else:
                row["FailureStage"] = "EXTRACTOR"
                row["FailureReason"] = f"TextureExtractor exit code {code} ({exit_hex(code)})"
        else:
            row["FailureStage"] = ""
            row["FailureReason"] = ""

        row["OVERALLPASS"] = str(core and decode_ok)

    except VerificationError as exc:
        row["FailureStage"] = exc.stage
        row["FailureReason"] = exc.reason
        row["CorePASS"] = "False"
        row["ExtractorDecodePASS"] = "False"
        row["OVERALLPASS"] = "False"
    except Exception as exc:
        row["FailureStage"] = "EXCEPTION"
        row["FailureReason"] = f"{type(exc).__name__}: {exc}"
        row["CorePASS"] = "False"
        row["ExtractorDecodePASS"] = "False"
        row["OVERALLPASS"] = "False"
    finally:
        for p in SCRATCH_ROOT.glob(f"{index:05d}.*"):
            try:
                p.unlink()
            except Exception:
                pass
        row["ElapsedSeconds"] = f"{time.perf_counter() - start:.3f}"

    return row


def consolidate_partial() -> dict[str, dict]:
    rows: dict[str, dict] = {}
    if PARTIAL_REPORT.exists():
        for row in read_csv(PARTIAL_REPORT):
            rel = key(row.get("RelativePath", ""))
            if rel:
                rows[rel] = row
    return rows


def write_final(rows: dict[str, dict]) -> None:
    with FINAL_REPORT.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for row in [rows[k] for k in sorted(rows)]:
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

    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    cleanup_scratch()

    mi = manifest_index()
    ti = tga_index()
    di = ddt_index()
    bi = bti_index()

    print("============================================")
    print("AoM:EE FULL DDT VERIFICATION V3")
    print("============================================")
    print(f"PBRify TGAs       : {len(ti)}")
    print(f"Compile manifest  : {len(mi)}")
    print(f"Production DDTs   : {len(di)}")
    print(f"Authoritative BTIs: {len(bi)}")
    print()

    excluded_key = key(EXCLUDED_TGA)
    expected_ddt_keys = {
        key(norm(str(Path(rel).with_suffix(".ddt"))))
        for rel in ti
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

    if not PARTIAL_REPORT.exists() or not args.resume:
        if not args.resume:
            try:
                PARTIAL_REPORT.unlink()
            except FileNotFoundError:
                pass
        write_partial_header()

    completed_passes = load_completed_passes() if args.resume else set()
    verified_now = failed_now = skipped = total = 0
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
                continue

            print(f"[{total + 1}/{EXPECTED_DDTS}] VERIFY: {rel}")
            row = verify_one(i, rel, ti[tga_key], di[key(ddt_rel)], manifest, bi, args.timeout)
            append_partial(row)
            total += 1

            if row["OVERALLPASS"] == "True":
                verified_now += 1
            else:
                failed_now += 1
                print(f"    >>> FAIL: {row['FailureStage']} — {row['FailureReason']}")

            if total % 100 == 0:
                print(f"    Progress: {total}/{EXPECTED_DDTS} | PASS now {verified_now} | FAIL now {failed_now} | skipped {skipped}")
    finally:
        cleanup_scratch()

    rows = consolidate_partial()
    write_final(rows)
    CHECKPOINT.write_text(
        f"last_run_completed={time.strftime('%Y-%m-%dT%H:%M:%S')}\n"
        f"rows_in_final={len(rows)}\n",
        encoding="utf-8",
    )

    failed = [r for r in rows.values() if str(r.get("OVERALLPASS", "")).lower() != "true"]
    core_failed = [r for r in rows.values() if str(r.get("CorePASS", "")).lower() != "true"]
    decoder_failed = [r for r in rows.values() if str(r.get("ExtractorDecodePASS", "")).lower() != "true"]
    final_pass = len(rows) == EXPECTED_DDTS and not failed

    summary = [
        "AoM:EE FULL DDT VERIFICATION V3",
        "================================",
        "",
        f"Expected production DDTs: {EXPECTED_DDTS}",
        f"Final report rows:        {len(rows)}",
        f"Verified this run:        {verified_now + failed_now}",
        f"Skipped prior PASS:       {skipped}",
        f"OVERALL PASS:             {EXPECTED_DDTS - len(failed) if len(rows) == EXPECTED_DDTS else 'n/a'}",
        f"OVERALL FAIL:             {len(failed)}",
        f"CORE DDT FAIL:            {len(core_failed)}",
        f"EXTRACTOR/DECODE FAIL:    {len(decoder_failed)}",
        "",
        "CORE GATES",
        "----------",
        "PBRify TGA SHA-256",
        "PBRify TGA structure / 32-bit",
        "Generated DDT SHA-256",
        "Generated DDT byte size",
        "RTS3 magic",
        "DDT format byte vs intended compile format",
        "DDT alpha bits vs authoritative BTI",
        "DDT dimensions vs PBRify TGA",
        "DDT image-entry table bounds / mip sizes",
        "DDT image-entry non-overlap",
        "DDT properties vs authoritative BTI",
        "",
        "DECODER GATE",
        "------------",
        "Official AoM TextureExtractor completes and produces a 32-bit TGA + BTI with matching dimensions",
        "",
        "The extractor-reconstructed BTI format is NOT used as the DDT storage-format gate.",
        "This is intentional: the extractor can emit a different BTI recipe from the source DDT.",
        "",
        "FULL DDT VERIFICATION: PASS" if final_pass else "FULL DDT VERIFICATION: FAIL",
    ]
    SUMMARY.write_text("\n".join(summary) + "\n", encoding="utf-8")

    print()
    print("============================================")
    print("FULL DDT VERIFICATION RESULT V3")
    print("============================================")
    print(f"Expected DDTs : {EXPECTED_DDTS}")
    print(f"Final rows    : {len(rows)}")
    print(f"PASS          : {EXPECTED_DDTS - len(failed) if len(rows) == EXPECTED_DDTS else 0}")
    print(f"FAIL          : {len(failed)}")
    print(f"CORE FAIL     : {len(core_failed)}")
    print(f"DECODER FAIL  : {len(decoder_failed)}")
    print(f"Report        : {FINAL_REPORT}")
    print(f"Summary       : {SUMMARY}")
    print()
    print("FULL DDT VERIFICATION: PASS" if final_pass else "FULL DDT VERIFICATION: FAIL")
    return 0 if final_pass else 1


if __name__ == "__main__":
    sys.exit(main())
