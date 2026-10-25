import Foundation

/// Finds a public icon URL for an app, since Bark's `icon` field takes a URL rather than image data.
/// Uses Apple's App Store lookup by bundle ID (Mac App Store first, then the iPhone App Store),
/// so apps distributed outside the App Store fall back to Bark's own icon.
actor AppIconLookup {
    private let session: URLSession
    private var cache: [String: String?] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func iconURL(for bundleID: String) async -> String? {
        if let cached = cache[bundleID] { return cached }
        var found: String?
        for entity in ["macSoftware", "software"] {
            guard let result = await lookup(bundleID: bundleID, entity: entity) else { return nil } // network error: retry later
            if let url = result {
                found = url
                break
            }
        }
        cache[bundleID] = found
        Log.forward.info("Icon for \(bundleID, privacy: .public): \(found ?? "none", privacy: .public)")
        return found
    }

    /// Returns nil on a network failure, `.some(nil)` when the store has no such app.
    private func lookup(bundleID: String, entity: String) async -> String?? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "bundleId", value: bundleID), URLQueryItem(name: "entity", value: entity)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 5
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        return .some(reply.results.first?.artworkUrl512 ?? reply.results.first?.artworkUrl100)
    }

    private struct Reply: Decodable {
        let results: [App]
        struct App: Decodable {
            let artworkUrl512: String?
            let artworkUrl100: String?
        }
    }
}
