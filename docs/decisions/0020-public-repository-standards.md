# 0020 — Public repository and development standards

- Date: 2026-10-20
- Status: Accepted; license choice superseded by [0021](0021-dual-licensing.md). Exact GitHub settings/validation evidence are in PROJECT_STATUS.md

## Decision

The owner requested public visibility and selected Apache-2.0. Add the official unmodified license text and project NOTICE, clarify preview/distribution limits, and provide contribution/support/security/conduct policies, issue/PR templates, CODEOWNERS and an Unreleased changelog.

Use the existing strict Swift format/build/test workflow plus a separate Linux repository-hygiene job. Both have read-only permissions, immutable checkout pins, timeouts and cancellation of superseded runs. Repository checks use Python's standard library with official checksum-pinned Gitleaks/actionlint in a temporary directory. They check intentional tracked data, JSON, relative Markdown file targets, workflow syntax and redacted history/working-tree secret scans. This adds development-only network/tooling requirements; no app dependencies or photo-processing behavior change.

Protect `main` with PR/check/conversation/linear-history requirements and disallow force pushes/deletion; require zero external approvals while there is a sole maintainer. Prefer squash merges and delete merged branches. Enable private vulnerability reporting and available secret scanning/push protection after publication. Verify applied settings through GitHub; do not infer enforcement from a policy file or bypass blocked checks.

## Audit and tradeoffs

Audit all reachable branches/history and repository metadata before changing visibility, because public access includes more than the current default-branch files. Preserve original author/history metadata and the unrelated local development-plan edit; sanitize current personal library references without rewriting commits. Retain only synthetic/redistributable fixtures with provenance. A clean scan is evidence of no detected findings, not a complete security/privacy guarantee. Full GitHub policy/community-file and current-branch acceptance are tracked separately from signed app distribution.
