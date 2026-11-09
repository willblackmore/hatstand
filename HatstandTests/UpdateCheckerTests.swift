import Testing
import Foundation
@testable import Hatstand

struct AppVersionTests {

    @Test func parsesCommonForms() {
        #expect(AppVersion("1.0")?.components == [1, 0])
        #expect(AppVersion("v1.2.3")?.components == [1, 2, 3])
        #expect(AppVersion("V2")?.components == [2])
        #expect(AppVersion(" 1.4-beta.2 ")?.components == [1, 4])
    }

    @Test func rejectsNonVersions() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("v") == nil)
        #expect(AppVersion("1..2") == nil)
    }

    @Test func comparesNumerically() throws {
        func v(_ s: String) throws -> AppVersion { try #require(AppVersion(s)) }
        #expect(try v("1.10") > v("1.9"))
        #expect(try v("2.0") > v("1.99.99"))
        #expect(try v("1.0.1") > v("1.0"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try v("v1.0") == v("1"))
        #expect(try !(v("1.0") < v("1.0")))
    }
}

struct ReleaseInfoTests {

    let json = """
    {
      "url": "https://api.github.com/repos/willblackmore/hatstand/releases/1",
      "html_url": "https://github.com/willblackmore/hatstand/releases/tag/v1.1",
      "tag_name": "v1.1",
      "name": "Hatstand 1.1",
      "draft": false,
      "prerelease": false
    }
    """

    @Test func decodesGitHubResponse() throws {
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        #expect(release.tagName == "v1.1")
        #expect(release.htmlURL.absoluteString == "https://github.com/willblackmore/hatstand/releases/tag/v1.1")
        #expect(release.version?.description == "1.1")
    }

    @Test func knowsWhenItIsNewer() throws {
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        #expect(release.isNewer(than: try #require(AppVersion("1.0"))))
        #expect(!release.isNewer(than: try #require(AppVersion("1.1"))))
        #expect(!release.isNewer(than: try #require(AppVersion("1.2"))))
    }

    @Test func ignoresUnreadableTags() {
        let release = ReleaseInfo(tagName: "nightly", htmlURL: URL(string: "https://example.com")!)
        #expect(!release.isNewer(than: AppVersion("0.1")!))
    }
}

struct UpdateSettingsTests {

    @Test func checkForUpdatesDefaultsToOnForOlderConfigs() throws {
        let json = #"{ "confirmBeforeSwitching": false, "claudeAppPath": "/Applications/Claude.app" }"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.checkForUpdates)
        #expect(!settings.confirmBeforeSwitching)
    }
}

/// Serves canned responses so the checker can be tested without the network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "X-Test-Key") ?? ""
        let (status, body) = Self.responses[key] ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct UpdateCheckerTests {

    func makeChecker(_ temp: TemporaryFolder, key: String) -> UpdateChecker {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Key": key]
        let store = InstanceStore(
            configURL: URL(fileURLWithPath: temp.path + "/config.json"),
            locations: ClaudeDefaultLocations(homeDirectory: temp.path + "/home")
        )
        return UpdateChecker(store: store, session: URLSession(configuration: config), currentVersion: AppVersion("1.0")!)
    }

    @Test func findsANewerRelease() async throws {
        StubURLProtocol.responses["newer"] = (200, #"{ "tag_name": "v99.0", "html_url": "https://github.com/willblackmore/hatstand/releases/tag/v99.0" }"#)
        let checker = makeChecker(try TemporaryFolder(), key: "newer")
        try await checker.check()
        #expect(checker.availableUpdate?.tagName == "v99.0")
    }

    @Test func staysQuietWhenUpToDate() async throws {
        StubURLProtocol.responses["same"] = (200, #"{ "tag_name": "v0.0.1", "html_url": "https://github.com/willblackmore/hatstand/releases/tag/v0.0.1" }"#)
        let checker = makeChecker(try TemporaryFolder(), key: "same")
        try await checker.check()
        #expect(checker.availableUpdate == nil)
    }

    @Test func treatsNoReleasesAsUpToDate() async throws {
        StubURLProtocol.responses["none"] = (404, #"{ "message": "Not Found" }"#)
        let checker = makeChecker(try TemporaryFolder(), key: "none")
        #expect(try await checker.check() == nil)
        #expect(checker.availableUpdate == nil)
    }

    @Test func reportsServerErrors() async throws {
        StubURLProtocol.responses["error"] = (503, "")
        let checker = makeChecker(try TemporaryFolder(), key: "error")
        await #expect(throws: UpdateChecker.UpdateError.self) {
            try await checker.check()
        }
        #expect(!checker.isChecking)
    }
}
