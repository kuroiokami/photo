# Photo Mechanic review and Photo workflow gaps

Reviewed 2026-10-19 against the [requested documentation index](https://docs.camerabits.com/support/solutions/48000450977) and current Camera Bits articles linked below. These are workflow references, not measured comparisons or a claim of complete Photo Mechanic compatibility.

## Navigation and decisions

Camera Bits describes folder navigation, reusable favorites, Command/Shift group selection, tagged selection and contact-sheet context menus. Photo adopts these patterns with saved sidebar roots and lazy subfolder disclosure, range/additive/rectangle selection, visible batch flag actions and contextual metadata access. Removing a sidebar shortcut never removes a directory. Browsing remains one directory at a time; expanding the tree does not recursively load photos. [Contact sheets](https://docs.camerabits.com/support/solutions/articles/48000207551-contact-sheets-an-overview)

| Keys in Photo | Result | Choice |
| --- | --- | --- |
| ⌘O / ⌘A | Open folder / select all visible photos | Shared familiar actions |
| ⌘D / ⇧⌘O | Deselect / invert selection | Adopted |
| T / ⌘T | Toggle selected picks / select visible picks | Adapt Photo Mechanic tags to Photo picks |
| ⌘G | Open Ingest | Adopted |
| M | Open Bulk Rename | Adopt contact-sheet alias; ⌘M retains macOS Minimize |
| I / ⌘I / ⌘K | Open IPTC & Keywords | Shared destination; Photo does not split individual Info and batch Template windows |
| P / X / U, 0–5 | Pick / reject / clear flag, independent stars | Retain Lightroom-oriented decisions |
| Shift + decision | Apply and advance for one selected representative | Existing behavior; batch decisions retain selection |
| Shift + arrow | Extend selection from a stable anchor | Native range-selection convention |
| Space / Escape | Toggle / hide preview | Existing behavior |

Photo Mechanic uses P/X/U differently in some contexts; copying those meanings would break Photo's established culling workflow. Its Control-number star aliases and color-class shortcuts are not adopted in this change. Unmodified browser shortcuts are unavailable while the workflow editor is open so ordinary typing and text Select All remain native. [macOS shortcuts](https://docs.camerabits.com/support/solutions/articles/48000317772-keyboard-shortcuts-macos)

## Field-specific metadata

Camera Bits distinguishes single-photo Info from the batch Template and supports copying into a template and applying to selected photos. Photo uses one editor: values come from the first selected representative in current contact-sheet order; typing checks that field; a per-field preview constructs a patch containing only that field. The combined preview includes checked nonempty fields and explicit keyword actions. Blank text is not deletion: Clear must be chosen. Review names and before/after values before applying. This avoids copying every populated field across a batch. [Metadata Info](https://docs.camerabits.com/support/solutions/articles/48000341504-using-the-metadata-info-tool-iptc-)

## Prioritized remaining work

This is a proposed backlog for the app's fast culling → organization → Lightroom goal, not implemented functionality or automatic authorization for further scope.

1. **Interoperability and resilience:** verify actual Lightroom import/round trips in an isolated catalog, including flags, hierarchy, location and preserved develop settings; exercise removable-drive interruptions and broaden RAW camera coverage. Existing field tests are not an application round trip.
2. **Ingest automation:** live verified destination arrivals are implemented for Photo ingest. Continuous source watching and automatic naming/metadata presets remain future work. [Ingest](https://docs.camerabits.com/support/solutions/articles/48000207409-ingesting-photos)
3. **Comparison acceptance:** pinned two-pane comparison and linked zoom/pan are implemented with explicit 512 MiB combined retained-detail allowance. Broaden camera, memory and accessibility testing. [2-Up previews](https://docs.camerabits.com/support/solutions/articles/48000340032-viewing-2-up-previews)
4. **Metadata efficiency:** persistent owned-field batch Undo/Redo is implemented. Dictionary import/export, synonyms/export rules, richer IPTC coverage and variables/code replacement remain planned. [Metadata documentation](https://docs.camerabits.com/support/solutions/folders/48000243593)
5. **Discoverability and access:** hover help, Quick Start, selected-only review and configurable EXIF thumbnail labels are implemented. First-use walkthrough, VoiceOver/keyboard-only coverage and shortcut customization remain planned. Rectangle selection does not auto-scroll.

FTP/publishing, catalog indexing and editing are not needed for this delivery. Prioritize latency, safe organization and reliable Lightroom interchange before broadening the product.

## Preview-screen review — 2026-10-20

Inspected the current Preview Window article and its illustrated large-image/bottom-filmstrip/right-info arrangement, the 2-Up reference/active-pane workflow, critical-focus controls, thumbnail-label customization and live ingest documentation. This is a product-fit assessment; it does not establish comparative speed. Photo’s requested Preview layout is implemented in this follow-up; the table below records the approved implementation and remaining proposals.

| Priority | Addition | Why it helps culling / implementation boundary |
| --- | --- | --- |
| Implemented | Pin a reference for two-photo comparison; optionally link pan/zoom | Judge adjacent burst frames while keeping the stronger frame fixed. Budget both detail images explicitly and keep expensive RAW work deliberate. |
| Implemented | Selected-only review set | Isolate a burst or shortlist in the filmstrip without changing ratings/flags. Define what happens when selection changes so photos do not unexpectedly disappear. |
| Implemented: thumbnail rows | Configurable thumbnail/Info fields | Let photographers choose exposure, focal length, capture time or camera labels from already indexed EXIF. Keep the filmstrip compact and reserve room for filenames/decisions. |
| Arrivals implemented; presets planned | Live verified arrivals and optional ingest naming/metadata presets | Remove manual Reload while ingesting. Publish stable, verified files; preserve selection, decisions and collision protection. |
| Batch Undo implemented; other features planned | Metadata Undo, field history, richer vocabulary and code replacement | Speed repetitive captioning without copying unrelated values; keep existing XMP preservation and conflict handling. |
| Deliberate inspection | Histogram and highlight/shadow overlays with explicit source labels | Embedded JPEG or rendered RGB information must not be described as sensor RAW exposure data. Measure their cost before adding background work. |
| Usability | Review-only full-screen mode, adjustable panels and keyboard/accessibility passes | Give the photo more room on small displays while keeping an obvious route back to the contact sheet. |

The full approved comparison/review/labels/arrivals/metadata-Undo list is implemented; broader native/accessibility acceptance and workflow interoperability are the next priorities. Lightroom round-trip verification remains acceptance work alongside these proposals. Arbitrary zoom magnifications, rotation/crop editing, external-editor integration and publishing are lower priority for the current fast-culling scope.

References: [Preview Window and screen illustrations](https://docs.camerabits.com/support/solutions/articles/48001144384-the-preview-window), [2-Up previews](https://docs.camerabits.com/support/solutions/articles/48000340032-viewing-2-up-previews), [critical focus and linked scrolling](https://docs.camerabits.com/support/solutions/articles/48000207552-how-to-zoom-and-check-for-critical-focus), [thumbnail labels](https://docs.camerabits.com/support/solutions/articles/48000960641-customize-thumbnail-labels-in-contact-sheets), [live ingest](https://docs.camerabits.com/support/solutions/articles/48000341503-live-ingest).

## Basic editing audit and first implementation — 2026-10-20

Read the installed Photo Mechanic’s **Image, Edit, File and Tools menus**, and opened its existing selected image in Preview to inspect zoom/crop/rotation/metadata/inspection controls. Closed only that newly opened preview afterward; no image-edit/file-operation commands were applied to its personal photos. Cross-checked Camera Bits documentation. This is a feature inventory and workflow assessment, not a comparative performance or usability study.

The user chose **rotate/mirror and crop first**. The first implementation includes direct thumbnail stars/flags, contact-sheet rotation/mirror/crop context actions, a crop editor, crop copy/paste, persistent Photo-local composition, session Undo and trackpad magnification. Adobe crop/orientation interchange and applied export remain acceptance/implementation work; local display edits are not claimed to transfer to Lightroom.

| Basic Photo Mechanic function | Photo status / next work |
| --- | --- |
| Contact-sheet stars and tag controls | Interactive stars and independent pick/reject/unflag menu; selection-wide actions, persistence and Undo. Tags are adapted to picks. |
| Rotate left/right and horizontal/vertical mirror | Implemented as protected Photo-local composition, including selected batches and thumbnails. No hard JPEG rotation. |
| Crop preview, move/resize and removal | Implemented rectangular Photo-local crop with corner handles, numeric percentages, grid/shield, ratio seeds, Cancel/Apply/Clear and Reset. |
| Copy/paste crop from contact sheet | Implemented normalized crop copy/paste to a selection, retaining each target’s other edits. |
| Locked-ratio resizing, crop angle/straightening and crop settings snapshots | Remaining; current ratios seed a centered crop and subsequent resizing is free. |
| Zoom levels, linked inspection and navigator | Magnification, Fit/exact physical 100%, pan/navigator and linked comparison implemented. Physical pinch device coverage remains separately recorded. |
| IPTC template/snapshots, keyword panels and structured keywords | Reviewed presets, one-field/batch patches and hierarchy implemented; full snapshots/code replacement/dictionary features remain gaps. |
| Color classes and remapping to stars | Planned after the user’s rotate/crop priority; stars and flags remain independent. |
| Set/import/reverse-geocode GPS; capture-clock correction | Not implemented. Existing metadata remains preserved. |
| External editor / droplet integration | Planned. Existing manual Lightroom Classic handoff is distinct from launching an editor. |
| Copy/move, rename and saved output | Verified ingest/handoff copies and reviewed rename exist. General move/copy browser, crop-applied export and output resizing remain gaps. |
| Histogram and highlight/shadow inspection | Planned with explicit preview/rendered-source labels; no claim of sensor-RAW exposure measurement. |
| Selection by crop/rotation/rating/date; Find/Replace and saved selection files | Selected review/picks/filter/rating selection exists in part; broader selectors/search/selection files remain gaps. |
| Resolution/ICC conversion, RAW→DNG, embedded-JPEG extraction, metadata stripping, hard JPEG rotation | Not implemented; separate conversion/destructive utilities are outside this first composition chunk. |
| Slideshows, print, email/FTP/upload and publishing | Not implemented; lower priority for the folder-first culling/Lightroom goal. |

References: [current Image menu](https://camerabits.freshdesk.com/support/solutions/articles/48001282950-image-menu), [current contact-sheet controls](https://docs.camerabits.com/support/solutions/articles/48000207551), [legacy documented soft rotation](https://docs.camerabits.com/support/solutions/articles/48001252577--legacy-rotate-photos), [legacy documented crop interactions/copy/paste](https://docs.camerabits.com/support/solutions/articles/48001252575--legacy-crop-tool-in-photo-mechanic), [external editor workflow](https://docs.camerabits.com/support/solutions/articles/48001077633-sending-photos-from-photo-mechanic-to-external-editors). Legacy articles are labeled deliberately; the installed app supplied the current menu/preview inventory.

## Thumbnail control follow-up — 2026-10-20

Camera Bits' [current contact-sheet guide](https://docs.camerabits.com/support/solutions/articles/48000207551) documents hover controls at four image corners: rotation at the top, IPTC at bottom left and Preview at bottom right. Photo adopts that arrangement, adds Crop at bottom center and Mirror at top center, and keeps controls visible on selected thumbnails for discoverability. Stars/flags remain below the image. The existing shared Image row and keyboard commands remain available. Actions reuse protected local edits and existing IPTC workflow; no Photo Mechanic artwork, private photos or proprietary implementation is copied. Native evidence and remaining accessibility/platform acceptance are recorded in the tracker.
