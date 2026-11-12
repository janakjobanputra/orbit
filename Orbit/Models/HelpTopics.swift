import Foundation

/// The questions answered in Settings › Help, grouped as they appear there.
struct HelpTopic: Identifiable, Hashable {

    enum Group: String, CaseIterable, Identifiable {
        case menuBar = "Menu bar"
        case calendar = "Calendar and events"
        case meetings = "Meetings"
        case appAndPrivacy = "Orbit itself"

        var id: Self { self }
    }

    let group: Group
    let question: String
    let answer: String

    var id: String { question }

    static func topics(in group: Group) -> [HelpTopic] {
        all.filter { $0.group == group }
    }

    static let all: [HelpTopic] = [
        // Menu bar
        HelpTopic(
            group: .menuBar,
            question: "My menu bar already shows the date and time. Can I hide them?",
            answer: "macOS can't remove its clock entirely, but you can make it tiny. Open System Settings › Menu Bar (on macOS 15, System Settings › Control Center), click Clock Options, then set Show date to Never, or choose the Analog style for a small clock icon with no date or day. Orbit can show the date and time in any format you like under Display › Menu bar."
        ),
        HelpTopic(
            group: .menuBar,
            question: "How do I move Orbit around in the menu bar?",
            answer: "Hold ⌘ and drag Orbit, or any other menu bar icon, left or right, then let go. Drag it next to the clock if you want it where the date used to be. Control Center always stays at the far right."
        ),
        HelpTopic(
            group: .menuBar,
            question: "I can't see Orbit in my menu bar.",
            answer: "On a MacBook with a notch, items that don't fit are hidden behind it. ⌘-drag a few other icons off the menu bar, or choose the Icon style under Display › Menu bar so Orbit takes up the least room. On macOS 26, also check System Settings › Menu Bar › Allow in the Menu Bar, and make sure Orbit is turned on there."
        ),
        HelpTopic(
            group: .menuBar,
            question: "What can Orbit show in the menu bar?",
            answer: "Choose a style under Display › Menu bar: the date and time, just the time, your next meeting, all three, or Icon for only Orbit's logo. Custom lets you choose and order the items yourself, including the week number. Add :ss to the time format to show seconds."
        ),

        // Calendar and events
        HelpTopic(
            group: .calendar,
            question: "Why don't I see my events?",
            answer: "Orbit shows the calendars your Mac syncs in Apple Calendar. Add Google, Exchange or other accounts in System Settings › Internet Accounts, then turn their calendars on under Calendars. If none appear at all, allow Orbit in System Settings › Privacy & Security › Calendars. Orbit notices new accounts and access by itself, so there's no need to restart it: open the calendar and they're there."
        ),
        HelpTopic(
            group: .meetings,
            question: "How do meeting alerts work?",
            answer: "A minute before each video meeting, a small window appears at the top right of your screen with Join. If you use Granola, Join opens it alongside the call for notes; the ⌄ next to Join joins without it. Join opens Zoom and Teams calls straight in their apps when they're installed, Google Meet in its app if you've installed it from Chrome, and everything else in your browser. Change when alerts appear, or turn them on for every event, in Settings › Notifications, where you can also preview one."
        ),
        HelpTopic(
            group: .calendar,
            question: "Can the calendar show just a few weeks instead of the month?",
            answer: "Yes. Set Display › Calendar display › Calendar shows to 3 weeks. You get last week, this week and next week, with this week always in the middle when you open Orbit. The arrows move a week at a time, and the dot button brings you back to this week."
        ),
        HelpTopic(
            group: .calendar,
            question: "How do I switch between the Day view and the agenda?",
            answer: "Use Display › Layout › Events view. Day shows the selected date hour by hour; Agenda lists the days ahead. Click any date in the month to see that day. Display › Layout › Events (Compact, Cozy or Airy) spaces out both: in the Day view it sets how tall each hour is."
        ),
        HelpTopic(
            group: .calendar,
            question: "How do I add, edit or delete an event?",
            answer: "Click + in the calendar, or press ⌘N, to add one. Click an event for its details, where you can delete it or choose Open in Calendar to edit it there. Events on read-only calendars, such as holidays, can't be deleted."
        ),
        HelpTopic(
            group: .calendar,
            question: "Why do some events look outlined, dashed or crossed out?",
            answer: "They're invitations you haven't accepted. An outline means you haven't answered yet, a lighter block with a dashed edge means you said maybe, and crossed out means you declined. Declined events are hidden unless you turn on Display › Layout › Show declined events. Reply from Apple Calendar: click the event, then Open in Calendar."
        ),
        HelpTopic(
            group: .calendar,
            question: "Which calendar do new events go to?",
            answer: "The one chosen under Calendars › Default calendar. Leave it on System default to use the same one as Apple Calendar."
        ),
        HelpTopic(
            group: .calendar,
            question: "Can I hide some calendars or events?",
            answer: "Turn calendars off under Calendars › Show calendars. To hide individual events, add words from their titles to Calendars › Event filters. Display › Layout can also hide all-day or past events."
        ),
        HelpTopic(
            group: .calendar,
            question: "What keyboard shortcuts are there?",
            answer: "Anywhere: ⇧⌘C opens the calendar and ⇧⌘J joins your next meeting (change them under General › Shortcuts). With the calendar open: ⌘N new event, ⌘F search, ⌘M show or hide the month, ⌘T today, ⌘, Settings, and Esc to step back out."
        ),

        // Meetings
        HelpTopic(
            group: .meetings,
            question: "How do I join a meeting?",
            answer: "The meeting you're in, or one starting within 10 minutes, shows a Join button in the calendar. You can also click any event and choose Join, or press ⇧⌘J from anywhere."
        ),
        HelpTopic(
            group: .meetings,
            question: "Why doesn't a meeting have a Join button?",
            answer: "Orbit looks for Zoom, Google Meet, Teams, Webex and other video links in the event's URL, location and notes. If your service isn't recognised, add its domain under General › Custom video services."
        ),

        // Orbit itself
        HelpTopic(
            group: .appAndPrivacy,
            question: "How do I back up my settings or move them to another Mac?",
            answer: "Open Backup in Settings and choose Export to save a JSON file, then Import on the other Mac. Hidden calendars are matched by account and name, so they carry over even though their IDs differ between Macs. The file contains your settings and calendar names, but no events."
        ),
        HelpTopic(
            group: .appAndPrivacy,
            question: "Does Orbit send my calendar anywhere?",
            answer: "No. Orbit reads your events on your Mac, and your events and calendar names are never sent anywhere. There's no account. Three things do use the network, and you can turn each off under Settings › General: a once-a-day check on GitHub for a new version, a crash report if Orbit crashes (on by default), and anonymous usage stats (off unless you turn them on)."
        ),
        HelpTopic(
            group: .appAndPrivacy,
            question: "What's in crash reports and usage stats?",
            answer: "A crash report says where in Orbit's code the crash happened, the type of crash, and your Orbit and macOS versions. Usage stats, if you turn them on, say once a day which Orbit and macOS versions you have, your Mac's chip type, and which main options you use, such as Day or Agenda and your menu bar style, plus a rough count of calendars. Neither includes your events, calendar names, an ID or anything that identifies you, and your IP address isn't stored. Settings › General › Privacy shows exactly what a usage report contains."
        ),
        HelpTopic(
            group: .appAndPrivacy,
            question: "How do I update Orbit?",
            answer: "When a new version is out, Orbit shows a window with its release notes. Install Update downloads it, checks it, and offers Install and Relaunch, so there is no disk image to open. Remind Me Later asks again tomorrow, and Skip This Version waits for the one after. An Update row also appears at the bottom of the calendar. Check any time under About › Check for Updates."
        ),
        HelpTopic(
            group: .appAndPrivacy,
            question: "How do I start Orbit at login, or quit it?",
            answer: "Turn on General › Startup › Launch at login. To quit, right-click Orbit in the menu bar and choose Quit Orbit."
        ),
    ]
}
