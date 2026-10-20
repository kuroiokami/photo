# Interface review — 2026-10-19

Reviewed the contact sheet, folder sidebar, preview/inspector, zoom controls, navigator, selection/filter controls, menu shortcuts and all four workflow panels. This is an implementation audit with targeted native checks, not a completed usability study.

| Area | Improvement and evidence |
| --- | --- |
| Detail overview | Click to center, drag frame preserving grab offset, clamp edges, quarter/full-view keyboard panning and named accessible actions. Native click/drag/edge/arrow/Center checks passed on a Sony RAW. |
| Detail controls | Segmented Fit/100% exposes selected mode; Cancel is separate while loading. Stable caption height avoids progressive-stage reflow. Native selected state and finished RAW badge verified. |
| Small images | Center at actual display-pixel scale without enlargement; native-scroller regression passes. |
| Batch decisions | Common stars/flags reflect the physical target set independently; mixed values are explicit. Core regression and native mixed-star feedback checks pass. Larger buttons and scope tooltips reduce ambiguity. |
| Folder/sidebar | Larger disclosure/remove targets, accurate Expand/Collapse labels, readable Workflow shortcut. Native labels inspected. |
| Filters/selection | Horizontal controls fall back to two rows. Clear Filters and Select All disable when unavailable. Compact-window native resizing could not be verified reliably. |
| Ingest/rename | Persistent source/destination/job/template/camera/sequence labels, specific chooser accessibility names, top-aligned rename controls and preview-before-apply. Native layout inspected; no personal files renamed/ingested. |
| Metadata | Visible Preview Field buttons, target count grammar, smaller preset menu, disabled empty actions, explicit keyword intent and instructions. Native states inspected; no personal metadata applied. |
| Handoff | Scrollable panel and explicit source/copy explanation. Native panel inspected; no Lightroom interchange attempted. |

Navigator focus changes arrow/Home/End menu actions to panning. Outside that focus they retain photo navigation/range selection. Hover help and Quick Start explain the behavior. Reopening workflow clears stale review plans, requiring a fresh review before applying.

Remaining: full VoiceOver and keyboard-only traversal, minimum-size window verification, Intel/minimum macOS coverage, native frame/input measurements and independent photographer usability testing. Accessibility labels/actions being present does not establish full VoiceOver usability. No screenshots containing personal photos are stored in Git.

## Preview layout follow-up — 2026-10-20

The preview is now above a horizontal bottom filmstrip, with an explicit full Contact Sheet view. Filename/navigation and decisions use compact horizontal controls; the optional information pane sits beside the image. Separate in-session thumbnail sizes and full-area empty/filter/error states keep the two modes usable.

Native verification on an isolated release build passed layout proportions, range selection, sample batch Pick, Undo and Space-to-grid. Final changes add missing-EXIF feedback and selected-index reveal; automated checks and standard release packaging passed. A locked Mac prevented final standard-app, compact-window, long-filmstrip and inspector checks. Those are pending, alongside full VoiceOver and platform coverage. The temporary review bundle and unused synthetic fixture were removed; no personal metadata was edited.

## Full approved follow-up — 2026-10-20

Native standard-app checks now pass the prior pending information-pane, long-filmstrip Home/End reveal and empty Picks recovery cases. Comparison has visible reference/active roles and a decision-scope explanation. Linked 100% on synthetic 4000×3000 fixtures pans both navigators equally; unlink pans only the active pane, and relink aligns the reference. Photo navigation resets both to Fit. Selected-only review freezes three members while navigating individually. EXIF row labels are spoken in thumbnail accessibility values; two selected rows disable additional choices.

Metadata Apply/Undo/Redo passed on a disposable two-photo copyright batch with visible field/count summaries. Dual ingest showed 26 images automatically after 28 image/companion files completed; no Reload was used. This run did not capture a mid-copy native event; automated callback/merge tests cover publication timing and state preservation. Quick Start now scrolls while its Done button remains outside the scroll area; native final guide content/scroll/Done accessibility inspection passed. Relaunch retained label choices and metadata Undo; replay after restart synchronized its original two files. Two real 60 MP Sony ARWs completed linked 100% detail/pan without decision writes.

Full VoiceOver/keyboard-only and minimum-size/platform acceptance remain open. The final native screenshots use synthetic photos; no private photo screenshot is stored in Git.

## Contact-sheet interaction and image editing — 2026-10-20

Selection images/filenames and decision buttons are separate controls. Native checks confirm unselected-tile rating, current-star clearing, a pick from the flag menu and a selected-group star action. Flag controls expose the actual state accessibly; direct clicks suppress auto-advance. Context menus expose explicit ratings and image-edit commands. Fit/exact 100% now have visible selected backgrounds and accessibility values while arbitrary detail magnification is shown in the caption.

Rotate/mirror, crop frame/shield/grid, corner resize, move/clamp, square ratio, numeric percentage commits, Apply and cropped-thumbnail markers passed native inspection on disposable PNGs. Crop's ratio menu uses its intrinsic width, corner handles have expanded hit areas, and Crop Cancel is independent of Apply. Main-folder requests activate Photo and fall back to its main window for sheets; the native picker worked after this correction. Competing folder/reload/culling commands yield to modal editing.

Native detail inspection exposed painting outside a crop's intended bounds. Drawing now explicitly clips the fitted composition, with source-pixel, letterbox and progressive-patch regressions. The Mac locked before final corrected-view/restart recheck. Physical pinch input cannot be generated through current automation; gesture/scroller/linked-scale/anchor tests are not a claim of physical device validation. Full VoiceOver, keyboard-only, compact-window and platform coverage remain open. Original photographs were not edited; synthetic pending-QA files stay outside Git.
