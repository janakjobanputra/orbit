import SwiftUI

struct AboutSettingsTab: View {

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Orbit")
                .font(.largeTitle.weight(.semibold))
            Text("A personal calendar for your menu bar")
                .foregroundStyle(.secondary)
            Text(version)
                .font(.callout.monospaced())
                .foregroundStyle(.tertiary)
            UpdateStatusView()
                .padding(.top, 4)
            Text("Free and open source under the GPL-3.0.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Link("Source code on GitHub", destination: URL(string: "https://github.com/janakjobanputra/orbit")!)
                .font(.callout)
                .foregroundStyle(Color.orbitTeal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct UpdateStatusView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        let updates = appState.updates
        VStack(spacing: 8) {
            if let release = updates.availableRelease {
                Text("Orbit \(release.version.description) is available")
                    .font(.callout.weight(.semibold))
                HStack(spacing: 12) {
                    Button("Download") { NSWorkspace.shared.open(release.bestURL) }
                        .buttonStyle(.borderedProminent)
                    Link("Release notes", destination: release.pageURL)
                        .foregroundStyle(Color.orbitTeal)
                }
            } else {
                Button(updates.status == .checking ? "Checking…" : "Check for Updates") {
                    Task { await updates.checkNow() }
                }
                .disabled(updates.status == .checking)
                Text(message(updates))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func message(_ updates: UpdateChecker) -> String {
        switch updates.status {
        case .upToDate: return "You're up to date."
        case .failed: return "Couldn't reach GitHub. Try again later."
        case .checking, .available: return " "
        case .idle:
            guard let lastChecked = updates.lastChecked else { return " " }
            return "Last checked \(lastChecked.formatted(.relative(presentation: .named)))."
        }
    }
}
