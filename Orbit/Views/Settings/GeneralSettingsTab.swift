import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsTab: View {

    @Environment(AppState.self) private var appState
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var isShowingShortcuts = false

    var body: some View {
        @Bindable var preferences = appState.preferences

        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle(isOn: $preferences.keepCalendarOnTop) {
                    Text("Keep calendar on top")
                    Text("The calendar stays open until you click the menu bar item again.")
                }
            }

            Section("Theme") {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Shortcuts") {
                Toggle("Enable global shortcuts", isOn: $preferences.globalShortcutsEnabled)
                Group {
                    KeyboardShortcuts.Recorder("Toggle calendar", name: .toggleCalendar)
                    KeyboardShortcuts.Recorder("Join next meeting", name: .joinNextMeeting)
                }
                .disabled(!preferences.globalShortcutsEnabled)
                LabeledContent("Calendar shortcuts") {
                    Button("Show…") { isShowingShortcuts = true }
                        .popover(isPresented: $isShowingShortcuts, arrowEdge: .trailing) {
                            ShortcutsHelpView()
                        }
                }
            }

            CustomVideoServicesSection()
        }
        .formStyle(.grouped)
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
        Section {
            ForEach(preferences.customVideoServices) { service in
                LabeledContent {
                    Button("Remove", systemImage: "minus.circle.fill", role: .destructive) {
                        preferences.customVideoServices.removeAll { $0.id == service.id }
                        appState.reload()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove \(service.name)")
                } label: {
                    Text(service.name)
                    Text(service.host)
                }
            }
            LabeledContent {
                Button("Add Service…") { isAdding = true }
            } label: {
                if preferences.customVideoServices.isEmpty {
                    Text("No custom services")
                    Text("Zoom, Meet, Teams, Webex and others are built in.")
                }
            }
        } header: {
            Text("Custom video services")
        } footer: {
            Text("Links to these domains in an event's URL, location or notes get a Join button.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
