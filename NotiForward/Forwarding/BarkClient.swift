import Foundation

enum BarkError: Error, LocalizedError {
    case notConfigured
    case invalidServerURL
    case invalidResponse
    case server(status: Int, message: String)
    case multipleDevices(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("Bark device key is not set")
        case .invalidServerURL: return L("Bark server URL is invalid")
        case .invalidResponse: return L("Bark server returned an invalid response")
        case .server(let status, let message): return "Bark \(status): \(message)"
        case .multipleDevices(let message): return message
        }
    }
}

struct BarkMessage: Encodable, Sendable {
    var title: String
    var subtitle: String
    var body: String
    var group: String?
    var url: String?
    var icon: String?

    init(title: String, subtitle: String = "", body: String, group: String? = nil, url: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.group = group
        self.url = url
    }

    init(_ notification: CapturedNotification, configuration: BarkConfiguration) {
        let app = notification.sourceAppName
        let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            title: title.isEmpty ? app : "\(app) · \(title)",
            subtitle: notification.subtitle,
            // Bark substitutes placeholder text for an empty body, so fall back to the title.
            body: body.isEmpty ? (title.isEmpty ? app : title) : body,
            group: configuration.groupByApp ? app : nil,
            url: configuration.opensAppOnTap ? notification.openURL : nil
        )
    }
}

struct BarkClient: Sendable {
    var session: URLSession = .shared

    /// Sends one push through `POST {server}/push`, see https://github.com/Finb/bark-server/blob/master/docs/API_V2.md
    func send(_ message: BarkMessage, configuration: BarkConfiguration) async throws {
        guard configuration.isConfigured else { throw BarkError.notConfigured }
        _ = try await post("push", configuration: configuration, body: Payload(
            deviceKey: configuration.trimmedKey,
            title: sourcedTitle(message.title),
            subtitle: message.subtitle.isEmpty ? nil : message.subtitle,
            body: message.body,
            group: message.group,
            level: configuration.level.rawValue,
            url: message.url,
            icon: message.icon
        ))
    }

    private func sourcedTitle(_ title: String) -> String {
        let computerName = Host.current().localizedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = computerName.flatMap { $0.isEmpty ? nil : $0 } ?? "Mac"
        let original = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return original.isEmpty ? "[\(source)]" : "\(original)[\(source)]"
    }

    /// Exchanges an APNs device token for a device key through `POST {server}/register`,
    /// the same call the Bark app makes when it adds a server.
    func register(configuration: BarkConfiguration) async throws -> String {
        guard !configuration.deviceToken.isEmpty else { throw BarkError.notConfigured }
        let reply = try await post("register", configuration: configuration, body: ["device_token": configuration.deviceToken])
        guard let key = reply.data?.deviceKey ?? reply.data?.key, !key.isEmpty else { throw BarkError.invalidResponse }
        return key
    }

    private func post(_ path: String, configuration: BarkConfiguration, body: some Encodable) async throws -> Reply {
        let server = configuration.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: server.isEmpty ? BarkConfiguration.defaultServer : server),
              let scheme = base.scheme, ["http", "https"].contains(scheme), base.host != nil else {
            throw BarkError.invalidServerURL
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BarkError.invalidResponse }
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        guard (200..<300).contains(http.statusCode), let reply, reply.code == 200 else {
            let message = reply?.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw BarkError.server(status: reply?.code ?? http.statusCode, message: message)
        }
        return reply
    }

    private struct Payload: Encodable {
        let deviceKey: String
        let title: String
        let subtitle: String?
        let body: String
        let group: String?
        let level: String
        let url: String?
        let icon: String?

        enum CodingKeys: String, CodingKey {
            case deviceKey = "device_key"
            case title, subtitle, body, group, level, url, icon
        }
    }

    private struct Reply: Decodable {
        let code: Int
        let message: String?
        let data: Registration?
    }

    private struct Registration: Decodable {
        let key: String?
        let deviceKey: String?

        enum CodingKeys: String, CodingKey {
            case key
            case deviceKey = "device_key"
        }
    }
}
