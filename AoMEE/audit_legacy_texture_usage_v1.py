from __future__ import annotations

import csv
import re
from pathlib import Path


ROOT = Path(r"D:\AI_upscaling\AoMEE")

SEARCH_ROOTS = [
    ROOT / r"Age of Mythology",
    ROOT / r"extracted",
    ROOT / r"reports\materials_xml",
]

OUT_DIR = ROOT / r"reports\legacy_texture_usage_v1"
OUT_CSV = OUT_DIR / "legacy_texture_usage_v1.csv"
OUT_SUMMARY = OUT_DIR / "legacy_texture_usage_v1_summary.txt"


CANDIDATES = {
    "black_tortoise": {
        "display": "Black Tortoise",
        "variants": [
            r"textures\icons\special c black tortoise icon.ddt",
            r"textures\icons\special c black tortoise icon.tga",
            r"textures\icons\special c black tortoise icon.bti",
            "special c black tortoise icon",
            "black tortoise",
        ],
    },
    "griffon": {
        "display": "Gryphon / Griffon",
        "variants": [
            r"textures\special g griffon map.ddt",
            r"textures\special g griffon map.tga",
            r"textures\special g griffon map.bti",
            "special g griffon map",
            "griffon",
            "gryphon",
        ],
    },
}


# Avoid spending time scanning obvious media/texture payloads for arbitrary
# binary matches. Executables are intentionally included because they can
# contain embedded resource names.
SKIP_EXTENSIONS = {
    ".tga", ".ddt", ".bti",
    ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif",
    ".dds", ".wav", ".mp3", ".ogg", ".flac",
    ".mp4", ".avi", ".mkv", ".wmv",
    ".zip", ".7z", ".rar",
    ".pak",
}

TEXT_EXTENSIONS = {
    ".txt", ".xml", ".ini", ".cfg", ".json", ".csv",
    ".mtrl", ".material", ".proto", ".dataset",
    ".set", ".def", ".inc", ".script", ".lua",
    ".scn", ".scenario", ".trigger", ".layout",
}

EXECUTABLE_EXTENSIONS = {
    ".exe", ".dll",
}

MAX_GENERIC_BINARY_MB = 128


def normalize(value: str) -> str:
    return value.replace("/", "\\").lower()


def build_search_terms() -> dict[str, list[bytes]]:
    result = {}

    for key, candidate in CANDIDATES.items():
        terms = []

        for variant in candidate["variants"]:
            raw = variant.lower().encode("utf-8")
            wide = variant.lower().encode("utf-16le")

            terms.append(raw)
            terms.append(wide)

        # Longest first reduces redundant matches where possible.
        result[key] = sorted(
            set(terms),
            key=len,
            reverse=True,
        )

    return result


SEARCH_TERMS = build_search_terms()


def find_term_hits(data: bytes, terms: list[bytes]) -> list[tuple[int, bytes]]:
    hits = []

    for term in terms:
        start = 0

        while True:
            pos = data.find(term, start)

            if pos < 0:
                break

            hits.append((pos, term))
            start = pos + max(1, len(term))

    return hits


def read_context(data: bytes, pos: int, term: bytes) -> str:
    start = max(0, pos - 80)
    end = min(len(data), pos + len(term) + 120)

    chunk = data[start:end]

    try:
        text = chunk.decode("utf-8", errors="replace")
    except Exception:
        text = repr(chunk)

    text = text.replace("\x00", " ")
    text = re.sub(r"\s+", " ", text).strip()

    return text


def scan_content(path: Path) -> list[dict]:
    suffix = path.suffix.lower()

    if suffix in SKIP_EXTENSIONS:
        return []

    try:
        size = path.stat().st_size
    except OSError:
        return []

    if suffix not in TEXT_EXTENSIONS and suffix not in EXECUTABLE_EXTENSIONS:
        if size > MAX_GENERIC_BINARY_MB * 1024 * 1024:
            return []
    try:
        data = path.read_bytes()
    except Exception:
        return []

    results = []

    for candidate_key, terms in SEARCH_TERMS.items():
        hits = find_term_hits(data, terms)

        # Collapse repeated matches of the same underlying location.
        seen = set()

        for pos, term in hits:
            marker = (pos, term)

            if marker in seen:
                continue

            seen.add(marker)

            encoding = (
                "UTF-16LE"
                if len(term) >= 2 and term[1] == 0
                else "UTF-8/ASCII"
            )

            results.append({
                "Candidate": candidate_key,
                "CandidateDisplay": CANDIDATES[candidate_key]["display"],
                "Kind": "CONTENT_REFERENCE",
                "File": str(path),
                "Offset": pos,
                "Encoding": encoding,
                "MatchedBytes": term.hex(" "),
                "Context": read_context(
                    data,
                    pos,
                    term,
                ),
            })

    return results


