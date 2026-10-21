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


## Photo Home and workflow language — 2026-10-20

Native review passed the migrated Home tree, its subfolders, explanatory chooser/cancel, default copy destination, numbered copy setup and Deliver / Edit guidance. No copying or decisions were applied to personal photos. A Home text badge crowded the root name at the default sidebar width; use the house icon plus accessible Photo Home name instead. Folder fields no longer say absolute path, working root or backup root, and accessibility names avoid duplicated “folder.”

The retained synthetic composition also restored after relaunch; Fit and physical-pixel 100% now visibly clip the rotated/mirrored crop correctly. This closes the previous lock-blocked final crop/restart check. Physical pinch remains hands-on acceptance work. News/wire and large-shoot routes are documented without claiming local-only pre-copy culling, rendered publication exports or 40k-photo performance as implemented.


## Protected source review — 2026-10-20

Native checks used three copied bundled synthetic PNGs in a disposable writable source with a child folder. Workflow → Ingest → Review Before Copying opens the collection and presents a persistent source-protected/review-only banner. Four stars and Pick remained independent; keyboard Undo/Redo restored the flag. Rotation and crop saved locally and displayed correctly. Child navigation retained protection and its three-star decision. After a normal quit and final-build relaunch, the child reviewed count/decision and parent stars/Pick/crop restored.

The source metadata button and workflow metadata controls are disabled with an explanation. A fully populated copy form using disposable destinations reports that protected-review copying is not available; neither destination was created. Original source listing and all three hashes match, with no XMP files. A read-only query restricted to this disposable session confirmed local review state/composition. The source shortcut/photos were removed and the original user folder/selection restored without personal decisions/edits. Real-card unplug/remount, larger collections, compact-window/VoiceOver and physical pinch remain separate acceptance work.


## Workflow walkthrough — 2026-10-20

Native optimized-build checks passed the Ingest invitation, five numbered steps and concrete examples, screenshot inspection of both card and guide, Back, Return/Next, Close/Escape and focus returning to the parent sheet. Not Now disappears only for the current panel; reopening restores it. Explicit permanent dismissal remained hidden after normal quit/relaunch. Help → Photo Quick Start & Shortcuts → Workflow Walkthrough reopened it while dismissed; unchecking restored the invitation. The default invitation was left enabled for the user. No photo decision, source protection, metadata, copy or rename operation was executed. The original folder/selection remained intact. The walkthrough adds headings and progress accessibility labels; this is not a full VoiceOver/compact-display/platform audit. Runtime save/protection messages remain outside help dismissal.


## Reviewed-copy completion — 2026-10-20

Final optimized native app: verified protected-source entry/banner and Copy Reviewed Photos… entry point, independent P/4 + rotation on the first synthetic PNG, X/2 on the second, child-folder P/3, source-root restoration in the copy panel, disposable photo/backup/shoot entries, and the menu listing all/picks/non-rejected/selection scopes. The native connection closed while attempting to prepare Picks Only. Photo remained running; direct refresh, rebind and runtime reset did not restore the native bridge. Plan summary/actual copy/explicit destination navigation/resume/relaunch and final visual acceptance are therefore not claimed as native-verified. Automated WorkflowModel/core tests cover those functional boundaries.

Read-only checks of only this disposable session show three durable reviewed rows with the expected values and rotation. Original directory listing and all three PNG plus original XMP hashes match; no native copy destinations exist. The source/temporary shortcut and copy-panel context remain at `/private/tmp/photo-reviewed-native-ns1lo9zw` for acceptance follow-up; the original personal view and unflagged/unrated selection are recorded only in the local task handoff. No personal photo decisions, metadata or protection were changed. Restore the original view and remove only test shortcuts/photos once native access returns; retain intentional local test history/protection. Do not bypass the disconnected bridge with another UI driver or delete the global source registry.

## Ingest setup clarity — 2026-10-20

Replaced the long scrolling form with source, destination, confirmation and progress pages. The source page explicitly offers cull-first versus complete-shoot copying, explains where thumbnails appear, and makes Start Culling the primary action. The protected-source banner explains P/X/U/stars and opens copy setup directly; Picks Only is the initial reviewed scope. Long inventories and saved recovery use separate bounded views. Native checks covered both copy routes, Back/replanning, separate file review, saved resume/relaunch, visible primary actions and original-image preservation. Fixed the false rename-recovery warning from reviewed-copy journals and stale previous-copy controls. The tracker records exact scope and remaining broader display/accessibility/media acceptance.

## Keyboard review, in-window ingest and Trash — 2026-10-20

Review Only Selected now explains its restricted scope, requires two selected representatives, shows the frozen physical-file count and exits through Show All Photos. Focusing one item is deliberate so decisions apply individually. Context/summary/save lines retain height; native ratings while at 100% retain inspection. Z enters/toggles inspection from both browsing layouts, [/] rotate, B/N browse regardless of inspection mode and ⇧⌘C opens a quick crop. Prefer a focus/flag pass, then keeper-only composition and captions.

The main window now hosts workflow setup, with explicit Back to Photos, Return to Culling and Cull While Copying callbacks and the source-banner return to copy setup. Screenshots at the current reference window size show source/destination setup without an outer scroll view. Native source → culling/P → copy setup/default Picks Only → return passed. Detailed lists/help/confirmations remain separate; full copy execution was not repeated natively for this presentation change. The browser stays mounted; some picker-label text still appears in the accessibility tree while hidden, so full VoiceOver traversal remains acceptance work.

Remove → Select Rejects (⇧⌘X) → Move Selected to Trash (⌘Delete) exposes exact images and exclusive XMP/ACR companions, picked-photo warnings, Escape cancellation and Return confirmation. Protected-source removal is visibly disabled. Native testing moved only two disposable rejects plus their XMPs into actual macOS Trash and immediately retained the keeper in the collection. Their known individual names/hashes were used to restore exactly those four test files; no other Trash contents were inspected or changed. Final shortcut/cancel checks preserve all restored files. Original image and pre-move working sidecar hashes match. Finder Put Back is the documented user recovery path; that Finder UI action, physical/network-volume availability, large-batch throughput, compact-window and broad accessibility/platform acceptance were not tested here. No personal photos were edited/deleted. The original folder/filter/focus and sidebar were restored before handoff.
