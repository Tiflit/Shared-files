from __future__ import annotations

import argparse
import csv
import hashlib
import os
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
EXTRACTOR = ROOT / r"tools\TextureExtractor.exe"

OUT_ROOT = ROOT / r"reports\ddt_full_verification_v1"
REPORT_PATH = OUT_ROOT / "ddt_full_verification_v1.csv"
SUMMARY_PATH = OUT_ROOT / "ddt_full_verification_v1_summary.txt"
CHECKPOINT_PATH = OUT_ROOT / "ddt_full_verification_v1_checkpoint.txt"

SCRATCH_ROOT = ROOT / r"tests\ddt_full_verification_stage"

EXPECTED_TOTAL = 7487
EXCLUDED_RELATIVE = (
    r"textures\icons\special c black tortoise icon.tga"
)
EXPECTED_PRODUCTION = 7486


CSV_FIELDS = [
    "RelativePath",
    "DDTRelativePath",

    "ManifestStatus",
    "OriginalBTIFormat",
    "CompileFormat",
    "FallbackUsed",
    "Provisional",

    "ExpectedTgaSHA256",
    "ActualTgaSHA256",
    "ExpectedDDTSHA256",
    "ActualDDTSHA256",

    "ExpectedDDTBytes",
    "ActualDDTBytes",

    "TgaExists",
    "DDTExists",

    "DDTMagic",
    "DDTWidth",
    "DDTHeight",
    "DDTHeaderSize",

    "ExpectedWidth",
    "ExpectedHeight",

    "ExtractorExitCode",
    "ExtractorExitHex",
    "ExtractorTimedOut",

    "ExtractedTgaExists",
    "ExtractedBTIExists",

    "ExtractedTgaWidth",
    "ExtractedTgaHeight",
    "ExtractedTgaBPP",
    "ExtractedTgaDescriptor",

    "ExtractedBTIFormat",
    "ExtractedBTIAlpha",
    "ExtractedBTINoAlphaTest",
    "ExtractedBTINoMip",
    "ExtractedBTIClamp",

    "ShaPASS",
    "SizePASS",
    "MagicPASS",
    "DDTDimensionsPASS",
    "ExtractDimensionsPASS",
    "ExtractFormatPASS",
    "ExtractBTIPASS",

    "OVERALLPASS",

    "FailureStage",
    "FailureReason",
    "ExtractorOutput",
    "ElapsedSeconds",
]


def normalize_path(value: str) -> str:
    return (
        value.replace("/", "\\")
        .strip()
        .lstrip("\\")
    )


def key_path(value: str) -> str:
    return normalize_path(value).lower()


def safe_int(value: str, default: int = 0) -> int:
    try:
        return int(float(value))
    except Exception:
        return default


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()

    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)

            if not chunk:
                break

            h.update(chunk)

    return h.hexdigest().lower()


def read_tga_header(path: Path) -> dict:
    data = path.read_bytes()

    if len(data) < 18:
        raise ValueError(
            f"TGA shorter than 18 bytes: {path}"
        )

    width = int.from_bytes(
        data[12:14],
        "little",
    )

    height = int.from_bytes(
        data[14:16],
        "little",
    )

    bpp = data[16]
    descriptor = data[17]

    return {
        "width": width,
        "height": height,
        "bpp": bpp,
        "descriptor": descriptor,
        "alpha_bits": descriptor & 0x0F,
        "image_type": data[2],
        "bytes": len(data),
    }


def read_ddt_header(path: Path) -> dict:
    with path.open("rb") as f:
        data = f.read(64)

    if len(data) < 20:
        raise ValueError(
            f"DDT shorter than 20 bytes: {path}"
        )

    magic = data[0:4]

    width = int.from_bytes(
        data[8:12],
        "little",
    )

    height = int.from_bytes(
        data[12:16],
        "little",
    )

    header_size = int.from_bytes(
        data[16:20],
        "little",
    )

    return {
        "magic": magic.decode(
            "ascii",
            errors="replace",
        ),
        "magic_bytes": magic,
        "width": width,
        "height": height,
        "header_size": header_size,
    }


