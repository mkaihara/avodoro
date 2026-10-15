import Foundation
import Testing
@testable import Avodoro

@MainActor
struct SettingsStoreTests {
    let suiteName = "AvodoroTests-\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    @Test func parsePresets() {
        #expect(SettingsStore.parsePresets("5,10,15,20") == [5, 10, 15, 20])
        #expect(SettingsStore.parsePresets(" 20, 5 ,10") == [5, 10, 20])
        #expect(SettingsStore.parsePresets("10,10,5") == [5, 10])
        #expect(SettingsStore.parsePresets("0,121,abc,-5,30") == [30])
        #expect(SettingsStore.parsePresets("1,2,3,4,5,6,7,8") == [1, 2, 3, 4, 5, 6])
        #expect(SettingsStore.parsePresets("") == [5, 10, 15, 20])
        #expect(SettingsStore.parsePresets("0,500") == [5, 10, 15, 20])
        #expect(SettingsStore.formatPresets([5, 45, 120]) == "5,45,120")
    }

    @Test func defaultsMatchTheSpec() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.logFolder == nil)
        #expect(store.presets == [5, 10, 15, 20])
        #expect(store.configuration == TimerEngine.Configuration(
            discardThreshold: 60, defaultBreakMinutes: 5, askEnergy: true, pauseOnScreenLock: true
        ))
        #expect(store.soundAtEnd)
        #expect(store.soundName == "Glass")
        #expect(store.notificationAtEnd)
    }

    @Test func reloadMapsValuesAndCallsBackOnlyOnChange() {
        let defaults = self.defaults
        let store = SettingsStore(defaults: defaults)
        var folders: [URL?] = []
        var configurations: [TimerEngine.Configuration] = []
        store.onLogFolderChange = { folders.append($0) }
        store.onConfigurationChange = { configurations.append($0) }

        defaults.set("/tmp/vault/log", forKey: SettingsKey.logFolderPath)
        defaults.set(3, forKey: SettingsKey.discardShorterThanMinutes)
        defaults.set(false, forKey: SettingsKey.askEnergy)
        defaults.set("45,5", forKey: SettingsKey.presets)
        store.reload()
        // The store also reloads on every `set` (didChangeNotification), so two configuration
        // values changed means up to two callbacks. Reloading with no change calls back nothing.
        let callbacks = (folders.count, configurations.count)
        store.reload()
        #expect(folders.count == callbacks.0)
        #expect(configurations.count == callbacks.1)

        #expect(folders == [URL(filePath: "/tmp/vault/log", directoryHint: .isDirectory)])
        #expect(!configurations.isEmpty)
        #expect(store.configuration.discardThreshold == 180)
        #expect(!store.configuration.askEnergy)
        #expect(store.presets == [5, 45])

        defaults.set("", forKey: SettingsKey.logFolderPath)
        store.reload()
        #expect(folders.count == 2)
        #expect(folders.last == .some(nil))
    }
}

struct VaultDetectorTests {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "AvodoroTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    func makeFolder(_ path: String) throws -> URL {
        let url = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func folderIsTheVault() throws {
        let vault = try makeFolder("Notes")
        _ = try makeFolder("Notes/.obsidian")
        #expect(VaultDetector.vaultName(containing: vault) == "Notes")
    }

    @Test func folderInsideAVault() throws {
        _ = try makeFolder("My Vault/.obsidian")
        let log = try makeFolder("My Vault/Journal/Pomodoro")
        #expect(VaultDetector.vaultName(containing: log) == "My Vault")
    }

    @Test func noVault() throws {
        let folder = try makeFolder("Plain/Folder")
        #expect(VaultDetector.vaultName(containing: folder) == nil)
    }

    @Test func obsidianFileIsNotAVault() throws {
        let folder = try makeFolder("Fake")
        FileManager.default.createFile(atPath: folder.appending(path: ".obsidian").path, contents: Data())
        #expect(VaultDetector.vaultName(containing: folder) == nil)
    }
}
