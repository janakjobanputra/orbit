import SwiftUI

/// Answers to common questions, one expandable row each.
struct HelpSettingsTab: View {

    @State private var expanded: Set<String> = []

    var body: some View {
        Form {
            ForEach(HelpTopic.Group.allCases) { group in
                Section(group.rawValue) {
                    ForEach(HelpTopic.topics(in: group)) { topic in
                        DisclosureGroup(isExpanded: binding(for: topic)) {
                            Text(topic.answer)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        } label: {
                            // The whole row toggles, not just the chevron.
                            Button {
                                withAnimation { binding(for: topic).wrappedValue.toggle() }
                            } label: {
                                Text(topic.question)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section {
                LabeledContent("Still stuck?") {
                    Link("Ask on GitHub", destination: URL(string: "https://github.com/janakjobanputra/orbit/issues")!)
                        .foregroundStyle(Color.orbitTeal)
                }
            }
        }
        .formStyle(.grouped)
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
