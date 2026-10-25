import Foundation

enum RuleEngine {
    static func evaluate(
        _ notification: CapturedNotification,
        rules: RuleConfiguration,
        ownBundleID: String = "com.ct106.notiforward"
    ) -> ForwardDecision {
        // The notification database stores bundle IDs lowercased (ru.keepcoder.telegram), while
        // apps picked in Settings keep their real case (ru.keepcoder.Telegram).
        let bundleID = notification.sourceBundleID.lowercased()
        let ownBundleID = ownBundleID.lowercased()
        if bundleID == ownBundleID || bundleID.hasPrefix(ownBundleID + ".") {
            return .blockedSelf
        }

        let isListed = rules.appBundleIDs.contains { $0.lowercased() == bundleID }
        switch rules.appMode {
        case .allExceptBlocked where isListed:
            return .blockedByApp
        case .onlyAllowed where !isListed:
            return .blockedByApp
        default:
            break
        }

        guard rules.keywordFilteringEnabled else { return .forward }
        let normalizedKeywords = rules.keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let searchable = [notification.title, notification.subtitle, notification.body]
            .joined(separator: "\n")
        let matched = normalizedKeywords.contains { searchable.localizedCaseInsensitiveContains($0) }

        switch rules.keywordMode {
        case .blocked:
            return matched ? .blockedByKeyword : .forward
        case .allowed:
            return matched ? .forward : .blockedByKeyword
        }
    }
}

