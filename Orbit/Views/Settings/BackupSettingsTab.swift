import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Save your settings to a JSON file, and load them back or onto another Mac.
struct BackupSettingsTab: View {

    @Environment(AppState.self) private var appState
    @State private var message: Message?

    private struct Message: Equatable {
        var text: String
        var isError = false
    }

    var body: some View {
        SettingsPage {
            SettingsSection("Settings file", footer: "A readable JSON file with every setting in this window, including your shortcuts and which calendars are hidden. Your events aren't in it, though calendar names are.") {
                SettingsRow(title: "Export settings", detail: "Save your settings to a file.") {
                    Button("Export…", action: export)
                }
                SettingsRow(title: "Import settings", detail: "Replace your settings with the ones in a file. Anything the file doesn't mention stays as it is.") {
                    Button("Import…", action: chooseFileToImport)
                }
            }
            if let message {
                Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(message.isError ? Color.orange : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Orbit Settings \(Date().formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let file = appState.settingsFile(
            launchAtLogin: LaunchAtLogin.isEnabled,
            shortcuts: .init(
                toggleCalendar: KeyboardShortcuts.getShortcut(for: .toggleCalendar),
                joinNextMeeting: KeyboardShortcuts.getShortcut(for: .joinNextMeeting)
            ),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )
        do {
            try file.encoded().write(to: url, options: .atomic)
            message = Message(text: "Saved \(url.lastPathComponent).")
        } catch {
            message = Message(text: "Couldn't save the file: \(error.localizedDescription)", isError: true)
        }
    }

    private func chooseFileToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try SettingsFile.read(Data(contentsOf: url))
            guard confirmImport(of: url.lastPathComponent) else { return }
            apply(file)
        } catch let error as SettingsFile.ReadError {
            message = Message(text: error.localizedDescription, isError: true)
        } catch {
            message = Message(text: "Couldn't open the file: \(error.localizedDescription)", isError: true)
        }
    }

    private func confirmImport(of name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace your settings?"
        alert.informativeText = "The settings in \(name) replace your current ones. To keep a copy of your current settings, cancel and export them first."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func apply(_ file: SettingsFile) {
        let result = appState.importSettings(file)
        if let shortcuts = file.settings.shortcuts {
            KeyboardShortcuts.setShortcut(shortcuts.toggleCalendar, for: .toggleCalendar)
            KeyboardShortcuts.setShortcut(shortcuts.joinNextMeeting, for: .joinNextMeeting)
        }
        var loginItemFailed = false
        if let launchAtLogin = file.settings.launchAtLogin, launchAtLogin != LaunchAtLogin.isEnabled {
            do { try LaunchAtLogin.setEnabled(launchAtLogin) } catch { loginItemFailed = true }
        }
        var text = "Settings imported."
        if !result.unmatchedCalendars.isEmpty {
            text += " These calendars aren't on this Mac, so their settings were skipped: \(result.unmatchedCalendars.joined(separator: ", "))."
        }
        if loginItemFailed { text += " Launch at login couldn't be changed." }
        message = Message(text: text, isError: !result.unmatchedCalendars.isEmpty || loginItemFailed)
    }
}
