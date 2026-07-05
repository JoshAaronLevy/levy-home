import Foundation

struct OpenMeteoDateParser {
    private let dateTimeFormatter: DateFormatter
    private let dateFormatter: DateFormatter

    init(timeZone: TimeZone) {
        dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateTimeFormatter.timeZone = timeZone
        dateTimeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
    }

    func dateTime(from value: String) -> Date? {
        dateTimeFormatter.date(from: value)
    }

    func date(from value: String) -> Date? {
        dateFormatter.date(from: value)
    }
}
