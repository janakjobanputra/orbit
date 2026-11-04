import AppKit
import SwiftUI

/// "A new version of Orbit is available!": the release notes and what to do about it.
struct UpdateDialogView: View {

    let release: ReleaseInfo
    let currentVersion: AppVersion
    @Bindable var preferences: Preferences
    let skip: () -> Void
    let remindLater: () -> Void
    let download: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 10) {
                Text("A new version of Orbit is available!")
                    .font(.headline)
                Text("Orbit \(release.version.description) is now available—you have \(currentVersion.description). Would you like to download it now?")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Release Notes:")
                    .font(.callout.weight(.semibold))
                    .padding(.top, 2)
                notes
                Toggle("Check for updates automatically", isOn: $preferences.checkForUpdates)
                    .toggleStyle(.checkbox)
                HStack {
                    Button("Skip This Version", action: skip)
                    Spacer()
                    Button("Remind Me Later", action: remindLater)
                        .keyboardShortcut(.cancelAction)
                    Button("Download Update", action: download)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(width: 560)
        .tint(.orbitTeal)
    }

    private var notes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                let lines = ReleaseNotes.lines(from: release.notes)
                if lines.isEmpty {
                    Text("This release has no notes.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    switch line {
                    case .heading(let text):
                        Text(text).font(.callout.weight(.semibold))
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(text).fixedSize(horizontal: false, vertical: true)
                        }
                    case .paragraph(let text):
                        Text(text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(height: 180)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay { Rectangle().strokeBorder(Color(nsColor: .separatorColor)) }
    }
}

/// Puts the update dialog in its own window, brought to the front even though Orbit lives in the menu bar.
@MainActor
final class UpdateDialogController {

    private var window: NSWindow?
    private let updates: UpdateChecker
    private let preferences: Preferences

    init(updates: UpdateChecker, preferences: Preferences) {
        self.updates = updates
        self.preferences = preferences
    }

    func show(_ release: ReleaseInfo) {
        window?.close()
        let view = UpdateDialogView(
            release: release,
            currentVersion: updates.currentVersion,
            preferences: preferences,
            skip: { [weak self] in
                self?.updates.skip(release)
                self?.close()
            },
            remindLater: { [weak self] in
                self?.updates.remindLater()
                self?.close()
            },
            download: { [weak self] in
                NSWorkspace.shared.open(release.bestURL)
                self?.close()
            }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Software Update"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func close() {
        window?.close()
        window = nil
    }
}
