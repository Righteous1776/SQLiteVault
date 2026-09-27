# WORK HANDOFF — SQLite Vault V0.3.6

## Source of truth
This directory is a **full cumulative source package**. Do not layer V0.1/V0.2/V0.3 packages on top of it.

Version: `0.3.6`  
Build: `11`  
Deployment target: iOS/iPadOS `26.0` (therefore compatible with 26.0.1)  
Target repo: `Righteous1776/SQLiteVault`

## Required upload flow
1. Use this cumulative directory as the replacement working tree for the app source/config/docs/tests.
2. Preserve repository history; commit the V0.3.5 changes on a branch or main according to the active workflow.
3. Generate with XcodeGen and run the GitHub `iOS 26 IPA` workflow.
4. Do not report success until both the Simulator build and unsigned iphoneos build pass.
5. Report commit SHA, Actions run URL/ID, and unsigned IPA artifact name.

## Regression acceptance checks
- Starting a vertical scroll on a metric/workspace card must scroll the page; the card must not capture the drag.
- `+`, language, and refresh toolbar controls must remain distinct in Chinese, English, and Japanese on iPhone-width layouts.
- Opening the language selector must frost the page and show one circular knob with three vertical language detents.
- Dragging the knob must provide repeated short tactile ticks; crossing a language detent must provide a stronger haptic and update the language without animated whole-page layout distortion.
- Releasing the knob must spring to the nearest detent.
- Refresh must show exactly one stable lifecycle: arrow -> progress -> check -> arrow, and ignore repeated taps while refreshing.
- Import must present the Files picker; selecting `.sqlite`, `.sqlite3`, or `.db` and pressing the system confirmation must invoke the delegate and import the copied file. Unsupported selections must show an error instead of silently doing nothing.


## iCloud acceptance checks
- On a correctly signed build with iCloud enabled, the sidebar iCloud row must show connected and the iCloud page must display `iCloud.com.zeostudio.SQLiteVault`.
- With iCloud unavailable or the provisioning profile missing the container, the app must show signed-out/container-unavailable rather than pretending sync is active.
- Importing a database while connected must place it in the iCloud Documents-backed Vault and expose it in the cloud file list.
- A remote-only ubiquitous SQLite item must offer Download and transition through downloading to locally available.
- Local fallback databases must be counted and the migration action must copy them into iCloud before removing the local source.
- Unresolved ubiquitous-file conflicts must surface in the file row and cloud metrics.

## Safety invariants
- Do not make source database SQL writable.
- Do not weaken SQLReadOnlyPolicy.
- Do not physically merge Workspace databases.
- Do not restore a zero-distance DragGesture to normal content cards.

## Optimized Storage acceptance checks
- In `Optimize Device Storage`, refreshing the Vault must not automatically download every remote-only SQLite file.
- Remote-only databases must remain visible in the sidebar and show a download placeholder instead of attempting SQLite inspection.
- `Download Database` must request the ubiquitous item and transition remote-only -> downloading -> available after iCloud reports completion.
- `Always Keep Downloaded` must persist per file and exclude that file from reclaimable storage.
- `Optimize Now` may evict only an uploaded, downloaded, idle, conflict-free file that is not pinned, favorite or currently open.
- Eviction must call `evictUbiquitousItem(at:)`, never `removeItem(at:)`; the cloud item must remain visible after the local copy is removed.
- Automatic optimization must run only in optimized mode and only when the device-storage pressure threshold is crossed; recently used files are protected.
- `Keep All Downloaded` must request all remote SQLite files and must not expose a remove-local-copy action.
- Device storage UI must report on-device cache, reclaimable bytes, free space, pinned count and cloud-only count.

## Storage Intelligence & Recovery acceptance checks
- Cache budget selection must persist across launches and Automatic must derive a bounded device-relative byte budget.
- Automatic optimization must run when either device free-space pressure is active or downloaded SQLite cache exceeds the selected budget.
- LRU ordering must prefer older database copies; a database opened within the last 30 minutes must not be automatically evicted.
- `Review Optimization` must show candidate files and estimated reclaimable bytes before a manual Optimize action.
- A cloud-only database must progress through download, SQLite header verification and `PRAGMA integrity_check` before becoming available to Schema/SQL/BLOB features.
- Temporary extracted BLOB previews must be measurable, manually clearable, and pruned after 24 hours on app bootstrap.
- Deleting a locally available database must first create a local recovery point; failure to create that point must block deletion.
- Manual recovery points must be restorable as a safe Vault copy without overwriting an existing database.
- iCloud unresolved conflict versions must be capturable into local Recovery before conflict resolution work.


## A9 Database Health acceptance checks
- Sidebar must expose `A9 Health` with a neutral state before first scan and GREEN/YELLOW/RED status afterward.
- A9 lattice must contain exactly 144 unique states covering 3 colors × 4 priorities × 6 levels × 2 persistence/blocker states.
- Canonical rules must remain P0→L5, RED+Blocker→L4, RED→L3, YELLOW+P1/persistent→L2, YELLOW→L1, GREEN→L0.
- RED risk threshold must remain 28 and persistent-yellow threshold must remain 3 unless a future migration explicitly versions the model.
- Fast scan must not run `PRAGMA integrity_check` or force-download cloud-only databases.
- Deep scan of a local database must run SQLite integrity and foreign-key checks read-only.
- RED latch must persist across scans and cannot be cleared automatically by A9; explicit acknowledgement is required.
- A9 must retain zero source mutation/repair/merge/freeze/cutover authority.
- Database detail navigation must remain scroll-safe and must not compress the five Overview/Schema/Files/A9/SQL sections into overlapping controls.


## V0.3.6 A9 Lifecycle + Preflight acceptance checks
- Import must run an external A9 Deep preflight plus objective SQLite header/integrity validation before copying into the Vault.
- Local and remote database opens must create an A9 lifecycle preflight record; Fast scans must not erase a stronger Deep YELLOW/RED finding.
- A canonical SHA-256 sqlite_schema fingerprint must be retained per database and schema drift must become an explicit A9 advisory signal.
- Fast schema-drift detection must not silently replace the trusted baseline; a clean Deep scan may accept the new baseline.
- Delete and local-copy eviction must preserve Recovery evidence when A9 marks the destructive action as requiring Recovery.
- Recovery metadata must retain the A9 state number/color and schema fingerprint that existed when the snapshot was created.
- Automatic storage optimization must protect non-GREEN A9 databases from eviction.
- A9 Health must expose recent lifecycle preflights and per-database health history without granting A9 source mutation authority.
