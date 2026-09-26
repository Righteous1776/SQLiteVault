# SQLite Vault

**Current cumulative baseline: V0.2.1**

SQLite Vault is an iOS/iPadOS 26-first personal SQLite control plane. It centralizes many independent SQLite databases without destroying their original boundaries.

## V0.2.1 — Control Plane + Binary Assets

- iCloud Drive vault with local Application Support fallback.
- Import `.sqlite`, `.sqlite3`, and `.db` files through the system file importer.
- Native SQLite schema inspection using `sqlite_schema` and `PRAGMA`.
- Stable database identity based on Vault file names instead of refresh-time UUIDs.
- Persistent iCloud metadata catalog (`.SQLiteVault/catalog-v2.json`).
- Workspaces: logical multi-database groups with categories and tags.
- Workspace SQL: attach selected databases read-only as `db1`, `db2`, … and run cross-database `SELECT`, `JOIN`, and `UNION` queries.
- Database organization: category, tags, and favorite state without modifying source schemas.
- Global Search across the entire Vault or one Workspace: database names, schema definitions, and bounded row-content matches.
- Read-only single-database SQL Console backed by `sqlite3_stmt_readonly`.
- Apple-style UI: restrained Neumorphism for data surfaces, iOS 26 Liquid Glass for floating controls, SF Symbols Replace transitions for Morphicons-like state changes.
- iPhone + iPad navigation based on SwiftUI `NavigationSplitView`.
- Deployment target: **iOS/iPadOS 26.0**. No iOS 15 compatibility layer.

## Safety model

Source databases remain independent files. Workspace composition uses read-only SQLite `ATTACH` aliases and never rewrites the original databases. Global Search only runs read-only statements. User-visible SQL consoles reject write statements.

The control metadata catalog is separate from source SQLite files, so categories/tags/workspaces do not contaminate a novel database, app database, or any other project schema.

Future write support must use local working copies, validation, snapshotting, and coordinated iCloud commit.

## Search behavior

V0.2 performs federated live search rather than building a destructive central copy. A search:

1. scopes to the whole Vault or one Workspace,
2. matches database names and schema definitions,
3. searches up to 80 table/view objects per database,
4. checks up to 24 columns per object,
5. returns at most 8 row matches per object and 200 hits overall.

This keeps the first control-plane implementation bounded. A persistent local FTS cache can be added later without changing source databases.

## Build

The repository uses XcodeGen so the Xcode project is deterministic.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project SQLiteVault.xcodeproj -scheme SQLiteVault -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow targets `macos-26` and Xcode 26.6.

## iCloud setup before real-device use

1. Open the generated project in Xcode.
2. Select your Apple Developer team.
3. Enable iCloud Documents for `iCloud.com.zeostudio.SQLiteVault`, or change the bundle/container identifiers in `project.yml`, `Info.plist`, `SQLiteVault.entitlements`, and `ICloudVault.swift`.
4. Build to an iOS/iPadOS 26 device signed into iCloud Drive.

See `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, and `WORK_HANDOFF.md`.


## SQL safety

Interactive SQL accepts query-shaped statements only (`SELECT`, `WITH`, `EXPLAIN`). SQLite's own `sqlite3_stmt_readonly()` remains a second gate. Workspace database attachment is performed only by the app with read-only file URIs; user SQL cannot issue `ATTACH` / `DETACH`.

## iOS 26.0.1 + Binary Assets

- Deployment target remains iOS/iPadOS 26.0, which covers devices running 26.0.1 and later 26.x patch releases.
- Liquid Glass is native SwiftUI: `GlassEffectContainer`, `.glassEffect`, `.buttonStyle(.glass)` and `.glassProminent` are used for floating controls while high-density data stays on restrained solid/neumorphic surfaces.
- **Binary Assets** scans SQLite BLOB metadata without eagerly loading every document. It recognizes filename/path/title hints and common signatures for PDF, DOCX/DOC, XLSX, PPTX, RTF, images, ZIP and generic binary data.
- Full BLOB extraction happens only after the user chooses **Preview** or **Export**. Preview uses SwiftUI Quick Look; Export uses the system share sheet so the file can be opened in Files or another compatible app.
