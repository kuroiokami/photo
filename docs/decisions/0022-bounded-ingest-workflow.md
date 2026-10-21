# 0022 — Bounded ingest setup and explicit culling entry

- Date: 2026-10-20
- Status: Implemented; acceptance evidence belongs in PROJECT_STATUS.md

## Decision

Replace the vertically scrolling Ingest form with four bounded pages: Choose photos, Set up copies, Review & copy, and Copying. The first page asks for a card/folder and explicitly offers choosing keepers before copying or copying the entire shoot first. Start Culling uses the existing protected-source operation, dismisses setup and opens thumbnails; its banner explains P/X/U/stars and returns to copy setup. The banner enters destination setup directly, with Picks Only as the initial scope. Other explicit scopes remain available; choosing the entire-shoot route uses All Photos for a protected source.

Move detailed inventories, destination metadata paths and saved-list recovery to separate bounded sheets with internal lists. Keep the introduction compact, retain permanent dismissal and Help access, and put full status text behind Details while keeping a short persistent status visible. Back permits setup edits, invalidates prepared lists, and never starts an operation. Copy begins only from confirmation. Reopening during a background copy shows progress.

Preserve the existing frozen-plan, source-protection, two-destination verification, identity/decision handover and resume services. No implicit selection/filter copying, source modification, new ingest engine or performance guarantee is introduced. Native checks must cover both routes, complete action visibility, Back/list invalidation, explicit opposing-pair acceptance, saved recovery and original-file preservation. Detailed file lists may scroll; the main setup must not require scrolling to reach its actions.
