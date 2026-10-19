# Instructions for AI contributors

## Start here

Read `PROJECT_STATUS.md`, `README.md`, and `docs/DEVELOPMENT_PLAN.md` before changing the project. Read relevant architecture decisions in `docs/decisions/`. Inspect the working tree and preserve unrelated user changes.

## Keep the handoff current

For every change affecting behavior, installation, usage, dependencies, architecture, validation, or delivery status:

1. Update `PROJECT_STATUS.md` in the same change, including the last-updated date, feature status, relevant commands, validation evidence, remaining work, and a concise dated change-log entry.
2. Update README setup commands when they change. Keep milestone acceptance criteria in the development plan consistent with the tracker.
3. Distinguish implemented, interfaces-only, planned, and verified behavior. Never mark a milestone complete solely because files or CI configuration exist.
4. Record actual checks and outcomes, and explain checks that were not run. Record remote CI links/results when inspected. Keep unresolved decisions visible; do not invent approvals or performance claims.
5. Record consequential architecture choices in a new numbered decision record.

Treat the tracker as the current operational handoff, the development plan as the milestone definition, and decision records as the rationale. Source code and observed test results take precedence if documentation is stale; reconcile it before handing off. Explicit user instructions take precedence over these conventions.

## Development conventions

- Use SwiftUI and Swift Package Manager, targeting macOS 14+ with Swift 6 language mode.
- Keep PhotoCore independent of SwiftUI/AppKit. Preserve main-actor UI state and asynchronous Sendable service boundaries.
- Run `sh scripts/format.sh` after Swift edits and `sh scripts/check.sh` before handing off code changes. Documentation-only changes need link and consistency checks, not an unnecessary rebuild.
- Protect original photos and metadata. Use small synthetic or licensed fixtures and record provenance. Keep personal libraries, secrets, generated builds, and local catalogs out of Git.
- Do not add dependencies or change product scope without explaining the need. Commit `Package.resolved` if external dependencies are introduced.
- Follow `CONTRIBUTING.md`. Keep commits focused and describe validation and limitations clearly.
