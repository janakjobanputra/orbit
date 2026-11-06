import SwiftUI

/// Answers to common questions, one expandable row each.
struct HelpSettingsTab: View {

    @Environment(AppState.self) private var appState
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?
    @State private var expanded: Set<String> = []

    var body: some View {
        SettingsPage {
            ForEach(HelpTopic.Group.allCases) { group in
                SettingsSection(group.rawValue) {
                    ForEach(HelpTopic.topics(in: group)) { topic in
                        SettingsDisclosureRow(question: topic.question, isExpanded: binding(for: topic)) {
                            Text(topic.answer).textSelection(.enabled)
                        }
                    }
                }
            }

            SettingsSection {
                SettingsRow(title: "New to Orbit?") {
                    Button("Take the Tour") { appState.showWelcomeTour() }
                }
                SettingsRow(title: "Still stuck?") {
                    Link("Ask on GitHub", destination: URL(string: "https://github.com/janakjobanputra/orbit/issues")!)
                        .foregroundStyle(Color.orbitTeal)
                }
            }
        }
        // A search result for a question opens its answer.
        .task(id: navigation?.requestedHelpQuestion) {
            guard let question = navigation?.requestedHelpQuestion else { return }
            expanded.insert(question)
            navigation?.requestedHelpQuestion = nil
        }
    }

    private func binding(for topic: HelpTopic) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(topic.id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(topic.id) } else { expanded.remove(topic.id) }
            }
        )
    }
}
