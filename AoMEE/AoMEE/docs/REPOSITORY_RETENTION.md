# Repository retention policy

Git is the reproducibility/review layer. Large source and generated trees remain local.

## Keep in Git

Canonical workflow definitions, source/integrity verification code, explicit compiler logic, compact manifests, research summaries, provenance records, technical references and experiment conclusions.

## Keep local only

Clean game, extracted TGA/BTI source, input staging, AI model, PBRify masters, generated DDTs, tests, full material XML snapshot, temporary compiler/extractor output and local tool installations.

## Privacy rule

No repository artifact should record a developer-specific absolute path, home directory, cloud-sync path, machine name, local log or other unnecessary local identifier. Use repository-relative paths.

## History note

This review branch sanitizes its current tree. Older repository commits are not rewritten or erased by this branch.