def parse_bti(path: Path) -> dict:
    raw = path.read_bytes()

    text = raw.decode(
        "utf-8-sig",
        errors="replace",
    )

    def match_value(pattern: str) -> str:
        m = re.search(
            pattern,
            text,
            re.IGNORECASE,
        )

        if not m:
            return ""

        return m.group(1)

    fmt = match_value(
        r"\bfmt\s*=\s*([A-Za-z0-9_]+)"
    ).upper()

    alpha = match_value(
        r"\balpha\s*=\s*(\d+)"
    )

    flags = set()

    for token in (
        "noalphatest",
        "nomip",
        "clamp",
    ):
        if re.search(
            rf"(^|\s){re.escape(token)}(\s|$)",
            text,
            re.IGNORECASE,
        ):
            flags.add(token.lower())

    return {
        "format": fmt,
        "alpha": alpha,
        "noalphatest": (
            "noalphatest" in flags
        ),
        "nomip": (
            "nomip" in flags
        ),
        "clamp": (
            "clamp" in flags
        ),
    }


def hex_exit_code(code: int | None) -> str:
    if code is None:
        return ""

    unsigned = code & 0xFFFFFFFF

    return f"0x{unsigned:08X}"


def load_manifest() -> dict[str, dict]:
    if not MANIFEST_PATH.is_file():
        raise SystemExit(
            f"Compile manifest not found:\n"
            f"{MANIFEST_PATH}"
        )

    with MANIFEST_PATH.open(
        "r",
        encoding="utf-8-sig",
        newline="",
    ) as f:
        rows = list(csv.DictReader(f))

    if len(rows) != EXPECTED_PRODUCTION:
        raise SystemExit(
            f"Expected {EXPECTED_PRODUCTION} compile-manifest rows, "
            f"found {len(rows)}."
        )

    result = {}

    for row in rows:
        relative = normalize_path(
            row.get("RelativePath", "")
        )

        if not relative:
            raise SystemExit(
                "Compile manifest contains a blank RelativePath."
            )

        key = key_path(relative)

        if key in result:
            raise SystemExit(
                f"Duplicate compile-manifest path: {relative}"
            )

        result[key] = row

    return result


def build_expected_tga_index() -> dict[str, Path]:
    tgas = sorted(
        PBRIFY_ROOT.rglob("*.tga")
    )

    if len(tgas) != EXPECTED_TOTAL:
        raise SystemExit(
            f"Expected {EXPECTED_TOTAL} PBRify TGAs, "
            f"found {len(tgas)}."
        )

    result = {}

    for path in tgas:
        relative = normalize_path(
            str(
                path.relative_to(
                    PBRIFY_ROOT
                )
            )
        )

        key = key_path(relative)

        if key in result:
            raise SystemExit(
                f"Duplicate PBRify TGA path: {relative}"
            )

        result[key] = path

    return result


def build_ddt_index() -> dict[str, Path]:
    ddds = sorted(
        DDT_ROOT.rglob("*.ddt")
    )

    result = {}

    for path in ddds:
        relative = normalize_path(
            str(
                path.relative_to(
                    DDT_ROOT
                )
            )
        )

        key = key_path(relative)

        if key in result:
            raise SystemExit(
                f"Duplicate DDT path: {relative}"
            )

        result[key] = path

    return result


def read_existing_results() -> dict[str, dict]:
    if not REPORT_PATH.is_file():
        return {}

    try:
        with REPORT_PATH.open(
            "r",
            encoding="utf-8-sig",
            newline="",
        ) as f:
            rows = list(csv.DictReader(f))
    except Exception:
        return {}

    result = {}

    for row in rows:
        key = key_path(
            row.get(
                "RelativePath",
                "",
            )
        )

        if not key:
            continue

        result[key] = row

    return result


def write_row(
    writer: csv.DictWriter,
    handle,
    row: dict,
) -> None:

    normalized = {
        key: row.get(key, "")
        for key in CSV_FIELDS
    }

    writer.writerow(normalized)
    handle.flush()


def prepare_report(
    resume: bool,
) -> tuple[dict[str, dict], object, csv.DictWriter]:

    OUT_ROOT.mkdir(
        parents=True,
        exist_ok=True,
    )

    previous = {}

    if resume:
        previous = read_existing_results()

    mode = (
        "a"
        if resume and REPORT_PATH.exists()
        else "w"
    )

    handle = REPORT_PATH.open(
        mode,
        encoding="utf-8-sig",
        newline="",
    )

    writer = csv.DictWriter(
        handle,
        fieldnames=CSV_FIELDS,
    )

    if mode == "w":
        writer.writeheader()
        handle.flush()
    else:
        # Existing report already has a header.
        pass

    return previous, handle, writer


