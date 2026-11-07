import Foundation
import Combine
import os

/// Owns the instance list and settings, and saves them to `config.json`.
@MainActor
final class InstanceStore: ObservableObject {

    enum StoreError: LocalizedError {
        case invalid([ValidationIssue])
        case notFound

        var errorDescription: String? {
            switch self {
            case .invalid(let issues):
                return issues.first { $0.severity == .error }?.message ?? "The instance isn’t valid."
            case .notFound:
                return "The instance couldn’t be found."
            }
        }
    }

    @Published private(set) var config: AppConfig
    /// Set if the last save failed, so the UI can say so.
    @Published private(set) var lastSaveError: String?

    let configURL: URL
    let locations: ClaudeDefaultLocations
    var validator: InstanceValidator { InstanceValidator(locations: locations) }

    private let logger = Logger(subsystem: "Hatstand", category: "InstanceStore")

    nonisolated static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Hatstand/config.json")
    }

    /// Where the app saved its config when it was called CSwitcher.
    nonisolated static var legacyConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CSwitcher/config.json")
    }

    /// Copies a config saved under the app's old name to the new location, once.
    ///
    /// Only `config.json` is copied. The old file is left in place, and instance
    /// folders are never moved: the config records their full paths, so instances
    /// created under the old `CSwitcher/Instances` folder keep working from there.
    /// Returns true if a copy was made.
    @discardableResult
    nonisolated static func copyLegacyConfigIfNeeded(from legacy: URL = legacyConfigURL,
                                                     to url: URL = defaultConfigURL) -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path), fm.fileExists(atPath: legacy.path) else { return false }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: legacy, to: url)
            Logger(subsystem: "Hatstand", category: "InstanceStore")
                .info("Copied config from \(legacy.path, privacy: .public)")
            return true
        } catch {
            Logger(subsystem: "Hatstand", category: "InstanceStore")
                .error("Couldn’t copy old config: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    init(configURL: URL = InstanceStore.defaultConfigURL,
         locations: ClaudeDefaultLocations = ClaudeDefaultLocations()) {
        self.configURL = configURL
        self.locations = locations
        self.config = InstanceStore.load(from: configURL)
    }

    // MARK: Reading

    var defaultInstance: Instance {
        Instance.makeDefault(name: config.defaultInstanceName, locations: locations)
    }

    /// The default instance first, then the others in the order they were added.
    var allInstances: [Instance] { [defaultInstance] + config.instances }

    var settings: AppSettings { config.settings }

    func instance(withID id: UUID) -> Instance? {
        allInstances.first { $0.id == id }
    }

    // MARK: Changing

    func rename(_ id: UUID, to newName: String) throws {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let issue = validator.validateName(name, existing: allInstances, excluding: id) {
            throw StoreError.invalid([issue])
        }
        if id == Instance.defaultID {
            config.defaultInstanceName = name
        } else if let index = config.instances.firstIndex(where: { $0.id == id }) {
            config.instances[index].name = name
        } else {
            throw StoreError.notFound
        }
        save()
    }

    /// Validates and adds a new instance. Paths are standardised first.
    @discardableResult
    func add(name: String, appDataPath: String, claudeCodePath: String) throws -> Instance {
        let home = locations.homeDirectory
        let instance = Instance(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            appDataPath: PathStandardiser.standardise(appDataPath, homeDirectory: home),
            claudeCodePath: PathStandardiser.standardise(claudeCodePath, homeDirectory: home)
        )
        var issues = validator.validatePaths(
            appData: instance.appDataPath,
            claudeCode: instance.claudeCodePath,
            existing: config.instances
        )
        if let nameIssue = validator.validateName(instance.name, existing: allInstances) {
            issues.append(nameIssue)
        }
        if issues.hasErrors { throw StoreError.invalid(issues) }

        config.instances.append(instance)
        save()
        return instance
    }

    func remove(_ id: UUID) {
        config.instances.removeAll { $0.id == id }
        save()
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var settings = config.settings
        change(&settings)
        guard settings != config.settings else { return }
        config.settings = settings
        save()
    }

    // MARK: Persistence

    static func load(from url: URL) -> AppConfig {
        guard let data = try? Data(contentsOf: url) else { return AppConfig() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            // Keep the unreadable file rather than overwrite it, so nothing is lost.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("config-unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            Logger(subsystem: "Hatstand", category: "InstanceStore")
                .error("Couldn’t read config, moved to \(backup.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return AppConfig()
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
            lastSaveError = nil
        } catch {
            logger.error("Couldn’t save config: \(error.localizedDescription, privacy: .public)")
            lastSaveError = error.localizedDescription
        }
    }
}
