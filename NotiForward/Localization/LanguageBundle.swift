import Foundation
import Combine

/// Runtime language switching.
///
/// `String(localized:)` without a bundle always follows the language the process launched with,
/// so every user-visible string goes through `L(_:)`, which reads from the `.lproj` bundle of the
/// language chosen in Settings. Views re-render on change because they are keyed by `language`.
@MainActor
final class LanguageBundle: ObservableObject {
    static let shared = LanguageBundle()

    /// Mirror of `bundle` for nonisolated callers such as `LocalizedError.errorDescription`.
    /// Only written on the main actor.
    nonisolated(unsafe) fileprivate static var currentBundle: Bundle = .main

    @Published private(set) var language: AppLanguage = .system
    @Published private(set) var bundle: Bundle = .main
    @Published private(set) var locale: Locale = .current

    private init() { apply(.system) }

    func apply(_ language: AppLanguage) {
        self.language = language
        // Also drives system-provided UI (standard menus, alerts) from the next launch on.
        UserDefaults.standard.set(language == .system ? nil : [language.rawValue], forKey: "AppleLanguages")
        let preferences = language == .system ? Self.systemLanguages : [language.rawValue]
        if let preferred = Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferences).first,
           let path = Bundle.main.path(forResource: preferred, ofType: "lproj"),
           let resolved = Bundle(path: path) {
            bundle = resolved
            locale = Locale(identifier: preferred)
        } else {
            bundle = .main
            locale = .current
        }
        Self.currentBundle = bundle
    }

    /// The user's system languages, ignoring the app-level `AppleLanguages` override set above.
    private static var systemLanguages: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
    }
}

/// The app's name in the chosen language: 知会 in Chinese, NotiForward elsewhere.
var appName: String { L("NotiForward") }

/// Localizes a string in the language chosen in Settings.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: LanguageBundle.currentBundle)
}
