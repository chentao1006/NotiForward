import Foundation
import Testing

@Suite struct RuleEngineTests {
    private func notification(bundleID: String = "com.example.mail", title: String = "Invoice", body: String = "Your order shipped") -> CapturedNotification {
        CapturedNotification(id: UUID(), databaseID: 1, sourceBundleID: bundleID, sourceAppName: "Mail",
                             title: title, subtitle: "", body: body, originalDate: Date(), capturedDate: Date())
    }

    @Test func forwardsEverythingByDefault() {
        #expect(RuleEngine.evaluate(notification(), rules: .initial) == .forward)
    }

    @Test func neverForwardsItself() {
        #expect(RuleEngine.evaluate(notification(bundleID: "com.ct106.notiforward"), rules: .initial) == .blockedSelf)
    }

    @Test func appBlockAndAllowLists() {
        var rules = RuleConfiguration.initial
        rules.appBundleIDs = ["com.example.mail"]
        #expect(RuleEngine.evaluate(notification(), rules: rules) == .blockedByApp)
        rules.appMode = .onlyAllowed
        #expect(RuleEngine.evaluate(notification(), rules: rules) == .forward)
        #expect(RuleEngine.evaluate(notification(bundleID: "com.example.chat"), rules: rules) == .blockedByApp)
    }

    @Test func matchesLowercasedBundleIDsFromNotificationDatabase() {
        var rules = RuleConfiguration.initial
        rules.appMode = .onlyAllowed
        rules.appBundleIDs = ["ru.keepcoder.Telegram"]
        #expect(RuleEngine.evaluate(notification(bundleID: "ru.keepcoder.telegram"), rules: rules) == .forward)
    }

    @Test func keywordsMatchCaseInsensitivelyAndIgnoreBlankLines() {
        var rules = RuleConfiguration.initial
        rules.keywordFilteringEnabled = true
        rules.keywords = ["", "  ", "SHIPPED"]
        #expect(RuleEngine.evaluate(notification(), rules: rules) == .blockedByKeyword)
        rules.keywordMode = .allowed
        #expect(RuleEngine.evaluate(notification(), rules: rules) == .forward)
        #expect(RuleEngine.evaluate(notification(body: "Hello"), rules: rules) == .blockedByKeyword)
    }
}

@Suite struct ProLimitsTests {
    @Test func freeTierAllowsOneAppAndNoKeywords() {
        var rules = RuleConfiguration.initial
        rules.appMode = .allExceptBlocked
        rules.appBundleIDs = ["com.b.app", "com.a.app"]
        rules.keywordFilteringEnabled = true
        let limited = ProLimits.effectiveRules(rules, isPro: false)
        #expect(limited.appMode == .onlyAllowed)
        #expect(limited.appBundleIDs == ["com.a.app"])
        #expect(!limited.keywordFilteringEnabled)
        #expect(ProLimits.effectiveRules(rules, isPro: true) == rules)
    }
}
