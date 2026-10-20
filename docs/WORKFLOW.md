# Copy, cull, organize and deliver

For setup, read [Installation](INSTALLATION.md). For the complete interface/control reference, read [Usage](USAGE.md).

Implemented development workflow, updated 2026-10-20. Read [PROJECT_STATUS](../PROJECT_STATUS.md) for current validation and delivery. Photo works with local files for publication or an editor. Lightroom **Classic** is an optional, documented interchange target; cloud Lightroom is not equivalent. See the [job routes and planned source review](USAGE.md#choose-a-route-for-the-job).

## Recommended order

1. **Ingest and verify.** Pick a card/source, a Photo folder, a Backup folder on another drive, and a unique Shoot name. Both receive `Job/Originals/<card tree>`. Photo recurses during ingest, copies supported photos and matching XMP/ACR companions, checks SHA-256, and publishes completed files through temporary-file moves. It never erases or ejects the card. Keep it until both copies finish verification.
2. **Cull quickly.** Continue Browsing while ingest runs; verified arrivals appear automatically in the current destination folder. The first published image's folder opens automatically. Ordinary browsing is shallow: open other card subfolders individually. Use fast Fit previews for the first pass; P/X/U and 0–5 for decisions; enter 100% only for deliberate focus/detail inspection. Rejecting does not delete files. Use RAW+JPEG grouping for a unique same-folder/stem pair, and Command/Shift-click or Select All for batches. A batch decision is one Undo action and does not auto-advance.
3. **Name once, before import.** Review full filename mappings, including companions, before Apply. Use a stable template rather than ratings, selection positions, or changing descriptive keywords. Recommended: `{date}_{time}_{camera}_{original}`; compact delivery sequence: `{date}_{camera}_{sequence}`. Keep a unique camera label for multi-camera jobs. Correct camera clocks separately before relying on capture ordering; clock editing is not implemented.
4. **Apply common metadata in layers.** Save an author/rights preset, a shoot/job/location preset, and smaller subject/individual-caption patches. Apply each explicitly after ingest. Photo does not apply a metadata preset automatically during ingest. Fields only change when checked and nonempty; Clear explicitly removes a value. Always review the per-file preview, especially for batch replacement.
5. **Keyword after the first cull.** Tag useful survivors with a consistent vocabulary: subject, species/person, activity, event and meaningful location. Example: `Wildlife|Birds|Herons|Great Blue Heron`. Use Append for adding facts; Remove for named corrections; Replace/Clear only deliberately. Saved presets contribute reusable vocabulary suggestions. This is a simple local vocabulary menu, not a complete controlled-vocabulary database.
6. **Hand off deliberately.** Resolve local-only/XMP errors and conflicts first. Deliver / Edit can create a dedicated, verified copy of all non-rejected files in the current folder. For Lightroom Classic, import that folder with **Add**, use Embedded & Sidecar previews, and avoid an import preset that replaces prepared metadata. Verify a small sample before committing the whole collection. Once catalogued, rename/move within Lightroom and maintain backups of the catalog, photos and all companions.

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

Flat tags use `dc:subject`; hierarchy paths use `lr:hierarchicalSubject`. Append incorporates embedded image keywords before merging sidecar intent. Explicit empty keyword containers suppress old embedded values. Lightroom keyword dictionary synonyms, export rules, vocabulary-file import/export and arbitrary IPTC fields are not implemented. Existing unowned XMP is retained, but dictionary-level features are not claimed to transfer.

Handoff first copies image/companion bytes and writes `.photo-handoff.json` with source checksums. Optional JPEG/PNG metadata embedding uses ImageIO's copy-source operation and verifies the requested XMP in a temporary result before replacement. Tests compare decoded pixel bytes and orientation. Resulting metadata bytes differ intentionally; `.photo-derived-checksums.json` records those final hashes. Use a **new dedicated folder** for a subsequent JPEG/PNG handoff; reusing a derived copy is a differing-byte collision. RAW files remain byte-identical. Original library JPEG/PNG bytes remain unchanged.

## RAW coverage and speed

Extension matching is case-insensitive: Sony ARW; Canon CR2, CR3 and legacy CRW; Olympus/OM System ORF; JPG/JPEG spelling variants and PNG. Real-camera checks cover Sony ILCE-7CR from prior work, Canon EOS Rebel SL1 (CR2), Canon EOS R (CR3), Olympus E-M1MarkII and OM System OM-1 (ORF). Legacy CRW is recognized but **not verified with a real camera sample**. Format recognition does not guarantee every camera/mode has an accessible preview or an installed macOS RAW decoder.

Fit uses existing JPEG previews and never enables generate-from-RAW options. CR3 has a bounded Canon-container reader for its embedded PRVW JPEG, because ImageIO's first container access measured about five seconds on the reference Mac. Unknown layouts fall back to ImageIO embedded-only access. Full detail still uses Apple CIRAWFilter only on demand, subject to the 256 MiB decoded-image limit. Embedded images can be much smaller than the sensor; only rendered detail is labelled Rendered RAW. EXIF reads remain asynchronous and may incur Apple's initialization delay. See [performance evidence](PERFORMANCE.md) and [public fixture provenance](fixtures/public-raw-provenance.json).

## Research basis and remaining acceptance

The sequence above is a product recommendation for this app. Camera Bits documents background/incremental ingest, dual destinations and metadata/rename automation; Photo adopts the verified-copy and early-browsing ideas with a smaller initial UI. [Camera Bits ingest documentation](https://camerabits.freshdesk.com/support/solutions/articles/48000207409-ingesting-photos).

Adobe documents keyword hierarchies and reusable keyword lists; this app implements per-image flat/hierarchical tags, with dictionary import/export remaining future work. [Adobe keyword documentation](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/keywords.html).

Location created and location shown have distinct meanings and must not be conflated. [IPTC user guide](https://www.iptc.org/std//photometadata/documentation/userguide/).

Lightroom Classic 15+ can place heavy edits in ACR companions in addition to XMP, so both are carried without interpreting or rewriting ACR bytes. [Adobe sidecar documentation](https://helpx.adobe.com/uk/lightroom-classic/desktop/organize-photos-in-lightroom-classic/create-xmp-acr-files.html). Modern flags are documented by [Adobe](https://helpx.adobe.com/lightroom-classic/desktop/organize-photos-in-lightroom-classic/flag-label-rate-photos.html); actual application-level exchange in this build remains unverified. No original Lightroom catalog was edited for these checks.

Remaining: isolated Lightroom round trip across RAW/JPEG/PNG and flags/hierarchies/structured locations; real CRW and broader camera/mode/macOS coverage; removable/network-drive failure testing; first-open profiling; continuous source watching, richer vocabulary management, and release/accessibility work.

## Saved locations, selections and one-field edits

Opened folders stay in the sidebar until explicitly removed. Use a disclosure arrow to discover immediate subfolders, then click a folder name to browse it. This keeps browsing shallow and fast; removing a shortcut does not delete anything. The last selected location restores on launch. A disconnected location stays listed so it can be retried.

Select a group with Command-click, Shift-click, Shift-arrow, Command-A or a rectangle over the viewport. Flag buttons and P/X/U apply to the full selection. T toggles picks; Command-T selects visible picks. Batch decisions do not auto-advance. Rectangle selection does not auto-scroll.

For a shared copyright across 50 photos, select the group and open IPTC & Keywords with Command-I. Its initial values come from the first selected representative in current contact-sheet order. Edit Copyright notice and click the Preview Field button beside that row. Review the 50 before/after values, then Apply Reviewed Fields. That preview contains only Copyright notice, even if other fields are checked. Existing captions, location, keywords, stars and develop settings remain per photo. Clear must be explicitly checked to delete a value. Applying retains the selection; the combined Preview Metadata Changes button instead reviews every checked nonempty field and the chosen keyword action.

Hover help and Help → Photo Quick Start & Shortcuts explain these actions. The [Photo Mechanic review](PHOTO_MECHANIC_REVIEW.md) records shortcut differences and remaining workflow priorities.

## Preview and contact sheet

Choose Preview for a large image above a horizontal bottom filmstrip, with optional shooting information beside it. Contact Sheet returns to the full grid. Space switches views; Escape shows the contact sheet, and double-clicking a thumbnail opens Preview. Each view keeps its own thumbnail size during the session. Command/Shift-click and batch decisions work in both views. Arrow keys move one photo in the single-row strip; Shift extends the range. Trackpad horizontal scrolling or the native scrollbar browses the strip; navigation reveals the focused photo. Changing views retains selection and returns detail to Fit. Empty/filtered/error states use the full browsing area.

## Comparison, selected review and thumbnail labels

Choose Compare (C) in Preview to pin the current photo as a reference and start on another visible candidate. Arrows change the active candidate; G pins the active photo, Swap exchanges roles when the reference is visible, and O returns to Single Image. Link Zoom/Pan (L) sends explicit Fit/100% choices and normalized image centers to the other pane. Differently sized photos clamp independently. Unlink for independent inspection. Changing either photo, view or folder returns both panes to Fit. Decisions continue to target the thumbnail selection; pinning alone does not select the reference.

Each pane has its own demand-only detail worker and 256 MiB retained region/full-image budget: comparison permits up to 512 MiB in total. Decoder/GPU/transient memory is additional. Fit/navigation releases detail. No speculative RAW rendering or full-detail cache is added.

Select a burst and choose Review Selection from the toolbar or Review menu. Membership freezes the selected physical files; culling then starts with a single focused photo. Selection changes, filters and ratings do not change membership. Filters can temporarily hide members; End Selected Review removes this restriction. Changing/reloading the folder ends review. Unique RAW+JPEG grouping still represents its physical members together.

Labels adds at most two optional rows: exposure, shutter, aperture, ISO, focal length, camera, lens, capture time or dimensions. Choices persist locally. Rows use indexed EXIF and show missing values explicitly; they do not trigger image decoding. Hide Extra Labels restores the compact strip.

## Automatic verified ingest arrivals

Photo publishes an image family only after its images and XMP/ACR companions have been verified at both destinations, source identities checked, and both manifests durably updated. Unique RAW+JPEG pairs arrive together. The first verified folder opens once; subsequent arrivals merge into the currently browsed destination folder without resetting selection, review, decision Undo, caches or the preview session. Opening another destination subfolder during ingest shows only approved arrivals. Browsing elsewhere is respected. Updates coalesce briefly; final/cancelled runs flush completed arrivals.

This applies to a normal Photo ingest snapshot. It is not continuous/tethered source watching, recursive photo browsing or automatic naming/metadata presets. The backup remains an initial snapshot. Ordinary filesystem changes outside Photo ingest require Reload.

## Metadata batch Undo and Redo

Apply Reviewed Fields commits the entire local batch and its history in one SQLite transaction before attempting sidecar writes. In IPTC & Keywords, Undo Metadata Batch and Redo Metadata show the latest affected fields and physical file count. They work independently of the currently selected folder and survive restart; retain the latest 20 batches. A new metadata batch clears Redo. Native text Undo remains available inside fields; ordinary culling Undo remains independent.

Undo/Redo changes only the batch's owned fields and keyword sets. Unrelated captions, ratings, flags, locations and develop settings retain their current values. All target identities and owned values are checked before recording intent. Replaced/missing files or later external changes to an owned field stop the whole replay with an explanation. Review current metadata before proceeding; no force-overwrite history command is provided. Restore renamed/moved files to their expected names before replaying older history.

Sidecar writes remain coordinated atomic replacements per file, not a multi-file filesystem transaction. Read-only folders, interrupted synchronization or conflicting sidecars leave locally saved intent pending for Retry XMP Sync. Cancellation before commit changes no batch intent; after commit the remaining files stay pending. Journal entries contain owned before/after values and file identity/path references, not copies of original images or unrelated XMP packets. Do not delete the SQLite database as a recovery step.

## Photo-local composition edits

Rotate/mirror/crop can now be used in the contact sheet or preview; see the [editing guide](USAGE.md#8-rotate-mirror-and-crop). They are saved in the local SQLite database and rendered consistently without rewriting image bytes. They are not yet written to Adobe crop/orientation fields, imported from external crop settings or baked into handoff copies. Lightroom handoff continues to carry originals plus existing companions/prepared descriptive metadata. Do not expect Photo-local composition to appear in Lightroom yet. Ratings, flags, IPTC and keywords retain their separate preserving XMP workflow.
