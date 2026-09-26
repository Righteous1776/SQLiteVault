import SwiftUI
import Observation

enum VaultLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var nativeName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    var symbol: String {
        switch self {
        case .simplifiedChinese: "character.book.closed.fill.zh"
        case .english: "character.book.closed.fill"
        case .japanese: "character.book.closed.fill.ja"
        }
    }
}

@Observable
final class VaultPreferences {
    private static let languageKey = "SQLiteVault.interfaceLanguage"

    var language: VaultLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.languageKey)
        language = VaultLanguage(rawValue: saved ?? "") ?? .simplifiedChinese
    }
}
