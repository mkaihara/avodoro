import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.logFolderPath) private var logFolderPath = ""
    @AppStorage(SettingsKey.presets) private var presetsText = SettingsStore.formatPresets(SettingsStore.defaultPresets)
    @AppStorage(SettingsKey.defaultBreakMinutes) private var defaultBreakMinutes = 5
    @AppStorage(SettingsKey.discardShorterThanMinutes) private var discardMinutes = 1
    @AppStorage(SettingsKey.askEnergy) private var askEnergy = true
    @AppStorage(SettingsKey.pauseOnScreenLock) private var pauseOnScreenLock = true
    @AppStorage(SettingsKey.soundAtEnd) private var soundAtEnd = true
    @AppStorage(SettingsKey.soundName) private var soundName = "Glass"
    @AppStorage(SettingsKey.notificationAtEnd) private var notificationAtEnd = true
    @AppStorage(SettingsKey.avocadoSize) private var size: AvocadoSize = .medium

    var body: some View {
        Form {
            Section("Log") {
                LogFolderRow(path: $logFolderPath)
            }

            Section("Timer") {
                PresetsEditor(text: $presetsText)
                Stepper(value: $defaultBreakMinutes, in: 1...60) {
                    LabeledContent("Default break", value: "\(defaultBreakMinutes) min")
                }
                Stepper(value: $discardMinutes, in: 0...10) {
                    LabeledContent("Discard sessions shorter than", value: "\(discardMinutes) min")
                }
                Toggle("Ask energy after focus", isOn: $askEnergy)
                Toggle("Pause on screen lock", isOn: $pauseOnScreenLock)
            }

            Section("End of session") {
                Toggle("Sound at end", isOn: $soundAtEnd)
                Picker("Sound", selection: $soundName) {
                    ForEach(Self.systemSounds, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!soundAtEnd)
                .onChange(of: soundName) { _, name in
                    NSSound(named: NSSound.Name(name))?.play()
                }
                Toggle("Notification at end", isOn: $notificationAtEnd)
            }

            Section("Avocado") {
                Picker("Size", selection: $size) {
                    Text("Small").tag(AvocadoSize.small)
                    Text("Medium").tag(AvocadoSize.medium)
                    Text("Large").tag(AvocadoSize.large)
                }
                .pickerStyle(.segmented)
            }

            Section("General") {
                LaunchAtLoginRow()
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Names of the sounds in /System/Library/Sounds, such as "Glass".
    private static let systemSounds: [String] = {
        let folder = URL(filePath: "/System/Library/Sounds", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let names = files.map { $0.deletingPathExtension().lastPathComponent }.sorted()
        return names.isEmpty ? ["Glass"] : names
    }()
}

// MARK: Log folder

private struct LogFolderRow: View {
    @Binding var path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(path.isEmpty ? "No folder chosen" : path)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(path)
                Spacer()
                Button("Choose…", action: choose)
            }
            status
        }
    }

    @ViewBuilder private var status: some View {
        if path.isEmpty {
            Text("Choose where the daily log files go.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if !Self.isDirectory(path) {
            Label("Folder not found.", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        } else if let vault = VaultDetector.vaultName(containing: URL(filePath: path, directoryHint: .isDirectory)) {
            Label("Inside vault: \(vault)", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Label("This folder is not inside an Obsidian vault.", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder for the daily log files."
        if !path.isEmpty {
            panel.directoryURL = URL(filePath: path, directoryHint: .isDirectory)
        }
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

// MARK: Presets

private struct PresetsEditor: View {
    @Binding var text: String
    @State private var rows: [Row] = []

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var minutes: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Presets")
            ForEach($rows) { $row in
                HStack {
                    Stepper(value: $row.minutes, in: SettingsStore.presetRange) {
                        Text("\(row.minutes) min")
                            .monospacedDigit()
                    }
                    Spacer()
                    Button {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(rows.count <= 1)
                    .accessibilityLabel("Remove \(row.minutes) minute preset")
                }
            }
            Button("Add preset", action: add)
                .disabled(rows.count >= SettingsStore.maxPresets)
        }
        .onAppear {
            rows = SettingsStore.parsePresets(text).map { Row(minutes: $0) }
        }
        .onChange(of: rows) { _, rows in
            // Stored as entered; the avocado shows them sorted and without duplicates.
            text = SettingsStore.formatPresets(rows.map(\.minutes))
        }
    }

    private func add() {
        let taken = Set(rows.map(\.minutes))
        let candidate = [25, 30, 45, 60, 90, 120].first { !taken.contains($0) }
            ?? SettingsStore.presetRange.first { !taken.contains($0) } ?? 25
        rows.append(Row(minutes: candidate))
    }
}

// MARK: Launch at login

private struct LaunchAtLoginRow: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A closure, not `set: setEnabled`: the method reference crashes the Swift 6.1 compiler.
            Toggle("Launch at login", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: { setEnabled($0) }
            ))
            if status == .requiresApproval {
                HStack {
                    Text("Allow Avodoro in System Settings › Login Items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Launch at login change failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}
