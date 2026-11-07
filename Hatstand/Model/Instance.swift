import Foundation

/// A Claude instance: a pair of data folders that Claude is launched with.
///
/// The default instance is represented with a fixed ID and uses Claude's
/// normal locations. It is never stored in `AppConfig.instances`.
struct Instance: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// Passed to Claude as `--user-data-dir`.
    var appDataPath: String
    /// Passed to Claude as `CLAUDE_CONFIG_DIR`.
    var claudeCodePath: String

    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var isDefault: Bool { id == Instance.defaultID }

    /// The default instance, shown with Claude's normal data locations.
    static func makeDefault(
        name: String,
        locations: ClaudeDefaultLocations = ClaudeDefaultLocations()
    ) -> Instance {
        Instance(
            id: defaultID,
            name: name,
            appDataPath: locations.appData,
            claudeCodePath: locations.claudeCode
        )
    }
}

struct AppSettings: Codable, Equatable {
    var confirmBeforeSwitching: Bool = true
    var claudeAppPath: String = "/Applications/Claude.app"
    /// Ask GitHub once a day whether there's a newer release.
    var checkForUpdates: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        confirmBeforeSwitching = try c.decodeIfPresent(Bool.self, forKey: .confirmBeforeSwitching)
            ?? defaults.confirmBeforeSwitching
        claudeAppPath = try c.decodeIfPresent(String.self, forKey: .claudeAppPath)
            ?? defaults.claudeAppPath
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates)
            ?? defaults.checkForUpdates
    }
}

/// Everything Hatstand saves to `config.json`.
struct AppConfig: Codable, Equatable {
    var version: Int = 1
    var defaultInstanceName: String = "Default"
    var instances: [Instance] = []
    var settings = AppSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? defaults.version
        defaultInstanceName = try c.decodeIfPresent(String.self, forKey: .defaultInstanceName)
            ?? defaults.defaultInstanceName
        instances = try c.decodeIfPresent([Instance].self, forKey: .instances) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        // Never let a stored instance masquerade as the default one.
        instances.removeAll { $0.isDefault }
    }
}
