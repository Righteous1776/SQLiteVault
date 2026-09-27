from pathlib import Path
import json
import plistlib
import sqlite3
from PIL import Image

root = Path(__file__).resolve().parents[1]

required = [
    root/'project.yml', root/'README.md', root/'CHANGELOG.md', root/'WORK_HANDOFF.md', root/'LICENSE',
    root/'SQLiteVault/App/SQLiteVaultApp.swift', root/'SQLiteVault/App/VaultPreferences.swift',
    root/'SQLiteVault/Services/SQLiteDatabase.swift', root/'SQLiteVault/Services/ICloudVault.swift',
    root/'SQLiteVault/Services/VaultCatalogStore.swift', root/'SQLiteVault/Services/WorkspaceQueryEngine.swift',
    root/'SQLiteVault/Services/SQLReadOnlyPolicy.swift', root/'SQLiteVault/Services/CrossVaultSearchService.swift',
    root/'SQLiteVault/Services/EmbeddedFileService.swift', root/'SQLiteVault/Services/CacheMaintenanceService.swift', root/'SQLiteVault/Services/RecoveryService.swift', root/'SQLiteVault/Services/A9DatabaseHealthService.swift', root/'SQLiteVault/Services/A9LifecycleService.swift', root/'SQLiteVault/Services/SchemaFingerprintService.swift', root/'SQLiteVault/Models/EmbeddedBinaryAsset.swift', root/'SQLiteVault/Models/A9LatticeModels.swift', root/'SQLiteVault/Models/A9LifecycleModels.swift',
    root/'SQLiteVault/Models/ICloudModels.swift', root/'SQLiteVault/Models/StorageOptimizationModels.swift', root/'SQLiteVault/Models/StorageIntelligenceModels.swift', root/'SQLiteVault/Views/ICloudControlCenterView.swift',
    root/'SQLiteVault/Views/RootView.swift', root/'SQLiteVault/Views/InteractionSystem.swift',
    root/'SQLiteVault/Views/SQLiteDocumentPicker.swift', root/'SQLiteVault/Views/WorkspaceViews.swift',
    root/'SQLiteVault/Views/GlobalSearchView.swift', root/'SQLiteVault/Views/EmbeddedFilesView.swift', root/'SQLiteVault/Views/A9HealthViews.swift',
    root/'SQLiteVault/Resources/zh-Hans.lproj/Localizable.strings',
    root/'SQLiteVault/Resources/en.lproj/Localizable.strings',
    root/'SQLiteVault/Resources/ja.lproj/Localizable.strings',
    root/'SQLiteVault/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png',
    root/'.github/workflows/ios26-ci.yml',
]
missing = [str(p) for p in required if not p.exists()]
if missing:
    raise SystemExit('Missing required files:\n' + '\n'.join(missing))

with open(root/'SQLiteVault/Resources/Info.plist','rb') as f:
    plistlib.load(f)
with open(root/'SQLiteVault/Resources/SQLiteVault.entitlements','rb') as f:
    plistlib.load(f)

# Asset catalog is structurally valid and app icon is 1024 square.
with open(root/'SQLiteVault/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json') as f:
    json.load(f)
icon = Image.open(root/'SQLiteVault/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')
assert icon.size == (1024, 1024)

# Sample databases remain intact.
checks = [
    ('SQLiteVaultDemo.sqlite', 'chapters', 3),
    ('SQLiteVaultResearchDemo.sqlite', 'notes', 3),
]
for filename, table, expected in checks:
    con = sqlite3.connect(root/'Samples'/filename)
    assert con.execute(f"select count(*) from {table}").fetchone()[0] == expected
    assert con.execute("pragma integrity_check").fetchone()[0] == 'ok'
    con.close()

# Workspace logical composition remains read-only and functional.
# This fixture only executes SELECT statements.  Use filesystem paths instead
# of URI attachments because Python's SQLite builds differ in ATTACH URI
# handling between local environments and the macOS Actions runner.
workspace = sqlite3.connect(':memory:')
for alias, filename in [('db1', 'SQLiteVaultDemo.sqlite'), ('db2', 'SQLiteVaultResearchDemo.sqlite')]:
    fixture_path = str((root/'Samples'/filename).resolve())
    workspace.execute(f"ATTACH DATABASE ? AS {alias}", (fixture_path,))
