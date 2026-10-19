import Foundation

enum L10n {
    static let preferenceKey = "nodebar.language"
    static let options = ["system", "en", "zh-Hans"]

    static var preference: String {
        let saved = UserDefaults.standard.string(forKey: preferenceKey)
        let bundled = Bundle.main.object(forInfoDictionaryKey: "NodeBarDefaultLanguage") as? String
        let value = saved ?? bundled ?? "system"
        return options.contains(value) ? value : "system"
    }

    static func language(for preference: String, preferredLanguages: [String]) -> String {
        if preference == "en" || preference == "zh-Hans" { return preference }
        for language in preferredLanguages {
            if language.lowercased().hasPrefix("zh") { return "zh-Hans" }
            if language.lowercased().hasPrefix("en") { return "en" }
        }
        return "en"
    }

    static var isChinese: Bool {
        language(for: preference, preferredLanguages: Locale.preferredLanguages) == "zh-Hans"
    }
}

/// Resolve UI and notification text locally; node names are always preserved.
func L(_ chinese: String, _ english: String) -> String {
    L10n.isChinese ? chinese : english
}
