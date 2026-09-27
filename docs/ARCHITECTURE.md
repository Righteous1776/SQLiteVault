# Architecture V0.3.5

## Principle

SQLite Vault is a **control plane**, not one giant user-data database. Every imported SQLite file remains independently recoverable. Workspaces provide logical composition, global search provides federation, and metadata is stored separately.

## Layers

1. **Vault storage** — iCloud Drive ubiquity container with explicit connection state and a visible local fallback path; fallback is never presented as cloud-synced.
2. **Control metadata** — coordinated JSON catalog in `.SQLiteVault/catalog-v2.json`; stores Workspaces, categories, tags, and favorites.
3. **SQLite engine** — direct system `libsqlite3`; user data paths remain read-only in V0.2.
4. **Schema analyzer** — `sqlite_schema`, `PRAGMA user_version`, `PRAGMA table_info`.
5. **Workspace engine** — ephemeral in-memory SQLite connection; source databases attach as read-only `db1`, `db2`, … aliases.
6. **Federated search** — bounded live search across selected SQLite assets; no physical merge required.
7. **Console UI** — dashboard, Workspace control, global search, schema browser, preview, SQL consoles, organization editors.
8. **Plugin contract** — declarative manifest reserved for domain-specific adapters without loading arbitrary executable code.

## Workspace query lifecycle

`Workspace metadata -> resolve file names -> create :memory: SQLite session -> ATTACH file URIs with mode=ro -> prepare user SQL -> sqlite3_stmt_readonly gate -> execute -> close session`

The alias list is intentionally deterministic within a Workspace session (`db1`, `db2`, ...). The UI displays the alias-to-file mapping above the editor.

## Global search lifecycle

`query -> scope (Vault/Workspace) -> database name match -> schema match -> bounded table/view scan -> result federation`

Search text is passed as a bound SQLite parameter. Table and column identifiers are separately quoted. Source databases never receive mutation statements.

## Stable identity

V0.1 generated a fresh UUID whenever the Vault refreshed. V0.2 replaces that with `DatabaseAsset.id == fileName`, which makes selection, metadata, Workspace membership, and search routing stable across refreshes. Rename support will require an explicit metadata migration in a future version.

## iCloud consistency rule

Do not treat iCloud Drive as a permanently-open network SQLite volume. V0.2 opens user databases read-only and keeps logical Workspace sessions short-lived. The write pipeline planned for V0.3 remains:

`iCloud master -> coordinated download/copy -> local working copy -> transaction -> WAL checkpoint -> integrity check -> close -> snapshot -> coordinated replacement -> metadata refresh`

## Metadata consistency

The control catalog uses `NSFileCoordinator` and atomic writes. V0.2 uses a simple latest-write catalog model suitable for the user's personal device set. Explicit conflict reconciliation/version history belongs to V0.3.

## Plugin direction

A `.sqliteplugin` package remains declarative rather than a dynamically loaded iOS binary. Planned contents:

- `manifest.json`
- `schema_match.json`
- `queries.sql`
- `views.sql`
- optional transformation declarations
- labels/icons

## Embedded Binary Asset pipeline

`EmbeddedFileService` opens source Vault databases read-only. Discovery never materializes every BLOB: it inspects candidate BLOB columns, byte length, a small prefix/suffix sample and nearby filename-like metadata. Row addressing uses `rowid` where available and falls back to a single primary key for `WITHOUT ROWID`-style schemas.

When the user explicitly chooses Preview or Export, only that BLOB is loaded and written to an isolated temporary directory. `quickLookPreview` handles in-app presentation and the system activity sheet handles export. Source SQLite files are never modified.

## iCloud control plane

`ICloudVault.statusSnapshot()` is the source of truth for cloud availability. It checks the device iCloud identity token, resolves the exact ubiquity container, enumerates SQLite files in `Documents`, and reads ubiquitous resource metadata for download/upload/conflict state. `VaultStore` exposes that snapshot to `ICloudControlCenterView`, which polls while visible and provides manual download/migration actions.

The app deliberately does **not** open a remote SQLite file as a network database. iCloud Documents owns transport; SQLite Vault waits for local availability before meaningful database inspection. Imports written into the ubiquitous Documents container are uploaded by iCloud Drive. Remote-only placeholders can be requested with `startDownloadingUbiquitousItem(at:)`.

Unsigned CI artifacts validate compilation only. Real iCloud access additionally requires the installed app to be signed with an App ID/provisioning profile that authorizes `iCloud.com.zeostudio.SQLiteVault` and the `CloudDocuments` service.

## Optimized storage lifecycle

iCloud Documents remains the master storage layer. A downloaded ubiquitous SQLite file is treated as a **local materialization/cache**, not as a second source of truth. V0.3.3 uses this lifecycle:

`cloud placeholder -> explicit/required download -> locally available SQLite -> read-only inspection/query -> close -> eligible cache -> safe eviction -> cloud placeholder`

A normal Vault listing never downloads an item merely because it exists in iCloud. `DatabaseAsset.localAvailability` exposes `available`, `downloading`, or `remoteOnly`, and database engines only inspect locally available assets.

Before local eviction, SQLite Vault requires the ubiquitous item to be fully uploaded and downloaded, with no upload/download in progress and no unresolved conflict. The app then calls `FileManager.evictUbiquitousItem(at:)`, which removes the local materialization while retaining the iCloud item. It never uses `removeItem(at:)` for optimization.

Retention policy is split into a global mode and per-database protection:

- **Optimize Device Storage** — automatic cleanup only under storage pressure; recently used databases are protected.
- **Keep All Downloaded** — requests all cloud databases and disables local-copy removal in the UI.
- **Manual** — no automatic download/eviction decisions.
- **Always Keep Downloaded** — per-file pin persisted with `DatabaseMetadata`.

Favorites and the currently active database are protected from optimization even if they are not pinned. `lastOpenedAt` provides a conservative recency signal.

## A9 deterministic database-health lattice — V0.3.5

A9 is an advisory sidecar, not a repair engine. `A9DatabaseHealthService` consumes local SQLite diagnostics plus iCloud/preparation state and emits `A9Decision` values without mutating source files.

The state encoding is exact and deterministic:

`3 health colors × 4 priorities × 6 intervention levels × 2 persistence/blocker states = 144 states`

Canonical arbitration remains:

- P0 → L5
- RED + blocker → L4
- RED → L3
- YELLOW + P1 or persistent condition → L2
- YELLOW → L1
- GREEN → L0

The RED risk threshold is 28 points and persistent YELLOW is reached after 3 consecutive advisory passes. RED is latched in Application Support and is never automatically cleared by A9; acknowledgement is explicit.

Fast scans inspect cloud conflict/preparation state, local availability, file size and the canonical SQLite header. They do not force-download cloud-only databases and do not run expensive full-database checks. Deep scans additionally run `PRAGMA integrity_check` and bounded `PRAGMA foreign_key_check` against a read-only SQLite handle.

A stronger non-GREEN Deep decision is not overwritten by a later Fast pass. A subsequent Deep pass is required to reassess that evidence. Deleting a database also deletes its persisted A9 state so a later same-name import does not inherit an unrelated RED latch.
