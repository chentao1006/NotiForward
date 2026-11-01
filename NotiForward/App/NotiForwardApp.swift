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
        if CommandLine.arguments.contains("--notiforward-login-item") {
            Self.launchedAsLoginItem = true
            return
        }
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return }
        Self.launchedAsLoginItem = event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AnalyticsManager.shared.start()
        NSApp.setActivationPolicy(.accessory)
        observeModel()
        updateMainMenu()
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
        model.language.$bundle
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateMainMenu() } }
            .store(in: &cancellables)
    }

    /// Text fields only receive ⌘C/⌘V/⌘X/⌘A/⌘Z through the main menu's key equivalents,
    /// and an app started from a hand-written main() has no main menu.
    private func updateMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        let settings = appMenu.addItem(withTitle: L("Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Hide \(appName)"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: L("Hide Others"),
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: L("Quit \(appName)"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        mainMenu.addItem(withTitle: appName, action: nil, keyEquivalent: "").submenu = appMenu

        let editMenu = NSMenu(title: L("Edit"))
        editMenu.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(withTitle: editMenu.title, action: nil, keyEquivalent: "").submenu = editMenu

        let windowMenu = NSMenu(title: L("Window"))
        windowMenu.addItem(withTitle: L("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        mainMenu.addItem(withTitle: windowMenu.title, action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func updateStatusItem() {
        guard model.isMenuBarVisible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        let symbol = model.isForwarding ? "bell.circle" : "bell.slash.circle"
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let image = (NSImage(systemSymbolName: symbol, accessibilityDescription: appName)
            ?? NSImage(systemSymbolName: "bell", accessibilityDescription: appName))?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.imageScaling = .scaleProportionallyUpOrDown
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
        let settings = addItem(L("Settings…"), action: #selector(showSettings), to: menu)
        settings.keyEquivalent = ","
#if !APP_STORE
        addItem(L("Check for Updates…"), action: #selector(checkForUpdates), to: menu)
#endif
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