def scan_filename_hits(root: Path) -> list[dict]:
    results = []

    try:
        files = root.rglob("*")
    except Exception:
        return results

    for path in files:
        if not path.is_file():
            continue

        name = normalize(path.name)

        for candidate_key, candidate in CANDIDATES.items():
            matched_variant = None

            for variant in candidate["variants"]:
                token = normalize(variant)

                if token in name:
                    matched_variant = variant
                    break

            if matched_variant is None:
                # Also handle bare candidate words for Gryphon/Gryphon variants.
                if candidate_key == "griffon":
                    if "griffon" not in name and "gryphon" not in name:
                        continue
                    matched_variant = "filename contains griffon/gryphon"
                else:
                    continue

            results.append({
                "Candidate": candidate_key,
                "CandidateDisplay": candidate["display"],
                "Kind": "FILENAME",
                "File": str(path),
                "Offset": "",
                "Encoding": "",
                "MatchedBytes": matched_variant,
                "Context": "",
            })

    return results


def main() -> None:
    OUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    print("============================================")
    print("AoM:EE LEGACY TEXTURE USAGE AUDIT V1")
    print("============================================")
    print()

    for root in SEARCH_ROOTS:
        print(f"Search root: {root}")

        if not root.exists():
            print("  MISSING")
            continue

        print("  Present")

    print()
    print("Scanning filenames and content...")
    print()

    results = []

    scanned_roots = 0

    for root in SEARCH_ROOTS:
        if not root.is_dir():
            continue

        scanned_roots += 1

        results.extend(
            scan_filename_hits(root)
        )

    # Content scan.
    for root in SEARCH_ROOTS:
        if not root.is_dir():
            continue

        for path in root.rglob("*"):
            if not path.is_file():
                continue

            # Filename hits were already handled separately.
            content_hits = scan_content(path)

            if content_hits:
                results.extend(content_hits)

    # Deduplicate identical records.
    unique = []
    seen = set()

    for row in results:
        key = (
            row["Candidate"],
            row["Kind"],
            row["File"].lower(),
            str(row["Offset"]),
            row["MatchedBytes"],
        )

        if key in seen:
            continue

        seen.add(key)
        unique.append(row)

    results = sorted(
        unique,
        key=lambda r: (
            r["Candidate"],
            r["Kind"],
            r["File"].lower(),
            str(r["Offset"]),
        ),
    )

    fields = [
        "Candidate",
        "CandidateDisplay",
        "Kind",
        "File",
        "Offset",
        "Encoding",
        "MatchedBytes",
        "Context",
    ]

    with OUT_CSV.open(
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

    candidate_counts = {}

    for key in CANDIDATES:
        candidate_counts[key] = sum(
            1
            for row in results
            if row["Candidate"] == key
        )

    # Separate meaningful game-data hits from reports/source metadata.
    game_root = ROOT / r"Age of Mythology"

    game_hits = [
        row
        for row in results
        if str(game_root).lower()
        in row["File"].lower()
    ]

    source_hits = [
        row
        for row in results
        if str(ROOT / "extracted").lower()
        in row["File"].lower()
        or str(ROOT / r"reports\materials_xml").lower()
        in row["File"].lower()
    ]

    with OUT_SUMMARY.open(
        "w",
        encoding="utf-8",
    ) as f:
        f.write(
            "AoM:EE LEGACY TEXTURE USAGE AUDIT V1\n"
        )
        f.write(
            "====================================\n\n"
        )

        f.write(
            f"Search roots present: {scanned_roots}\n"
        )

        f.write(
            f"Total unique hits: {len(results)}\n"
        )

        f.write("\nCANDIDATE COUNTS\n")
        f.write("----------------\n")

        for key, candidate in CANDIDATES.items():
            f.write(
                f"{candidate['display']:22} "
                f"{candidate_counts[key]:6}\n"
            )

        f.write("\nCLEAN GAME TREE HITS\n")
        f.write("--------------------\n")
        f.write(
            f"{len(game_hits)}\n"
        )

        f.write("\nSOURCE / MATERIAL TREE HITS\n")
        f.write("---------------------------\n")
        f.write(
            f"{len(source_hits)}\n"
        )

        f.write("\nINTERPRETATION\n")
        f.write("--------------\n")
        f.write(
            "Filename-only hits show that the candidate exists "
            "in a scanned tree.\n"
        )
        f.write(
            "CONTENT_REFERENCE hits show the candidate name/path "
            "was found inside another file.\n"
        )
        f.write(
            "A hit in reports or extracted is not proof of live "
            "runtime usage.\n"
        )
        f.write(
            "A content hit inside the clean Age of Mythology tree "
            "is the strongest evidence in this audit, but should "
            "still be interpreted according to the file type.\n"
        )
        f.write(
            "No hit does not mathematically prove the asset is "
            "unused if the engine constructs the name dynamically.\n"
        )

    print()
    print("============================================")
    print("LEGACY USAGE AUDIT COMPLETE")
    print("============================================")
    print()
    print(
        f"Unique hits           : {len(results)}"
    )
    print(
        f"Clean game-tree hits  : {len(game_hits)}"
    )
    print(
        f"Source/material hits  : {len(source_hits)}"
    )
    print()

    for key, candidate in CANDIDATES.items():
        rows = [
            row
            for row in results
            if row["Candidate"] == key
        ]

        print(
            f"{candidate['display']:22}: "
            f"{len(rows)} hits"
        )

    print()
    print(f"CSV     : {OUT_CSV}")
    print(f"Summary : {OUT_SUMMARY}")


if __name__ == "__main__":
    main()