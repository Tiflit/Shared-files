# Review guide

Please review this branch before normalization/runtime release.

Questions: Is the 7,487-texture source gate reproducible? Are workflow inputs/model/outputs and alpha handling clear? Is explicit compiler format selection correct? Is the Blue Lagoon fallback sufficiently narrow? Does the DDT verifier correctly separate core integrity from the legacy extractor? Are the six core zlib failures accurately classified? Can the experiment log explain the discarded approaches without raw test trees? Are all committed paths privacy-safe?

Run `python verify_repository_hygiene.py` before publishing a future snapshot.

Open issues: six tiny DeflatedRGBA8 lower-mip failures; independent decoder validation; clean-game runtime validation; final resolution normalization; post-normalization material/player-colour validation.
