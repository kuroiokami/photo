## Problem and resulting behavior

Describe the concrete trigger and what changes for the photographer. Link the issue if relevant.

## Validation

List the checks actually run and their results. For UI changes include native keyboard/window checks; for file/metadata changes include disposable-copy, identity, original-byte and recovery evidence. Explicitly name checks not run or blocked.

## Handoff

- [ ] Updated PROJECT_STATUS.md and relevant guides/milestones/ADRs.
- [ ] Ran `sh scripts/check.sh` for Swift changes and `python3 scripts/check-repository.py` for repository checks.
- [ ] Added meaningful regressions where the behavior warrants them.
- [ ] No secrets, private photos/catalogs, generated builds or unrelated edits included.
- [ ] Described data, compatibility, performance and recovery limitations that affect this change.
