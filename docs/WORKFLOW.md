# Ingest, cull, organize and hand off to Lightroom Classic

Implemented development workflow, 2026-10-19. Read [PROJECT_STATUS](../PROJECT_STATUS.md) for current validation and delivery. This workflow targets Lightroom **Classic** and local files; cloud Lightroom is not an equivalent interchange target.

## Recommended order

1. **Ingest and verify.** Pick a card/source, a working root, a backup root on another drive, and a unique job folder. Both receive `Job/Originals/<card tree>`. Photo recurses during ingest, copies supported photos and matching XMP/ACR companions, checks SHA-256, and publishes completed files through temporary-file moves. It never erases or ejects the card. Keep it until both copies finish verification.
2. **Cull quickly.** Continue Browsing while ingest runs; Reload shows new arrivals. The first published image's folder opens automatically. Ordinary browsing is shallow: open other card subfolders individually. Use fast Fit previews for the first pass; P/X/U and 0–5 for decisions; enter 100% only for deliberate focus/detail inspection. Rejecting does not delete files. Use RAW+JPEG grouping for a unique same-folder/stem pair, and Command/Shift-click or Select All for batches. A batch decision is one Undo action and does not auto-advance.
3. **Name once, before import.** Review full filename mappings, including companions, before Apply. Use a stable template rather than ratings, selection positions, or changing descriptive keywords. Recommended: `{date}_{time}_{camera}_{original}`; compact delivery sequence: `{date}_{camera}_{sequence}`. Keep a unique camera label for multi-camera jobs. Correct camera clocks separately before relying on capture ordering; clock editing is not implemented.
4. **Apply common metadata in layers.** Save an author/rights preset, a shoot/job/location preset, and smaller subject/individual-caption patches. Apply each explicitly after ingest. Photo does not apply a metadata preset automatically during ingest. Fields only change when checked and nonempty; Clear explicitly removes a value. Always review the per-file preview, especially for batch replacement.
5. **Keyword after the first cull.** Tag useful survivors with a consistent vocabulary: subject, species/person, activity, event and meaningful location. Example: `Wildlife|Birds|Herons|Great Blue Heron`. Use Append for adding facts; Remove for named corrections; Replace/Clear only deliberately. Saved presets contribute reusable vocabulary suggestions. This is a simple local vocabulary menu, not a complete controlled-vocabulary database.
6. **Hand off deliberately.** Resolve local-only/XMP errors and conflicts first. Lightroom tab can create a dedicated, verified copy of all non-rejected files in the current folder. Import that folder in Lightroom Classic with **Add**, use Embedded & Sidecar previews, and avoid an import preset that replaces prepared metadata. Verify a small sample before committing the whole collection. Once catalogued, rename/move within Lightroom and maintain backups of the catalog, photos and all companions.

The dedicated handoff is optional and costs extra space. For an all-RAW workflow, synchronized source files plus XMP/ACR can be imported directly with Add instead. JPEG/PNG full-filename sidecars are not consistently recognized by other applications; the handoff option embeds prepared metadata in **derived copies**, leaving the source library intact.

## Ingest behavior and recovery

- Two destinations are required. Same-volume destinations produce a visible warning; they do not provide drive-failure independence. Photo does not create an offsite copy or continuous backup.
- Supported photos and matching companions are copied; videos, unsupported formats, hidden files, symlinks and unrelated files are excluded. Original folder structure is retained.
- `.photo-ingest.json` records original names/relative paths, source hashes and verified destination paths after each completed file. Re-running re-verifies existing identical copies; a differing file blocks overwriting. Review the status before removing the card.
- Renaming through Photo updates the working ingest manifest's destination mappings, so re-ingesting the same card does not recreate the old names. Previously ingested XMP/ACR copies that were edited locally are retained and counted as **preserved metadata**, not described as checksum-identical. The backup is an initial snapshot; later edits are not mirrored automatically.
- Cancel leaves completed copies and a resumable manifest. A partial hidden copy is removed during orderly cancellation. A crash can leave an unused hidden partial file; retry publishes a fresh verified copy and does not treat the partial as complete. No automatic card formatting, deletion or background filesystem watching is implemented.
- Culling saves remain independent of ingest. Normal Quit waits for file operations and queued decision saves. Forced termination cannot guarantee completion of an in-memory operation.

## Bulk naming details

Tokens: `{date}` = `yyyyMMdd`, `{time}` = `HHmmss`, `{camera}` = your label, `{original}` = original stem, `{sequence}` = a minimum of six digits. Sequence increases once per photo family. The next value and explicitly saved template are remembered locally. Missing capture times block templates requiring them; use original/sequence tokens or correct metadata elsewhere. Offset-tagged capture times use UTC; untagged times use a consistent wall-clock interpretation. There is no automatic timezone or clock-drift correction.

A unique RAW+JPEG pair shares the stem and sequence. Matching RAW `basename.xmp`/`.acr` and JPEG/PNG `filename.ext.xmp`/`.acr` move with the family. Multiple RAWs or case-only collisions sharing companions are ambiguous and require correction. Rename one folder at a time. Existing targets, changed inputs, unsafe names and duplicate identities block the operation.

