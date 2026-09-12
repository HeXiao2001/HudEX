import Foundation

/// Localisation for everything the user can read.
///
/// Only English and Simplified Chinese ship today. The system language decides
/// which one is used; anything that is neither falls back to English.
public enum L10n {
    /// Languages this build ships.
    public static let supported = ["en", "zh-Hans"]

    /// Bundle that holds the `.lproj` tables.
    public static var bundle: Bundle { .module }

    /// UserDefaults key holding a manual override (`en`, `zh-Hans`, or empty
    /// for "follow the system").
    public static let overrideKey = "HudEX.languageOverride"

    /// The language actually in use, e.g. `zh-Hans`.
    public static var language: String {
        let override = UserDefaults.standard.string(forKey: overrideKey) ?? ""
        if supported.contains(override) { return override }
        return systemLanguage
    }

    /// What the system would choose (English, Chinese, or English as fallback).
    public static let systemLanguage: String = {
        let preferred = Bundle.preferredLocalizations(from: supported)
        return preferred.first ?? "en"
    }()

    /// Sets (or clears) the manual language override.
    public static func setLanguageOverride(_ language: String?) {
        if let language, supported.contains(language) {
            UserDefaults.standard.set(language, forKey: overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: overrideKey)
        }
        NotificationCenter.default.post(name: languageDidChange, object: nil)
    }

    public static let languageDidChange = Notification.Name("HudEX.languageDidChange")

    public static var isChinese: Bool { language.hasPrefix("zh") }

    /// Looks up a key. A missing key returns the key itself, which makes the
    /// gap obvious without crashing.
    public static func t(_ key: String) -> String {
        guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
              let table = NSDictionary(contentsOfFile: path) as? [String: String],
              let value = table[key] else {
            return key
        }
        return value
    }

    /// Looks up a key and formats it with arguments (`%@`, `%d`, `%.2f`).
    public static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }

    /// Table used by tests to check completeness.
    public static func table(for language: String) -> [String: String] {
        guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
              let dictionary = NSDictionary(contentsOfFile: path) as? [String: String] else {
            return [:]
        }
        return dictionary
    }
}
