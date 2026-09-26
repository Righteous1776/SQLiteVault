# SQLite Vault

SQLite Vault is an iOS/iPadOS 26 native control plane for personal SQLite assets. It keeps source databases independent, groups them into logical Workspaces, provides bounded cross-database search, read-only SQL, and discovers embedded binary documents for selective preview/export.

## Current release

**V0.3.6 / Build 10 — A9 Database Health Lattice**

This release restores the database-native A9 lattice as a first-class health arbitration layer while preserving the existing iCloud, optimized-storage, Recovery, Workspace, read-only SQL, and tactile UI systems. A9 is implemented as a pure-Swift advisory sidecar with zero source-database mutation authority.

- Scroll-safe cards: content cards no longer install a zero-distance drag gesture, so vertical ScrollView/List scrolling starts normally from a card.
- Stable toolbar: the trailing toolbar is reduced to fixed-size `+`, `globe`, and refresh controls so language text cannot collide with adjacent actions.
- Reliable import: SwiftUI `fileImporter` is replaced with `UIDocumentPickerViewController(forOpeningContentTypes:asCopy:)`, with a delegate callback and explicit error path.
- Refresh state machine: `idle -> refreshing -> success -> idle`; no competing Boolean-driven symbol replacement.
- Runtime localization: Simplified Chinese, English, and Japanese resources are bundled.
- Tactile language dial: a full-screen frosted overlay with a circular three-detent language control, magnetic resistance, spring snapping, short rigid gear-tooth haptics, and stronger detent feedback.
- Liquid Glass is reserved for high-level navigation/controls. Content surfaces retain restrained neumorphic depth for readability.



### Optimized Storage

- `Optimize Device Storage` keeps iCloud as the master copy and treats downloaded ubiquitous SQLite files as a reclaimable local cache.
- Simple Vault refresh no longer forces every remote database to download. Remote-only databases remain visible and can be downloaded on demand.
- `Keep All Downloaded` requests every database for offline use; `Manual` disables automatic download/eviction decisions.
- Per-file `Always Keep Downloaded` pins protect selected databases from eviction. Favorites and the database currently open are also protected.
- `Optimize Now` removes only safe local copies. A file must be fully uploaded, downloaded, conflict-free, idle, and unpinned before `evictUbiquitousItem(at:)` is allowed. The iCloud master copy is never deleted by optimization.
- Automatic optimization is conservative: it only runs in optimized mode under device-storage pressure and targets files that have not been used recently.
- Device storage metrics expose local SQLite cache size, reclaimable bytes, free device space, cloud-only count and pinned count.

### Real iCloud control layer

- Dedicated iCloud page in the sidebar with live connection state instead of silent fallback.
- Checks `ubiquityIdentityToken` and the exact `iCloud.com.zeostudio.SQLiteVault` container.
- Reads per-file ubiquitous metadata for local availability, download/upload activity and unresolved conflicts.
- `Sync Now` requests outstanding cloud downloads; iCloud Drive continues to manage upload transport for files written into the app container.
- Local fallback SQLite files are surfaced explicitly and can be migrated into iCloud Drive.
- The app now distinguishes signed-out, container-unavailable, connected and error states.
- Entitlements declare `CloudDocuments`, the iCloud container, and the ubiquity container.


## A9 Database Health Lattice (V0.3.6)

SQLite Vault now embeds the database-native A9 arbitration core as a pure-Swift advisory sidecar. A9 maps observed SQLite/cloud health signals into an exact 144-state lattice: GREEN/YELLOW/RED × P0–P3 × L0–L5 × transient/persistent-or-blocker. Fast scans stay lightweight; Deep scans add `PRAGMA integrity_check` and `PRAGMA foreign_key_check`. RED is latched and cannot be silently cleared by the chip. A9 has zero authority to mutate, repair, merge, freeze or cut over source databases.

## Data safety

SQLite Vault treats imported databases as copied Vault assets. Interactive SQL remains query-only and passes both the explicit SQL allow-list and SQLite read-only statement checks. Workspace SQL uses read-only ATTACH aliases and does not physically merge source files.

## Embedded files

BLOB scanning is metadata-first. Full binary contents are materialized only for a selected Preview/Export action. The current scanner recognizes common PDF, Office/OpenXML, image, archive, and generic binary signatures and tries nearby filename/name/path/title metadata.

## Build

The project is generated with XcodeGen.

```bash
xcodegen generate
xcodebuild -project SQLiteVault.xcodeproj -scheme SQLiteVault -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions targets macOS 26 + Xcode 26.6 and also produces an unsigned device IPA artifact.


## Storage Intelligence & Recovery (V0.3.4)
SQLite Vault now treats downloaded iCloud databases as a managed local cache. A selectable cache budget and LRU policy work alongside device free-space pressure. Manual optimization always provides a preview before eviction. Cloud-only databases pass a download + SQLite validation state machine before inspection. Temporary extracted documents are tracked separately and can be cleared without touching database masters. Local Recovery stores restore points before destructive deletion and can capture unresolved iCloud conflict versions.


## A9 lifecycle preflight (V0.3.6)
A9 now follows database lifecycle transitions rather than operating only as a scan screen. Import, open, Recovery, conflict capture, local eviction, optimization and deletion produce persistent preflight evidence. SQLite Vault also computes a canonical SHA-256 fingerprint from `sqlite_schema` + `user_version`; unexpected drift becomes advisory evidence until a clean Deep scan confirms the new schema baseline. Recovery snapshots record the A9 state and schema fingerprint present when the snapshot was created. A9 remains advisory-only and cannot write, repair, merge, freeze, or cut over a source SQLite database.
