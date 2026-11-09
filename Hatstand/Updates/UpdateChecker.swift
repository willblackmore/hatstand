import AppKit
import Combine
import os

/// A dotted version number such as `1.2` or `v1.2.3`, compared numerically
/// (so 1.10 is newer than 1.9, and 1.0 equals 1.0.0).
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    /// Accepts an optional leading "v" and ignores anything after the numbers,
    /// such as "-beta". Returns nil if there's no version number to read.
    init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let numeric = text.prefix { $0.isNumber || $0 == "." }
        let parts = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let n = Int(part) else { return nil }
            numbers.append(n)
        }
        components = numbers
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// The parts of GitHub's "latest release" response that Hatstand uses.
struct ReleaseInfo: Decodable, Equatable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    var version: AppVersion? { AppVersion(tagName) }

    /// True if this release is newer than `current`.
    func isNewer(than current: AppVersion) -> Bool {
        guard let version else { return false }
        return version > current
    }
}

/// Checks GitHub for a newer release of Hatstand. It never downloads or
/// installs anything: it only tells the user and opens the release page.
@MainActor
final class UpdateChecker: ObservableObject {

    /// GitHub's API for the newest published release (drafts and pre-releases are excluded).
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/willblackmore/hatstand/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Set when a newer release has been found.
    @Published private(set) var availableUpdate: ReleaseInfo?
    @Published private(set) var isChecking = false

    let currentVersion: AppVersion
    private let store: InstanceStore
    private let session: URLSession
    private var timer: Timer?
    private let logger = Logger(subsystem: "Hatstand", category: "UpdateChecker")

    /// `currentVersion` is for tests, which may not run inside the app bundle
    /// (for example under `swift test`); normally it's read from `bundle`.
    init(store: InstanceStore, session: URLSession = .shared, bundle: Bundle = .main, currentVersion: AppVersion? = nil) {
        self.store = store
        self.session = session
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        self.currentVersion = currentVersion ?? short.flatMap(AppVersion.init) ?? AppVersion("0")!
    }

    /// Checks shortly after launch and then once a day, if the setting is on.
    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkAutomatically() }
        }
        timer.tolerance = 60 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            await self?.checkAutomatically()
        }
    }

    private func checkAutomatically() async {
        guard store.settings.checkForUpdates else { return }
        _ = try? await check()
    }

    /// Asks GitHub for the latest release. Updates `availableUpdate` and returns the release found.
    @discardableResult
    func check() async throws -> ReleaseInfo? {
        guard !isChecking else { return availableUpdate }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Hatstand/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                // No releases published yet.
                availableUpdate = nil
                return nil
            }
            guard (200..<300).contains(status) else {
                throw UpdateError.badResponse(status)
            }
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            availableUpdate = release.isNewer(than: currentVersion) ? release : nil
            logger.info("Latest release \(release.tagName, privacy: .public); running \(self.currentVersion.description, privacy: .public)")
            return release
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// For "Check for Updates…": checks now and always reports the result.
    func checkAndReport() {
        Task { @MainActor in
            do {
                try await check()
                if let update = availableUpdate {
                    presentUpdate(update)
                } else {
                    showMessage(title: "Hatstand is up to date",
                                text: "You’re running the latest version, Hatstand \(currentVersion).")
                }
            } catch {
                showMessage(title: "Couldn’t check for updates",
                            text: "Hatstand couldn’t reach GitHub. Check your internet connection and try again.\n\n\(error.localizedDescription)",
                            style: .warning)
            }
        }
    }

    /// Shows what's new and offers to open the download page.
    func presentUpdate(_ release: ReleaseInfo) {
        let alert = NSAlert()
        let version = release.version?.description ?? release.tagName
        alert.messageText = "Hatstand \(version) is available"
        alert.informativeText = "You have Hatstand \(currentVersion). Download the new version from GitHub, then drag it into Applications to replace this one."
        alert.addButton(withTitle: "Download…")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func showMessage(title: String, text: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }

    enum UpdateError: LocalizedError {
        case badResponse(Int)
        var errorDescription: String? {
            switch self {
            case .badResponse(let status): return "GitHub replied with an error (\(status))."
            }
        }
    }
}
