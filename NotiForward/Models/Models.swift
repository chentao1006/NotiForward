import Foundation

enum AppFilterMode: String, Codable, CaseIterable, Sendable {
    case allExceptBlocked
    case onlyAllowed
}

enum KeywordFilterMode: String, Codable, CaseIterable, Sendable {
    case blocked
    case allowed
}

struct RuleConfiguration: Codable, Equatable, Sendable {
    var appMode: AppFilterMode = .allExceptBlocked
    var appBundleIDs: Set<String> = []
    var keywordFilteringEnabled = false
    var keywordMode: KeywordFilterMode = .blocked
    var keywords: [String] = []
    var updatedAt = Date()

    static let initial = RuleConfiguration()
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case portugueseBrazil = "pt-BR"

    var id: String { rawValue }
}

/// Bark interruption levels, see https://bark.day.app/#/tutorial
enum BarkLevel: String, Codable, CaseIterable, Sendable {
    case active
    case timeSensitive
    case passive
}

struct BarkConfiguration: Codable, Equatable, Identifiable, Sendable {
    static let defaultServer = "https://api.day.app"

    var id = UUID()
    var name = ""
    var serverURL = BarkConfiguration.defaultServer
    /// The key used for pushing; obtained from `/register` when the user entered a device token.
    var deviceKey = ""
    /// The APNs device token shown in the Bark app, when that is what the user entered.
    var deviceToken = ""
    var level: BarkLevel = .active
    var groupByApp = true
    var opensAppOnTap = true
    var showsAppIcon = true

    var isConfigured: Bool { !trimmedKey.isEmpty }
    var trimmedKey: String { deviceKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    var needsRegistration: Bool { !deviceToken.isEmpty && trimmedKey.isEmpty }
    /// What the user typed, for display.
    var input: String { deviceToken.isEmpty ? deviceKey : deviceToken }

    /// Accepts a device token, a bare device key, or a URL copied from the Bark app,
    /// such as `https://api.day.app/abcdef/` or `https://bark.example.com/abcdef/Hello`.
    mutating func apply(input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isDeviceToken(trimmed) {
            if trimmed != deviceToken { deviceKey = "" }
            deviceToken = trimmed
            return
        }
        deviceToken = ""
        guard trimmed.contains("://"),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme, let host = components.host,
              let key = components.path.split(separator: "/").first.map(String.init) else {
            deviceKey = input
            return
        }
        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        origin.port = components.port
        serverURL = origin.string ?? serverURL
        deviceKey = key
    }

    /// APNs tokens are hex strings of 64 characters or more; Bark keys are short alphanumerics.
    static func isDeviceToken(_ value: String) -> Bool {
        (64...160).contains(value.count) && value.allSatisfy(\.isHexDigit)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? Self.defaultServer
        deviceKey = try container.decodeIfPresent(String.self, forKey: .deviceKey) ?? ""
        deviceToken = try container.decodeIfPresent(String.self, forKey: .deviceToken) ?? ""
        if deviceToken.isEmpty, Self.isDeviceToken(deviceKey) {
            // Saved before device tokens were recognized; register it on next launch.
            deviceToken = deviceKey
            deviceKey = ""
        }
        level = try container.decodeIfPresent(BarkLevel.self, forKey: .level) ?? .active
        groupByApp = try container.decodeIfPresent(Bool.self, forKey: .groupByApp) ?? true
        opensAppOnTap = try container.decodeIfPresent(Bool.self, forKey: .opensAppOnTap) ?? true
        showsAppIcon = try container.decodeIfPresent(Bool.self, forKey: .showsAppIcon) ?? true
    }
}

struct GeneralSettings: Codable, Equatable, Sendable {
    var launchAtLogin = false
    var barkDevices: [BarkConfiguration] = []
    var language: AppLanguage = .system

    var isBarkConfigured: Bool { barkDevices.contains(where: \.isConfigured) }
    var configuredBarkDevices: [BarkConfiguration] { barkDevices.filter(\.isConfigured) }

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, barkDevices, bark, language
    }

    init() {}

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(barkDevices, forKey: .barkDevices)
        try container.encode(language, forKey: .language)
    }

    // Decoded field by field so settings saved by older builds keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        if let devices = try container.decodeIfPresent([BarkConfiguration].self, forKey: .barkDevices) {
            barkDevices = devices
        } else if let legacy = try container.decodeIfPresent(BarkConfiguration.self, forKey: .bark), legacy.isConfigured || legacy.needsRegistration {
            barkDevices = [legacy]
        } else {
            barkDevices = []
        }
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
    }
}

struct PendingNotification: Codable, Sendable {
    var notification: CapturedNotification
    var remainingDeviceIDs: [UUID]
}

struct CapturedNotification: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let databaseID: Int64
    let sourceBundleID: String
    let sourceAppName: String
    let title: String
    let subtitle: String
    let body: String
    let originalDate: Date
    let capturedDate: Date
    /// URL opened when the push is tapped on iPhone, built from the Mac app's URL scheme.
    var openURL: String? = nil
}

struct RecentNotificationSource: Identifiable, Hashable, Sendable {
    let identifier: String
    let name: String
    let lastSeenAt: Date

    var id: String { identifier }
}

enum AppURLScheme {
    /// Apps whose Mac scheme differs from the one their iPhone app registers.
    private static let overrides = [
        "com.tencent.xinwechat": "weixin",
        "com.apple.mail": "message",
        "com.apple.mobilesms": "sms",
    ]
    /// Schemes that open a browser, file or system handler rather than the app itself.
    private static let generic: Set<String> = ["http", "https", "file", "ftp", "mailto", "tel", "facetime", "webcal"]

    /// Picks the scheme most likely to open the same app on iPhone, from the Mac app's
    /// public `CFBundleURLSchemes` in declaration order.
    static func preferred(bundleID: String, schemes: [String]) -> String? {
        if let override = overrides[bundleID.lowercased()] { return override }
        let candidates = schemes.map { $0.lowercased() }.filter { !generic.contains($0) && !$0.hasPrefix("x-") }
        // Reverse-DNS schemes are usually sign-in callbacks that only the Mac app handles.
        return candidates.first { !$0.contains(".") } ?? candidates.first
    }
}

enum ForwardDecision: Equatable, Sendable {
    case forward
    case blockedByApp
    case blockedByKeyword
    case blockedSelf
}

extension JSONEncoder {
    static var notiForward: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var notiForward: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
