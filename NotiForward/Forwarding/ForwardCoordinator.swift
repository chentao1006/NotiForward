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
        if settings.barkDevices != self.settings.barkDevices { resetBackoff() }
        self.settings = settings
        self.rules = rules
    }

    /// Queues the notification if it passes the rules. Nothing is queued while Bark is unconfigured,
    /// and old notifications found after a long gap (e.g. the app was not running) are skipped.
    func receive(_ notification: CapturedNotification) async throws -> Bool {
        let source = "#\(notification.databaseID) \(notification.sourceBundleID)"
        let deviceIDs = settings.configuredBarkDevices.map(\.id)
        guard !deviceIDs.isEmpty else {
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
        try await store.enqueue(notification, deviceIDs: deviceIDs)
        Log.forward.info("Queued \(source, privacy: .public): \(notification.title, privacy: .private)")
        return true
    }

    /// Delivers queued notifications in order and returns how many were sent.
    /// After a failure, delivery backs off exponentially up to one minute.
    func flush() async throws -> Int {
        try await store.purgePending(olderThan: Date().addingTimeInterval(-Self.maximumPendingAge))
        let configuredDevices = settings.configuredBarkDevices
        guard !configuredDevices.isEmpty else { return 0 }
        if let retryAfter, retryAfter > Date() { return 0 }
        var sent = 0
        for var pending in try await store.pendingNotifications() {
            let notification = pending.notification
            let targetIDs = pending.remainingDeviceIDs.isEmpty ? Set(configuredDevices.map(\.id)) : Set(pending.remainingDeviceIDs)
            let targets = configuredDevices.filter { targetIDs.contains($0.id) }
            if targets.isEmpty {
                try await store.removePending(id: notification.id)
                continue
            }
            let icon = targets.contains(where: \.showsAppIcon) ? await icons.iconURL(for: notification.sourceBundleID) : nil
            let failures = await withTaskGroup(of: (UUID, String?).self, returning: [(UUID, String?)].self) { group in
                for configuration in targets {
                    group.addTask { [bark] in
                        do {
                            var message = BarkMessage(notification, configuration: configuration)
                            if configuration.showsAppIcon { message.icon = icon }
                            try await bark.send(message, configuration: configuration)
                            return (configuration.id, nil)
                        } catch {
                            return (configuration.id, error.localizedDescription)
                        }
                    }
                }
                var results: [(UUID, String?)] = []
                for await result in group { results.append(result) }
                return results.filter { $0.1 != nil }
            }
            if !failures.isEmpty {
                pending.remainingDeviceIDs = failures.map(\.0)
                try await store.updatePending(pending)
                consecutiveFailures += 1
                let delay = min(60, pow(2, Double(consecutiveFailures)))
                retryAfter = Date().addingTimeInterval(delay)
                let message = failures.compactMap(\.1).joined(separator: "; ")
                Log.forward.error("Send failed for #\(notification.databaseID) on \(failures.count) device(s), retrying in \(Int(delay))s: \(message, privacy: .public)")
                throw BarkError.multipleDevices(message)
            }
            Log.forward.info("Sent #\(notification.databaseID) \(notification.sourceBundleID, privacy: .public) to \(targets.count) Bark device(s)")
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
