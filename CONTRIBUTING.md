# Contributing

Read the [project tracker](PROJECT_STATUS.md) for current status and the [AI contributor instructions](AGENTS.md) for handoff maintenance. Update the tracker in the same change whenever behavior, setup, validation, or status changes.

Start with the [development plan](docs/DEVELOPMENT_PLAN.md) and keep changes focused on the current milestone.

## Before you contribute

Photo is a development preview licensed under [Apache-2.0](LICENSE); retain [NOTICE](NOTICE). Submit only work you have the right to contribute under that license. Follow the [community conduct](CODE_OF_CONDUCT.md), use [SUPPORT.md](SUPPORT.md) for questions, and report vulnerabilities privately through [SECURITY.md](SECURITY.md).

Start from current `main` and open a focused pull request; discuss new dependencies and large changes first. A helpful title states the concrete result. Maintain the [Unreleased changelog](CHANGELOG.md) for user-visible behavior. AI-assisted changes follow the same standards and must distinguish observed results from assumptions.

## Workflow

1. Use a short-lived branch, normally `codex/<description>` for agent work.
2. Keep changes focused and explain their user-visible effect.
3. Run `sh scripts/format.sh`, then `sh scripts/check.sh`.
4. For UI changes, launch `swift run Photo` and verify keyboard and window behavior.
5. Run `python3 scripts/check-repository.py` for repository hygiene, links, pinned workflow validation and redacted secret scanning. It uses Python 3's standard library and downloads checksum-pinned Gitleaks/actionlint into a temporary directory; see [repository standards](docs/REPOSITORY_STANDARDS.md). `--metadata-only` runs the offline file/link checks without claiming a secret scan.
6. Include relevant validation and known limitations in the change description. Wait for final-head checks before merging; use squash merges and resolve review conversations.

CI runs the same formatting, build, and test checks. Compilation uses Swift 6 language mode and treats warnings as errors. Keep PhotoCore independent of AppKit and SwiftUI; UI state uses main-actor isolation, and service protocols use Sendable asynchronous read-only interfaces.

## Files and data

- Never commit credentials, personal photo libraries, private metadata, or local catalogs.
- Use small synthetic or appropriately licensed fixtures and record their provenance.
- Keep dependency lockfiles tracked when dependencies are introduced.
- Preserve original images; test future metadata writes on disposable copies.
- Document new setup commands in the README as part of the same change.

## Architecture decisions

Record consequential choices in `docs/decisions/` using the template there. Give each decision a sequential number and descriptive filename. Include alternatives and tradeoffs.


## Review and release

Keep `main` ready to build. File/metadata changes need identity, replacement, source-byte preservation and interruption/retry coverage; UI changes need keyboard and window evidence. Fast embedded previews and deliberate full RAW rendering remain product priorities. Do not add tests that simply repeat the implementation; document unmeasured platform/camera/performance cases.

Only maintainers publish releases. Use `vMAJOR.MINOR.PATCH` tags with release notes, tested platform/camera limits and artifact checksums after the [distribution acceptance](docs/DISTRIBUTION.md) passes. Until then, label builds as development previews; never present ad-hoc builds as signed/notarized downloads. Include LICENSE/NOTICE in distributions. No CLA, automatic release, upload or publishing workflow is configured.