def invoke_extractor(
    ddt_path: Path,
    out_tga: Path,
    timeout_seconds: int,
) -> tuple[int | None, bool, str]:

    try:

        result = subprocess.run(
            [
                str(EXTRACTOR),
                "-i",
                str(ddt_path),
                "-o",
                str(out_tga),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_seconds,
            creationflags=(
                getattr(
                    subprocess,
                    "CREATE_NO_WINDOW",
                    0,
                )
            ),
        )

        return (
            result.returncode,
            False,
            result.stdout or "",
        )

    except subprocess.TimeoutExpired as exc:

        output = ""

        if exc.stdout:
            if isinstance(exc.stdout, bytes):
                output = exc.stdout.decode(
                    "utf-8",
                    errors="replace",
                )
            else:
                output = str(exc.stdout)

        return (
            None,
            True,
            output,
        )


def make_scratch_paths(
    index: int,
) -> tuple[Path, Path]:

    stem = (
        SCRATCH_ROOT
        / f"{index:05d}"
    )

    return (
        stem.with_suffix(".tga"),
        stem.with_suffix(".bti"),
    )


def clean_scratch_file(path: Path) -> None:
    try:
        if path.is_file():
            path.unlink()
    except Exception:
        pass


def verify_one(
    index: int,
    relative: str,
    tga_path: Path,
    ddt_path: Path,
    manifest: dict,
    timeout_seconds: int,
) -> dict:

    started = time.perf_counter()

    key = key_path(relative)

    row = {
        "RelativePath": relative,
        "DDTRelativePath": (
            str(
                Path(relative).with_suffix(".ddt")
            ).replace("/", "\\")
        ),

        "ManifestStatus":
            manifest.get("Status", ""),

        "OriginalBTIFormat":
            manifest.get(
                "OriginalBTIFormat",
                "",
            ),

        "CompileFormat":
            manifest.get(
                "CompileFormat",
                "",
            ),

        "FallbackUsed":
            manifest.get(
                "FallbackUsed",
                "",
            ),

        "Provisional":
            manifest.get(
                "Provisional",
                "",
            ),

        "ExpectedTgaSHA256":
            manifest.get(
                "SourceTgaSHA256",
                "",
            ),

        "ActualTgaSHA256": "",

        "ExpectedDDTSHA256":
            manifest.get(
                "DDTSHA256",
                "",
            ),

        "ActualDDTSHA256": "",

        "ExpectedDDTBytes":
            manifest.get(
                "DDTBytes",
                "",
            ),

        "ActualDDTBytes": "",

        "TgaExists":
            tga_path.is_file(),

        "DDTExists":
            ddt_path.is_file(),

        "DDTMagic": "",
        "DDTWidth": "",
        "DDTHeight": "",
        "DDTHeaderSize": "",

        "ExpectedWidth": "",
        "ExpectedHeight": "",

        "ExtractorExitCode": "",
        "ExtractorExitHex": "",
        "ExtractorTimedOut": "False",

        "ExtractedTgaExists": "False",
        "ExtractedBTIExists": "False",

        "ExtractedTgaWidth": "",
        "ExtractedTgaHeight": "",
        "ExtractedTgaBPP": "",
        "ExtractedTgaDescriptor": "",

        "ExtractedBTIFormat": "",
        "ExtractedBTIAlpha": "",
        "ExtractedBTINoAlphaTest": "",
        "ExtractedBTINoMip": "",
        "ExtractedBTIClamp": "",

        "ShaPASS": "False",
        "SizePASS": "False",
        "MagicPASS": "False",
        "DDTDimensionsPASS": "False",
        "ExtractDimensionsPASS": "False",
        "ExtractFormatPASS": "False",
        "ExtractBTIPASS": "False",

        "OVERALLPASS": "False",

        "FailureStage": "",
        "FailureReason": "",

        "ExtractorOutput": "",

        "ElapsedSeconds": "",
    }

    try:

        # -----------------------------------------------------
        # Required files.
        # -----------------------------------------------------

        if not tga_path.is_file():
            row["FailureStage"] = "INPUT"
            row["FailureReason"] = (
                "Expected PBRify TGA missing."
            )
            return finalize_row(
                row,
                started,
            )

        if not ddt_path.is_file():
            row["FailureStage"] = "INPUT"
            row["FailureReason"] = (
                "Expected production DDT missing."
            )
            return finalize_row(
                row,
                started,
            )

        # -----------------------------------------------------
        # PBRify TGA dimensions.
        # -----------------------------------------------------

        source_tga = read_tga_header(
            tga_path
        )

        row["ExpectedWidth"] = (
            source_tga["width"]
        )

        row["ExpectedHeight"] = (
            source_tga["height"]
        )

        # -----------------------------------------------------
        # TGA SHA.
        # -----------------------------------------------------

        actual_tga_sha = sha256_file(
            tga_path
        )

        row["ActualTgaSHA256"] = (
            actual_tga_sha
        )

        expected_tga_sha = (
            row["ExpectedTgaSHA256"]
            .strip()
            .lower()
        )

        row["ShaPASS"] = (
            expected_tga_sha != ""
            and actual_tga_sha
            == expected_tga_sha
        )

        if not row["ShaPASS"]:
            row["FailureStage"] = "SOURCE_TGA_HASH"
            row["FailureReason"] = (
                "PBRify TGA SHA-256 differs "
                "from compile manifest."
            )
            return finalize_row(
                row,
                started,
            )

        # -----------------------------------------------------
        # DDT size/hash.
        # -----------------------------------------------------

        actual_ddt_size = (
            ddt_path.stat().st_size
        )

        row["ActualDDTBytes"] = (
            actual_ddt_size
        )

        expected_ddt_size = safe_int(
            row["ExpectedDDTBytes"]
        )

        row["SizePASS"] = (
            expected_ddt_size > 0
            and actual_ddt_size
            == expected_ddt_size
            and actual_ddt_size
            > 24
        )

        actual_ddt_sha = sha256_file(
            ddt_path
        )

        row["ActualDDTSHA256"] = (
            actual_ddt_sha
        )

        expected_ddt_sha = (
            row["ExpectedDDTSHA256"]
            .strip()
            .lower()
        )

        sha_pass = (
            expected_ddt_sha != ""
            and actual_ddt_sha
            == expected_ddt_sha
        )

        row["ShaPASS"] = (
            bool(row["ShaPASS"])
            and sha_pass
        )

        if not row["SizePASS"]:
            row["FailureStage"] = "DDT_SIZE"
            row["FailureReason"] = (
                "DDT size differs from "
                "compile manifest or is invalid."
            )

            # Continue to structural verification.
        }

        # -----------------------------------------------------
        # DDT structural header.
        # -----------------------------------------------------

        ddt_header = read_ddt_header(
            ddt_path
        )

        row["DDTMagic"] = (
            ddt_header["magic"]
        )

        row["DDTWidth"] = (
            ddt_header["width"]
        )

        row["DDTHeight"] = (
            ddt_header["height"]
        )

        row["DDTHeaderSize"] = (
            ddt_header["header_size"]
        )

        row["MagicPASS"] = (
            ddt_header["magic_bytes"]
            == b"RTS3"
        )

        row["DDTDimensionsPASS"] = (
            row["MagicPASS"]
            and ddt_header["width"]
            == source_tga["width"]
            and ddt_header["height"]
            == source_tga["height"]
            and ddt_header["header_size"]
            >= 20
            and ddt_header["header_size"]
            < actual_ddt_size
        )

        if not row["MagicPASS"]:
            row["FailureStage"] = "DDT_HEADER"
            row["FailureReason"] = (
                "Missing RTS3 DDT signature."
            )
            return finalize_row(
                row,
                started,
            )

        # -----------------------------------------------------
        # Official AoM TextureExtractor round-trip.
        # -----------------------------------------------------

        out_tga, out_bti = make_scratch_paths(
            index
        )

        out_tga.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        clean_scratch_file(out_tga)
        clean_scratch_file(out_bti)

        try:

            (
                exit_code,
                timed_out,
                extractor_output,
            ) = invoke_extractor(
                ddt_path,
                out_tga,
                timeout_seconds,
            )

            row["ExtractorExitCode"] = (
                ""
                if exit_code is None
                else str(exit_code)
            )

            row["ExtractorExitHex"] = (
                hex_exit_code(exit_code)
            )

            row["ExtractorTimedOut"] = (
                str(timed_out)
            )

            # Preserve only a compact diagnostic excerpt.
            row["ExtractorOutput"] = (
                extractor_output[-4000:]
            )

            row["ExtractedTgaExists"] = str(
                out_tga.is_file()
            )

            row["ExtractedBTIExists"] = str(
                out_bti.is_file()
            )

            if timed_out:
                row["FailureStage"] = "EXTRACTOR"
                row["FailureReason"] = (
                    f"TextureExtractor exceeded "
                    f"{timeout_seconds}s."
                )
                return finalize_row(
                    row,
                    started,
                )

            if exit_code != 0:
                row["FailureStage"] = "EXTRACTOR"
                row["FailureReason"] = (
                    "TextureExtractor returned "
                    f"exit code {exit_code}."
                )
                return finalize_row(
                    row,
                    started,
                )

            if not out_tga.is_file():
                row["FailureStage"] = "EXTRACTOR_OUTPUT"
                row["FailureReason"] = (
                    "TextureExtractor returned success "
                    "but did not create a TGA."
                )
                return finalize_row(
                    row,
                    started,
                )

            if not out_bti.is_file():
                row["FailureStage"] = "EXTRACTOR_OUTPUT"
                row["FailureReason"] = (
                    "TextureExtractor returned success "
                    "but did not create a BTI."
                )
                return finalize_row(
                    row,
                    started,
                )

            # -------------------------------------------------
            # Extracted TGA sanity.
            # -------------------------------------------------

            extracted_tga = read_tga_header(
                out_tga
            )

            row["ExtractedTgaWidth"] = (
                extracted_tga["width"]
            )

            row["ExtractedTgaHeight"] = (
                extracted_tga["height"]
            )

            row["ExtractedTgaBPP"] = (
                extracted_tga["bpp"]
            )

            row["ExtractedTgaDescriptor"] = (
                extracted_tga["descriptor"]
            )

            row["ExtractDimensionsPASS"] = (
                extracted_tga["width"]
                == source_tga["width"]
                and
                extracted_tga["height"]
                == source_tga["height"]
                and
                extracted_tga["bpp"]
                == 32
            )

            if not row["ExtractDimensionsPASS"]:
                row["FailureStage"] = "EXTRACTED_TGA"
                row["FailureReason"] = (
                    "Extracted TGA dimensions or "
                    "32-bit pixel format differ "
                    "from the PBRify source."
                )
                return finalize_row(
                    row,
                    started,
                )

            # -------------------------------------------------
            # Extracted BTI sanity.
            # -------------------------------------------------

            extracted_bti = parse_bti(
                out_bti
            )

            row["ExtractedBTIFormat"] = (
                extracted_bti["format"]
            )

            row["ExtractedBTIAlpha"] = (
                extracted_bti["alpha"]
            )

            row["ExtractedBTINoAlphaTest"] = str(
                extracted_bti["noalphatest"]
            )

            row["ExtractedBTINoMip"] = str(
                extracted_bti["nomip"]
            )

            row["ExtractedBTIClamp"] = str(
                extracted_bti["clamp"]
            )

            expected_format = (
                row["CompileFormat"]
                .strip()
                .upper()
            )

            row["ExtractFormatPASS"] = (
                expected_format != ""
                and
                extracted_bti["format"]
                == expected_format
            )

            # Compare alpha when both representations
            # provide an explicit value.
            #
            # The TextureExtractor can legitimately omit
            # metadata which isn't represented explicitly in
            # the generated BTI, so absence is not treated
            # as a failure.
            original_bti_alpha = (
                manifest.get(
                    "BTIAlphaBits",
                    "",
                )
                .strip()
            )

            alpha_ok = True

            if (
                original_bti_alpha
                and extracted_bti["alpha"]
            ):
                alpha_ok = (
                    original_bti_alpha
                    == extracted_bti["alpha"]
                )

            row["ExtractBTIPASS"] = (
                row["ExtractFormatPASS"]
                and alpha_ok
            )

            if not row["ExtractBTIPASS"]:
                row["FailureStage"] = "EXTRACTED_BTI"
                row["FailureReason"] = (
                    "Regenerated BTI does not match "
                    "the compile format/metadata."
                )
                return finalize_row(
                    row,
                    started,
                )

            # -------------------------------------------------
            # Complete pass.
            # -------------------------------------------------

            row["OVERALLPASS"] = (
                row["ShaPASS"]
                and row["SizePASS"]
                and row["MagicPASS"]
                and row["DDTDimensionsPASS"]
                and row["ExtractDimensionsPASS"]
                and row["ExtractFormatPASS"]
                and row["ExtractBTIPASS"]
            )

            if not row["OVERALLPASS"]:
                row["FailureStage"] = "VALIDATION"
                row["FailureReason"] = (
                    "One or more independent "
                    "validation gates failed."
                )

            return finalize_row(
                row,
                started,
            )

        finally:

            clean_scratch_file(
                out_tga
            )

            clean_scratch_file(
                out_bti
            )

    except Exception as exc:

        row["FailureStage"] = (
            row["FailureStage"]
            or "EXCEPTION"
        )

        row["FailureReason"] = (
            f"{type(exc).__name__}: {exc}"
        )

        return finalize_row(
            row,
            started,
        )


