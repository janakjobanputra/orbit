import Foundation

struct YearProgress: Equatable, Sendable {

    let year: Int
    /// Share of the year's time already elapsed, from 0 to 1.
    let fraction: Double
    /// Whole days after today until the year ends.
    let daysLeft: Int

    init(date: Date, calendar: Calendar) {
        year = calendar.component(.year, from: date)
        guard let interval = calendar.dateInterval(of: .year, for: date),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
            fraction = 0
            daysLeft = 0
            return
        }
        fraction = min(max(date.timeIntervalSince(interval.start) / interval.duration, 0), 1)
        daysLeft = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: lastDay).day ?? 0
    }

    /// "83.1% of 2026"
    var elapsedText: String { "\(ProgressText.percent(fraction)) of \(String(year))" }

    /// "61 days left", "1 day left", or "Last day" on 31 December.
    var remainingText: String {
        switch daysLeft {
        case ...0: "Last day"
        case 1: "1 day left"
        default: "\(daysLeft) days left"
        }
    }
}

enum ProgressText {

    /// One decimal place, rounded down, so it never says 100% before the time is actually up.
    static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        return ((clamped * 1000).rounded(.down) / 1000).formatted(.percent.precision(.fractionLength(1)))
    }
}
