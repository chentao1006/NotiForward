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
    static let folderName = "group.com.apple.usernoted"
    private static let defaultsKey = "NotificationFolderBookmark"

    /// ~/Library/Group Containers/group.com.apple.usernoted
    static var expectedFolder: URL {
        realHomeDirectory.appending(path: "Library/Group Containers/\(folderName)", directoryHint: .isDirectory)
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
        NSApp.activate()
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
