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

    var shortName: String {
        switch self {
        case .simplifiedChinese: "中"
        case .english: "EN"
        case .japanese: "日"
        }
    }

    var index: Int {
        switch self {
        case .simplifiedChinese: 0
        case .english: 1
        case .japanese: 2
        }
    }

    static func language(at index: Int) -> VaultLanguage {
        switch min(max(index, 0), 2) {
        case 0: .simplifiedChinese
        case 1: .english
        default: .japanese
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
