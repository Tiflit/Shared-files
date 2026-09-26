# Repository retention policy

Git is the reproducibility/review layer. Keep canonical workflows, verification code, compact manifests, research summaries, provenance, technical references and experiment conclusions.

Keep local: clean game, extracted source, input staging, AI model, PBRify masters, generated DDTs, tests, full material XML, temporary compiler/extractor output and local tool installations.

No repository artifact should record a developer-specific absolute path, home directory, cloud-sync path, machine name or local log. This branch sanitizes its current tree; older commits are not rewritten.