logical_count = workspace.execute(
    "SELECT count(*) FROM db1.chapters UNION ALL SELECT count(*) FROM db2.notes"
).fetchall()
assert logical_count == [(3,), (3,)]
workspace.close()

# Query-only SQL safety stays in both interactive query paths.
policy = (root/'SQLiteVault/Services/SQLReadOnlyPolicy.swift').read_text()
assert 'case "SELECT", "WITH", "EXPLAIN"' in policy
assert 'ATTACH' in policy and 'DETACH' in policy
for source in [
    root/'SQLiteVault/Services/SQLiteDatabase.swift',
    root/'SQLiteVault/Services/WorkspaceQueryEngine.swift',
]:
    assert 'SQLReadOnlyPolicy().requireQueryOnly' in source.read_text(), source

# Binary asset fixtures and selective extraction contract.
con = sqlite3.connect(root/'Samples'/'SQLiteVaultDemo.sqlite')
rows = con.execute("SELECT filename, length(payload), hex(substr(payload,1,8)) FROM embedded_documents ORDER BY id").fetchall()
assert len(rows) == 2
assert rows[0][0].endswith('.pdf') and rows[0][2].startswith('25504446')
assert rows[1][0].endswith('.docx') and rows[1][2].startswith('504B0304')
assert con.execute("pragma integrity_check").fetchone()[0] == 'ok'
con.close()

embedded_service = (root/'SQLiteVault/Services/EmbeddedFileService.swift').read_text()
embedded_view = (root/'SQLiteVault/Views/EmbeddedFilesView.swift').read_text()
assert 'SQLITE_OPEN_READONLY' in embedded_service
assert 'quickLookPreview' in embedded_view
assert 'UIActivityViewController' in embedded_view

# V0.3.4 real iCloud + storage-intelligence checks.
icloud_service = (root/'SQLiteVault/Services/ICloudVault.swift').read_text()
icloud_models = (root/'SQLiteVault/Models/ICloudModels.swift').read_text()
icloud_view = (root/'SQLiteVault/Views/ICloudControlCenterView.swift').read_text()
root_view_v032 = (root/'SQLiteVault/Views/RootView.swift').read_text()
entitlements = plistlib.load(open(root/'SQLiteVault/Resources/SQLiteVault.entitlements','rb'))
for token in ['ubiquityIdentityToken', 'statusSnapshot()', 'requestDownloadAll()', 'migrateLocalFallbackDatabasesToICloud()', 'startDownloadingUbiquitousItem', 'evictUbiquitousItem', 'optimizeLocalCopies(', 'ubiquitousItemIsUploadedKey']:
    assert token in icloud_service, token
for token in ['ICloudVaultStatus', 'ICloudFileStatus', 'isUploaded', 'filesNeedingDownload', 'conflictCount']:
    assert token in icloud_models, token
for token in ['Sync Now', 'Move to iCloud', 'Cloud Diagnostics', 'Review Optimization', 'Remove Local Copy', 'Always Keep Downloaded']:
    assert token in icloud_view, token
assert 'case iCloud' in root_view_v032 and 'ICloudControlCenterView()' in root_view_v032
assert entitlements['com.apple.developer.icloud-services'] == ['CloudDocuments']
assert 'iCloud.com.zeostudio.SQLiteVault' in entitlements['com.apple.developer.icloud-container-identifiers']
assert 'iCloud.com.zeostudio.SQLiteVault' in entitlements['com.apple.developer.ubiquity-container-identifiers']

# V0.3.1 regression checks.
root_view = (root/'SQLiteVault/Views/RootView.swift').read_text()
interaction = (root/'SQLiteVault/Views/InteractionSystem.swift').read_text()
picker = (root/'SQLiteVault/Views/SQLiteDocumentPicker.swift').read_text()
preferences = (root/'SQLiteVault/App/VaultPreferences.swift').read_text()

