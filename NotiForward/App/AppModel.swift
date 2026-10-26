import AppKit
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    enum CaptureStatus: Equatable { case starting, running, permissionRequired, failed(String) }
    enum TestStatus: Equatable { case idle, sending, succeeded, failed(String) }
    enum SettingsTab: Hashable { case general, rules, client }

    var general = GeneralSettings()
    var rules = RuleConfiguration.initial
    var catalog: [CatalogApp] = []
    var captureStatus: CaptureStatus = .starting
    var isPaused = false
    var isMenuBarVisible = true
    var lastForwardedAt: Date?
    var deliveryError: String?
    var testStatus: TestStatus = .idle
    // Until Bark is set up there is nothing to forward to, so Settings starts on the client tab.
    var settingsTab: SettingsTab = AppModel.isBarkConfigured ? .general : .client

    let language = LanguageBundle.shared
#if !APP_STORE
    let updater = Updater()
#endif

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
    private var store: LocalStore?
    private var coordinator: ForwardCoordinator?
    private var monitorTask: Task<Void, Never>?
    private var registrationTask: Task<Void, Never>?
    private var hasStarted = false

    /// Mirrors whether a Bark key is saved, readable synchronously when scenes are built at launch.
    static var isBarkConfigured: Bool { UserDefaults.standard.bool(forKey: "barkConfigured") }

    var isForwarding: Bool { captureStatus == .running && !isPaused && general.bark.isConfigured }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            let store = try LocalStore()
            self.store = store
            let loaded = try await store.loadSettings()
            general = loaded.0
            rules = loaded.1
            language.apply(general.language)
            UserDefaults.standard.set(general.bark.isConfigured, forKey: "barkConfigured")
            registerIfNeeded()
            let coordinator = ForwardCoordinator(store: store, settings: general, rules: rules)
            self.coordinator = coordinator
            monitorTask?.cancel()
            monitorTask = Task { [weak self] in await self?.runCapture(store: store, coordinator: coordinator) }
            catalog = await Task.detached(priority: .utility) { AppCatalog.load() }.value
        } catch {
            captureStatus = .failed(error.localizedDescription)
        }
    }

    /// Opens the notification database and reads it whenever it changes, reopening after errors so that
    /// granting folder access takes effect without relaunching the app.
    private func runCapture(store: LocalStore, coordinator: ForwardCoordinator) async {
        while !Task.isCancelled {
            guard let folder = NotificationFolderAccess.resolveFolder() else {
                if captureStatus != .permissionRequired { Log.capture.notice("Waiting for notification folder access") }
                captureStatus = .permissionRequired
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            do {
                let reader = try NotificationDatabaseReader(folder: folder)
                var cursor = try await store.syncCursor()
                let maximum = try await reader.maximumRecordID()
                if cursor == 0 || cursor > maximum {
                    cursor = maximum
                    try await store.saveSyncCursor(cursor)
                }
                captureStatus = .running
                Log.capture.info("Capturing from record #\(cursor)")
                let monitor = DatabaseChangeMonitor(databasePath: reader.databasePath)
                defer { monitor.stop() }
                while !Task.isCancelled {
                    if isPaused {
                        // Notifications that arrive while paused are skipped, not forwarded on resume.
                        let latest = try await reader.maximumRecordID()
                        if latest != cursor {
                            cursor = latest
                            try await store.saveSyncCursor(cursor)
                        }
                    } else {
                        let records = try await reader.records(after: cursor)
                        if !records.isEmpty { Log.capture.debug("Read \(records.count) new record(s) after #\(cursor)") }
                        for notification in records {
                            _ = try await coordinator.receive(notification)
                            cursor = max(cursor, notification.databaseID)
                        }
                        if !records.isEmpty { try await store.saveSyncCursor(cursor) }
                        await deliverPending(coordinator)
                    }
                    // Sleep until Notification Center writes its database. The timeout is only a
                    // safety net, shorter while a failed delivery is waiting to be retried.
                    await monitor.waitForChange(timeout: .seconds(deliveryError == nil ? 60 : 5))
                    // Notification Center writes several times per notification; let it settle.
                    try? await Task.sleep(for: .milliseconds(150))
                }
            } catch NotificationDatabaseError.permissionDenied {
                if captureStatus != .permissionRequired {
                    Log.capture.notice("Notification folder is not readable (scope active: \(scoped)); waiting for access")
                }
                captureStatus = .permissionRequired
            } catch {
                Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
                captureStatus = .failed(error.localizedDescription)
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func deliverPending(_ coordinator: ForwardCoordinator) async {
        do {
            if try await coordinator.flush() > 0 {
                lastForwardedAt = Date()
                deliveryError = nil
                AnalyticsManager.shared.track("notification_forwarded")
            }
        } catch {
            deliveryError = error.localizedDescription
        }
    }

    func saveSettings() {
        language.apply(general.language)
        setLaunchAtLogin(general.launchAtLogin)
        UserDefaults.standard.set(general.bark.isConfigured, forKey: "barkConfigured")
        guard let store else { return }
        rules.updatedAt = Date()
        let general = general, rules = rules
        Task {
            try? await store.save(general: general)
            try? await store.save(rules: rules)
            await coordinator?.update(settings: general, rules: rules)
        }
    }

    /// Accepts a device token, a bare key or a full Bark URL pasted from the iPhone app.
    func setBarkInput(_ input: String) {
        general.bark.apply(input: input)
        deliveryError = nil
        testStatus = .idle
        saveSettings()
        registerIfNeeded()
    }

    /// Keys are issued per server, so a key registered from a device token is dropped when the server changes.
    func barkServerChanged() {
        if !general.bark.deviceToken.isEmpty { general.bark.deviceKey = "" }
        saveSettings()
        registerIfNeeded()
    }

    func resetBarkServer() {
        general.bark.serverURL = BarkConfiguration.defaultServer
        barkServerChanged()
    }

    var isRegistering: Bool { registrationTask != nil }

    private func registerIfNeeded() {
        registrationTask?.cancel()
        registrationTask = nil
        guard general.bark.needsRegistration else { return }
        let configuration = general.bark
        registrationTask = Task {
            do {
                let key = try await BarkClient().register(configuration: configuration)
                guard !Task.isCancelled, general.bark.deviceToken == configuration.deviceToken,
                      general.bark.serverURL == configuration.serverURL else { return }
                general.bark.deviceKey = key
                deliveryError = nil
                saveSettings()
            } catch {
                guard !Task.isCancelled else { return }
                deliveryError = error.localizedDescription
            }
            registrationTask = nil
        }
    }

    func sendTest() {
        let configuration = general.bark
        testStatus = .sending
        Task {
            do {
                let message = BarkMessage(
                    title: appName,
                    body: L("Test notification from \(Host.current().localizedName ?? "Mac")"),
                    group: configuration.groupByApp ? appName : nil
                )
                try await BarkClient().send(message, configuration: configuration)
                testStatus = .succeeded
                AnalyticsManager.shared.track("test_notification_sent")
            } catch {
                testStatus = .failed(error.localizedDescription)
            }
        }
    }

    func togglePaused() {
        isPaused.toggle()
        AnalyticsManager.shared.track(isPaused ? "forwarding_paused" : "forwarding_resumed")
    }
    func hideMenuBar() { isMenuBarVisible = false }
    func restoreMenuBar() { isMenuBarVisible = true }

    func requestNotificationAccess() {
        AnalyticsManager.shared.track("notification_access_requested")
        NotificationFolderAccess.request()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if !enabled && SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        } catch {
            general.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
