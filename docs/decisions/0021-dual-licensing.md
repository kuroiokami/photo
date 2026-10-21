# 0021 — MIT or Apache-2.0 licensing

- Date: 2026-10-20
- Status: Accepted; supersedes the license choice in decision 0020

## Decision

The owner explicitly requested the same licensing model as [ArtCraft](https://github.com/storytold/artcraft): recipients may choose MIT or Apache-2.0. The SPDX expression is `MIT OR Apache-2.0`.

Keep the existing Apache text unchanged as LICENSE-APACHE and add LICENSE-MIT with Photo’s copyright notice. README, NOTICE, contribution terms, fixture provenance and installation/distribution guidance describe both options. Contributions are offered under both licenses unless explicitly stated otherwise, preserving that choice for recipients. Preserve independently licensed third-party material and its notices; external RAW references retain their recorded licenses.

Repository checks require both complete license files. Distributions should include both texts and NOTICE. Historical Apache-only commits are retained; this change does not rewrite Git history. App behavior, dependencies and release-signing status do not change.
