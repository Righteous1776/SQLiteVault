# 0.2.1 — iOS 26.0.1 / Binary Assets

- Added Vault-wide **Binary Assets** browser and per-database **Files** tab.
- Added low-memory BLOB discovery using metadata + head/tail signature probes.
- Added filename inference from `filename`, `file_name`, `path`, `name`, `title`, `original_name`, `document_name`, and `attachment_name` style columns.
- Added file signature detection for PDF, Office Open XML, legacy Word/OLE, RTF, PNG/JPEG/GIF/TIFF/HEIC, ZIP and generic binary data.
- Added selective extraction to a temporary file only when Preview/Export is requested.
- Added native SwiftUI Quick Look previews and system share-sheet export.
- UI remains iOS/iPadOS 26 native with Liquid Glass controls and reduced-motion-aware transitions.
- Added embedded PDF and DOCX fixtures to `SQLiteVaultDemo.sqlite`.

# Changelog

## V0.2.0 — Workspace Control Plane

- Promoted SQLite Vault from single-database viewer baseline to a multi-database control plane.
- Replaced refresh-time random database UUIDs with stable file-name identity.
- Added coordinated iCloud control metadata catalog (`catalog-v2.json`).
- Added persistent Workspaces with multi-database membership, category, tags, created/updated timestamps.
- Added database category, tags, and favorites without modifying source SQLite schemas.
- Added Workspace editor and Workspace dashboard.
- Added ephemeral read-only multi-database `ATTACH` sessions (`db1`, `db2`, ...).
- Added Workspace SQL Console for cross-database `SELECT`, `JOIN`, and `UNION` queries.
- Hardened both SQL consoles with an explicit query-only statement allow-list before SQLite readonly checks, closing the `ATTACH`/`DETACH` gap in `sqlite3_stmt_readonly`.
- Added parameter-bound global search across database names, schema definitions, and bounded row data.
- Added whole-Vault and Workspace-scoped search.
- Added result routing back to the matching source database.
- Added a second sample SQLite database for multi-database validation.
- Expanded validation script and unit-test contracts.
- Preserved V0.1.1 Apple / Neumorphic design system and read-only safety model.

## V0.1.1 — Apple / Neumorphic UI pass

- Added a centralized `DesignSystem.swift` for visual tokens and reusable UI primitives.
- Rebuilt Dashboard as a high-information personal data control plane.
- Applied restrained Neumorphism to content cards and inset editor surfaces.
- Adopted iOS 26 Liquid Glass only for important controls and selected states.
- Added SF Symbols Replace transitions and spring-driven state changes as the native SwiftUI equivalent of Morphicons-style icon morphing.
- Rebuilt database overview, schema browser, schema detail, query preview, and SQL Console.
- Added schema search.
- Added reduced-motion handling for section and action transitions.
- Preserved the V0.1 read-only SQL and iCloud data-safety model without service-layer mutations.

## V0.1.0 — 2026-09-26
- Established iOS/iPadOS 26-only baseline.
- Added iCloud Drive vault and local fallback.
- Added SQLite import, schema analyzer, row preview, and read-only SQL console.
- Added Workspace and plugin data contracts.
- Added GitHub Actions macOS 26 / Xcode 26.6 build gate.
- Added sample SQLite database and local package validator.