# No SwiftUI fileImporter regression; delegate picker must be used as copy.
assert '.fileImporter(' not in root_view
assert 'SQLiteDocumentPicker' in root_view
assert 'UIDocumentPickerViewController' in picker
assert 'asCopy: true' in picker
assert 'documentPicker(_ controller:' in picker

# Card scrolling regression: no zero-distance card drag remains.
assert 'DragGesture(minimumDistance: 0' not in interaction
assert 'struct InteractiveTiltPanel' in interaction
assert '.hoverEffect(.lift)' in interaction

# Language dial must contain magnetic detents, spring snapping and gear haptics.
for token in ['LanguageGearDialOverlay', 'gearTick()', 'gearDetent()', 'magnetized(', '.spring(', '.ultraThinMaterial']:
    assert token in interaction, token
assert 'character.book.closed' not in preferences
assert 'globe' in root_view

# Refresh is a single state machine, not a refreshPulse Boolean.
assert 'RefreshVisualState' in root_view
assert 'refreshPulse' not in root_view
assert 'case .refreshing' in root_view and 'case .success' in root_view

# Toolbar labels are fixed icon controls; language nativeName is not embedded in toolbar geometry.
assert 'toolbarIcon("plus"' in root_view
assert 'toolbarIcon("globe"' in root_view
assert 'preferences.language.nativeName' not in root_view

# All three language resources are meaningful, not empty/fallback-only.
for locale in ['zh-Hans', 'en', 'ja']:
    text = (root/f'SQLiteVault/Resources/{locale}.lproj/Localizable.strings').read_text()
    assert text.count('=') >= 35, locale


# Optimized storage must preserve cloud-master semantics and never auto-download during simple Vault listing.
storage_models = (root/'SQLiteVault/Models/StorageOptimizationModels.swift').read_text()
vault_store = (root/'SQLiteVault/Services/VaultStore.swift').read_text()
database_model = (root/'SQLiteVault/Models/DatabaseAsset.swift').read_text()
for token in ['OptimizedStorageMode', 'Optimize Device Storage', 'keepDownloaded', 'manual', 'StorageOptimizationStatus']:
    assert token in storage_models, token
for token in ['storageMode', 'optimizeStorageNow', 'setKeepDownloaded', 'removeLocalCopy', 'markDatabaseOpened']:
    assert token in vault_store, token
assert 'localAvailability' in database_model and 'remoteOnly' in database_model
list_block = icloud_service.split('func listDatabases()', 1)[1].split('func metadataDirectory()', 1)[0]
assert 'startDownloadingUbiquitousItem' not in list_block
assert 'isSafeEvictionCandidate' in icloud_service

# V0.3.4 storage intelligence and recovery checks.
intelligence_models = (root/'SQLiteVault/Models/StorageIntelligenceModels.swift').read_text()
recovery_service = (root/'SQLiteVault/Services/RecoveryService.swift').read_text()
cache_service = (root/'SQLiteVault/Services/CacheMaintenanceService.swift').read_text()
database_view = (root/'SQLiteVault/Views/DatabaseDetailView.swift').read_text()
for token in ['CacheBudgetPreset', 'DatabasePreparationPhase', 'StorageOptimizationPreview', 'RecoveryPoint']:
    assert token in intelligence_models, token
for token in ['createRecoveryPoint', 'listRecoveryPoints', 'snapshotURL', 'prune(maxCount']:
    assert token in recovery_service, token
for token in ['SQLiteVaultExtracted', 'purgeFiles(olderThan', 'TemporaryCacheSnapshot']:
    assert token in cache_service, token
for token in ['cacheBudgetPreset', 'optimizationPreview', 'prepareDatabaseForOpen', 'purgeTemporaryPreviewCache', 'createRecoveryPoint', 'restoreRecoveryPoint', 'captureConflictRecovery']:
    assert token in vault_store, token
for token in ['optimizationPreview(', 'cacheBudgetBytes', 'validateSQLiteFile', 'integrityCheck', 'unresolvedConflictVersionURLs']:
    assert token in icloud_service, token
