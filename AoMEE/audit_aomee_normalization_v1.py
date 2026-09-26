from __future__ import annotations

import csv
import re
import struct
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(r"D:\AI_upscaling\AoMEE")

MASTER_MANIFEST = ROOT / r"reports\master_texture_manifest.csv"
TGA_CLASSIFICATION = ROOT / r"reports\tga_classification.csv"
MTRL_SUMMARY = ROOT / r"reports\mtrl_texture_summary.csv"

PBRIFY_ROOT = ROOT / r"processed\PBRify_V4"
DDT_ROOT = ROOT / r"processed\DDT_PBRify_V4"
EXTRACTED_ROOT = ROOT / r"extracted"

OUT_ROOT = ROOT / r"reports\normalization_audit_v1"


def normalize_path(value: str) -> str:
    return (
        value.replace("/", "\\")
        .strip()
        .lstrip("\\")
    )


def key_path(value: str) -> str:
    return normalize_path(value).lower()


def read_csv(path: Path) -> list[dict]:
    if not path.is_file():
        return []

    with path.open(
        "r",
        encoding="utf-8-sig",
        newline="",
    ) as f:
        return list(csv.DictReader(f))


def field(row: dict, *names: str, default: str = "") -> str:
    for name in names:
        if name in row:
            value = row[name]
            if value is not None:
                return str(value)

    return default


def to_int(value: str, default: int = 0) -> int:
    try:
        return int(float(value))
    except Exception:
        return default


