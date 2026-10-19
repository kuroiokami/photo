# Contributing

Read the [project tracker](PROJECT_STATUS.md) for current status and the [AI contributor instructions](AGENTS.md) for handoff maintenance. Update the tracker in the same change whenever behavior, setup, validation, or status changes.

Start with the [development plan](docs/DEVELOPMENT_PLAN.md) and keep changes focused on the current milestone.

## Workflow

1. Use a short-lived branch, normally `codex/<description>` for agent work.
2. Keep changes focused and explain their user-visible effect.
3. Run `sh scripts/format.sh`, then `sh scripts/check.sh`.
4. For UI changes, launch `swift run Photo` and verify keyboard and window behavior.
5. Include relevant validation and known limitations in the change description.

CI runs the same formatting, build, and test checks. Compilation uses Swift 6 language mode and treats warnings as errors. Keep PhotoCore independent of AppKit and SwiftUI; UI state uses main-actor isolation, and service protocols use Sendable asynchronous read-only interfaces.

## Files and data

- Never commit credentials, personal photo libraries, private metadata, or local catalogs.
- Use small synthetic or appropriately licensed fixtures and record their provenance.
- Keep dependency lockfiles tracked when dependencies are introduced.
- Preserve original images; test future metadata writes on disposable copies.
- Document new setup commands in the README as part of the same change.

## Architecture decisions

Record consequential choices in `docs/decisions/` using the template there. Give each decision a sequential number and descriptive filename. Include alternatives and tradeoffs.
