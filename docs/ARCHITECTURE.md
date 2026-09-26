# Architecture V0.2

## Principle

SQLite Vault is a **control plane**, not one giant user-data database. Every imported SQLite file remains independently recoverable. Workspaces provide logical composition, global search provides federation, and metadata is stored separately.

## Layers

1. **Vault storage** — iCloud Drive ubiquity container, with local fallback for development/offline conditions.
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
