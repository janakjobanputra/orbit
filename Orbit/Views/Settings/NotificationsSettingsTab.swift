import SwiftUI

struct NotificationsSettingsTab: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var preferences = appState.preferences

        SettingsPage {
            SettingsSection("Meeting alerts", footer: "Join opens Zoom and Teams calls in their apps when they're installed, Google Meet in its app if you've installed it from Chrome, and other calls in your browser.") {
                SettingsToggle("Alert me before meetings", detail: "A small window at the top right of your screen with a Join button, on top of whatever you're doing.", isOn: $preferences.meetingAlerts)
                if preferences.meetingAlerts {
                    SettingsMenuPicker(title: "When", selection: $preferences.meetingAlertLeadMinutes) {
                        ForEach(MeetingAlertSchedule.leadOptions, id: \.self) { minutes in
                            Text(Self.leadLabel(minutes)).tag(minutes)
                        }
                    }
                    SettingsSegmentedPicker(title: "Alert for", selection: $preferences.meetingAlertScope) {
                        ForEach(MeetingAlertScope.allCases) { Text($0.label).tag($0) }
                    }
                    SettingsToggle("Play a sound", isOn: $preferences.meetingAlertSound)
                    SettingsToggle(
                        "Open Granola when joining",
                        detail: Granola.isInstalled
                            ? "Join opens Granola alongside the call, for notes. The ⌄ next to Join joins without it."
                            : "Works once Granola is installed.",
                        isOn: $preferences.meetingAlertShowsGranola
                    )
                    SettingsRow(title: "Show a sample alert") {
                        Button("Show") { appState.showSampleMeetingAlert() }
                    }
                }
            }
        }
    }

    static func leadLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "When it starts"
        case 1: "1 minute before"
        default: "\(minutes) minutes before"
        }
    }
}
