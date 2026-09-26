# Review guide

This branch is intended for independent technical review before normalization/runtime release.

## Review questions

- Does the v7 source gate establish a reproducible 7,487-texture population without developer-specific paths?
- Do the committed ChaiNNer workflows clearly identify inputs, model, outputs, alpha handling and 4x master intent?
- Is explicit compiler format selection correctly separated from authoritative BTI metadata?
- Is DeflatedRGB8 24-bit staging justified and isolated?
- Is the Blue Lagoon fallback sufficiently narrow?
- Does the DDT verifier distinguish core container integrity from the legacy extractor?
- Are the six core zlib failures accurately classified and still clearly open?
- Can the experiment log explain why earlier approaches were abandoned without the raw multi-gigabyte tests?
- Are scripts/reports free of developer-specific absolute paths?

Run `python verify_repository_hygiene.py` before publishing future snapshots.

## Deliberately unresolved

- six tiny DeflatedRGBA8 lower-mip decode failures
- independent decoder validation
- clean-game runtime validation
- final resolution normalization
- post-normalization material/player-colour validation
