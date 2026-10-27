import AppKit

@main
@MainActor
final class LoginItemAppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let application = NSApplication.shared
        let delegate = LoginItemAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let helperURL = Bundle.main.bundleURL
        let mainAppURL = (0..<4).reduce(helperURL) { url, _ in url.deletingLastPathComponent() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.arguments = ["--notiforward-login-item"]
        NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration) { _, _ in
            NSApplication.shared.terminate(nil)
        }
    }
}
