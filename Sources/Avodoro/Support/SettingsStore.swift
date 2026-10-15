import Foundation
import Observation

/// `UserDefaults` keys. `SettingsView` binds them with `@AppStorage`.
enum SettingsKey {
    static let logFolderPath = "logFolderPath"
    static let presets = "presets"
    static let defaultBreakMinutes = "defaultBreakMinutes"
    static let askEnergy = "askEnergy"
    static let soundAtEnd = "soundAtEnd"
    static let soundName = "soundName"
    static let notificationAtEnd = "notificationAtEnd"
    static let pauseOnScreenLock = "pauseOnScreenLock"
    static let discardShorterThanMinutes = "discardShorterThanMinutes"
    static let avocadoSize = AvocadoSize.defaultsKey
}

/// Typed, observable view of the settings for code outside the Settings window.
@MainActor
@Observable
final class SettingsStore {
    nonisolated static let defaultPresets = [5, 10, 15, 20]
    nonisolated static let maxPresets = 6
    nonisolated static let presetRange = 1...120

    nonisolated static var registeredDefaults: [String: Any] {
        [
        SettingsKey.presets: formatPresets(defaultPresets),
        SettingsKey.defaultBreakMinutes: 5,
        SettingsKey.askEnergy: true,
        SettingsKey.soundAtEnd: true,
        SettingsKey.soundName: "Glass",
        SettingsKey.notificationAtEnd: true,
        SettingsKey.pauseOnScreenLock: true,
        SettingsKey.discardShorterThanMinutes: 1,
        SettingsKey.avocadoSize: AvocadoSize.medium.rawValue,
        ]
    }

    private(set) var logFolder: URL?
    private(set) var presets: [Int]
    private(set) var configuration: TimerEngine.Configuration
    private(set) var soundAtEnd: Bool
    private(set) var soundName: String
    private(set) var notificationAtEnd: Bool

    @ObservationIgnored var onLogFolderChange: ((URL?) -> Void)?
    @ObservationIgnored var onConfigurationChange: ((TimerEngine.Configuration) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: Self.registeredDefaults)
        self.defaults = defaults
        logFolder = Self.logFolder(in: defaults)
        presets = Self.parsePresets(defaults.string(forKey: SettingsKey.presets) ?? "")
        configuration = Self.configuration(in: defaults)
        soundAtEnd = defaults.bool(forKey: SettingsKey.soundAtEnd)
        soundName = defaults.string(forKey: SettingsKey.soundName) ?? "Glass"
        notificationAtEnd = defaults.bool(forKey: SettingsKey.notificationAtEnd)

        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Re-reads every value; assigns and calls back only for values that changed.
    func reload() {
        let folder = Self.logFolder(in: defaults)
        if folder != logFolder {
            logFolder = folder
            onLogFolderChange?(folder)
        }
        let newConfiguration = Self.configuration(in: defaults)
        if newConfiguration != configuration {
            configuration = newConfiguration
            onConfigurationChange?(newConfiguration)
        }
        let newPresets = Self.parsePresets(defaults.string(forKey: SettingsKey.presets) ?? "")
        if newPresets != presets { presets = newPresets }
        let newSoundAtEnd = defaults.bool(forKey: SettingsKey.soundAtEnd)
        if newSoundAtEnd != soundAtEnd { soundAtEnd = newSoundAtEnd }
        let newSoundName = defaults.string(forKey: SettingsKey.soundName) ?? "Glass"
        if newSoundName != soundName { soundName = newSoundName }
        let newNotification = defaults.bool(forKey: SettingsKey.notificationAtEnd)
        if newNotification != notificationAtEnd { notificationAtEnd = newNotification }
    }

    // MARK: Pure helpers

    /// Each preset 1…120, unique, sorted, at most 6. Nothing valid → the defaults.
    nonisolated static func parsePresets(_ text: String) -> [Int] {
        let values = text
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { presetRange.contains($0) }
        let unique = Array(Set(values)).sorted().prefix(maxPresets)
        return unique.isEmpty ? defaultPresets : Array(unique)
    }

    nonisolated static func formatPresets(_ presets: [Int]) -> String {
        presets.map(String.init).joined(separator: ",")
    }

    private static func logFolder(in defaults: UserDefaults) -> URL? {
        guard let path = defaults.string(forKey: SettingsKey.logFolderPath), !path.isEmpty else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    private static func configuration(in defaults: UserDefaults) -> TimerEngine.Configuration {
        TimerEngine.Configuration(
            discardThreshold: TimeInterval(max(0, defaults.integer(forKey: SettingsKey.discardShorterThanMinutes)) * 60),
            defaultBreakMinutes: min(max(defaults.integer(forKey: SettingsKey.defaultBreakMinutes), 1), 60),
            askEnergy: defaults.bool(forKey: SettingsKey.askEnergy),
            pauseOnScreenLock: defaults.bool(forKey: SettingsKey.pauseOnScreenLock)
        )
    }
}
