from __future__ import annotations

import csv
import hashlib
import os
import sys
import tempfile
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


ROOT = Path(r"D:\AI_upscaling\AoMEE")
CLEAN = ROOT / "Age of Mythology"
EXTRACTED = ROOT / "extracted"
REPORTS = ROOT / "reports"
INVENTORY = REPORTS / "tga_inventory.csv"
RECOVERY = REPORTS / "file_converter_recovery.csv"
USAGE_RECOVERY = REPORTS / "ddt_usage_recovery_08_to_09.txt"
GATE = REPORTS / "extraction_integrity_gate_v7"

EXPECTED_TOTAL = 7487
EXPECTED_NORMAL = 7452
EXPECTED_RECOVERED = 35


def norm(value: str) -> str:
    return value.replace("/", "\\").strip("\\").lower()


def logical_tga_from_ddt(rel: str) -> str:
    rel = norm(rel)
    if not rel.endswith(".ddt"):
        raise ValueError(f"Not a DDT path: {rel}")
    return rel[:-4] + ".tga"


def logical_bti_from_tga(tga: str) -> str:
    return tga[:-4] + ".bti"


def write_lines(path: Path, values: Iterable[str]) -> None:
    vals = list(values)
    if not vals:
        if path.exists():
            path.unlink()
        return
    path.write_text("\n".join(vals) + "\n", encoding="utf-8")


def die(message: str) -> None:
    print(f"\nERROR: {message}")
    raise SystemExit(1)


def scan_files(root: Path, suffix: str) -> List[Path]:
    target = suffix.lower()
    return [p for p in root.rglob("*") if p.is_file() and p.suffix.lower() == target]