for token in ['Local Cache Budget', 'Optimization Preview', 'Recovery', 'Review Optimization']:
    assert token in icloud_view, token
assert 'Download & Verify' in database_view
assert 'PRAGMA integrity_check' in (root/'SQLiteVault/Services/SQLiteDatabase.swift').read_text()

project = (root/'project.yml').read_text()
assert 'iOS: "26.0"' in project
assert 'MARKETING_VERSION: 0.3.6' in project
assert 'CURRENT_PROJECT_VERSION: 11' in project
assert 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' in project

workflow = (root/'.github/workflows/ios26-ci.yml').read_text()
assert 'Xcode_26.6.app' in workflow
assert 'SQLiteVault-V0.3.6-unsigned.ipa' in workflow

for p in root.rglob('*.swift'):
    text = p.read_text()
    if 'IPHONEOS_DEPLOYMENT_TARGET = 15' in text:
        raise SystemExit(f'iOS15 residue: {p}')


# V0.3.5 A9 deterministic database-health lattice.
a9_models = (root/'SQLiteVault/Models/A9LatticeModels.swift').read_text()
a9_service = (root/'SQLiteVault/Services/A9DatabaseHealthService.swift').read_text()
a9_view = (root/'SQLiteVault/Views/A9HealthViews.swift').read_text()
for token in ['stateCount = 144', 'persistentYellowThreshold = 3', 'redRiskThreshold = 28', 'case p0', 'A9Decision']:
    assert token in a9_models, token
for token in ['integrityCheck()', 'foreignKeyViolationCount', 'redLatched', 'acknowledgeRedLatch', 'Deep inspection deferred']:
    assert token in a9_service, token
for token in ['A9HealthConsoleView', 'DatabaseA9HealthView', r'State \(decision.stateNumber)/144', 'Deep Scan']:
    assert token in a9_view, token
assert 'case a9' in root_view and 'A9HealthConsoleView()' in root_view
assert 'case health = "A9"' in database_view and 'DatabaseA9HealthView' in database_view
assert 'runA9Scan(depth: .fast)' in vault_store
assert 'SQLReadOnlyPolicy().requireQueryOnly' in (root/'SQLiteVault/Services/SQLiteDatabase.swift').read_text()


# V0.3.6 A9 lifecycle preflight + schema fingerprinting.
a9_lifecycle_models = (root/'SQLiteVault/Models/A9LifecycleModels.swift').read_text()
a9_lifecycle_service = (root/'SQLiteVault/Services/A9LifecycleService.swift').read_text()
schema_fingerprint_service = (root/'SQLiteVault/Services/SchemaFingerprintService.swift').read_text()
for token in ['A9LifecycleAction', 'A9PreflightResult', 'A9HealthHistoryEntry', 'SchemaFingerprint', 'DatabaseLifecyclePhase']:
    assert token in a9_lifecycle_models, token
for token in ['recordDecision', 'recordPreflight', 'updateTrustedFingerprint', 'lifecycle-v1.json']:
    assert token in a9_lifecycle_service, token
for token in ['CryptoKit', 'SHA256.hash', 'sqlite_schema', 'PRAGMA user_version']:
    assert token in schema_fingerprint_service, token
for token in ['a9History', 'a9Preflights', 'schemaFingerprints', 'runA9Preflight', 'refreshA9LifecycleState']:
    assert token in vault_store, token
for token in ['scanImportSource', 'schema-fingerprint-drift', 'schemaDriftDetected']:
    assert token in a9_service, token
assert 'validateImportSource' in icloud_service
assert 'Before local eviction · A9' in vault_store
assert 'Before deletion · A9' in vault_store
assert 'Download & Verify this database before deletion' in vault_store
assert 'protected.formUnion(a9Decisions.compactMap' in vault_store
assert 'a9StateNumber' in intelligence_models and 'schemaFingerprint' in intelligence_models
assert 'Lifecycle preflight' in a9_view and 'Health history' in a9_view and 'Schema fingerprint' in a9_view

print('PACKAGE_VALIDATION_OK')
