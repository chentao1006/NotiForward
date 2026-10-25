import AppKit
import Foundation

struct CatalogApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL?
    var id: String { bundleID }

    var icon: NSImage {
        guard let url else { return NSWorkspace.shared.icon(for: .application) }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    init(bundleID: String, url: URL?) {
        self.bundleID = bundleID
        self.url = url
        name = url.map(Self.displayName) ?? bundleID
    }

    /// Looks up an app that was selected earlier but is outside the scanned folders, or uninstalled.
    static func resolve(bundleID: String) -> CatalogApp {
        CatalogApp(bundleID: bundleID, url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID))
    }

    /// Public URL schemes from the app's Info.plist, in declaration order.
    var urlSchemes: [String] {
        guard let url, let types = Bundle(url: url)?.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else { return [] }
        return types
            .filter { ($0["CFBundleURLIsPrivate"] as? Bool) != true }
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    }

    /// The localized name without the `.app` suffix Finder adds when extensions are shown.
    private static func displayName(_ url: URL) -> String {
        let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

enum AppCatalog {
    static func load() -> [CatalogApp] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            realHomeDirectory.appending(path: "Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities")
        ]
        var byID: [String: CatalogApp] = [:]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
                byID[id] = CatalogApp(bundleID: id, url: url)
            }
        }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
