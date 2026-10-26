import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    enum CaptureStatus: Equatable { case starting, running, permissionRequired, failed(String) }
    enum TestStatus: Equatable { case idle, sending, succeeded, failed(String) }
    enum SettingsTab: Hashable { case general, rules, client }

    @Published var general = GeneralSettings()
    @Published var rules = RuleConfiguration.initial
    @Published var catalog: [CatalogApp] = []
    @Published var captureStatus: CaptureStatus = .starting
    @Published var isPaused = false
    @Published var isMenuBarVisible = true
    @Published var lastForwardedAt: Date?
    @Published var deliveryError: String?
    @Published var testStatus: TestStatus = .idle
    // Until Bark is set up there is nothing to forward to, so Settings starts on the client tab.
    @Published var settingsTab: SettingsTab = AppModel.isBarkConfigured ? .general : .client

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
    private var registrationTasks: [UUID: Task<Void, Never>] = [:]
    @Published var registeringDeviceIDs: Set<UUID> = []
    private var hasStarted = false

    /// Mirrors whether a Bark key is saved, readable synchronously when scenes are built at launch.
    static var isBarkConfigured: Bool { UserDefaults.standard.bool(forKey: "barkConfigured") }

    var isForwarding: Bool { captureStatus == .running && !isPaused && general.isBarkConfigured }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            let store = try LocalStore()
            self.store = store
            let loaded = try await store.loadSettings()
            general = loaded.0
            rules = loaded.1
            normalizeSharedBarkSettings()
            // Persist generated device IDs immediately when upgrading a legacy single-key configuration.
            try await store.save(general: general)
            language.apply(general.language)
            UserDefaults.standard.set(general.isBarkConfigured, forKey: "barkConfigured")
            registerAllIfNeeded()
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
                try? await Task.sleep(nanoseconds: 2_000_000_000)
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
                    await monitor.waitForChange(timeout: deliveryError == nil ? 60 : 5)
                    // Notification Center writes several times per notification; let it settle.
                    try? await Task.sleep(nanoseconds: 150_000_000)
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
            try? await Task.sleep(nanoseconds: 3_000_000_000)
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
        UserDefaults.standard.set(general.isBarkConfigured, forKey: "barkConfigured")
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
    func addBarkDevice() {
        var device = sharedBarkConfiguration
        device.id = UUID()
        device.name = ""
        device.deviceKey = ""
        device.deviceToken = ""
        general.barkDevices.append(device)
        saveSettings()
    }

    func removeBarkDevice(id: UUID) {
        guard general.barkDevices.contains(where: { $0.id == id }) else { return }
        registrationTasks[id]?.cancel()
        registrationTasks[id] = nil
        registeringDeviceIDs.remove(id)
        general.barkDevices.removeAll { $0.id == id }
        deliveryError = nil
        testStatus = .idle
        saveSettings()
    }

    func setBarkInput(_ input: String, deviceID: UUID) {
        guard let index = general.barkDevices.firstIndex(where: { $0.id == deviceID }) else { return }
        let previousServer = general.barkDevices[index].serverURL
        general.barkDevices[index].apply(input: input)
        if general.barkDevices[index].serverURL != previousServer {
            setBarkServer(general.barkDevices[index].serverURL)
        }
        deliveryError = nil
        testStatus = .idle
        saveSettings()
        registerIfNeeded(deviceID: deviceID)
    }

    var sharedBarkConfiguration: BarkConfiguration {
        general.barkDevices.first ?? BarkConfiguration()
    }

    private func normalizeSharedBarkSettings() {
        guard let shared = general.barkDevices.first else { return }
        for index in general.barkDevices.indices.dropFirst() {
            general.barkDevices[index].serverURL = shared.serverURL
            general.barkDevices[index].level = shared.level
            general.barkDevices[index].groupByApp = shared.groupByApp
            general.barkDevices[index].opensAppOnTap = shared.opensAppOnTap
            general.barkDevices[index].showsAppIcon = shared.showsAppIcon
        }
    }

    /// Keys are issued per server, so registered keys are refreshed when the shared server changes.
    func setBarkServer(_ serverURL: String) {
        for index in general.barkDevices.indices {
            general.barkDevices[index].serverURL = serverURL
            if !general.barkDevices[index].deviceToken.isEmpty { general.barkDevices[index].deviceKey = "" }
        }
        saveSettings()
        registerAllIfNeeded()
    }

    func resetBarkServer() {
        setBarkServer(BarkConfiguration.defaultServer)
    }

    func setBarkLevel(_ level: BarkLevel) {
        for index in general.barkDevices.indices { general.barkDevices[index].level = level }
        saveSettings()
    }

    func setBarkGroupByApp(_ enabled: Bool) {
        for index in general.barkDevices.indices { general.barkDevices[index].groupByApp = enabled }
        saveSettings()
    }

    func setBarkShowsAppIcon(_ enabled: Bool) {
        for index in general.barkDevices.indices { general.barkDevices[index].showsAppIcon = enabled }
        saveSettings()
    }

    func setBarkOpensAppOnTap(_ enabled: Bool) {
        for index in general.barkDevices.indices { general.barkDevices[index].opensAppOnTap = enabled }
        saveSettings()
    }

    func isRegistering(deviceID: UUID) -> Bool { registeringDeviceIDs.contains(deviceID) }

    private func registerAllIfNeeded() {
        for device in general.barkDevices { registerIfNeeded(deviceID: device.id) }
    }

    private func registerIfNeeded(deviceID: UUID) {
        registrationTasks[deviceID]?.cancel()
        registrationTasks[deviceID] = nil
        registeringDeviceIDs.remove(deviceID)
        guard let configuration = general.barkDevices.first(where: { $0.id == deviceID }), configuration.needsRegistration else { return }
        registeringDeviceIDs.insert(deviceID)
        registrationTasks[deviceID] = Task {
            defer {
                registeringDeviceIDs.remove(deviceID)
                registrationTasks[deviceID] = nil
            }
            do {
                let key = try await BarkClient().register(configuration: configuration)
                guard !Task.isCancelled,
                      let index = general.barkDevices.firstIndex(where: { $0.id == deviceID }),
                      general.barkDevices[index].deviceToken == configuration.deviceToken,
                      general.barkDevices[index].serverURL == configuration.serverURL else { return }
                general.barkDevices[index].deviceKey = key
                deliveryError = nil
                saveSettings()
            } catch {
                guard !Task.isCancelled else { return }
                deliveryError = error.localizedDescription
            }
        }
    }

    func sendTest() {
        let configurations = general.configuredBarkDevices
        guard !configurations.isEmpty else { return }
        testStatus = .sending
        Task {
            let failures = await withTaskGroup(of: String?.self, returning: [String].self) { group in
                for configuration in configurations {
                    group.addTask {
                        do {
                            let message = BarkMessage(
                                title: appName,
                                body: L("Test notification from \(Host.current().localizedName ?? "Mac")"),
                                group: configuration.groupByApp ? appName : nil
                            )
                            try await BarkClient().send(message, configuration: configuration)
                            return nil
                        } catch {
                            return error.localizedDescription
                        }
                    }
                }
                var errors: [String] = []
                for await error in group { if let error { errors.append(error) } }
                return errors
            }
            if failures.isEmpty {
                testStatus = .succeeded
                AnalyticsManager.shared.track("test_notification_sent")
            } else {
                testStatus = .failed(failures.joined(separator: "; "))
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
        if #available(macOS 13.0, *) {
            setModernLaunchAtLogin(enabled)
        } else {
            // SMLoginItemSetEnabled works for the main application on Monterey. It is deprecated
            // on newer systems, where SMAppService is used above instead.
            let succeeded = SMLoginItemSetEnabled(Bundle.main.bundleIdentifier! as CFString, enabled)
            if !succeeded { general.launchAtLogin.toggle() }
        }
    }

    @available(macOS 13.0, *)
    private func setModernLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if !enabled && SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        } catch {
            general.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
