import AppKit
import Combine
import SwiftUI

@main
enum NotiForwardMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) static var launchedAsLoginItem = false

    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Forwarding notifications")
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return }
        Self.launchedAsLoginItem = event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AnalyticsManager.shared.start()
        NSApp.setActivationPolicy(.accessory)
        observeModel()
        updateStatusItem()
        Task { await model.start() }
        if !Self.launchedAsLoginItem && !AppModel.isBarkConfigured { showSettings() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.restoreMenuBar()
        showSettings()
        return true
    }

    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }

    private func observeModel() {
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusItem() } }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard model.isMenuBarVisible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        statusItem?.button?.image = NSImage(
            systemSymbolName: model.isForwarding ? "bell.and.waves.left.and.right" : "bell.slash",
            accessibilityDescription: appName
        )
        statusItem?.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        addItem(statusText, image: statusIcon, enabled: false, to: menu)
        if let error = model.deliveryError {
            addItem(error, enabled: false, to: menu)
        } else if let date = model.lastForwardedAt {
            let formatter = DateFormatter()
            formatter.locale = model.language.locale
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            addItem(L("Last forwarded: \(formatter.string(from: date))"), enabled: false, to: menu)
        }
        menu.addItem(.separator())
        addItem(model.isPaused ? L("Resume Forwarding") : L("Pause Forwarding"), action: #selector(togglePaused),
                enabled: model.general.isBarkConfigured, to: menu)
        addItem(L("Send Test Notification"), action: #selector(sendTest),
                enabled: model.general.isBarkConfigured, to: menu)
#if !APP_STORE
        addItem(L("Check for Updates…"), action: #selector(checkForUpdates), to: menu)
#endif
        let settings = addItem(L("Settings…"), action: #selector(showSettings), to: menu)
        settings.keyEquivalent = ","
        menu.addItem(.separator())
        let quit = addItem(L("Quit \(appName)"), action: #selector(quit), to: menu)
        quit.keyEquivalent = "q"
        return menu
    }

    @discardableResult
    private func addItem(_ title: String, image: String? = nil, action: Selector? = nil,
                         enabled: Bool = true, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        if let image { item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil) }
        menu.addItem(item)
        return item
    }

    private var statusText: String {
        switch model.captureStatus {
        case .starting: return L("Starting…")
        case .permissionRequired: return L("Notification folder access is required")
        case .failed(let message): return message
        case .running:
            if !model.general.isBarkConfigured { return L("Bark device key is not set") }
            if model.isPaused { return L("Forwarding is paused") }
            return L("Forwarding to Bark")
        }
    }

    private var statusIcon: String {
        switch model.captureStatus {
        case .starting: return "clock"
        case .permissionRequired, .failed: return "exclamationmark.triangle.fill"
        case .running:
            if !model.general.isBarkConfigured { return "exclamationmark.triangle.fill" }
            return model.isPaused ? "pause.circle.fill" : "checkmark.circle.fill"
        }
    }

    @objc private func togglePaused() { model.togglePaused() }
    @objc private func sendTest() { model.sendTest() }
#if !APP_STORE
    @objc private func checkForUpdates() { model.updater.checkForUpdates() }
#endif
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showSettings() {
        model.restoreMenuBar()
        if settingsWindow == nil {
            let contentView = SettingsView(model: model)
                .environment(\.locale, model.language.locale)
                .frame(width: 500)
                .frame(minHeight: 460, idealHeight: 580)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: contentView)
            window.title = appName
            window.titlebarAppearsTransparent = true
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.title = appName
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
