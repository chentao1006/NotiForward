import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when macOS started the app as a login item; launch is then silent (menu bar icon only).
    @MainActor private(set) static var launchedAsLoginItem = false

    /// A menu bar app keeps running with no windows; without this, closing Settings quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Automatic termination would also quit a windowless app that is still forwarding.
        ProcessInfo.processInfo.disableAutomaticTermination("Forwarding notifications")
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return }
        Self.launchedAsLoginItem = event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.launchedAsLoginItem else { return }
        // Backstop in case a window was created before the launch kind was known.
        DispatchQueue.main.async {
            NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.forEach { $0.close() }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .restoreMenuBar, object: nil)
        return true
    }
}

extension Notification.Name {
    static let restoreMenuBar = Notification.Name("NotiForward.restoreMenuBar")
}

@main
struct NotiForwardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra(isInserted: $model.isMenuBarVisible) {
            MenuContentView(model: model)
                .environment(\.locale, model.language.locale)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window(appName, id: "settings") {
            SettingsView(model: model)
                .environment(\.locale, model.language.locale)
                .frame(width: 500)
                .frame(minHeight: 460, idealHeight: 580)
                .onReceive(NotificationCenter.default.publisher(for: .restoreMenuBar)) { _ in
                    model.restoreMenuBar()
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        // Never reopen Settings from the previous session, so a login launch stays silent.
        .restorationBehavior(.disabled)
        // Settings opens by itself at launch until a Bark key has been entered, except at login.
        .defaultLaunchBehavior(AppModel.isBarkConfigured || AppDelegate.launchedAsLoginItem ? .suppressed : .presented)
    }
}

/// The label is rendered at launch, so it is where capture starts. Opening the app again
/// (Finder, Spotlight, Launchpad) brings up Settings.
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.isForwarding ? "bell.and.waves.left.and.right" : "bell.slash")
            .task { await model.start() }
            .onReceive(NotificationCenter.default.publisher(for: .restoreMenuBar)) { _ in
                model.restoreMenuBar()
                openSettingsWindow(openWindow)
            }
    }
}