Journals in `~/Library/Application Support/Photo/Operations` record original, staging, final and recovery paths plus identity/hash checks before moves. **Undo Last Rename** restores only unchanged members. Subsequent metadata edits can block Undo; Photo retains the journal rather than discarding those edits. **Recover Original Names** appears for interrupted operations. If a file was externally changed/moved, restore its expected version/location from backup before retrying; do not delete the journal as a first response. Photo does not rewrite Lightroom catalog references.

## Metadata ownership and interoperability

Author, copyright, usage rights, copyright URL, title, caption, credit, job identifier and separate location-created/location-shown fields are supported. Only selected fields are merged. Existing develop settings, unknown properties and non-default language alternatives are preserved semantically. Multiple structured location entries are not flattened; ambiguous edits are refused.

Stars and flags remain independent. RAW decisions/descriptions use basename XMP; JPEG/PNG use full-filename XMP. Local SQLite stores pending descriptive intent before sidecar publication, shares file identity protections with decisions, and retains failed writes for Retry. Subsequent pending patches retain earlier pending fields. Own decision/description writes update each other's sync baselines; external changes require explicit Local or External resolution. Original image bytes are never rewritten by culling or descriptive editing.

Flat tags use `dc:subject`; hierarchy paths use `lr:hierarchicalSubject`. Append incorporates embedded image keywords before merging sidecar intent. Explicit empty keyword containers suppress old embedded values. Lightroom keyword dictionary synonyms, export rules, vocabulary-file import/export, arbitrary IPTC fields and metadata Undo are not implemented. Existing unowned XMP is retained, but dictionary-level features are not claimed to transfer.

Handoff first copies image/companion bytes and writes `.photo-handoff.json` with source checksums. Optional JPEG/PNG metadata embedding uses ImageIO's copy-source operation and verifies the requested XMP in a temporary result before replacement. Tests compare decoded pixel bytes and orientation. Resulting metadata bytes differ intentionally; `.photo-derived-checksums.json` records those final hashes. Use a **new dedicated folder** for a subsequent JPEG/PNG handoff; reusing a derived copy is a differing-byte collision. RAW files remain byte-identical. Original library JPEG/PNG bytes remain unchanged.

## RAW coverage and speed

Extension matching is case-insensitive: Sony ARW; Canon CR2, CR3 and legacy CRW; Olympus/OM System ORF; JPG/JPEG spelling variants and PNG. Real-camera checks cover Sony ILCE-7CR from prior work, Canon EOS Rebel SL1 (CR2), Canon EOS R (CR3), Olympus E-M1MarkII and OM System OM-1 (ORF). Legacy CRW is recognized but **not verified with a real camera sample**. Format recognition does not guarantee every camera/mode has an accessible preview or an installed macOS RAW decoder.

Fit uses existing JPEG previews and never enables generate-from-RAW options. CR3 has a bounded Canon-container reader for its embedded PRVW JPEG, because ImageIO's first container access measured about five seconds on the reference Mac. Unknown layouts fall back to ImageIO embedded-only access. Full detail still uses Apple CIRAWFilter only on demand, subject to the 256 MiB decoded-image limit. Embedded images can be much smaller than the sensor; only rendered detail is labelled Rendered RAW. EXIF reads remain asynchronous and may incur Apple's initialization delay. See [performance evidence](PERFORMANCE.md) and [public fixture provenance](fixtures/public-raw-provenance.json).

## Research basis and remaining acceptance

The sequence above is a product recommendation for this app. Camera Bits documents background/incremental ingest, dual destinations and metadata/rename automation; Photo adopts the verified-copy and early-browsing ideas with a smaller initial UI. [Camera Bits ingest documentation](https://camerabits.freshdesk.com/support/solutions/articles/48000207409-ingesting-photos).

Adobe documents keyword hierarchies and reusable keyword lists; this app implements per-image flat/hierarchical tags, with dictionary import/export remaining future work. [Adobe keyword documentation](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/keywords.html).

Location created and location shown have distinct meanings and must not be conflated. [IPTC user guide](https://www.iptc.org/std//photometadata/documentation/userguide/).

Lightroom Classic 15+ can place heavy edits in ACR companions in addition to XMP, so both are carried without interpreting or rewriting ACR bytes. [Adobe sidecar documentation](https://helpx.adobe.com/uk/lightroom-classic/desktop/organize-photos-in-lightroom-classic/create-xmp-acr-files.html). Modern flags are documented by [Adobe](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/flag-label-rate-photos.html); actual application-level exchange in this build remains unverified. No original Lightroom catalog was edited for these checks.

Remaining: isolated Lightroom round trip across RAW/JPEG/PNG and flags/hierarchies/structured locations; real CRW and broader camera/mode/macOS coverage; removable/network-drive failure testing; first-open profiling; live arrivals, richer vocabulary management, and release/accessibility work.
