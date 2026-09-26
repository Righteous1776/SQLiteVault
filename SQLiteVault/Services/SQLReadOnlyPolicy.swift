import Foundation

struct SQLReadOnlyPolicy: Sendable {
    enum PolicyError: LocalizedError, Equatable {
        case blockedStatement(String)

        var errorDescription: String? {
            switch self {
            case .blockedStatement(let keyword):
                let label = keyword.isEmpty ? "Unknown statement" : keyword
                return "SQLite Vault SQL Console is query-only. \(label) is not allowed."
            }
        }
    }

    /// First-line policy gate for the interactive consoles.
    ///
    /// `sqlite3_stmt_readonly()` is still checked after prepare, but SQLite
    /// intentionally reports ATTACH/DETACH as readonly because they do not
    /// directly modify database-file contents. This explicit allow-list keeps
    /// connection-changing statements out of the console entirely.
    func requireQueryOnly(_ sql: String) throws {
        let keyword = firstKeyword(in: sql)
        switch keyword {
        case "SELECT", "WITH", "EXPLAIN":
            return
        default:
            throw PolicyError.blockedStatement(keyword)
        }
    }

    func firstKeyword(in sql: String) -> String {
        let scalars = Array(sql.unicodeScalars)
        var index = 0

        func skipWhitespace() {
            while index < scalars.count,
                  CharacterSet.whitespacesAndNewlines.contains(scalars[index]) {
                index += 1
            }
        }

        while index < scalars.count {
            skipWhitespace()
            guard index < scalars.count else { return "" }

            // SQL line comment: -- ... newline
            if index + 1 < scalars.count, scalars[index] == "-", scalars[index + 1] == "-" {
                index += 2
                while index < scalars.count, scalars[index] != "\n", scalars[index] != "\r" {
                    index += 1
                }
                continue
            }

            // SQL block comment: /* ... */
            if index + 1 < scalars.count, scalars[index] == "/", scalars[index + 1] == "*" {
                index += 2
                var closed = false
                while index + 1 < scalars.count {
                    if scalars[index] == "*", scalars[index + 1] == "/" {
                        index += 2
                        closed = true
                        break
                    }
                    index += 1
                }
                if !closed { return "" }
                continue
            }
            break
        }

        let start = index
        while index < scalars.count {
            let scalar = scalars[index]
            let isLetter = CharacterSet.letters.contains(scalar)
            let isUnderscore = scalar == "_"
            guard isLetter || isUnderscore else { break }
            index += 1
        }

        guard index > start else { return "" }
        return String(String.UnicodeScalarView(scalars[start..<index])).uppercased()
    }
}
