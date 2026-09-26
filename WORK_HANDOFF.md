# WORK HANDOFF — SQLite Vault V0.2.1

## Current cumulative state

V0.2.1 is the first real **control-plane** release candidate. It is cumulative on V0.1.1 and retains the Apple / Neumorphic UI design contract. Deployment target remains iOS/iPadOS 26.0.

## Implemented in V0.2

- Persistent iCloud metadata catalog for Workspaces and organization metadata.
- Stable database identity across refreshes.
- Workspace create/edit/delete.
- Logical grouping of multiple SQLite databases without physical merge.
- Database/Workspace category and tags; database favorites.
- Read-only Workspace `ATTACH DATABASE` sessions with `db1`, `db2`, ... aliases.
- Cross-database SQL Console.
- Global Search across the entire Vault or one Workspace.
- Search matches database names, schema definitions, and bounded row content.
- Second sample database for multi-database validation.

## Safety contract

- User source databases remain independent and recoverable.
- Single-database SQL Console remains read-only.
- Interactive SQL is first gated by an explicit query-only allow-list (`SELECT` / `WITH` / `EXPLAIN`), then checked with `sqlite3_stmt_readonly`; Workspace source files are attached using `mode=ro`.
- Global Search performs only read-only queries and uses bound user search text.
- V0.2 does **not** implement physical merging or direct source-database editing.
- Do not treat iCloud Drive as a permanently-open network SQLite volume.

## UI design contract

- Continue using `emilkowalski/skills` → `skills/apple-design/SKILL.md` as interaction reference.
- Neumorphism remains restrained and data-readable.
- Liquid Glass is reserved for navigation, selection, and primary actions.
- Morphicons intent is implemented natively through SF Symbols replace transitions/springs; do not add a JS runtime.
- Respect Reduced Motion and system accessibility settings.

## Validation completed locally

- Swift 6.2 parser: all Swift sources parse with 0 syntax errors.
- `scripts/validate_package.py` must return `PACKAGE_VALIDATION_OK` before upload.
- Both sample SQLite files must return `PRAGMA integrity_check = ok`.
- Full Xcode/iOS 26 typecheck and simulator build still require GitHub Actions / Xcode 26.6.

## Repository mission

Upload/replace the standalone `SQLiteVault` repository with this cumulative V0.2.1 package, commit to `main`, and run `ios26-ci.yml`.

## Non-negotiable product decisions

- Primary target: iOS/iPadOS 26.0+.
- Primary devices: iPhone 13 and iPad.
- Do not add an iOS 15 compatibility layer.
- Product is a personal SQLite control plane, not merely a file viewer.
- Logical Workspace composition is the default way to combine databases.
- Physical merge remains a separate future Merge Lab output.
- Control metadata must remain separate from source databases.

## Upload / CI procedure

1. Create `SQLiteVault` if the standalone repository still does not exist.
2. Unpack this cumulative package at repository root.
3. Commit all source, docs, two sample DBs, tests, and workflow files.
4. Push to `main`.
5. Run `ios26-ci.yml`.
6. Fix build/configuration defects only; preserve architecture and read-only safety constraints.
7. Report repository URL, commit SHA, CI run URL/status, and any remaining signing/iCloud-container steps.

## CI acceptance gate

- XcodeGen project generation succeeds.
- iOS 26 simulator compile succeeds with signing disabled.
- Unit tests compile/run where a matching simulator runtime is available.
- Workspace SQL compiles with system `libsqlite3`.
- No write-capable or user-controlled `ATTACH`/`DETACH` SQL path is introduced.

## V0.2.1 handoff additions

- Runtime target: iOS/iPadOS 26.0+, specifically intended for 26.0.1 devices. Do not change deployment target to `26.0.1`; Apple deployment targets use the SDK-supported major/minor baseline, and 26.0 covers 26.0.1.
- Verify `Binary Assets` on both iPhone and iPad.
- Verify Quick Look with `Samples/SQLiteVaultDemo.sqlite` → `embedded_documents` PDF and DOCX rows.
- Verify Export presents the system activity view and exports the extracted file with the inferred filename/extension.
- Keep extraction read-only and on-demand; do not preload all BLOB payloads.
