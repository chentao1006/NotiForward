import Foundation

actor ForwardCoordinator {
    /// Queued notifications older than this are dropped instead of delivered late.
    private static let maximumPendingAge: TimeInterval = 6 * 3_600

    private let store: LocalStore
    private let bark = BarkClient()
    private let icons = AppIconLookup()
    private var settings: GeneralSettings
    private var rules: RuleConfiguration
    private var consecutiveFailures = 0
    private var retryAfter: Date?

    init(store: LocalStore, settings: GeneralSettings, rules: RuleConfiguration) {
        self.store = store
        self.settings = settings
        self.rules = rules
    }

    func update(settings: GeneralSettings, rules: RuleConfiguration) {
        if settings.bark != self.settings.bark { resetBackoff() }
        self.settings = settings
        self.rules = rules
    }

    /// Queues the notification if it passes the rules. Nothing is queued while Bark is unconfigured,
    /// and old notifications found after a long gap (e.g. the app was not running) are skipped.
    func receive(_ notification: CapturedNotification) async throws -> Bool {
        let source = "#\(notification.databaseID) \(notification.sourceBundleID)"
        guard settings.bark.isConfigured else {
            Log.forward.info("Skipped \(source, privacy: .public): Bark is not configured")
            return false
        }
        guard notification.originalDate > Date().addingTimeInterval(-Self.maximumPendingAge) else {
            Log.forward.info("Skipped \(source, privacy: .public): older than \(Int(Self.maximumPendingAge / 3_600))h")
            return false
        }
        let decision = RuleEngine.evaluate(notification, rules: rules)
        guard decision == .forward else {
            Log.forward.info("Skipped \(source, privacy: .public): \(String(describing: decision), privacy: .public)")
            return false
        }
        try await store.enqueue(notification)
        Log.forward.info("Queued \(source, privacy: .public): \(notification.title, privacy: .private)")
        return true
    }

    /// Delivers queued notifications in order and returns how many were sent.
    /// After a failure, delivery backs off exponentially up to one minute.
    func flush() async throws -> Int {
        try await store.purgePending(olderThan: Date().addingTimeInterval(-Self.maximumPendingAge))
        guard settings.bark.isConfigured else { return 0 }
        if let retryAfter, retryAfter > Date() { return 0 }
        var sent = 0
        for notification in try await store.pendingNotifications() {
            do {
                var message = BarkMessage(notification, configuration: settings.bark)
                if settings.bark.showsAppIcon {
                    message.icon = await icons.iconURL(for: notification.sourceBundleID)
                }
                try await bark.send(message, configuration: settings.bark)
            } catch {
                consecutiveFailures += 1
                let delay = min(60, pow(2, Double(consecutiveFailures)))
                retryAfter = Date().addingTimeInterval(delay)
                Log.forward.error("Send failed for #\(notification.databaseID), retrying in \(Int(delay))s: \(error.localizedDescription, privacy: .public)")
                throw error
            }
            Log.forward.info("Sent #\(notification.databaseID) \(notification.sourceBundleID, privacy: .public) to Bark")
            try await store.removePending(id: notification.id)
            resetBackoff()
            sent += 1
        }
        return sent
    }

    private func resetBackoff() {
        consecutiveFailures = 0
        retryAfter = nil
    }
}
