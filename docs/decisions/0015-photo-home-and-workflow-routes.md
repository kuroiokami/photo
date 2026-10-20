# 0015 — Photo Home and publication/editor workflow routes

- Date: 2026-10-20
- Status: Accepted navigation and product direction; source-review wizard planned

## Context

The user requests ordinary folder language and a stable home with a browsable tree. The app serves urgent wire/news delivery without Lightroom as well as large shoots before an editor. Lightroom must be optional, while fast embedded previews remain the primary browsing path.

## Decision

Photo Home is a remembered navigation shortcut, not an import, filesystem root or managed catalog. It appears first with a house icon. Choose it explicitly on a fresh installation; migrate the first existing saved folder on older installations. Changing it retains other saved folders. The context action keeps the active collection; the chooser opens the chosen Home and reveals its immediate subfolders. Removing Home clears its designation, including across restart. No filesystem contents are changed and subfolders remain loaded on demand. An unset ingest Photo folder falls back to Home; explicitly remembered copy destinations retain precedence.

Use Photo folder, Backup folder and Shoot name in copy setup, with numbered copy steps and a Deliver / Edit tab. Keep Lightroom-specific instructions inside that optional route. Existing copies contain originals and metadata, not rendered Photo-local edits or agency uploads.

## Planned source review and consequences

Pre-copy culling must use local-only decisions and leave source/card bytes and sidecars unchanged. It requires explicit reviewed copy scope, identity-protected decisions across restart/reconnection, safe transfer to copied identities and tests of family completion/filtering/cancellation. Ordinary source browsing currently attempts XMP writes, so it cannot be labeled as this mode. A future guided flow must retain direct browsing and verified-arrival culling.

Publication-ready JPEG rendering and 10–40k-photo performance are explicit future acceptance work, not capabilities established by these interface changes. Home does not recursively collect images or automatically move previous shoots. Folder shortcuts remain path-based and can need re-selection after a drive/folder moves.
