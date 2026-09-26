# Roadmap

## V0.1 — Baseline ✅
- iOS/iPadOS 26 shell
- iCloud vault
- import
- schema inspection
- row preview
- read-only SQL console

## V0.1.1 — Apple / Neumorphic UI ✅
- shared design system
- restrained Neumorphism
- iOS 26 Liquid Glass controls
- Morphicons-style native symbol transitions
- schema search and UI refinement

## V0.2 — Workspace Control Plane ✅
- persistent iCloud Workspace catalog
- stable database identity
- logical multi-database grouping
- controlled read-only `ATTACH DATABASE`
- Workspace cross-database SQL
- categories / tags / favorites
- whole-Vault or Workspace-scoped global search
- bounded schema + row-content federation

## V0.3 — Safe Editing & Version Timeline
- local working copies
- transaction editor
- snapshots and rollback
- integrity checks
- conflict detection
- coordinated iCloud commit
- control-catalog history/conflict recovery

## V0.4 — Plugin Runtime
- `.sqliteplugin` manifest parser
- schema matching
- named read-only queries
- domain views for novel / VeilLink / study databases

## V0.5 — Merge Lab
- schema fingerprinting
- mapping suggestions
- conflict report
- non-destructive physical merge into a new output database

## Later optimization
- optional local FTS/search cache for very large Vaults
- background incremental indexing without modifying source databases
- richer relation graph and schema diff tools