def finalize_row(
    row: dict,
    started: float,
) -> dict:

    row["OVERALLPASS"] = str(
        bool(
            row.get("OVERALLPASS") is True
            or (
                str(
                    row.get(
                        "OVERALLPASS",
                        "False",
                    )
                ).lower()
                == "true"
            )
        )
    )

    row["ElapsedSeconds"] = round(
        time.perf_counter() - started,
        3,
    )

    return row


def write_checkpoint(last_relative: str) -> None:
    CHECKPOINT_PATH.write_text(
        last_relative,
        encoding="utf-8",
    )


def main() -> int:

    parser = argparse.ArgumentParser(
        description=(
            "Exhaustively verify every generated "
            "AoM:EE production DDT."
        )
    )

    parser.add_argument(
        "--resume",
        action="store_true",
        help=(
            "Resume from existing CSV and skip "
            "already-PASSed textures."
        ),
    )

    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help=(
            "Maximum TextureExtractor runtime "
            "per DDT in seconds."
        ),
    )

    args = parser.parse_args()

    print("============================================")
    print("AoM:EE FULL DDT VERIFICATION V1")
    print("============================================")
    print()

    required = [
        PBRIFY_ROOT,
        DDT_ROOT,
        MANIFEST_PATH,
        EXTRACTOR,
    ]

    for path in required:
        if not path.exists():
            raise SystemExit(
                f"Required path not found:\n{path}"
            )

    if args.timeout <= 0:
        raise SystemExit(
            "--timeout must be greater than zero."
        )

    print(
        f"PBRify root       : {PBRIFY_ROOT}"
    )

    print(
        f"DDT root          : {DDT_ROOT}"
    )

    print(
        f"Manifest          : {MANIFEST_PATH}"
    )

    print(
        f"TextureExtractor  : {EXTRACTOR}"
    )

    print(
        f"Extractor timeout : {args.timeout}s"
    )

    print()

    manifest_index = load_manifest()
    tga_index = build_expected_tga_index()
    ddt_index = build_ddt_index()

    print(
        f"PBRify TGAs       : {len(tga_index)}"
    )

    print(
        f"Compile manifest  : {len(manifest_index)}"
    )

    print(
        f"Production DDTs   : {len(ddt_index)}"
    )

    print()

    # ---------------------------------------------------------
    # Verify complete DDT inventory before extraction.
    # ---------------------------------------------------------

    expected_ddt_keys = {
        key_path(
            str(
                Path(relative)
                .with_suffix(".ddt")
            )
        )
        for relative in tga_index
        if key_path(relative)
        != key_path(EXCLUDED_RELATIVE)
    }

    actual_ddt_keys = set(
        ddt_index.keys()
    )

    missing = sorted(
        expected_ddt_keys - actual_ddt_keys
    )

    unexpected = sorted(
        actual_ddt_keys - expected_ddt_keys
    )

    if missing:
        print(
            f"INVENTORY FAILURE: "
            f"{len(missing)} missing DDTs"
        )

        for path in missing[:50]:
            print(
                f"  MISSING: {path}"
            )

        return 2

    if unexpected:
        print(
            f"INVENTORY FAILURE: "
            f"{len(unexpected)} unexpected DDTs"
        )

        for path in unexpected[:50]:
            print(
                f"  UNEXPECTED: {path}"
            )

        return 2

    if len(expected_ddt_keys) != EXPECTED_PRODUCTION:
        raise SystemExit(
            "Internal expected inventory count mismatch: "
            f"{len(expected_ddt_keys)}"
        )

    if len(ddt_index) != EXPECTED_PRODUCTION:
        raise SystemExit(
            "Production DDT count mismatch: "
            f"{len(ddt_index)}"
        )

    print(
        "Inventory/path gate: PASS"
    )
    print()

    # ---------------------------------------------------------
    # Check expected manifest coverage.
    # ---------------------------------------------------------

    manifest_missing = sorted(
        expected_ddt_keys
        - set(manifest_index.keys())
    )

    manifest_unexpected = sorted(
        set(manifest_index.keys())
        - expected_ddt_keys
    )

    if manifest_missing or manifest_unexpected:
        print(
            "COMPILE MANIFEST COVERAGE: FAIL"
        )

        print(
            f"Missing rows    : "
            f"{len(manifest_missing)}"
        )

        print(
            f"Unexpected rows : "
            f"{len(manifest_unexpected)}"
        )

        return 2

    print(
        "Compile-manifest coverage: PASS"
    )
    print()

    # ---------------------------------------------------------
    # Prepare report.
    # ---------------------------------------------------------

    previous, handle, writer = prepare_report(
        args.resume
    )

    scratch_exists = (
        SCRATCH_ROOT.exists()
    )

    if scratch_exists:
        # Scratch files from an interrupted verification
        # are safe to delete. Production files are untouched.
        shutil.rmtree(
            SCRATCH_ROOT,
            ignore_errors=True,
        )

    SCRATCH_ROOT.mkdir(
        parents=True,
        exist_ok=True,
    )

    passed = 0
    failed = 0
    skipped = 0

    processed = 0

    started_total = time.perf_counter()

    try:

        ordered_relatives = sorted(
            tga_index.keys()
        )

        for index, tga_key in enumerate(
            ordered_relatives,
            start=1,
        ):

            if (
                tga_key
                == key_path(
                    EXCLUDED_RELATIVE
                )
            ):
                continue

            relative = normalize_path(
                tga_index[tga_key]
                .relative_to(PBRIFY_ROOT)
                .as_posix()
            )

            ddt_relative = str(
                Path(relative).with_suffix(
                    ".ddt"
                )
            ).replace("/", "\\")

            ddt_key = key_path(
                ddt_relative
            )

            ddt_path = ddt_index[
                ddt_key
            ]

            manifest = manifest_index[
                ddt_key.replace(
                    ".ddt",
                    ".tga",
                )
                if ddt_key.endswith(
                    ".ddt"
                )
                else ddt_key
            ] if ddt_key.replace(
                ".ddt",
                ".tga"
            ) in manifest_index else None

            # The previous expression is intentionally followed
            # by an explicit fallback because compile manifests
            # use .tga paths.
            if manifest is None:
                manifest = manifest_index[
                    key_path(relative)
                ]

            # -------------------------------------------------
            # Resume support.
            # -------------------------------------------------

            if args.resume and tga_key in previous:

                previous_row = previous[
                    tga_key
                ]

                if (
                    str(
                        previous_row.get(
                            "OVERALLPASS",
                            ""
                        )
                    ).lower()
                    == "true"
                ):

                    skipped += 1

                    if (
                        skipped == 1
                        or skipped % 250 == 0
                    ):
                        print(
                            f"[{index}/{EXPECTED_PRODUCTION}] "
                            f"RESUME SKIP: {relative}"
                        )

                    continue

            print(
                f"[{index}/{EXPECTED_PRODUCTION}] "
                f"VERIFY: {relative}"
            )

            row = verify_one(
                index=index,
                relative=relative,
                tga_path=tga_index[tga_key],
                ddt_path=ddt_path,
                manifest=manifest,
                timeout_seconds=args.timeout,
            )

            write_row(
                writer,
                handle,
                row,
            )

            write_checkpoint(
                relative
            )

            processed += 1

            is_pass = (
                str(
                    row["OVERALLPASS"]
                ).lower()
                == "true"
            )

            if is_pass:
                passed += 1
            else:
                failed += 1

                print(
                    "    >>> FAIL: "
                    f"{row['FailureStage']} "
                    f"{row['FailureReason']}"
                )

            if (
                processed % 100 == 0
            ):
                elapsed = (
                    time.perf_counter()
                    - started_total
                )

                print(
                    "    Progress: "
                    f"{processed} processed, "
                    f"{passed} PASS, "
                    f"{failed} FAIL, "
                    f"{elapsed:.1f}s elapsed"
                )

    finally:

        handle.close()

        shutil.rmtree(
            SCRATCH_ROOT,
            ignore_errors=True,
        )

    # ---------------------------------------------------------
    # Final summary.
    # ---------------------------------------------------------

    total_verification_targets = (
        EXPECTED_PRODUCTION
    )

    completed = passed + failed

    final_pass = (
        completed == total_verification_targets
        and
        passed == total_verification_targets
        and
        failed == 0
        and
        skipped == 0
    )

    total_elapsed = (
        time.perf_counter()
        - started_total
    )

    summary = [
        "AoM:EE FULL DDT VERIFICATION V1",
        "================================",
        "",
        f"Expected production DDTs: {EXPECTED_PRODUCTION}",
        f"Processed this run:       {processed}",
        f"Resumed/skipped PASS:     {skipped}",
        f"PASS:                     {passed}",
        f"FAIL:                     {failed}",
        f"Completed:                {completed}",
        f"Total elapsed seconds:    {total_elapsed:.3f}",
        "",
        "INVENTORY",
        "---------",
        f"Expected DDT paths:       {len(expected_ddt_keys)}",
        f"Actual DDT paths:         {len(ddt_index)}",
        f"Missing DDTs:             {len(missing)}",
        f"Unexpected DDTs:          {len(unexpected)}",
        "",
        "VERIFICATION GATES",
        "------------------",
        "1. Production DDT inventory/path completeness",
        "2. Compile-manifest coverage",
        "3. PBRify source TGA SHA-256",
        "4. Generated DDT SHA-256",
        "5. Generated DDT byte size",
        "6. RTS3 DDT signature",
        "7. Embedded DDT width/height",
        "8. DDT dimensions vs PBRify TGA",
        "9. Official TextureExtractor decode",
        "10. Extracted TGA dimensions",
        "11. Extracted TGA 32-bit format",
        "12. Regenerated BTI exists",
        "13. Regenerated BTI format",
        "14. Regenerated BTI alpha metadata when available",
        "",
        "NOTE",
        "----",
        "This verification never modifies the production DDTs.",
        "TextureExtractor output is temporary and deleted after each texture.",
        "Black Tortoise is excluded by the production policy.",
        "Blue Lagoon is expected to report CompileFormat=BC2.",
        "",
        (
            "FULL DDT VERIFICATION: PASS"
            if final_pass
            else
            "FULL DDT VERIFICATION: FAIL"
        ),
    ]

    SUMMARY_PATH.write_text(
        "\n".join(summary)
        + "\n",
        encoding="utf-8",
    )

    print()
    print("============================================")
    print("FULL DDT VERIFICATION RESULT")
    print("============================================")
    print()
    print(
        f"Expected DDTs : {EXPECTED_PRODUCTION}"
    )
    print(
        f"Processed      : {processed}"
    )
    print(
        f"Skipped PASS   : {skipped}"
    )
    print(
        f"PASS           : {passed}"
    )
    print(
        f"FAIL           : {failed}"
    )
    print()

    print(
        f"Report         : {REPORT_PATH}"
    )

    print(
        f"Summary        : {SUMMARY_PATH}"
    )

    if args.resume:
        print(
            "Resume mode    : ENABLED"
        )

    print()

    if final_pass:
        print(
            "FULL DDT VERIFICATION: PASS"
        )
        return 0

    print(
        "FULL DDT VERIFICATION: FAIL"
    )

    return 1


if __name__ == "__main__":
    sys.exit(
        main()
    )