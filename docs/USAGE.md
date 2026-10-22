# Using Photo

Photo is built for **fast browsing → choosing keepers → naming and captions → publication or an editor**. It uses embedded RAW previews for normal browsing and requests genuine RAW detail only when you deliberately inspect it.

Install/build it with the [installation guide](INSTALLATION.md). The [tracker](../PROJECT_STATUS.md) separates implemented features from verified behavior and remaining acceptance work.

## Contents

1. [A first culling session](#1-a-first-culling-session)
2. [Workspace and saved folders](#2-workspace-and-saved-folders)
3. [Select individual photos and groups](#3-select-individual-photos-and-groups)
4. [Stars, flags and thumbnail controls](#4-stars-flags-and-thumbnail-controls)
5. [Filters, sorting and EXIF labels](#5-filters-sorting-and-exif-labels)
6. [Preview, trackpad zoom and focus inspection](#6-preview-trackpad-zoom-and-focus-inspection)
7. [Compare photos and review a shortlist](#7-compare-photos-and-review-a-shortlist)
8. [Rotate, mirror and crop](#8-rotate-mirror-and-crop)
9. [Ingest safely](#9-ingest-safely)
10. [Bulk rename](#10-bulk-rename)
11. [IPTC, keywords and Lightroom](#11-iptc-keywords-and-lightroom)
12. [Saving, conflicts and recovery](#12-saving-conflicts-and-recovery)
13. [Keyboard reference](#13-keyboard-reference)
14. [Current boundaries](#14-current-boundaries)

## 1. A first culling session

### Learn the workflow in the app

Open **Workflow → Ingest** for a small introduction, then choose **Show Walkthrough**. The five steps cover choosing a starting point, verified copying, two-pass culling, captions and delivery, with deadline and wedding examples. **Not Now** hides the invitation for that panel session. **Don’t Show Again**, or the walkthrough’s **Don’t show the ingest introduction again** checkbox, remembers your choice between launches. This hides only the introduction; important source-protection/save messages remain visible.

Reopen it from **Help → Photo Quick Start & Shortcuts → Workflow Walkthrough**, or the **Workflow Walkthrough** button in the workflow panel. Uncheck the same checkbox to restore the ingest invitation. The guide never runs a file operation or changes photo decisions; it does not open automatically over browsing or while copying.


1. **Open a working folder** with **⌘O**. For a card, use verified ingest for copied output, or **Workflow → Ingest → Choose keepers before copying → Start Culling** to choose photos before copying them with their review decisions.
2. **Scan in Fit.** Use the large Preview and bottom filmstrip, or press **Space** for the Contact Sheet grid.
3. **Make decisions.** Press **P** to pick, **X** to reject, **U** to clear a flag, and **0–5** for stars. Flags and stars are independent. Reject does not delete anything.
4. **Inspect focus deliberately.** Double-click the large image, choose **100%**, or pinch out over the preview. Pan with a two-finger scroll or drag; use the small navigator to jump to another area.
5. **Compare a burst.** Press **C** to pin a reference beside the active image. Arrows advance the active candidate. Press **O** to return to one image.
6. **Organize survivors.** Filter picks/stars, rename before Lightroom import, then apply shared IPTC fields and keywords in reviewed batches.
7. **Resolve save/conflict messages**, then follow the Lightroom handoff checklist. Preserve originals and all companion files in your backups.

For a safe introduction, choose **Show Sample Collection**. Sample decisions and image edits are temporary.

### Choose a route for the job

- **News or wire deadline:** copy and verify, begin culling as verified photos arrive, caption the keepers and prepare delivery copies in **Deliver / Edit**. Lightroom is optional. JPEG/PNG delivery copies can carry embedded captions/copyright. RAW files still require a RAW-capable editor; Photo does not yet render publication JPEGs, apply its local crop to exports or upload to an agency.
- **Wedding or large shoot:** keep the shoot under Photo Home, verify both copies, cull in passes with flags/stars and compare similar frames. Add shared rights/event metadata, then individual captions/keywords. Rename survivors before importing into Lightroom or another editor. A 10–40k-photo shoot is a design target, not a newly verified performance claim.
- **Review before copying:** Workflow → Ingest → choose the card/source → **Start Culling**. Stars, flags, Undo and Photo-local rotate/mirror/crop save on this Mac while the source stays protected. Choose **Copy Reviewed Photos…** in the source banner, prepare an explicit copy list and copy to both destinations with the review decisions. [Workflow and recovery](PRE_COPY_CULLING.md).


Workflow setup now occupies the main window’s content area rather than a pop-up. **Back to Photos**, **Return to Culling** and **Cull While Copying** return to the retained browser. For protected reviews, the source banner takes you directly back to copy setup. Long file lists, help and confirmations can still open separate sheets.

## 2. Workspace and saved folders

| Area | Purpose |
| --- | --- |
| Folder sidebar | Photo Home, saved folders and subfolders loaded on demand |
| Collection header | Contact Sheet/Preview, sort, EXIF label menu, thumbnail size and visible/total count |
| Filter/selection rows | Flag/star filters, RAW+JPEG grouping, selection-wide decisions, selected review and auto-advance |
| Large preview | Fast Fit view, detail controls, rotate/mirror/crop and optional shooting-information pane |
| Contact sheet / bottom filmstrip | Selection, direct stars/flags and contextual actions |
| Status bar | Decision or image-edit saving state and current photo/count |
| Workflow | In-window Ingest, Bulk Rename, IPTC & Keywords, and Deliver / Edit |

### Open and revisit folders

Choose **File → Open Folder…** or **⌘O**. Photo lists visible, regular supported image files directly inside that folder. It does not recursively mix all descendants into one collection. Hidden items and symlinks are excluded.

Choose **Photo Home** in the sidebar to set your usual photo folder, such as Pictures or a folder on a photo drive. It appears first with a house icon. This is a starting place, not a move/import operation. If no copy destination has been remembered, Ingest suggests Photo Home as the Photo folder. Other saved folders remain alongside it. Use **Change Photo Home…** or a folder’s **Use as Photo Home** context command to change it. Existing installations initially use their first saved folder. A new installation asks you to choose; it does not scan your home directory.

A saved folder stays in the sidebar until removed. Expand its arrow to discover subfolders, then click a name to display that folder’s images. The last folder restores on launch. Disconnected folders remain listed for retry. The sidebar’s remove button deletes only the shortcut.

**⌘R** reloads the current folder, clears image caches and retains the selected identity when possible. Ordinary external filesystem changes require Reload. Verified arrivals during Photo ingest update automatically.

### Change the browsing layout

- **Preview:** large image above a horizontal filmstrip.
- **Contact Sheet:** full thumbnail grid.
- **Space:** switch between them.
- **Escape:** return to Contact Sheet.
- **Double-click a thumbnail image:** open Preview.

Each view keeps its own thumbnail size during the session. Use its slider or pinch over the collection to adjust density. The filmstrip scrolls horizontally; the focused photo is revealed after keyboard navigation or sorting.

Background shooting information and saved decisions appear in small updates while a folder loads. Photo prioritizes the focused photo; choosing an EXIF sort waits for indexing to finish before reordering the collection.

### Thumbnail caching

Photo remembers generated thumbnails in memory and on this Mac's disk so returning to photos does not repeatedly decode the originals. The memory allowance adapts to your Mac within a fixed limit; the disk cache is also limited. New or changed files still need an initial thumbnail.

Choose **View → Clear Thumbnail Cache** if you need thumbnails recreated. This removes temporary thumbnails from the current window's memory and the shared disk cache; it does not delete photos or change flags, ratings, captions or crops. Other open windows may retain their loaded thumbnails. Reload the folder after external image changes. Photo saves reusable thumbnails in the background. If you quit immediately, some thumbnails may need to be generated again next time; saved stars, flags and metadata have their own durable storage.

## 3. Select individual photos and groups

| Action | Result |
| --- | --- |
| Click image/filename | Select that photo and focus navigation |
| ⌘-click | Add/remove an individual photo |
| Shift-click | Select the range from the stable anchor |
| Shift-arrow | Extend a range while navigating |
| Drag a rectangle | Select thumbnails intersecting the visible rectangle |
| ⌘/Shift + rectangle | Add to the existing selection |
| ⌘A | Select all currently visible photos |
| ⌘D | Deselect all |
| ⇧⌘O | Invert the visible selection |
| ⌘T | Select visible picks |

Rectangle selection does not auto-scroll beyond the viewport. Filters restrict Select All and other visible-selection commands.

**RAW+JPEG** groups one unique same-folder/stem RAW+JPEG pair into one representative. Ratings, flags and image-edit actions on that representative target both physical files. They retain independent identities/sidecars. Ambiguous multi-RAW/stem matches are not combined.

## 4. Stars, flags and thumbnail controls

### Two independent decisions

A photo can be a pick, reject or unflagged, and separately have zero to five stars. Rejecting never moves or deletes it. Setting stars never changes the flag.

| Key | Decision |
| --- | --- |
| P | Pick |
| X | Reject |
| U | Clear flag |
| 0 | Clear stars |
| 1–5 | Set stars |
| T | Toggle picks for the selection |

The toolbar and preview controls apply to the selected physical target set. Mixed batch values are shown explicitly.

### Click directly on a thumbnail

The flag and five stars beneath each thumbnail are interactive in both the grid and filmstrip:

- Click a star to set that rating. Click the current rating again to clear stars.
- Open the flag control to choose Pick, Reject or Unflagged.
- If that tile belongs to the current group selection, the action applies to the group.
- If it is outside the selection, it becomes the single selected representative first.
- Direct tile actions keep focus on the collection and suppress auto-advance. Filters can still remove the decided photo from view.

Right-click a tile for flags, explicit 0–5 stars, rotation/mirror, crop commands and IPTC access. A context action on an unselected tile first targets that tile; an action on a selected tile retains the selected group. Crop itself opens the clicked image for composition.

### Advance and Undo

**Auto-advance** starts off and is remembered. It advances after single-photo keyboard/preview decisions. Hold **Shift** with a decision to apply and advance regardless of the toggle. Batch and direct-thumbnail decisions keep the selection.

If a filter hides the decided photo, Photo selects the next surviving neighbor, or the previous one if necessary, without advancing twice. Rating sort retains the photo unless advancement was requested; advancement follows the pre-action order.

**⌘Z / ⇧⌘Z** undo/redo culling decisions and image edits in their actual session order. They reset when opening/reloading a folder. Saved decisions and edits remain. Metadata batches have separate persistent Undo buttons described below.

### Move rejected photos to Trash

**X marks a reject; it does not delete anything.** In a working folder:

1. Choose **Show All Photos** if reviewing a shortlist, then **Clear Filters** if you want every reject in the current folder included.
2. Press **⇧⌘X** or open **Remove → Select Rejects** (also available in the Decisions menu). Check the selected count. This selects visible rejected thumbnails; it does not search subfolders.
3. Press **⌘Delete** or choose **Remove → Move Selected to Trash…**.
4. Check the exact file list and any picked-photo warning, then click **Move to Trash** or press **Return**. Escape cancels.

You can also select any working photos manually and use the same command. RAW+JPEG grouping expands a selection to both physical files, so check the list; mixed pairs may include a keeper. Only the listed images and exclusively owned XMP/ACR companions move. Shared sidecars stay with unselected photos. Copies in other folders and backups are unaffected. Bundled sample photos and protected pre-copy sources cannot be trashed. During pre-copy review, copy only keepers and leave the source card alone.

Restore through **Finder → Trash → select the files → Put Back**; include matching sidecars, then Reload the folder in Photo. Photo’s Undo history does not restore files and clears after a successful move. Local decision/edit records remain so they can be recovered when the same files are restored. File replacements, changed sidecars, folder arrivals or protection changes stop a stale plan. A batch is not atomic: failures stop and report actual moves, leaving remaining files untouched. If macOS Trash is unavailable, Photo reports the error and never falls back to permanent deletion. A crash/interruption may leave sidecars beside the original folder; inspect the reported/remaining files and Finder Trash before retrying.

## 5. Filters, sorting and EXIF labels

Combine a flag filter with a minimum-star filter. The header shows visible and total counts. **Clear Filters** removes both restrictions; a selected-review set is ended separately.

Sort by filename, capture time, ISO, shutter speed, aperture, focal length or rating. Numeric EXIF values sort numerically; missing values go last with filename ties. EXIF sorts wait for indexing rather than repeatedly shuffling the collection. Selection follows identity after reordering. Rating sort puts highest stars first.

The **shooting-information** button displays capture time, camera/lens, shutter, aperture, ISO, focal length and dimensions. A compact exposure strip remains near preview decisions.

The **Labels** menu adds up to two remembered rows beneath thumbnail filenames: exposure summary, shutter, aperture, ISO, focal length, camera, lens, capture time or dimensions. Values reuse already indexed metadata; they do not decode images. Missing values are explicit. **Hide Extra Labels** restores compact thumbnails.

## 6. Preview, trackpad zoom and focus inspection

### A fast keyboard pass

| Key | Action |
| --- | --- |
| **Z** | Toggle Fit / genuine 100% on the active photo, including from the contact sheet |
| **B / N** | Previous / next photo, even when the zoom view or navigator has focus |
| **[ / ]** | Rotate the selected photo(s) left / right |
| **⇧⌘C** | Open Crop for the focused photo |
| **P / X / U** | Pick / reject / clear flag; Shift also advances |
| **0–5** | Set stars independently of flags |

Use Z to check focus, Z to return to Fit, then P/X or Shift-P/Shift-X to decide and move on. Arrow keys can pan when the zoom navigator has focus; B/N always navigate photos. Each new photo starts at Fit. Rotation/mirror/crop remains Photo-local and is not applied to delivery copies or Lightroom. For speed, do a focus/flag pass first, then crop and caption the keepers.

### Fast Fit versus real detail

Fit uses a bounded JPEG/PNG preview or the RAW’s embedded JPEG. Its badge identifies the source and decoded dimensions. An embedded preview may be much smaller than the sensor.

**100%** means one original image pixel per physical display pixel, including Retina scaling. JPEG/PNG detail decodes full resolution. RAW detail uses Apple’s installed camera decoder and is labeled **Rendered RAW**. Camera support and appearance depend on macOS.

For RAWs, a full-quality focus region can appear first while the rest finishes. Outside that ready region remains black until completion. This is progressive presentation, not a claim that only part of the RAW was processed. Cancel/Fit releases detail and stops subsequent work; an active Apple render call cannot stop mid-call.

### Trackpad and mouse

| Gesture/control | Behavior |
| --- | --- |
| Spread two fingers apart over the preview | Enter deliberate detail viewing and increase magnification |
| Pinch fingers together in detail | Reduce magnification; reaching the Fit range returns to Fit |
| Two-finger swipe/scroll | Pan while zoomed; it does not change magnification |
| Drag the detail image | Pan |
| Click 100% | Restore exact physical-pixel 100% |
| Click Fit | Show the full edited composition |
| Double-click the large Fit image | Inspect around that image location |
| Double-click detail | Return to Fit |
| Pinch over thumbnails | Adjust contact-sheet/filmstrip thumbnail density |

The detail caption shows the current percentage. Zoom reuses decoded pixels; changing magnification does not repeatedly render the RAW. At magnifications above 100%, pixels are enlarged for inspection; no extra detail is claimed. Photo/view changes reset to Fit. Crop and rotate are reflected in both Fit and detail without rewriting original pixels.

### Small navigator

At detail magnification, the bottom-right image shows the current viewport. Click another area to center there; drag the white frame to pan without losing the grab point. With the navigator focused, arrows pan a quarter view, Shift-arrows a full view, and Home/End jump to opposite corners. Named accessibility actions pan and center. Click a thumbnail to resume photo navigation.

One pane retains at most 256 MiB of decoded region/full detail. Two-pane comparison allows 512 MiB combined, plus decoder/GPU/transient allocations. Oversized/unsupported requests preserve a recoverable Fit view. Cropping does not bypass the original detail limit.

## 7. Compare photos and review a shortlist

Choose **Compare** or press **C**. Photo pins a reference and selects another visible candidate beside it.

| Control | Action |
| --- | --- |
| Arrows | Browse the active candidate |
| G / Pin Current | Replace the reference with the active photo |
| L / Link Zoom/Pan | Link or unlink magnification and normalized viewport centers |
| Swap | Exchange reference/active if the reference is visible in the current set |
| O / Single Image | Close comparison |

The reference stays fixed while the active candidate changes. Decisions follow thumbnail selection, not the reference pane. Changing either photo returns both panes to Fit. Linked coordinates refer to each photo’s displayed composition; different crops/aspect ratios clamp independently.

For a burst shortlist, select two or more photos and choose **Review Only Selected**. Membership freezes those physical files while selection returns to a single focused photo for individual decisions. Filters still apply; navigating/rating does not redefine membership. **Show All Photos** restores the folder. Opening/reloading ends review. Ingest arrivals do not enter a frozen shortlist automatically.

## 8. Rotate, mirror and crop

These are **non-destructive Photo-local image edits**. They persist in Photo’s SQLite database and follow its file-identity protection. They change the displayed composition in thumbnails, Preview, comparison and detail. Original bytes, embedded EXIF, existing XMP orientation and Lightroom develop settings remain untouched.

**Current interoperability boundary:** these image edits are not yet written to Adobe crop/orientation fields, baked into handoff copies or imported from external crop settings. Lightroom receives the originals and existing metadata, not Photo’s local crop/mirror/rotation. Keep the local database in your backups. Ratings, flags and descriptive metadata continue their separate XMP synchronization.

### Rotate or mirror a selection

Select one or more photos. Use the **Image** menu or the thumbnail context menu:

- **Rotate Left / Right:** 90° steps.
- **Mirror Horizontally:** flip left/right.
- **Mirror Vertically:** flip top/bottom.
- **Reset Image Edits:** remove Photo’s rotation, mirror and crop for the targets.

Hover over a thumbnail to reveal quick actions on the image itself; selected thumbnails keep these controls visible. The top corners rotate left/right, the top center opens Mirror, the bottom-left **i** opens IPTC/keywords, the bottom center opens Crop, and the bottom-right magnifying glass opens Preview. Hover help names each action. These controls also appear in the Preview filmstrip.

Rotate, mirror and IPTC on a selected thumbnail retain the selected group. On an unselected thumbnail, they select that photo first. Crop edits only the clicked photo; Preview opens the clicked photo as a single selection. Direct editing does not auto-advance. Stars and flags remain below each thumbnail, and keyboard shortcuts and the visible Image row remain available.

Both Preview and Contact Sheet have a visible **Image** row with **Rotate Left [**, **Rotate Right ]**, **Mirror** and **Crop ⇧⌘C** controls. The Image menu retains the same commands, including Copy/Paste Crop and Reset. Grouped RAW+JPEG actions apply to both physical files. Existing crops follow orientation changes rather than jumping to another subject area. A Photo-edit/crop label identifies adjusted thumbnails.

### Crop a photo

1. Select the photo and choose **Crop…**, press **⇧⌘C**, or use its context menu.
2. The editor shows the uncropped rotated/mirrored image, using the fast preview.
3. Drag outside the current crop to draw a new rectangle. Drag inside to move it. Drag one of four corner handles to resize.
4. Optionally choose **Center a Ratio**: Original, Square, 3:2, 4:3 or 16:9. This creates a centered rectangle; later dragging is unconstrained.
5. The Left/Top/Width/Height percentage fields provide precise, keyboard-accessible adjustments.
6. Choose **Apply Crop** to save, **Clear Crop** to restore the full oriented image, or **Cancel** to leave the composition unchanged.

For grouped RAW+JPEG, cropping the representative applies the normalized crop to both companions. It does not copy other image or descriptive edits across the group.

### Copy a crop across a group

Use **Copy Crop** on a cropped thumbnail (or Image → Copy Crop). Select the targets and choose **Paste Crop to Selection**. Only the normalized rectangle is copied; each target retains its own orientation, stars, flag and metadata. Clear Crop removes just the rectangle. Use ⌘Z to undo the batch.

Image-edit values survive restart; session Undo does not. Watch the status for **Image edits saved in Photo**. If local saving fails, retain the files and use **Image → Retry Image Edit Save** after resolving the cause. Replaced/changed files require Reload before further saving.

## 9. Ingest safely

Open **Workflow → Ingest** (**⌘G**):

The setup stays on one screen at a time: **Choose photos → Set up copies → Review & copy → Copying**. Back returns to the previous step. File inventories, saved-copy recovery and full status messages open separately; the main setup does not scroll.


1. Choose the card/source folder, select **Copy the entire shoot first**, then **Set Up Copies →**.
2. Choose your **Photo folder** and **Backup folder**. Prefer separate drives for independence; Photo warns when both are on the same volume.
3. Enter a unique **Shoot name**, such as `2026-10-20_Wedding`.
4. Choose **Review Copy Setup →**, check the destinations, then **Copy & Verify Both Copies**.
5. Use **Continue Browsing** while it runs. Keep the card until the operation reports successful verification.

Both destinations receive `Shoot name/Originals/<source folders>`. Photo recurses for ingest, copies supported images and matching XMP/ACR companions, verifies SHA-256, and records durable manifests. It does not erase/eject/format the card.

The first fully verified image family’s folder opens once. Subsequent approved arrivals merge into the currently browsed destination folder without Reload or resetting decisions/selection. Unique RAW+JPEG companions complete together. Other source subfolders remain separately browsable; browsing elsewhere is respected. This is a snapshot ingest, not tethered/continuous source watching.

Re-running verifies matching copies; differing targets are not overwritten. Cancellation retains verified copies and resumable copy records. Keep the hidden `.photo-ingest.json` and `.photo-ingest.events` files with interrupted destinations, and resume using the updated app. The second destination is an initial snapshot; later edits/renames are not continuously mirrored. Read the [workflow recovery details](WORKFLOW.md#ingest-behavior-and-recovery) before retrying interrupted operations.

### Review a source before copying

1. In **Workflow → Ingest**, choose the card/source using **Card or folder → Choose…**.
2. Choose **Choose keepers before copying**, then click **Start Culling**. Photo protects that source and opens it for browsing. If another file operation is running, finish it first.
3. Check the **Reviewing source · Source unchanged** banner. P/X/U, 0–5, multi-selection, filtering, comparison, Fit/detail and Photo-local composition work as usual. An explicit decision marks the file reviewed; merely navigating does not. Clearing an already-clear flag also counts, and Undo restores the previous reviewed state.
4. Expand the source in the sidebar and click child folders. Protection and local decisions restore after Reload or relaunch. A second window cannot write normal XMP/metadata into this source.
5. Watch for **Review saved on this Mac** or **Review edits saved on this Mac**. Actual save failures expose review retry; they are not XMP errors.

6. Choose **Copy Reviewed Photos…** in the source banner (or return to Workflow → Ingest). Set Photo folder, Backup folder and Shoot name. Picks Only is the default; change Photos to copy if you need another scope.
7. Choose a scope, then **Review Copy Setup →**. Review photo/file counts, unreviewed inclusions/omissions, source bytes and destinations. Choose **View Files & Details…** to inspect paths. RAW+JPEG additions are listed; an added companion with an opposing flag needs explicit confirmation or a new plan with pair grouping off.
8. Click **Copy & Verify Both Copies**. Photo verifies both copies and saves their independent stars/flags and Photo-local image edits. Continue culling the source, or explicitly choose **Review Copied Photos** once a verified group is available. The source is not automatically replaced on screen.
9. Wait for both verification and metadata readiness before delivery. Add captions/keywords and rename on the working copy; backup is the initial snapshot, not a mirror of later changes.

| Copy choice | Included photos |
| --- | --- |
| All Photos | Every supported source photo across subfolders, including rejects and unreviewed photos |
| Picks Only (default after culling) | Picks across the source, including flags imported from existing XMP |
| Everything Except Rejects | Unflagged and unreviewed photos as well as picks |
| Current Selection | The exact selected physical files, plus explicitly enabled pair companions; other source folders are not scanned or counted |

Filters do not narrow a source-wide choice. **Unreviewed** means no explicit decision was made in this review, not a reject. Required XMP/ACR companions follow included images independently of pair grouping. The list freezes the current saved decisions; later source changes are not silently added. After copying, changed included review revisions are reported. To copy later choices, prepare a new list and fresh shoot folder; this version does not overwrite existing destination decisions with another snapshot.

**Resume after interruption:** reopen Ingest and use **Resume a saved reviewed copy → Resume Saved Copy**. Keep the original source and both destinations connected. Resume rechecks source identities/hashes and verified copies, recovers local decision/XMP handover, and preserves newer destination ratings, composition and metadata. Conflicting/read-only XMP remains locally saved and visibly pending; open the relevant photo or backup folder to inspect its saving status and use the existing explicit conflict/retry actions. Then resume again to check readiness. Missing/replaced files, changed source metadata or differing destination bytes stop rather than guess. Finish synchronization before renaming; moved/renamed destination files stop this immutable-plan resume, so restore the recorded names/locations before retrying. Do not delete local recovery data as a workaround.

If metadata was changed on the source by another app before planning, inspect that change and enable **Use Updated Source Metadata** to keep your explicitly set review stars/flags while using its current other fields. Malformed or ambiguous source packets must be fixed before copying. This option never writes to the source.

Normal copy/handoff routes still refuse protected sources; use the reviewed route to carry decisions safely. Metadata editing and renaming are disabled on the source. Closing a source, copying it or removing its sidebar shortcut does not remove protection; no unprotect command is available yet. Photo does not erase or eject the card. Photo-local composition transfers between these copies inside Photo, but is not baked into delivered pixels or Lightroom develop settings.

Keep Photo’s Application Support folder in backups: `decisions.sqlite` contains reviews/composition and `source-protection.json` contains protected-source bindings, and `Operations` contains saved copy lists/recovery events. The protection policy applies to this running Photo process, not other software or a forensic write blocker. Ambiguous reconnect/reformatted sources need a new review rather than guessing by filename. Removing local Photo data also removes reviews/protection. [Architecture and boundaries](decisions/0017-source-review-only.md).

## 10. Bulk rename

Rename before delivery or importing into your editor. Open **Bulk Rename** with **M** or Workflow:

1. Choose Selection, Visible photos or All files in folder.
2. Set a template, camera label and starting sequence.
3. Choose **Preview Names** and review every image/companion mapping.
4. Apply only the reviewed plan. Collisions or changed inputs stop the operation.

| Token | Meaning |
| --- | --- |
| `{date}` | Capture date `yyyyMMdd` |
| `{time}` | Capture time `HHmmss` |
| `{camera}` | Your camera label |
| `{original}` | Original stem |
| `{sequence}` | Sequence padded to at least six digits |

Example: `{date}_{time}_{camera}_{original}` preserves useful original identity; `{date}_{camera}_{sequence}` gives a shorter delivery sequence. Unique RAW+JPEG pairs share a sequence. Matching XMP/ACR follows the family. Templates needing absent capture times are refused. Clock/timezone correction is not implemented.

Rename one folder at a time. **Undo Last Rename** and **Recover Original Names** use durable journals and refuse changed/moved inputs. Later metadata writes can block a rename Undo to preserve those changes. Do not delete recovery journals as the first fix. After Lightroom import, use Lightroom to rename/move catalogued files.

## 11. IPTC, keywords and Lightroom

### Apply one shared field without flattening a batch

For 50 photos needing the same copyright but different captions:

1. Select the 50 and press **⌘I**, **I** or **⌘K**.
2. Initial values come from the first selected representative in contact-sheet order. The editor shows the physical file count.
3. Edit **Copyright notice** and choose that row’s **Preview Field** action.
4. Review the per-file before/after values.
5. Apply the reviewed fields. Each photo retains its caption, location, keywords, stars and unrelated settings.

Typing checks a field for the combined preview. The combined **Preview Metadata Changes** includes all checked nonempty fields plus the keyword action. Blank text is not deletion; choose **Clear** explicitly. Per-field preview includes only its one field, even if others are checked. Applying retains the selection.

Supported descriptions include creator, copyright/rights/URL, title, caption, credit, job identifier and separate location-created/location-shown fields. Existing unknown properties, language alternatives and develop settings are preserved semantically; ambiguous structured edits are refused.

### Presets and keywords

Use layered presets for author/rights, shoot/job/location and subject details. Save only the intended fields and keyword action; load then review before applying. Automatic ingest presets are not implemented.

| Keyword action | Effect |
| --- | --- |
| Leave unchanged | No keyword changes |
| Append | Add facts while retaining current tags |
| Remove | Remove the named tags |
| Replace | Replace the set deliberately |
| Clear | Explicitly empty the set |

Enter one keyword or hierarchy per line, e.g. `Wildlife|Birds|Herons`. Photo writes flat keywords and Lightroom-style hierarchy paths. Saved presets contribute suggestions. Full dictionary import/export, synonyms, export rules and code replacement remain future work.

### Undo metadata batches

**Undo Metadata Batch / Redo Metadata** in IPTC & Keywords retain the latest 20 batches across restart. The summary names changed fields and physical file count. They target the original batch files, independently of the current selection/folder. A new metadata batch clears Redo.

Replay checks every identity and expected owned value before committing intent, and restores only the batch’s owned fields/keywords. Later external edits to those fields or missing/replaced files stop the whole replay. Unrelated fields, stars, flags and develop settings retain current values. Sidecars synchronize per file after the local transaction; interrupted/failed writes remain pending. Native text Undo remains text editing while a field is focused.

### Hand off to Lightroom Classic

Resolve pending writes/conflicts first. Workflow’s **Deliver / Edit** tab can prepare a new dedicated verified copy of current-folder non-rejects, including XMP/ACR companions. Optional JPEG/PNG metadata embedding applies only to derived copies and verifies pixels/orientation. It does not apply Photo-local image edits. Reusing a differing derived destination is refused.

In Lightroom Classic, use **Add** for the prepared folder and Embedded & Sidecar previews. Avoid an import preset that replaces prepared metadata. Verify a small sample before a whole job. Direct source-plus-sidecar import is also possible for RAW workflows. JPEG/PNG full-filename sidecar recognition varies, which is why derived metadata copies are offered.

Actual application-level Lightroom round trips remain unverified. Field compatibility tests are not proof of full interchange. Cloud Lightroom is not an equivalent handoff target. See the [detailed workflow and research](WORKFLOW.md).

## 12. Saving, conflicts and recovery

| State | Meaning / action |
| --- | --- |
| Saving | In-memory change is queued; allow normal saving to finish |
| Saved | Decision/descriptive synchronization succeeded |
| Saved locally / XMP pending | Intent is durable in SQLite; resolve access errors and Retry XMP Sync |
| XMP conflict | External changes differ from the saved synchronization baseline; choose local or external explicitly |
| Image edits saved in Photo | Photo-local composition is durable; it is not an XMP/Lightroom edit |
| Local image-edit save failure | Fix the cause, then Retry Image Edit Save; Reload if the image changed |
| Preview unavailable | File/embedded preview failed; Try Again or Reload, while keeping originals |

Normal **⌘Q** drains queued saves and file operations. Forced termination can lose a change still marked Saving. Sidecar replacement is coordinated/atomic per file; a whole batch of filesystem writes is not one transaction.

RAW sidecars use `basename.xmp`; JPEG/PNG use `filename.ext.xmp`. Rejection never uses a star rating of −1 when writing independent decisions. Existing −1 ratings can import as rejected/unrated. Malformed/ambiguous XMP, symlinks and unsafe collisions are not silently overwritten.

Local data lives in `~/Library/Application Support/Photo`; see [installation/data locations](INSTALLATION.md#10-local-data-and-uninstalling). Include photos, companions, local SQLite state and operation journals in backups. Do not delete the database to resolve a sync conflict. Cached previews can remain stale until Reload after external pixel edits.

## 13. Keyboard reference

Browser shortcuts yield to modal editors and native text editing. Hover help and Help → Quick Start explain controls.

| Shortcut | Action |
| --- | --- |
| ⌘O / ⌘R | Open / Reload folder |
| Arrows / Home / End | Navigate photos; up/down move a grid row or one filmstrip photo |
| Shift-arrow | Extend selection; with navigator focus, pan one view |
| Space / Escape | Toggle Preview / return to Contact Sheet |
| P / X / U | Pick / Reject / Unflag selection |
| 0–5 | Set stars; 0 clears |
| Shift + decision | Apply and advance once for a single representative |
| T / ⌘T | Toggle picks / select visible picks |
| ⌘A / ⌘D / ⇧⌘O | Select all / deselect / invert visible selection |
| ⌘Z / ⇧⌘Z | Undo / Redo decision or image edit in the current folder session |
| C / G / L / O | Compare / pin current / link zoom-pan / single image |
| ⇧⌘C | Crop focused photo |
| ⌘G / M | Ingest / Bulk Rename |
| I / ⌘I / ⌘K | IPTC & Keywords |
| ⌘M | Standard macOS Minimize |
| ⌘Q | Normal quit with save/operation barrier |

On compact Mac keyboards, Fn-left/right provide Home/End. Photo keeps Lightroom-style plain star numbers and P/X/U flags; it does not duplicate every Photo Mechanic shortcut. In particular, **C** already means Compare, so Crop uses **⇧⌘C**.

## 14. Current boundaries

Implemented features and open acceptance are tracked in [PROJECT_STATUS](../PROJECT_STATUS.md). Current limits include:

- Photo-local rotation/mirror/crop has no Lightroom/XMP crop exchange or baked export yet; arbitrary-angle straightening, exposure/color adjustments and a full pixel editor are absent.
- Color classes, GPS editing and external-editor launching are still planned after the requested rotate/crop priority.
- No continuous source watcher, recursive combined photo collection, HEIC or additional RAW extensions beyond the supported list.
- No RAW histogram, focus peaking or sensor exposure adjustment. Rendered/embedded appearances are not sensor exposure measurements.
- Crop ratio presets seed a rectangle; a locked-ratio resize and crop rotation are future work.
- Native physical trackpad, broader camera/storage/platform, compact-window and full VoiceOver/keyboard-only coverage must be distinguished from automated gesture/model tests.
- No installable signed/notarized release or automatic updater yet.
