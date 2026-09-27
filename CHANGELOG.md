# Changelog

## V0.3.6 — Build 11

### Added
- A9 lifecycle preflight journal covering import, open, Recovery, conflict capture, local eviction, storage optimization and deletion.
- Canonical SHA-256 `sqlite_schema` fingerprint with persistent trusted-baseline drift detection.
- Per-database A9 health history and lifecycle-phase UI.
- Recovery snapshots now retain A9 state/color and schema-fingerprint metadata.
- External import Deep preflight before the file is copied into the Vault.

### Safety
- A9 remains advisory-only; objective SQLite validation and Recovery invariants remain the only hard mutation guards.
- Fast schema-drift scans never silently accept a changed baseline. A clean Deep scan is required before the new schema becomes trusted.
- Non-GREEN A9 databases are protected from automatic local-copy eviction.

## V0.3.5 — Build 10 — A9 Database Health Lattice

### Added
- Restored the original database-oriented `DBH-LATTICE-CHIP V0.9 A9` concept as a pure-Swift deterministic advisory engine.
- Exact 144-state lattice: 3 health colors × 4 priorities × 6 intervention levels × 2 persistence/blocker states.
- Canonical arbitration semantics: P0→L5, RED+Blocker→L4, RED→L3, persistent/P1 YELLOW→L2, YELLOW→L1, GREEN→L0.
- Risk threshold 28 and persistent-yellow threshold 3.
- Fast scan for lightweight header/cloud/preparation checks and Deep scan for `PRAGMA integrity_check` plus `PRAGMA foreign_key_check`.
- Persistent RED latch that A9 never clears automatically; explicit acknowledgement is required after review.
- Global A9 Health console plus per-database A9 detail tab with evidence signals, state number, risk, priority and level.
- Automatic Fast A9 pass after Vault refresh without forcing heavy integrity checks on every database.

### Safety
- A9 remains advisory-only with zero mutation, repair, merge, freeze or cutover authority.
- Existing SQL read-only policy is unchanged.
- Cloud-only databases are not downloaded merely for A9 Fast scans.
- Database detail section navigation is horizontally scrollable so the fifth A9 tab cannot compress or overlap on iPhone layouts.

## V0.3.4 — Build 9

### Added
- Storage Intelligence layer with configurable local SQLite cache budgets: Automatic, 1 GB, 5 GB, 10 GB, and Unlimited.
- LRU-aware automatic eviction driven by both device free-space pressure and cache-budget overage.
- Optimization Preview sheet that lists every safe eviction candidate and estimated reclaimable bytes before a manual cleanup runs.
- Download preparation state machine: request -> download progress -> SQLite header verification -> `PRAGMA integrity_check` -> ready.
- Temporary BLOB/Quick Look extraction cache accounting, 24-hour startup pruning, and explicit cache clearing.
- Recovery service with local restore points, automatic snapshot-before-delete, manual restore points, restore/delete actions, and iCloud conflict-version capture.

### Safety
- Automatic eviction protects the active database, favorites, pinned databases, active transfers, conflicts, files not fully uploaded, and databases opened within the last 30 minutes.
- Destructive deletion of a locally available database now requires a recovery snapshot first; if that snapshot cannot be created, deletion does not continue.
- A remote database is not handed to Schema/SQL/BLOB readers until its download completes and SQLite validation succeeds.

## V0.3.3 — Build 8

### Added
- Apple-style **Optimize Device Storage** mode with iCloud master copies and reclaimable local SQLite caches.
- `Keep All Downloaded` and `Manual` storage-management modes.
- Per-database **Always Keep Downloaded** retention policy persisted in the Vault catalog metadata.
- On-demand remote database placeholder UI with explicit download before Schema/SQL/BLOB access.
- Local-copy eviction through `FileManager.evictUbiquitousItem(at:)`; the iCloud item remains intact.
- Device storage metrics: downloaded cloud bytes, reclaimable bytes, free device space, pinned files and cloud-only files.
- Explicit **Optimize Now** action plus conservative automatic cleanup under device-storage pressure.
- Last-opened tracking used to avoid evicting recently used databases.

### Safety
- Local eviction requires the iCloud file to report fully uploaded, downloaded, idle and conflict-free.
- Favorites, pinned databases, and the database currently in use are never automatic eviction candidates.
- Normal Vault refresh no longer calls `startDownloadingUbiquitousItem` for every remote database.

## V0.3.2 — Build 7

### Added
- Visible iCloud Control Center in the primary sidebar.
- Real iCloud account/container status from `ubiquityIdentityToken` and the SQLite Vault ubiquity container.
- Per-database ubiquitous-file state: downloaded, downloading, uploading, remote-only and conflict.
- Manual cloud download requests and `Sync Now` for outstanding remote SQLite files.
- Explicit local-fallback inventory and one-tap migration of fallback databases into iCloud Drive.
- Cloud diagnostics showing the exact container identifier, connection state and last status check.
- iCloud `CloudDocuments` and iCloud-container entitlements in addition to the ubiquity entitlement.

### Changed
- iCloud failure is no longer invisible in the product UI. The app clearly reports local fallback, signed-out and provisioning/container errors.
- Dashboard iCloud status now reflects the real current cloud state instead of a static capability row.

## V0.3.1 — Build 6

### Fixed
- Removed the card-level `DragGesture(minimumDistance: 0)` interaction that competed with vertical scrolling.
- Reworked runtime language switching so locale changes no longer participate in matched-geometry layout animation.
- Replaced variable-width language/new-item toolbar labels with fixed-size icon controls.
- Replaced the unstable refresh pulse with a single `idle -> refreshing -> success -> idle` visual state machine.
- Replaced SwiftUI `fileImporter` with an explicit UIKit document picker delegate path and `asCopy: true` behavior.
- Import errors now surface through the app error alert instead of being silently discarded.

### Added
- Three-detent tactile language dial for 简体中文 / English / 日本語.
- Full-screen frosted material background during language selection.
- Circular raised/glass knob with restrained skeuomorphic depth.
- Magnetic resistance around language detents, spring snap on release, repeated short rigid haptic ticks while traversing gear teeth, and stronger detent impacts.
- Full English localization resource rather than fallback-only English strings.
- `SQLiteDocumentPicker.swift` and package-level regression assertions for the known V0.3.0 interaction bugs.

## V0.3.0 — Build 5
- Runtime localization preferences and Chinese/Japanese/English language support.
- Tactile motion/haptic layer and dashboard interaction refinements.
- iOS 26 unsigned IPA workflow.

## V0.2.1 — Build 4
- Binary Assets scanner, selective BLOB extraction, Quick Look preview and system export.
- iOS/iPadOS 26.0 deployment target (covers iOS 26.0.1 and later 26.x releases).