def relative_norm(path: Path, root: Path) -> str:
    return norm(str(path.relative_to(root)))


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def read_inventory() -> Tuple[Dict[str, dict], Dict[str, dict], Dict[str, dict]]:
    rows = []
    with INVENTORY.open("r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            if row.get("Path"):
                rows.append(row)

    if len(rows) != EXPECTED_TOTAL:
        die(f"Historical tga_inventory.csv contains {len(rows)} rows; expected {EXPECTED_TOTAL}.")

    combined: Dict[str, dict] = {}
    normal: Dict[str, dict] = {}
    recovered: Dict[str, dict] = {}

    for row in rows:
        raw = norm(row["Path"])
        if raw.startswith("patched_to_verify\\"):
            logical = raw[len("patched_to_verify\\"):]
            cls = "recovered"
        else:
            logical = raw
            cls = "normal"

        if logical in combined:
            die(f"Duplicate logical inventory path: {logical}")

        combined[logical] = row
        (recovered if cls == "recovered" else normal)[logical] = row

    if len(normal) != EXPECTED_NORMAL:
        die(f"Historical inventory has {len(normal)} normal textures; expected {EXPECTED_NORMAL}.")
    if len(recovered) != EXPECTED_RECOVERED:
        die(f"Historical inventory has {len(recovered)} recovered textures; expected {EXPECTED_RECOVERED}.")

    return combined, normal, recovered


def read_documented_recovery() -> set[str]:
    documented: set[str] = set()

    with RECOVERY.open("r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            if row.get("Status") == "RecoveredTGAandBTI":
                ddt = row.get("RelativePath", "").strip()
                if ddt:
                    documented.add(logical_tga_from_ddt(ddt))

    if USAGE_RECOVERY.exists():
        text = USAGE_RECOVERY.read_text(encoding="utf-8-sig", errors="replace")
        for line in text.splitlines():
            if line.lower().startswith("file:"):
                ddt = line.split(":", 1)[1].strip()
                if ddt.lower().endswith(".ddt"):
                    documented.add(logical_tga_from_ddt(ddt))

    return documented


def parse_tga(path: Path) -> dict:
    """Structural TGA validator/decoder for 32-bit true-color type 2 and 10.

    This deliberately does not depend on Pillow. AoM extraction contains known
    type-10 RLE TGAs for which generic image readers may reject the stream even
    though the game/toolchain can consume them.
    """
    data = path.read_bytes()
    if len(data) < 18:
        raise ValueError(f"file is only {len(data)} bytes; shorter than TGA header")

    h = data[:18]
    id_len = h[0]
    cmap_type = h[1]
    image_type = h[2]
    cmap_origin = int.from_bytes(h[3:5], "little")
    cmap_length = int.from_bytes(h[5:7], "little")
    cmap_depth = h[7]
    width = int.from_bytes(h[12:14], "little")
    height = int.from_bytes(h[14:16], "little")
    bpp = h[16]
    descriptor = h[17]
    alpha_bits = descriptor & 0x0F

    if width <= 0 or height <= 0:
        raise ValueError(f"invalid dimensions {width}x{height}")
    if image_type not in (2, 10):
        raise ValueError(f"unsupported TGA image type {image_type}")
    if bpp != 32:
        raise ValueError(f"unsupported pixel depth {bpp}; expected 32")
    if cmap_type not in (0, 1):
        raise ValueError(f"invalid color-map type {cmap_type}")

    if cmap_type == 1:
        cmap_entry_bytes = (cmap_depth + 7) // 8
        cmap_bytes = cmap_length * cmap_entry_bytes
    else:
        cmap_bytes = 0

    pixel_offset = 18 + id_len + cmap_bytes
    if pixel_offset > len(data):
        raise ValueError(
            f"pixel data starts at {pixel_offset}, beyond EOF {len(data)}"
        )

    pixels_expected = width * height
    bytes_per_pixel = 4
    pos = pixel_offset
    decoded = 0
    packets = 0

    if image_type == 2:
        payload = len(data) - pos
        needed = pixels_expected * bytes_per_pixel
        if payload < needed:
            raise ValueError(
                f"type-2 pixel payload is {payload} bytes; need {needed}"
            )
        decoded = pixels_expected
        packets = 1

    else:  # type 10 RLE
        while decoded < pixels_expected:
            if pos >= len(data):
                raise ValueError(
                    f"RLE stream ended at {decoded}/{pixels_expected} pixels"
                )

            packet_header = data[pos]
            pos += 1
            count = (packet_header & 0x7F) + 1
            is_rle = (packet_header & 0x80) != 0

            if decoded + count > pixels_expected:
                raise ValueError(
                    f"RLE packet overruns image: decoded={decoded}, "
                    f"packet_count={count}, expected_total={pixels_expected}"
                )

            if is_rle:
                if pos + bytes_per_pixel > len(data):
                    raise ValueError("RLE packet has no complete pixel payload")
                pos += bytes_per_pixel
            else:
                raw_bytes = count * bytes_per_pixel
                if pos + raw_bytes > len(data):
                    raise ValueError(
                        f"raw packet needs {raw_bytes} bytes but only "
                        f"{len(data) - pos} remain"
                    )
                pos += raw_bytes

            decoded += count
            packets += 1

    return {
        "Width": width,
        "Height": height,
        "ImageType": image_type,
        "BitsPerPixel": bpp,
        "AlphaBits": alpha_bits,
        "DecodedPixels": decoded,
        "Bytes": len(data),
        "PixelOffset": pixel_offset,
        "Packets": packets,
        "FileSizeKBActual": len(data) / 1024.0,
        "Status": "PASS",
        "Error": "",
    }


def main() -> int:
    GATE.mkdir(parents=True, exist_ok=True)

    for p in [ROOT, CLEAN, EXTRACTED, REPORTS, INVENTORY, RECOVERY]:
        if not p.exists():
            die(f"Missing required path: {p}")

    print("")
    print("============================================================")
    print("AoM:EE SOURCE / EXTRACTION INTEGRITY GATE v7")
    print("============================================================")
    print("")
    print(f"Clean game: {CLEAN}")
    print(f"Extracted : {EXTRACTED}")
    print("")

    # 1. Historical inventory + recovery reconciliation.
    combined, expected_normal, expected_recovered = read_inventory()
    documented_recovered = read_documented_recovery()

    rec_missing = sorted(documented_recovered - set(expected_recovered))
    rec_unexpected = sorted(set(expected_recovered) - documented_recovered)
    write_lines(GATE / "recovery_documented_missing_from_inventory.txt", rec_missing)
    write_lines(GATE / "recovery_inventory_not_documented.txt", rec_unexpected)

    if rec_missing or rec_unexpected:
        die("Historical recovery records do not exactly match the combined inventory.")

    print("[1/7] Historical inventory: PASS")
    print(f"      Total {EXPECTED_TOTAL} | Normal {EXPECTED_NORMAL} | Recovered {EXPECTED_RECOVERED}")

    # 2. Fresh clean DDT inventory.
    clean_ddts = scan_files(CLEAN, ".ddt")
    clean_rel = sorted(relative_norm(p, CLEAN) for p in clean_ddts)
    clean_tga_keys = {logical_tga_from_ddt(x) for x in clean_rel}
    write_lines(GATE / "clean_ddt_inventory.txt", clean_rel)

    clean_missing_history = sorted(set(combined) - clean_tga_keys)
    clean_extra_history = sorted(clean_tga_keys - set(combined))
    write_lines(GATE / "clean_ddt_missing_from_historical_inventory.txt", clean_missing_history)
    write_lines(GATE / "clean_ddt_extra_vs_historical_inventory.txt", clean_extra_history)

    if len(clean_ddts) != EXPECTED_TOTAL or clean_missing_history or clean_extra_history:
        die(
            f"Clean DDT reconciliation failed: found {len(clean_ddts)}, "
            f"missing {len(clean_missing_history)}, extra {len(clean_extra_history)}."
        )

    print(f"[2/7] Clean installation DDT scan: {len(clean_ddts)} PASS")

    # 3. Current extracted coverage.
    current_tgas = scan_files(EXTRACTED, ".tga")
    current_btis = scan_files(EXTRACTED, ".bti")

    normal_tga_files = []
    recovered_tga_files = []
    normal_bti_files = []
    recovered_bti_files = []

    for p in current_tgas:
        rel = relative_norm(p, EXTRACTED)
        if rel.startswith("patched_to_verify\\"):
            recovered_tga_files.append(p)
        else:
            normal_tga_files.append(p)

    for p in current_btis:
        rel = relative_norm(p, EXTRACTED)
        if rel.startswith("patched_to_verify\\"):
            recovered_bti_files.append(p)
        else:
            normal_bti_files.append(p)

    normal_map: Dict[str, Path] = {}
    for p in normal_tga_files:
        key = relative_norm(p, EXTRACTED)
        if key in normal_map:
            die(f"Duplicate current normal TGA logical path: {key}")
        normal_map[key] = p

    normal_bti_map: Dict[str, Path] = {}
    for p in normal_bti_files:
        key = relative_norm(p, EXTRACTED)
        if key in normal_bti_map:
            die(f"Duplicate current normal BTI logical path: {key}")
        normal_bti_map[key] = p

    if len(recovered_tga_files) != EXPECTED_RECOVERED:
        die(f"patched_to_verify contains {len(recovered_tga_files)} TGA files; expected {EXPECTED_RECOVERED}.")
    if len(recovered_bti_files) != EXPECTED_RECOVERED:
        die(f"patched_to_verify contains {len(recovered_bti_files)} BTI files; expected {EXPECTED_RECOVERED}.")

    expected_rec_tga_leaves = {Path(x).name.lower() for x in expected_recovered}
    expected_rec_bti_leaves = {Path(logical_bti_from_tga(x)).name.lower() for x in expected_recovered}
    actual_rec_tga_leaves = {p.name.lower() for p in recovered_tga_files}
    actual_rec_bti_leaves = {p.name.lower() for p in recovered_bti_files}

    if actual_rec_tga_leaves != expected_rec_tga_leaves:
        write_lines(
            GATE / "patched_recovered_tga_basename_mismatch.txt",
            sorted(
                [f"MISSING: {x}" for x in expected_rec_tga_leaves - actual_rec_tga_leaves]
                + [f"EXTRA: {x}" for x in actual_rec_tga_leaves - expected_rec_tga_leaves]
            )
        )
        die("Recovered TGA filenames do not match the expected 35.")
    if actual_rec_bti_leaves != expected_rec_bti_leaves:
        write_lines(
            GATE / "patched_recovered_bti_basename_mismatch.txt",
            sorted(
                [f"MISSING: {x}" for x in expected_rec_bti_leaves - actual_rec_bti_leaves]
                + [f"EXTRA: {x}" for x in actual_rec_bti_leaves - expected_rec_bti_leaves]
            )
        )
        die("Recovered BTI filenames do not match the expected 35.")

    rec_tga_by_leaf: Dict[str, List[Path]] = {}
    rec_bti_by_leaf: Dict[str, List[Path]] = {}
    for p in recovered_tga_files:
        rec_tga_by_leaf.setdefault(p.name.lower(), []).append(p)
    for p in recovered_bti_files:
        rec_bti_by_leaf.setdefault(p.name.lower(), []).append(p)

    recovered_map: Dict[str, Path] = {}
    recovered_bti_map: Dict[str, Path] = {}
    for logical in expected_recovered:
        tm = rec_tga_by_leaf.get(Path(logical).name.lower(), [])
        bm = rec_bti_by_leaf.get(Path(logical_bti_from_tga(logical)).name.lower(), [])
        if len(tm) != 1 or len(bm) != 1:
            die(f"Ambiguous recovered match for {logical}.")
        recovered_map[logical] = tm[0]
        recovered_bti_map[logical_bti_from_tga(logical)] = bm[0]

    current_logical_tgas = set(normal_map) | set(recovered_map)
    current_logical_btis = set(normal_bti_map) | set(recovered_bti_map)
    expected_btis = {logical_bti_from_tga(x) for x in combined}

    missing_tga = sorted(set(combined) - current_logical_tgas)
    extra_tga = sorted(current_logical_tgas - set(combined))
    missing_bti = sorted(expected_btis - current_logical_btis)
    extra_bti = sorted(current_logical_btis - expected_btis)

    write_lines(GATE / "extracted_missing_tga_vs_clean_ddt.txt", missing_tga)
    write_lines(GATE / "extracted_extra_tga_vs_clean_ddt.txt", extra_tga)
    write_lines(GATE / "extracted_missing_bti.txt", missing_bti)
    write_lines(GATE / "extracted_extra_bti.txt", extra_bti)

    if missing_tga or extra_tga or missing_bti or extra_bti:
        die("Current extracted TGA/BTI coverage does not exactly match the clean DDT set.")

    print(f"[3/7] Extracted TGA coverage: {len(current_logical_tgas)} PASS")
    print(f"      Extracted BTI coverage: {len(current_logical_btis)} PASS")

    # 4. Robust TGA structure validation, independent of Pillow.
    ordered: List[Tuple[str, str, Path]] = []
    for logical in sorted(expected_normal):
        ordered.append(("normal", logical, normal_map[logical]))
    for logical in sorted(expected_recovered):
        ordered.append(("recovered", logical, recovered_map[logical]))

    metadata_rows = []
    failures = 0
    type_counts: Dict[int, int] = {}

    for idx, (source_class, logical, path) in enumerate(ordered, 1):
        hist = combined[logical]
        row = {
            "LogicalTGA": logical,
            "SourceClass": source_class,
            "Path": str(path),
            "ExpectedWidth": hist["Width"],
            "ExpectedHeight": hist["Height"],
            "ActualWidth": "",
            "ActualHeight": "",
            "ExpectedImageType": hist["ImageType"],
            "ActualImageType": "",
            "ExpectedBitsPerPixel": hist["BitsPerPixel"],
            "ActualBitsPerPixel": "",
            "ExpectedAlphaBits": hist["AlphaBits"],
            "ActualAlphaBits": "",
            "ExpectedDecodedPixels": hist["DecodedPixels"],
            "ActualDecodedPixels": "",
            "ActualBytes": "",
            "ActualPixelOffset": "",
            "Packets": "",
            "Status": "FAIL",
            "Error": "",
        }

        try:
            parsed = parse_tga(path)
            type_counts[parsed["ImageType"]] = type_counts.get(parsed["ImageType"], 0) + 1

            width_ok = parsed["Width"] == int(hist["Width"])
            height_ok = parsed["Height"] == int(hist["Height"])
            type_ok = parsed["ImageType"] == int(hist["ImageType"])
            bpp_ok = parsed["BitsPerPixel"] == int(hist["BitsPerPixel"])
            alpha_ok = parsed["AlphaBits"] == int(hist["AlphaBits"])
            pixels_ok = parsed["DecodedPixels"] == int(hist["DecodedPixels"])

            row.update({
                "ActualWidth": str(parsed["Width"]),
                "ActualHeight": str(parsed["Height"]),
                "ActualImageType": str(parsed["ImageType"]),
                "ActualBitsPerPixel": str(parsed["BitsPerPixel"]),
                "ActualAlphaBits": str(parsed["AlphaBits"]),
                "ActualDecodedPixels": str(parsed["DecodedPixels"]),
                "ActualBytes": str(parsed["Bytes"]),
                "ActualPixelOffset": str(parsed["PixelOffset"]),
                "Packets": str(parsed["Packets"]),
            })

            ok = all([width_ok, height_ok, type_ok, bpp_ok, alpha_ok, pixels_ok])
            row["Status"] = "PASS" if ok else "FAIL"

            if not width_ok:
                row["Error"] += "width mismatch; "
            if not height_ok:
                row["Error"] += "height mismatch; "
            if not type_ok:
                row["Error"] += "image type mismatch; "
            if not bpp_ok:
                row["Error"] += "bits-per-pixel mismatch; "
            if not alpha_ok:
                row["Error"] += "alpha bits mismatch; "
            if not pixels_ok:
                row["Error"] += "decoded pixel count mismatch; "

        except Exception as exc:
            row["Error"] = str(exc)

        if row["Status"] != "PASS":
            failures += 1

        metadata_rows.append(row)

        if idx % 250 == 0 or idx == len(ordered):
            print(f"      TGA structural validation: {idx}/{len(ordered)}")

    metadata_path = GATE / "tga_structural_qa.csv"
    with metadata_path.open("w", encoding="utf-8-sig", newline="") as f:
        fields = list(metadata_rows[0].keys())
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(metadata_rows)

    if failures:
        print(f"\nTGA structural failures: {failures}")
        # Print concise failed rows so diagnosis does not require another command.
        for row in metadata_rows:
            if row["Status"] != "PASS":
                print(f"      FAIL {row['LogicalTGA']} :: {row['Error']}")
        die(f"TGA structural verification failed for {failures} files.")

    print(f"[4/7] TGA structural validation: PASS")
    print(f"      Type 2: {type_counts.get(2,0)} | Type 10 RLE: {type_counts.get(10,0)}")

    # 5. Hash clean DDTs with visible progress and atomic commit.
    print("[5/7] SHA-256 clean DDT baseline")
    clean_hash = GATE / "clean_ddt_sha256_baseline.csv"
    clean_partial = GATE / "clean_ddt_sha256_baseline.csv.partial"

    with clean_partial.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["RelativePath", "Bytes", "SHA256"])
        ordered_clean = sorted(clean_ddts, key=lambda p: relative_norm(p, CLEAN))
        for i, p in enumerate(ordered_clean, 1):
            rel = relative_norm(p, CLEAN)
            writer.writerow([rel, p.stat().st_size, sha256_file(p)])
            if i % 100 == 0 or i == len(ordered_clean):
                print(f"      Clean DDT hash: {i}/{len(ordered_clean)}")
        f.flush()
        os.fsync(f.fileno())

    clean_partial.replace(clean_hash)
    clean_manifest = sha256_file(clean_hash)
    (GATE / "clean_ddt_baseline_manifest_sha256.txt").write_text(
        clean_manifest + "\n", encoding="ascii"
    )

    # 6. Hash extracted TGA/BTI with visible progress.
    print("[6/7] SHA-256 extracted TGA + BTI baseline")
    extracted_hash = GATE / "extracted_tga_bti_sha256_baseline.csv"
    extracted_partial = GATE / "extracted_tga_bti_sha256_baseline.csv.partial"

    with extracted_partial.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "LogicalTGA","SourceClass",
            "TGAPath","TGABYTES","TGASHA256",
            "BTIPath","BTIBYTES","BTISHA256"
        ])

        logicals = sorted(combined)
        for i, logical in enumerate(logicals, 1):
            if logical in normal_map:
                tga = normal_map[logical]
                bti = normal_bti_map[logical_bti_from_tga(logical)]
                cls = "normal"
            else:
                tga = recovered_map[logical]
                bti = recovered_bti_map[logical_bti_from_tga(logical)]
                cls = "recovered"

            writer.writerow([
                logical, cls,
                str(tga), tga.stat().st_size, sha256_file(tga),
                str(bti), bti.stat().st_size, sha256_file(bti),
            ])

            if i % 100 == 0 or i == len(logicals):
                print(f"      Extracted TGA+BTI hash: {i}/{len(logicals)}")

        f.flush()
        os.fsync(f.fileno())

    extracted_partial.replace(extracted_hash)
    extracted_manifest = sha256_file(extracted_hash)
    (GATE / "extracted_baseline_manifest_sha256.txt").write_text(
        extracted_manifest + "\n", encoding="ascii"
    )

    # 7. Final source lock record.
    summary = [
        "AoM:EE SOURCE / EXTRACTION INTEGRITY GATE v7",
        "==============================================",
        "",
        f"Clean DDT count                    : {len(clean_ddts)}",
        f"Historical combined texture count : {EXPECTED_TOTAL}",
        f"Historical normal count            : {EXPECTED_NORMAL}",
        f"Historical recovered count         : {EXPECTED_RECOVERED}",
        f"Current logical TGA count           : {len(current_logical_tgas)}",
        f"Current logical BTI count           : {len(current_logical_btis)}",
        "",
        "Clean DDT vs historical inventory  : PASS",
        "Clean DDT vs extracted TGA          : PASS",
        "TGA -> BTI pairing                  : PASS",
        "TGA structural/header validation    : PASS",
        "Clean DDT SHA-256 baseline          : CREATED",
        "Extracted TGA/BTI SHA-256 baseline  : CREATED",
        "",
        f"Clean DDT baseline manifest SHA-256 : {clean_manifest}",
        f"Extracted baseline manifest SHA-256 : {extracted_manifest}",
        "",
        "SOURCE LOCK: PASS",
        "Do not modify the clean game or extracted source tree.",
    ]
    (GATE / "source_gate_summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")

    print("")
    print("============================================================")
    print("SOURCE / EXTRACTION INTEGRITY GATE v7: PASS")
    print("============================================================")
    print("")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nInterrupted by user.")
        raise SystemExit(130)
