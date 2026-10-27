import Foundation
import Testing

@Suite struct BarkConfigurationTests {
    @Test(arguments: [
        ("abcDEF123", "https://api.day.app", "abcDEF123"),
        (" https://api.day.app/abcDEF123/ ", "https://api.day.app", "abcDEF123"),
        ("https://bark.example.com:8080/KEY9/Hello", "https://bark.example.com:8080", "KEY9"),
        ("http://192.168.1.2/k", "http://192.168.1.2", "k"),
    ])
    func parsesKeyOrURL(input: String, server: String, key: String) {
        var configuration = BarkConfiguration()
        configuration.apply(input: input)
        #expect(configuration.serverURL == server)
        #expect(configuration.trimmedKey == key)
        #expect(configuration.isConfigured)
    }

    @Test func recognizesDeviceTokenAndNeedsRegistration() {
        let token = String(repeating: "0123456789abcdef", count: 4)
        var configuration = BarkConfiguration()
        configuration.apply(input: "  \(token)\n")
        #expect(configuration.deviceToken == token)
        #expect(configuration.input == token)
        #expect(!configuration.isConfigured)
        #expect(configuration.needsRegistration)
        configuration.deviceKey = "registered"
        configuration.apply(input: token)
        #expect(configuration.trimmedKey == "registered", "re-entering the same token keeps its key")
        configuration.apply(input: "plainKey")
        #expect(configuration.deviceToken.isEmpty)
        #expect(configuration.trimmedKey == "plainKey")
    }

    @Test func movesTokenSavedAsKeyByOlderBuilds() throws {
        let token = String(repeating: "ab", count: 32)
        let saved = #"{"bark":{"serverURL":"https://api.day.app","deviceKey":"\#(token)"}}"#
        let settings = try JSONDecoder.notiForward.decode(GeneralSettings.self, from: Data(saved.utf8))
        #expect(settings.barkDevices.count == 1)
        #expect(settings.barkDevices[0].deviceToken == token)
        #expect(settings.barkDevices[0].needsRegistration)
    }

    @Test func emptyKeyIsNotConfigured() {
        var configuration = BarkConfiguration()
        configuration.apply(input: "   ")
        #expect(!configuration.isConfigured)
    }

    @Test func decodesSettingsSavedByOlderBuilds() throws {
        let legacy = #"{"launchAtLogin":true,"iCloudSyncEnabled":true,"retention":30,"language":"zh-Hans"}"#
        let settings = try JSONDecoder.notiForward.decode(GeneralSettings.self, from: Data(legacy.utf8))
        #expect(settings.launchAtLogin)
        #expect(settings.language == .chineseSimplified)
        #expect(settings.barkDevices.isEmpty)
    }

    @Test func migratesLegacyConfiguredDeviceAndRoundTripsMultipleDevices() throws {
        let legacy = #"{"bark":{"serverURL":"https://api.day.app","deviceKey":"first"}}"#
        var settings = try JSONDecoder.notiForward.decode(GeneralSettings.self, from: Data(legacy.utf8))
        #expect(settings.barkDevices.map(\.trimmedKey) == ["first"])
        var second = BarkConfiguration()
        second.name = "iPad"
        second.apply(input: "second")
        settings.barkDevices.append(second)
        let decoded = try JSONDecoder.notiForward.decode(GeneralSettings.self, from: JSONEncoder.notiForward.encode(settings))
        #expect(decoded.barkDevices.map(\.trimmedKey) == ["first", "second"])
        #expect(decoded.barkDevices[1].name == "iPad")
        #expect(decoded.isBarkConfigured)
    }
}

@Suite struct BarkMessageTests {
    private func notification(title: String = "", subtitle: String = "", body: String = "") -> CapturedNotification {
        CapturedNotification(id: UUID(), databaseID: 1, sourceBundleID: "com.example.chat", sourceAppName: "Chat",
                             title: title, subtitle: subtitle, body: body, originalDate: Date(), capturedDate: Date())
    }

    @Test func prefixesTitleWithAppAndGroupsByApp() {
        let message = BarkMessage(notification(title: "Alice", subtitle: "Team", body: "Hi"), configuration: BarkConfiguration())
        #expect(message.title == "Chat · Alice")
        #expect(message.subtitle == "Team")
        #expect(message.body == "Hi")
        #expect(message.group == "Chat")
    }