def to_float(value: str, default: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return default


def parse_bti(path: Path) -> dict:

    raw = path.read_bytes()

    text = raw.decode(
        "utf-8-sig",
        errors="replace",
    )

    compact = " ".join(
        line.strip()
        for line in text.splitlines()
        if line.strip()
    )

    alpha_bits = ""

    match = re.search(
        r"\balpha\s*=\s*(\d+)",
        text,
        re.IGNORECASE,
    )

    if match:
        alpha_bits = match.group(1)

    fmt = ""

    match = re.search(
        r"\bfmt\s*=\s*([A-Za-z0-9_]+)",
        text,
        re.IGNORECASE,
    )

    if match:
        fmt = match.group(1).upper()

    flags = []

    for token in (
        "noalphatest",
        "nomip",
        "clamp",
        "nopicmip",
    ):
        if re.search(
            rf"(^|\s){re.escape(token)}(\s|$)",
            text,
            re.IGNORECASE,
        ):
            flags.append(token)

    return {
        "raw_bytes": len(raw),
        "text": compact,
        "alpha_bits": alpha_bits,
        "format": fmt,
        "noalphatest": "noalphatest" in flags,
        "nomip": "nomip" in flags,
        "clamp": "clamp" in flags,
        "flags": ";".join(flags),
        "bom": (
            len(raw) >= 3
            and raw[:3] == b"\xef\xbb\xbf"
        ),
    }


def read_tga_header(path: Path) -> dict:

    data = path.read_bytes()

    if len(data) < 18:
        raise ValueError(
            f"TGA shorter than 18 bytes: {path}"
        )

    image_type = data[2]

    width = struct.unpack_from(
        "<H",
        data,
        12,
    )[0]

    height = struct.unpack_from(
        "<H",
        data,
        14,
    )[0]

    bpp = data[16]

    descriptor = data[17]

    return {
        "bytes": len(data),
        "image_type": image_type,
        "width": width,
        "height": height,
        "bpp": bpp,
        "alpha_bits": descriptor & 0x0F,
        "descriptor": descriptor,
        "origin_top": bool(descriptor & 0x20),
    }


def find_authoritative_btis() -> dict[str, Path]:

    index: dict[str, Path] = {}

    for path in EXTRACTED_ROOT.rglob("*.bti"):

        rel = normalize_path(
            str(path.relative_to(EXTRACTED_ROOT))
        )

        if rel.lower().startswith(
            "patched_to_verify\\"
        ):
            rel = rel[
                len("patched_to_verify\\"):
            ]

        key = rel.lower()

        if key in index:
            raise RuntimeError(
                "Duplicate logical BTI:\n"
                f"  {rel}\n"
                f"  {index[key]}\n"
                f"  {path}"
            )

        index[key] = path

    return index


def make_mtrl_index(
    rows: list[dict],
) -> dict[str, dict]:

    result = {}

    for row in rows:

        texture = field(
            row,
            "Texture",
            "texture",
        ).strip()

        if not texture:
            continue

        name = Path(texture).stem
        key = name.lower()

        total = to_int(
            field(row, "Total", default="0")
        )

        ct0 = to_int(
            field(row, "CT0", default="0")
        )

        ct4 = to_int(
            field(row, "CT4", default="0")
        )

        other = to_int(
            field(row, "OtherCT", "Other", default="0")
        )

        pixel_xform = to_int(
            field(row, "PixelXForm", default="0")
        )

        result[key] = {
            "mtrl_total": total,
            "mtrl_ct0": ct0,
            "mtrl_ct4": ct4,
            "mtrl_other_ct": other,
            "mtrl_pixel_xform": pixel_xform,
        }

    return result


def main() -> None:

    print("============================================")
    print("AoM:EE NORMALIZATION AUDIT V1")
    print("============================================")
    print()

    required = [
        MASTER_MANIFEST,
        PBRIFY_ROOT,
        EXTRACTED_ROOT,
    ]

    for path in required:
        if not path.exists():
            raise SystemExit(
                f"Required path not found:\n{path}"
            )

    OUT_ROOT.mkdir(
        parents=True,
        exist_ok=True,
    )

    # ---------------------------------------------------------
    # Load metadata reports
    # ---------------------------------------------------------

    master_rows = read_csv(
        MASTER_MANIFEST
    )

    if not master_rows:
        raise SystemExit(
            f"Could not read master manifest:\n"
            f"{MASTER_MANIFEST}"
        )

    classification_rows = read_csv(
        TGA_CLASSIFICATION
    )

    mtrl_rows = read_csv(
        MTRL_SUMMARY
    )

    print(
        f"Master manifest rows : {len(master_rows)}"
    )

    print(
        f"TGA classification   : {len(classification_rows)}"
    )

    print(
        f"MTRL texture rows     : {len(mtrl_rows)}"
    )

    # ---------------------------------------------------------
    # Classification index
    # ---------------------------------------------------------

    classification_index = {}

    for row in classification_rows:

        rel = field(
            row,
            "Path",
            "RelativePath",
            "Filename",
        ).strip()

        if not rel:
            continue

        classification_index[
            key_path(rel)
        ] = row

    # ---------------------------------------------------------
    # MTRL index
    # ---------------------------------------------------------

    mtrl_index = make_mtrl_index(
        mtrl_rows
    )

    # ---------------------------------------------------------
    # Authoritative BTI index
    # ---------------------------------------------------------

    print(
        "Indexing authoritative BTIs..."
    )

    bti_index = find_authoritative_btis()

    print(
        f"Logical BTIs indexed: {len(bti_index)}"
    )

    # ---------------------------------------------------------
    # Production TGA index
    # ---------------------------------------------------------

    production_tgas = sorted(
        PBRIFY_ROOT.rglob("*.tga")
    )

    production_tga_index = {}

    for path in production_tgas:

        rel = normalize_path(
            str(path.relative_to(PBRIFY_ROOT))
        )

        key = key_path(rel)

        if key in production_tga_index:
            raise RuntimeError(
                f"Duplicate production TGA: {rel}"
            )

        production_tga_index[key] = path

    print(
        f"Production PBRify TGAs: "
        f"{len(production_tgas)}"
    )

    # ---------------------------------------------------------
    # Build unified audit rows
    # ---------------------------------------------------------

    results = []

    for index, master in enumerate(
        master_rows,
        start=1,
    ):

        relative = normalize_path(
            field(
                master,
                "RelativePath",
                "Path",
            )
        )

        if not relative:
            continue

        source_key = key_path(
            relative
        )

        source_width = to_int(
            field(
                master,
                "Width",
                "TgaWidth",
                "OriginalWidth",
            )
        )

        source_height = to_int(
            field(
                master,
                "Height",
                "TgaHeight",
                "OriginalHeight",
            )
        )

        category = field(
            master,
            "Category",
            "SuggestedGroup",
            "SourceCategory",
            default="Unknown",
        )

        source_type = field(
            master,
            "SourceType",
            default="",
        )

        # -----------------------------------------------------
        # Find authoritative BTI
        # -----------------------------------------------------

        bti_relative = str(
            Path(relative).with_suffix(".bti")
        )

        bti_path = bti_index.get(
            key_path(bti_relative)
        )

        bti = {}

        if bti_path:
            bti = parse_bti(
                bti_path
            )

        # -----------------------------------------------------
        # PBRify output
        # -----------------------------------------------------

        pbrify_path = production_tga_index.get(
            source_key
        )

        pbrify_info = {}

        if pbrify_path:

            try:
                pbrify_info = read_tga_header(
                    pbrify_path
                )
            except Exception:
                pbrify_info = {}

        output_width = pbrify_info.get(
            "width",
            source_width * 4,
        )

        output_height = pbrify_info.get(
            "height",
            source_height * 4,
        )

        output_area = (
            output_width
            * output_height
        )

        output_megapixels = (
            output_area / 1_000_000
        )

        max_dimension = max(
            output_width,
            output_height,
        )

        source_area = (
            source_width
            * source_height
        )

        # -----------------------------------------------------
        # Current DDT
        # -----------------------------------------------------

        ddt_relative = str(
            Path(relative).with_suffix(".ddt")
        )

        ddt_path = DDT_ROOT / ddt_relative

        ddt_exists = ddt_path.is_file()

        ddt_bytes = (
            ddt_path.stat().st_size
            if ddt_exists
            else 0
        )

        ddt_valid_size = (
            ddt_exists
            and ddt_bytes > 24
        )

        # -----------------------------------------------------
        # Format
        # -----------------------------------------------------

        fmt = bti.get(
            "format",
            "",
        )

        alpha_bits = bti.get(
            "alpha_bits",
            "",
        )

        noalphatest = bti.get(
            "noalphatest",
            False,
        )

        if fmt == "BC1":
            canonical_family = "BC1"
        elif fmt == "BC2":
            canonical_family = "BC2"
        elif fmt == "BC3":
            canonical_family = "BC3"
        elif fmt.startswith("DEFLATED"):
            canonical_family = "DEFLATED"
        elif fmt:
            canonical_family = fmt
        else:
            canonical_family = "UNKNOWN"

        # -----------------------------------------------------
        # Alpha / classification metadata
        # -----------------------------------------------------

        classification = classification_index.get(
            source_key,
            {},
        )

        alpha_band = field(
            classification,
            "AlphaBand",
            "AlphaType",
            default="",
        )

        alpha_coverage = to_float(
            field(
                classification,
                "AlphaCoveragePercent",
                "AlphaCoverage",
                default="",
            )
        )

        alpha_value_count = to_int(
            field(
                classification,
                "AlphaValueCount",
                default="",
            )
        )

        # -----------------------------------------------------
        # MTRL relationship metadata
        # -----------------------------------------------------

        texture_name = Path(
            relative
        ).stem.lower()

        mtrl = mtrl_index.get(
            texture_name,
            {},
        )

        mtrl_total = mtrl.get(
            "mtrl_total",
            0,
        )

        mtrl_ct0 = mtrl.get(
            "mtrl_ct0",
            0,
        )

        mtrl_ct4 = mtrl.get(
            "mtrl_ct4",
            0,
        )

        # -----------------------------------------------------
        # Candidate flags
        # -----------------------------------------------------

        large_1024_plus = (
            max_dimension >= 1024
        )

        large_2048_plus = (
            max_dimension >= 2048
        )

        large_4096_plus = (
            max_dimension >= 4096
        )

        square_1024 = (
            output_width == 1024
            and output_height == 1024
        )

        bc1_large = (
            fmt == "BC1"
            and max_dimension >= 1024
        )

        bc1_square_1024 = (
            fmt == "BC1"
            and square_1024
        )

        oversized_relative_to_source = (
            source_width > 0
            and output_width == source_width * 4
            and output_height == source_height * 4
        )

        # -----------------------------------------------------
        # Estimate uncompressed VRAM for output image.
        #
        # This is intentionally NOT a claim about actual engine
        # allocation. It is only a useful upper-bound-style
        # comparison between textures.
        # -----------------------------------------------------

        rgba_bytes = (
            output_area * 4
        )

        results.append({

            "RelativePath": relative,

            "Category": category,
            "SourceType": source_type,

            "SourceWidth": source_width,
            "SourceHeight": source_height,
            "SourceArea": source_area,

            "OutputWidth": output_width,
            "OutputHeight": output_height,
            "OutputArea": output_area,
            "OutputMegapixels": round(
                output_megapixels,
                4,
            ),
            "OutputMaxDimension": max_dimension,

            "BTIFormat": fmt,
            "BTIAlphaBits": alpha_bits,
            "NoAlphaTest": noalphatest,
            "NoMip": bti.get(
                "nomip",
                False,
            ),
            "Clamp": bti.get(
                "clamp",
                False,
            ),
            "BTIBOM": bti.get(
                "bom",
                False,
            ),

            "AlphaBand": alpha_band,
            "AlphaCoveragePercent": alpha_coverage,
            "AlphaValueCount": alpha_value_count,

            "MTRLTotal": mtrl_total,
            "MTRLCT0": mtrl_ct0,
            "MTRLCT4": mtrl_ct4,

            "PBRifyFound": bool(
                pbrify_path
            ),

            "DDTFound": ddt_exists,
            "DDTBytes": ddt_bytes,
            "DDTNonEmpty": ddt_valid_size,

            "Large1024Plus": large_1024_plus,
            "Large2048Plus": large_2048_plus,
            "Large4096Plus": large_4096_plus,

            "Square1024Output": square_1024,

            "BC1Large": bc1_large,
            "BC1Square1024": bc1_square_1024,

            "CanonicalFamily":
                canonical_family,

            "EstimatedRGBABytes":
                rgba_bytes,

            "OutputExactly4x":
                oversized_relative_to_source,
        })

        if index % 500 == 0:
            print(
                f"Processed {index} / "
                f"{len(master_rows)}"
            )

    # ---------------------------------------------------------
    # Full CSV
    # ---------------------------------------------------------

    full_csv = (
        OUT_ROOT
        / "normalization_audit_v1.csv"
    )

    fields = [
        "RelativePath",
        "Category",
        "SourceType",
        "SourceWidth",
        "SourceHeight",
        "SourceArea",
        "OutputWidth",
        "OutputHeight",
        "OutputArea",
        "OutputMegapixels",
        "OutputMaxDimension",
        "BTIFormat",
        "BTIAlphaBits",
        "NoAlphaTest",
        "NoMip",
        "Clamp",
        "BTIBOM",
        "AlphaBand",
        "AlphaCoveragePercent",
        "AlphaValueCount",
        "MTRLTotal",
        "MTRLCT0",
        "MTRLCT4",
        "PBRifyFound",
        "DDTFound",
        "DDTBytes",
        "DDTNonEmpty",
        "Large1024Plus",
        "Large2048Plus",
        "Large4096Plus",
        "Square1024Output",
        "BC1Large",
        "BC1Square1024",
        "CanonicalFamily",
        "EstimatedRGBABytes",
        "OutputExactly4x",
    ]

    with full_csv.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as f:

        writer = csv.DictWriter(
            f,
            fieldnames=fields,
        )

        writer.writeheader()
        writer.writerows(results)

    # ---------------------------------------------------------
    # Helper to write filtered reports.
    # ---------------------------------------------------------

    def write_filtered(
        filename: str,
        rows: list[dict],
    ) -> None:

        path = OUT_ROOT / filename

        with path.open(
            "w",
            newline="",
            encoding="utf-8",
        ) as f:

            writer = csv.DictWriter(
                f,
                fieldnames=fields,
            )

            writer.writeheader()
            writer.writerows(rows)

    large_rows = [
        r for r in results
        if r["Large1024Plus"]
    ]

    huge_rows = [
        r for r in results
        if r["Large4096Plus"]
    ]

    bc1_large_rows = [
        r for r in results
        if r["BC1Large"]
    ]

    bc1_1024_rows = [
        r for r in results
        if r["BC1Square1024"]
    ]

    write_filtered(
        "normalization_large_1024plus.csv",
        large_rows,
    )

    write_filtered(
        "normalization_huge_4096plus.csv",
        huge_rows,
    )

    write_filtered(
        "normalization_bc1_large.csv",
        bc1_large_rows,
    )

    write_filtered(
        "normalization_bc1_square_1024.csv",
        bc1_1024_rows,
    )

    # ---------------------------------------------------------
    # Summary
    # ---------------------------------------------------------

    summary_path = (
        OUT_ROOT
        / "normalization_audit_v1_summary.txt"
    )

    fmt_counts = Counter(
        r["CanonicalFamily"]
        for r in results
    )

    category_counts = Counter(
        r["Category"]
        for r in results
    )

    dimension_counts = Counter(
        (
            r["OutputWidth"],
            r["OutputHeight"],
        )
        for r in results
    )

    large_category_counts = Counter(
        r["Category"]
        for r in large_rows
    )

    bc1_category_counts = Counter(
        r["Category"]
        for r in bc1_large_rows
    )

    total_ddt_bytes = sum(
        r["DDTBytes"]
        for r in results
        if r["DDTNonEmpty"]
    )

    average_ddt = (
        total_ddt_bytes
        / max(
            1,
            sum(
                r["DDTNonEmpty"]
                for r in results
            ),
        )
    )

    with summary_path.open(
        "w",
        encoding="utf-8",
    ) as f:

        f.write(
            "AoM:EE NORMALIZATION AUDIT V1\n"
        )
        f.write(
            "=============================\n\n"
        )

        f.write(
            f"Master manifest rows: "
            f"{len(master_rows)}\n"
        )

        f.write(
            f"Unified audit rows: "
            f"{len(results)}\n"
        )

        f.write(
            f"Production PBRify TGAs: "
            f"{len(production_tgas)}\n"
        )

        f.write(
            f"Authoritative BTIs: "
            f"{len(bti_index)}\n"
        )

        f.write("\nFORMAT DISTRIBUTION\n")
        f.write("-------------------\n")

        for name, count in fmt_counts.most_common():
            f.write(
                f"{name:15} {count:6}\n"
            )

        f.write("\nCATEGORY DISTRIBUTION\n")
        f.write("--------------------\n")

        for name, count in category_counts.most_common():
            f.write(
                f"{name:25} {count:6}\n"
            )

        f.write("\nOUTPUT SIZE BANDS\n")
        f.write("-----------------\n")

        f.write(
            f"1024+ max dimension : "
            f"{len(large_rows)}\n"
        )

        f.write(
            f"2048+ max dimension : "
            f"{sum(r['Large2048Plus'] for r in results)}\n"
        )

        f.write(
            f"4096+ max dimension : "
            f"{len(huge_rows)}\n"
        )

        f.write(
            f"1024×1024 outputs   : "
            f"{sum(r['Square1024Output'] for r in results)}\n"
        )

        f.write("\nBC1 LARGE OUTPUTS\n")
        f.write("-----------------\n")

        f.write(
            f"BC1 with max dimension >=1024: "
            f"{len(bc1_large_rows)}\n"
        )

        f.write(
            f"BC1 1024×1024: "
            f"{len(bc1_1024_rows)}\n"
        )

        f.write("\nLARGE OUTPUTS BY CATEGORY\n")
        f.write("--------------------------\n")

        for name, count in (
            large_category_counts.most_common()
        ):
            f.write(
                f"{name:25} {count:6}\n"
            )

        f.write("\nLARGE BC1 OUTPUTS BY CATEGORY\n")
        f.write("-----------------------------\n")

        for name, count in (
            bc1_category_counts.most_common()
        ):
            f.write(
                f"{name:25} {count:6}\n"
            )

        f.write("\nMOST COMMON OUTPUT DIMENSIONS\n")
        f.write("----------------------------\n")

        for (width, height), count in (
            dimension_counts.most_common(40)
        ):
            f.write(
                f"{width:5} x {height:<5} "
                f"{count:6}\n"
            )

        f.write("\nCURRENT DDT OUTPUT\n")
        f.write("------------------\n")

        f.write(
            f"Non-empty DDT files: "
            f"{sum(r['DDTNonEmpty'] for r in results)}\n"
        )

        f.write(
            f"Total non-empty DDT bytes: "
            f"{total_ddt_bytes:,}\n"
        )

        f.write(
            f"Average non-empty DDT bytes: "
            f"{average_ddt:,.1f}\n"
        )

        f.write("\nNOTES\n")
        f.write("-----\n")
        f.write(
            "This audit is READ-ONLY.\n"
        )
        f.write(
            "It does not modify extracted, processed, "
            "input, models, or the clean game.\n"
        )
        f.write(
            "It intentionally does NOT choose a final "
            "resolution or compression policy.\n"
        )
        f.write(
            "The 4x output dimensions are measured from "
            "the actual PBRify TGA when available.\n"
        )
        f.write(
            "DDTBytes reflect the current local DDT output "
            "when that output exists.\n"
        )

    # ---------------------------------------------------------
    # Console summary
    # ---------------------------------------------------------

    print()
    print("============================================")
    print("NORMALIZATION AUDIT COMPLETE")
    print("============================================")
    print()

    print(
        f"Audit rows                 : "
        f"{len(results)}"
    )

    print(
        f"PBRify TGAs                : "
        f"{len(production_tgas)}"
    )

    print(
        f"Authoritative BTIs         : "
        f"{len(bti_index)}"
    )

    print()

    print(
        f"1024+ outputs              : "
        f"{len(large_rows)}"
    )

    print(
        f"2048+ outputs              : "
        f"{sum(r['Large2048Plus'] for r in results)}"
    )

    print(
        f"4096+ outputs              : "
        f"{len(huge_rows)}"
    )

    print(
        f"1024x1024 outputs          : "
        f"{sum(r['Square1024Output'] for r in results)}"
    )

    print()

    print(
        f"Large BC1 outputs          : "
        f"{len(bc1_large_rows)}"
    )

    print(
        f"BC1 1024x1024 outputs      : "
        f"{len(bc1_1024_rows)}"
    )

    print()

    print(
        "Reports:"
    )

    print(
        f"  {full_csv}"
    )

    print(
        f"  {summary_path}"
    )


if __name__ == "__main__":
    main()