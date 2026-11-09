import Testing
import Foundation
@testable import Hatstand

@MainActor
struct InstanceStoreTests {

    func makeStore(_ temp: TemporaryFolder) -> InstanceStore {
        InstanceStore(
            configURL: URL(fileURLWithPath: temp.path + "/config/config.json"),
            locations: ClaudeDefaultLocations(homeDirectory: temp.path + "/home")
        )
    }

    @Test func startsWithJustTheDefaultInstance() throws {
        let temp = try TemporaryFolder()
        let store = makeStore(temp)
        #expect(store.allInstances.count == 1)
        #expect(store.allInstances[0].isDefault)
        #expect(store.allInstances[0].name == "Default")
        #expect(store.settings.confirmBeforeSwitching)
        #expect(store.settings.claudeAppPath == "/Applications/Claude.app")
    }

    @Test func addsRenamesAndPersists() throws {
        let temp = try TemporaryFolder()
        let store = makeStore(temp)
        let personal = try store.add(name: "  Personal ",
                                     appDataPath: temp.path + "/home/.claude-instances/personal/",
                                     claudeCodePath: temp.path + "/home/.claude-personal")
        try store.rename(Instance.defaultID, to: "Work")
        store.updateSettings { $0.confirmBeforeSwitching = false }

        #expect(personal.name == "Personal")
        #expect(!personal.appDataPath.hasSuffix("/"))

        let reloaded = makeStore(temp)
        #expect(reloaded.config == store.config)
        #expect(reloaded.allInstances.map(\.name) == ["Work", "Personal"])
        #expect(reloaded.settings.confirmBeforeSwitching == false)
    }

    @Test func refusesInvalidInstances() throws {
        let temp = try TemporaryFolder()
        let store = makeStore(temp)
        try store.rename(Instance.defaultID, to: "Work")

        #expect(throws: InstanceStore.StoreError.self) {
            try store.add(name: "work", appDataPath: temp.path + "/a", claudeCodePath: temp.path + "/b")
        }
        #expect(throws: InstanceStore.StoreError.self) {
            try store.add(name: "Personal", appDataPath: temp.path + "/home/.claude", claudeCodePath: temp.path + "/b")
        }
        #expect(throws: InstanceStore.StoreError.self) {
            try store.rename(Instance.defaultID, to: " ")
        }
        #expect(store.config.instances.isEmpty)
    }

    @Test func removes() throws {
        let temp = try TemporaryFolder()
        let store = makeStore(temp)
        let a = try store.add(name: "A", appDataPath: temp.path + "/a/app", claudeCodePath: temp.path + "/a/cc")
        store.remove(a.id)
        #expect(makeStore(temp).config.instances.isEmpty)
    }

    @Test func keepsUnreadableConfigInsteadOfOverwriting() throws {
        let temp = try TemporaryFolder()
        let folder = try temp.makeFolder("config")
        try Data("{ not json".utf8).write(to: URL(fileURLWithPath: folder + "/config.json"))

        let store = makeStore(temp)
        #expect(store.config == AppConfig())
        let files = try FileManager.default.contentsOfDirectory(atPath: folder)
        #expect(files.contains { $0.hasPrefix("config-unreadable-") })
    }

    @Test func toleratesMissingKeys() throws {
        let json = #"{ "defaultInstanceName": "Work", "instances": [] }"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.defaultInstanceName == "Work")
        #expect(config.settings == AppSettings())
    }

    @Test func dropsStoredInstancesUsingTheDefaultID() throws {
        let json = #"""
        { "instances": [ { "id": "00000000-0000-0000-0000-000000000000", "name": "Sneaky",
                           "appDataPath": "/a", "claudeCodePath": "/b" } ] }
        """#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.instances.isEmpty)
    }
}
