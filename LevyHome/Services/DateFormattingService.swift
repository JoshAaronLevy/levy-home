import Foundation

struct DateFormattingService {
    private let isoFormatterWithFractionalSeconds: ISO8601DateFormatter
    private let isoFormatter: ISO8601DateFormatter
    private let relativeFormatter: RelativeDateTimeFormatter
    private let fallbackFormatter: DateFormatter
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        isoFormatterWithFractionalSeconds = ISO8601DateFormatter()
        isoFormatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .full

        fallbackFormatter = DateFormatter()
        fallbackFormatter.dateStyle = .medium
        fallbackFormatter.timeStyle = .short

        self.now = now
    }

    func displayString(for rawDate: String) -> String {
        guard let date = date(from: rawDate) else {
            return rawDate
        }

        let referenceDate = now()
        let interval = abs(date.timeIntervalSince(referenceDate))
        if interval < 60 * 60 * 24 {
            return relativeFormatter.localizedString(for: date, relativeTo: referenceDate)
        }

        return fallbackFormatter.string(from: date)
    }

    private func date(from rawDate: String) -> Date? {
        isoFormatterWithFractionalSeconds.date(from: rawDate) ?? isoFormatter.date(from: rawDate)
    }
}
