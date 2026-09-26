from pathlib import Path
import plistlib, sqlite3

root = Path(__file__).resolve().parents[1]
required = [
    root/'project.yml', root/'README.md', root/'WORK_HANDOFF.md',
    root/'SQLiteVault/App/SQLiteVaultApp.swift',
    root/'SQLiteVault/Services/SQLiteDatabase.swift',
    root/'SQLiteVault/Services/ICloudVault.swift',
    root/'SQLiteVault/Services/VaultCatalogStore.swift',
    root/'SQLiteVault/Services/WorkspaceQueryEngine.swift',
    root/'SQLiteVault/Services/SQLReadOnlyPolicy.swift',
    root/'SQLiteVault/Services/CrossVaultSearchService.swift',
    root/'SQLiteVault/Services/EmbeddedFileService.swift',
    root/'SQLiteVault/Models/EmbeddedBinaryAsset.swift',
    root/'SQLiteVault/Views/WorkspaceViews.swift',
    root/'SQLiteVault/Views/GlobalSearchView.swift',
    root/'SQLiteVault/Views/EmbeddedFilesView.swift',
    root/'.github/workflows/ios26-ci.yml',
]
missing = [str(p) for p in required if not p.exists()]
if missing:
    raise SystemExit('Missing required files:\n' + '\n'.join(missing))

with open(root/'SQLiteVault/Resources/Info.plist','rb') as f:
    plistlib.load(f)
with open(root/'SQLiteVault/Resources/SQLiteVault.entitlements','rb') as f:
    plistlib.load(f)

checks = [
    ('SQLiteVaultDemo.sqlite', 'chapters', 3),
    ('SQLiteVaultResearchDemo.sqlite', 'notes', 3),
]
for filename, table, expected in checks:
    con = sqlite3.connect(root/'Samples'/filename)
    assert con.execute(f"select count(*) from {table}").fetchone()[0] == expected
    assert con.execute("pragma integrity_check").fetchone()[0] == 'ok'
    con.close()


# Validate the V0.2 logical-composition idea with two read-only ATTACH aliases.
workspace = sqlite3.connect(':memory:')
for alias, filename in [('db1', 'SQLiteVaultDemo.sqlite'), ('db2', 'SQLiteVaultResearchDemo.sqlite')]:
    uri = (root/'Samples'/filename).resolve().as_uri() + '?mode=ro'
    workspace.execute(f"ATTACH DATABASE ? AS {alias}", (uri,))
logical_count = workspace.execute(
    "SELECT count(*) FROM db1.chapters UNION ALL SELECT count(*) FROM db2.notes"
).fetchall()
assert logical_count == [(3,), (3,)]
assert workspace.execute("SELECT count(*) FROM db2.notes WHERE topic LIKE '%Tokyo%' OR body LIKE '%Tokyo%'").fetchone()[0] == 1
workspace.close()

# Safety contract: both interactive query paths must pass the explicit query-only gate.
policy = (root/'SQLiteVault/Services/SQLReadOnlyPolicy.swift').read_text()
assert 'case "SELECT", "WITH", "EXPLAIN"' in policy
assert 'ATTACH' in policy and 'DETACH' in policy
for source in [
    root/'SQLiteVault/Services/SQLiteDatabase.swift',
    root/'SQLiteVault/Services/WorkspaceQueryEngine.swift',
]:
    assert 'SQLReadOnlyPolicy().requireQueryOnly' in source.read_text(), source


# Binary-asset fixtures and implementation contract.
con = sqlite3.connect(root/'Samples'/'SQLiteVaultDemo.sqlite')
rows = con.execute("SELECT filename, length(payload), hex(substr(payload,1,8)) FROM embedded_documents ORDER BY id").fetchall()
assert len(rows) == 2
assert rows[0][0].endswith('.pdf') and rows[0][2].startswith('25504446')
assert rows[1][0].endswith('.docx') and rows[1][2].startswith('504B0304')
assert con.execute("pragma integrity_check").fetchone()[0] == 'ok'
con.close()

embedded_service = (root/'SQLiteVault/Services/EmbeddedFileService.swift').read_text()
embedded_view = (root/'SQLiteVault/Views/EmbeddedFilesView.swift').read_text()
assert "SQLITE_OPEN_READONLY" in embedded_service
assert "substr(" in embedded_service and "65536" in embedded_service
assert "quickLookPreview" in embedded_view
assert "UIActivityViewController" in embedded_view
assert "Binary Assets" in (root/'SQLiteVault/Views/RootView.swift').read_text()

project = (root/'project.yml').read_text()
assert 'iOS: "26.0"' in project
assert 'MARKETING_VERSION: 0.2.1' in project
assert 'CURRENT_PROJECT_VERSION: 4' in project

for p in root.rglob('*.swift'):
    text = p.read_text()
    if 'IPHONEOS_DEPLOYMENT_TARGET = 15' in text:
        raise SystemExit(f'iOS15 residue: {p}')

print('PACKAGE_VALIDATION_OK')
