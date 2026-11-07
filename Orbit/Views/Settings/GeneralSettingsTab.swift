import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsTab: View {

    @Environment(AppState.self) private var appState
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var isShowingShortcuts = false

    var body: some View {
        @Bindable var preferences = appState.preferences

        SettingsPage {
            SettingsSection("Startup") {
                SettingsToggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                SettingsToggle("Keep calendar on top", detail: "The calendar stays open until you click the menu bar item again.", isOn: $preferences.keepCalendarOnTop)
            }

            SettingsSection("Theme") {
                SettingsSegmentedPicker(title: "Appearance", selection: $preferences.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
            }

            SettingsSection("Shortcuts") {
                SettingsToggle("Enable global shortcuts", isOn: $preferences.globalShortcutsEnabled)
                SettingsRow(title: "Toggle calendar") {
                    KeyboardShortcuts.Recorder(for: .toggleCalendar)
                        .disabled(!preferences.globalShortcutsEnabled)
                }
                SettingsRow(title: "Join next meeting") {
                    KeyboardShortcuts.Recorder(for: .joinNextMeeting)
                        .disabled(!preferences.globalShortcutsEnabled)
                }
                SettingsRow(title: "Calendar shortcuts") {
                    Button("Show…") { isShowingShortcuts = true }
                        .popover(isPresented: $isShowingShortcuts, arrowEdge: .trailing) {
                            ShortcutsHelpView()
                        }
                }
            }

            SettingsSection("Updates") {
                SettingsToggle("Check for updates automatically", detail: "Once a day, Orbit asks GitHub for the latest version. Nothing about you or your calendar is sent.", isOn: $preferences.checkForUpdates)
            }

            PrivacySection()

            CustomVideoServicesSection()
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LaunchAtLogin.isEnabled else { return }
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchError = nil
        } catch {
            launchError = "Couldn't change the login item: \(error.localizedDescription)"
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

private struct PrivacySection: View {

    @Environment(AppState.self) private var appState
    @State private var isShowingDetails = false

    var body: some View {
        @Bindable var preferences = appState.preferences
        SettingsSection("Privacy", footer: "Your events and calendar names are never sent. Neither report includes an ID or anything that identifies you, and your IP address isn't stored.") {
            SettingsToggle("Share anonymous usage stats", detail: "Once a day: your Orbit and macOS versions and which main options you use.", isOn: $preferences.shareUsageStats)
            SettingsToggle("Send crash reports", detail: "If Orbit crashes: where in Orbit's code it happened, and your Orbit and macOS versions.", isOn: $preferences.sendCrashReports)
            SettingsDisclosureRow(question: "See exactly what's in a usage report", isExpanded: $isShowingDetails) {
                Text(UsageReport(preferences: preferences, calendarCount: appState.calendars.count).readableJSON)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ShortcutsHelpView: View {

    private let shortcuts: [(keys: String, action: String)] = [
        ("⌘N", "New event"),
        ("⌘F", "Search events"),
        ("⌘M", "Show or hide the month"),
        ("⌘T", "Jump to today"),
        ("⌘,", "Settings"),
        ("Esc", "Close search or the new-event form"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("While the calendar is open")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(shortcuts, id: \.keys) { shortcut in
                    GridRow {
                        Text(shortcut.keys)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                        Text(shortcut.action)
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct CustomVideoServicesSection: View {

    @Environment(AppState.self) private var appState
    @State private var isAdding = false

    var body: some View {
        let preferences = appState.preferences
        SettingsSection("Custom video services", footer: "Links to these domains in an event's URL, location or notes get a Join button.") {
            ForEach(preferences.customVideoServices) { service in
                SettingsRow(title: service.name, detail: service.host) {
                    Button("Remove", systemImage: "minus.circle.fill", role: .destructive) {
                        preferences.customVideoServices.removeAll { $0.id == service.id }
                        appState.reload()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove \(service.name)")
                }
            }
            SettingsRow(
                title: preferences.customVideoServices.isEmpty ? "No custom services" : "Add another",
                detail: preferences.customVideoServices.isEmpty ? "Zoom, Meet, Teams, Webex and others are built in." : nil
            ) {
                Button("Add Service…") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            AddVideoServiceSheet { service in
                preferences.customVideoServices.append(service)
                appState.reload()
            }
        }
    }
}

private struct AddVideoServiceSheet: View {

    let onAdd: (CustomVideoService) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var link = ""

    private var host: String? { CustomVideoService.normalizedHost(from: link) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Optional"))
                    TextField("Link or domain", text: $link, prompt: Text("meet.example.com"))
                } header: {
                    Text("Add video service")
                } footer: {
                    if let host {
                        Text("Links to \(host) will get a Join button.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let host else { return }
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    onAdd(CustomVideoService(name: trimmed.isEmpty ? host : trimmed, host: host))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host == nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}
