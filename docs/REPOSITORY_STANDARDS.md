# Repository standards

Photo is a development-preview macOS application, dual-licensed under [MIT](../LICENSE-MIT) or [Apache-2.0](../LICENSE-APACHE), at the recipient’s option, with [NOTICE](../NOTICE). This document is the shared human/AI maintenance contract alongside [AGENTS.md](../AGENTS.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).

## Contributions and evidence

1. Branch from current `main`; keep each PR focused. Agent branches normally use `codex/`.
2. Describe the photographer's problem and resulting behavior. Update the tracker, relevant guides/milestones and Unreleased changelog; record consequential choices in an ADR.
3. Run `sh scripts/format.sh` and `sh scripts/check.sh` for Swift changes. Native keyboard/window checks and disposable file/metadata/recovery checks depend on scope. Record blocked/unrun checks honestly.
4. Run `python3 scripts/check-repository.py`. It checks tracked-data policy, required community files, JSON/local links, GitHub workflows and secrets in history plus tracked working files. Python 3 standard library is the only scripting dependency. Gitleaks/actionlint come from official releases with version/SHA-256 pins in `scripts/repository-tools.json`, run in a temporary directory, and are removed afterward. No global install or third-party Python package is needed.
5. Use `--metadata-only` for offline file/link checks; it does not count as workflow/secret validation. For new fixtures, record license/origin/privacy in adjacent PROVENANCE.md. Keep private source photos, catalogs, credentials, signing keys and generated installers outside Git.
6. Merge only the final reviewed commit with passing required checks and resolved conversations. Use a squash merge and keep `main` linear. Maintainer review is routed by CODEOWNERS; a single-maintainer repository does not require an impossible self-approval.

The checks are review aids, not proof that no secret, vulnerability or private metadata exists. Review changes to policies, workflows and tool pins as carefully as product code. Do not weaken checks or add ignore rules simply to hide a finding.

## GitHub configuration

The intended public configuration is: descriptive project metadata/topics, issues enabled, weekly dependency PRs for pinned GitHub Actions, squash merges, automatic cleanup of merged branches, and protected `main` requiring PRs, successful `check` and `repository-hygiene` contexts, up-to-date branches, resolved conversations and linear history. Force pushes/deletion of `main` are disabled. Enable private vulnerability reporting and GitHub secret scanning/push protection when the account exposes them. Exact applied/verified settings and any service limitation are recorded in PROJECT_STATUS.md rather than assumed from these files.

Workflows run on PRs and pushes to `main`, use read-only token permissions, do not persist checkout credentials, pin actions to full commit SHAs, time out, and cancel superseded runs. Only macOS runs compile Swift; repository hygiene runs on Linux. There is no auto-merge, publishing, artifact upload or signing workflow.

## Releases and licensing

There is no signed/notarized public download yet. Maintain Unreleased entries in CHANGELOG.md; use semantic `vMAJOR.MINOR.PATCH` tags only for an accepted release with notes, tested platforms/cameras, original-file/recovery evidence, checksums, LICENSE-MIT, LICENSE-APACHE and NOTICE. Follow [distribution acceptance](DISTRIBUTION.md). Public source availability does not complete packaging or platform verification.

The maintainer selected MIT OR Apache-2.0 on 2026-10-20, matching ArtCraft’s recipient-choice model. Both licenses cover project code/documentation and original synthetic fixtures unless a file explicitly says otherwise. External RAW sample references keep their recorded independent licenses; no external photo bytes are distributed here. Preserve third-party notices if dependencies/assets are introduced.

## Publication audit

Before public visibility, all 58 reachable commits were inventoried: 414 distinct blobs totaling approximately 4.75 MB, with only three project-created PNG gradients and no tracked private photo/library/catalog/signing artifacts. Gitleaks scanned history and GitHub issue/PR metadata without detected leaks; no Actions artifacts existed. New standards are scanned again before publishing. These counts describe that audit point, not future repository contents.

Current documentation removes personal library selection details. Ordinary author metadata and older local-machine/test references remain in historical commits; no history rewrite is implied. No personal photo bytes were added, and local development builds/data were excluded. GitHub makes Actions history/logs public along with source; see [visibility documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility).
