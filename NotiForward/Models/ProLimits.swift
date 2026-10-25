import Foundation

/// Free-tier limits of the App Store build. The direct download is always Pro.
enum ProLimits {
    static let freeAppCount = 1

    /// The rules actually applied. Free users get an allow list of one app and no keyword
    /// filtering; saved rules are kept as they are, so upgrading again restores them.
    static func effectiveRules(_ rules: RuleConfiguration, isPro: Bool) -> RuleConfiguration {
        guard !isPro else { return rules }
        var limited = rules
        limited.appMode = .onlyAllowed
        limited.appBundleIDs = Set(freeApps(in: rules))
        limited.keywordFilteringEnabled = false
        return limited
    }

    /// The selected apps that still forward on the free tier, in a stable order.
    static func freeApps(in rules: RuleConfiguration) -> [String] {
        Array(rules.appBundleIDs.sorted().prefix(freeAppCount))
    }
}
