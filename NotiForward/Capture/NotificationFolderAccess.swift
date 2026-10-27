import AppKit
import Darwin
import Foundation

/// The user's real home folder. Inside the sandbox, `NSHomeDirectory()`, `NSHomeDirectoryForUser`
/// and `homeDirectoryForCurrentUser` all return the app container instead.
let realHomeDirectory: URL = {
    if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }
    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
}()

/// Read access to the Notification Center data folder, granted by picking that one folder in an
/// open panel and kept across launches as a security-scoped bookmark (the approach BrowSync uses
/// for Safari), so the app needs neither Full Disk Access nor anything outside this folder.
@MainActor
enum NotificationFolderAccess {
    private static var usesLegacyLocation: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 15
    }
    static var folderName: String {
        usesLegacyLocation ? "com.apple.notificationcenter" : "group.com.apple.usernoted"
    }
    private static var defaultsKey: String {
        // Keep the existing key on macOS 15+ so upgrades retain the user's access grant.
        usesLegacyLocation ? "NotificationFolderBookmark.Legacy" : "NotificationFolderBookmark"
    }

    /// Monterey through Sonoma use DARWIN_USER_DIR; Sequoia and later use the group container.
    static var expectedFolder: URL {
        if usesLegacyLocation {
            return darwinUserDirectory.appendingPathComponent(folderName, isDirectory: true)
        }
        return realHomeDirectory
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// Resolves the saved bookmark, refreshing it when macOS reports it stale.
    /// Callers still have to call `startAccessingSecurityScopedResource()`.
    static func resolveFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            invalidate("bookmark could not be resolved")
            return nil
        }
        if isStale {
            guard let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                    includingResourceValuesForKeys: nil, relativeTo: nil) else {
                invalidate("stale bookmark could not be refreshed")
                return nil
            }
            UserDefaults.standard.set(fresh, forKey: defaultsKey)
        }
        return url
    }

    /// Shows an open panel already inside the notification folder, so the user only has to confirm.
    @discardableResult
    static func request() -> Bool {
        let panel = NSOpenPanel()
        panel.message = L("Click Grant Access to let \(appName) read the Notification Center folder. Nothing else on your Mac is accessed.")
        panel.prompt = L("Grant Access")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = expectedFolder
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard url.lastPathComponent == folderName else {
            Log.capture.error("Wrong folder selected: \(url.path, privacy: .public)")
            return false
        }
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            Log.capture.notice("Notification folder access granted")
            return true
        } catch {
            Log.capture.error("Could not save folder bookmark: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func invalidate(_ reason: String) {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        Log.capture.notice("Notification folder access invalidated: \(reason, privacy: .public)")
    }
}

/// `getconf DARWIN_USER_DIR` without launching a subprocess. On macOS 12–14 Notification Center
/// stores its database below this per-user directory rather than in the home Library.
private let darwinUserDirectory: URL = {
    func unsandboxedRoot(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent()
        // Sandboxed apps receive …/0/<bundle-id>/ instead of the real …/0/ directory.
        // Notification Center is a sibling of the app container, not a child of it.
        if standardized.lastPathComponent != "0", parent.lastPathComponent == "0" {
            return parent
        }
        return standardized
    }

    let key = Int32(_CS_DARWIN_USER_DIR)
    let length = confstr(key, nil, 0)
    guard length > 0 else {
        return unsandboxedRoot(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
    }
    var buffer = [CChar](repeating: 0, count: length)
    guard confstr(key, &buffer, length) > 0 else {
        return unsandboxedRoot(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
    }
    let bytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
    return unsandboxedRoot(URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self), isDirectory: true))
}()
