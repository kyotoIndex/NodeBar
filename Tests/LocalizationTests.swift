import Foundation

enum LocalizationTests {
    static func run() throws {
        precondition(L10n.language(for: "en", preferredLanguages: ["zh-Hans"]) == "en")
        precondition(L10n.language(for: "zh-Hans", preferredLanguages: ["en-US"]) == "zh-Hans")
        precondition(L10n.language(for: "system", preferredLanguages: ["zh-Hans-CN", "en-US"]) == "zh-Hans")
        precondition(L10n.language(for: "system", preferredLanguages: ["en-GB", "zh-Hans"]) == "en")
        precondition(L10n.language(for: "system", preferredLanguages: ["de-DE"]) == "en")
    }
}
