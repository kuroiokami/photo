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
2. **Live ingest arrivals:** retain selection and decisions while verified arrivals appear incrementally. Current ingest permits early browsing, but new arrivals require Reload. Automatic ingest naming/metadata presets remain future work. [Ingest](https://docs.camerabits.com/support/solutions/articles/48000207409-ingesting-photos)
3. **Compare near duplicates:** pin a reference and compare two photos with synchronized focus inspection. Camera Bits provides a reference/active-pane 2-Up workflow; Photo currently has one detail pane. This is a high-value next culling feature, subject to the existing detail memory budget. [2-Up previews](https://docs.camerabits.com/support/solutions/articles/48000340032-viewing-2-up-previews)
4. **Metadata efficiency:** field history, dictionary import/export, synonyms and export rules, metadata Undo, richer IPTC field coverage and user/client variables/code replacement. Existing presets and hierarchy are a foundation, not a complete controlled-vocabulary system. [Metadata documentation](https://docs.camerabits.com/support/solutions/folders/48000243593)
5. **Discoverability and access:** native hover help and a Quick Start sheet are implemented. A dismissible first-use walkthrough, configurable thumbnail shooting-information labels, VoiceOver/keyboard-only coverage and shortcut customization remain planned. Rectangle selection currently covers the viewport and does not auto-scroll.

FTP/publishing, catalog indexing and editing are not needed for this delivery. Prioritize latency, safe organization and reliable Lightroom interchange before broadening the product.
