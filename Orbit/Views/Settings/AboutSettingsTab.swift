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
