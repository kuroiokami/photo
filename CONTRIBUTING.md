# Contributing to Photo

Thanks for helping improve Photo. Bug reports, documentation fixes, accessibility feedback, camera compatibility reports and code contributions are all welcome.

Photo focuses on fast culling, reliable copying and practical photo organization. Check the [roadmap](ROADMAP.md) and [project tracker](PROJECT_STATUS.md) to see what's already available and where help is needed.

## Report a bug or suggest a feature

[Open an issue](https://github.com/kuroiokami/photo/issues/new/choose) and choose the appropriate form. Describe what you were trying to do, what happened and what you expected. For image problems, include the camera model, file format, macOS version and app build or commit.

Use synthetic or redistributable examples and remove private information from screenshots and logs. Report security issues [privately](SECURITY.md).

For a larger feature, dependency or workflow change, please open an issue before starting so we can agree on the approach.

## Work on the code

Follow the [installation guide](docs/INSTALLATION.md) to set up Apple's tools and build Photo. Start a branch from current `main` and keep each pull request focused on one change. Agent-created branches normally use `codex/`.

For Swift changes, run:

```sh
sh scripts/format.sh
sh scripts/check.sh
```

For documentation and repository changes, run:

```sh
python3 scripts/check-repository.py
```

The repository checker uses Python 3's standard library and downloads checksum-pinned Gitleaks and actionlint into a temporary directory. Use `--metadata-only` for offline file/link checks; the full command also checks workflows and scans for secrets. Documentation-only changes do not need a local Swift rebuild.

For UI changes, also open the app and check the affected controls, keyboard shortcuts and window behavior. Test file operations on disposable copies. Add tests for meaningful behavior, especially original-file preservation, interruption and recovery.

## Open a pull request

Explain the problem, what changes for users, and how you checked it. Mention any checks you couldn't run and any remaining limitations. Screenshots help when a change affects the interface.

Update relevant guides and the Unreleased [changelog](CHANGELOG.md). Keep [PROJECT_STATUS.md](PROJECT_STATUS.md) and [development milestones](docs/DEVELOPMENT_PLAN.md) current; record significant architecture choices in `docs/decisions/`. The tracker holds detailed implementation and validation evidence so the README can stay focused on getting started.

Pull requests need passing checks and resolved review conversations before merging. We use squash merges. See [repository conventions](docs/REPOSITORY_STANDARDS.md) for the full process.

## Project conventions

- Target macOS 14+ with Swift 6. Keep PhotoCore independent of SwiftUI and AppKit.
- Keep UI state on the main actor and service boundaries asynchronous and Sendable.
- Prioritize responsive browsing, embedded RAW previews and deliberate full-detail rendering.
- Keep credentials, private photos, catalogs and generated builds out of Git. Record fixture origins and licenses in an adjacent `PROVENANCE.md`.
- Preserve original image bytes. Document metadata writes and verify them using disposable files.
- Follow the same review and evidence standards for AI-assisted contributions. [AGENTS.md](AGENTS.md) contains the additional handoff instructions for coding agents.

## Releases

Maintainers publish releases after the [distribution checks](docs/DISTRIBUTION.md) pass. Releases use `vMAJOR.MINOR.PATCH` tags and include release notes, tested platform/camera limits, checksums and license notices. Local ad-hoc builds remain development previews until a signed, notarized release is available.

## License and conduct

Contributions are provided under Photo's [Apache-2.0 license](LICENSE); retain [NOTICE](NOTICE) and submit only material you have the right to contribute. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).