    @Test func carriesOpenURLUnlessDisabled() {
        var source = notification(title: "Alice", body: "Hi")
        source.openURL = "tg://"
        var configuration = BarkConfiguration()
        #expect(BarkMessage(source, configuration: configuration).url == "tg://")
        configuration.opensAppOnTap = false
        #expect(BarkMessage(source, configuration: configuration).url == nil)
    }

    @Test(arguments: [
        ("ru.keepcoder.Telegram", ["tg", "telegram", "ton", "tc"], "tg"),
        ("com.tencent.xinWeChat", ["xweixin", "weixin", "wechat"], "weixin"),
        ("com.microsoft.edgemac", ["http", "https", "microsoft-edge", "file"], "microsoft-edge"),
        ("com.example.app", ["com.example.app.oauth", "example"], "example"),
        ("com.example.none", ["https"], nil),
    ] as [(String, [String], String?)])
    func picksIPhoneFriendlyScheme(bundleID: String, schemes: [String], expected: String?) {
        #expect(AppURLScheme.preferred(bundleID: bundleID, schemes: schemes) == expected)
    }

    @Test func fallsBackWhenFieldsAreEmpty() {
        var configuration = BarkConfiguration()
        configuration.groupByApp = false
        #expect(BarkMessage(notification(title: "Done"), configuration: configuration).body == "Done")
        let bare = BarkMessage(notification(), configuration: configuration)
        #expect(bare.title == "Chat")
        #expect(bare.body == "Chat")
        #expect(bare.group == nil)
    }
}

/// Serves canned responses and records requests for `BarkClient`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (status: Int, body: String) = (200, #"{"code":200,"message":"success"}"#)
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: [String: Any] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            Self.lastBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: Self.response.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct BarkClientTests {
    private let client: BarkClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return BarkClient(session: URLSession(configuration: configuration))
    }()

    private var configuration: BarkConfiguration {
        var configuration = BarkConfiguration()
        configuration.apply(input: "https://bark.example.com/KEY123/")
        configuration.level = .timeSensitive
        return configuration
    }

    @Test func postsJSONToPushEndpoint() async throws {
        StubURLProtocol.response = (200, #"{"code":200,"message":"success"}"#)
        try await client.send(BarkMessage(title: "T", body: "B", group: "G"), configuration: configuration)
        #expect(StubURLProtocol.lastRequest?.url?.absoluteString == "https://bark.example.com/push")
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubURLProtocol.lastBody["device_key"] as? String == "KEY123")
        let sentTitle = StubURLProtocol.lastBody["title"] as? String
        #expect(sentTitle?.hasPrefix("T[") == true)
        #expect(sentTitle?.hasSuffix("]") == true)
        #expect(StubURLProtocol.lastBody["body"] as? String == "B")
        #expect(StubURLProtocol.lastBody["group"] as? String == "G")
        #expect(StubURLProtocol.lastBody["level"] as? String == "timeSensitive")
        #expect(StubURLProtocol.lastBody["subtitle"] == nil)
        #expect(StubURLProtocol.lastBody["url"] == nil)
    }

    @Test func registersDeviceTokenForKey() async throws {
        StubURLProtocol.response = (200, #"{"code":200,"message":"success","data":{"key":"NEWKEY","device_key":"NEWKEY","device_token":"t"}}"#)
        var configuration = BarkConfiguration()
        configuration.apply(input: String(repeating: "ab", count: 32))
        let key = try await client.register(configuration: configuration)
        #expect(key == "NEWKEY")
        #expect(StubURLProtocol.lastRequest?.url?.absoluteString == "https://api.day.app/register")
        #expect(StubURLProtocol.lastBody["device_token"] as? String == String(repeating: "ab", count: 32))
    }

    @Test func surfacesServerErrors() async {
        StubURLProtocol.response = (400, #"{"code":400,"message":"failed to get device token"}"#)
        await #expect {
            try await client.send(BarkMessage(title: "T", body: "B"), configuration: configuration)
        } throws: { error in
            guard case BarkError.server(400, "failed to get device token") = error else { return false }
            return true
        }
    }

    @Test func rejectsMissingKeyAndBadServer() async {
        await #expect(throws: BarkError.self) {
            try await client.send(BarkMessage(title: "T", body: "B"), configuration: BarkConfiguration())
        }
        var bad = configuration
        bad.serverURL = "ftp://example.com"
        await #expect(throws: BarkError.self) {
            try await client.send(BarkMessage(title: "T", body: "B"), configuration: bad)
        }
    }
}
