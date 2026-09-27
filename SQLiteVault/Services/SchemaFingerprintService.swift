import CryptoKit
import Foundation

struct SchemaFingerprintService: Sendable {
    func fingerprint(url: URL) throws -> SchemaFingerprint {
        let database = try SQLiteDatabase(url: url)
        let result = try database.query("""
        SELECT type, name, tbl_name, COALESCE(sql, '')
        FROM sqlite_schema
        WHERE name NOT LIKE 'sqlite_%'
        ORDER BY type, name, tbl_name, sql;
        """, rowLimit: 50_000)
        let userVersion = try database.scalarInt("PRAGMA user_version;")

        var canonical = "user_version=\(userVersion)\n"
        for row in result.rows {
            canonical += row.map { $0 ?? "NULL" }.joined(separator: "\u{1f}")
            canonical += "\n"
        }
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return SchemaFingerprint(
            digest: digest,
            objectCount: result.rows.count,
            userVersion: userVersion,
            sampledAt: .now
        )
    }
}
