import Foundation
import SwiftUI

enum ToDoDateDefaults {
    static let today = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    static let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
    static let thisWeek = Calendar.current.date(byAdding: .day, value: 4, to: today)
    static let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: today)
}

enum ToDoDateScope: String, CaseIterable, Identifiable {
    case today
    case tomorrow
    case week

    var id: String {
        rawValue
    }

    func title(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .today:
            return Self.tabDateFormatter.string(from: now)
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
                return Self.tabDateFormatter.string(from: now)
            }

            return Self.tabDateFormatter.string(from: tomorrow)
        case .week:
            return "Week"
        }
    }

    var summaryPeriodText: String {
        switch self {
        case .today:
            return "Today"
        case .tomorrow:
            return "Tomorrow"
        case .week:
            return "this Week"
        }
    }

    func dateInterval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)

        switch self {
        case .today:
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            return DateInterval(start: startOfToday, end: endOfToday)
        case .tomorrow:
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            let endOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfTomorrow) ?? startOfTomorrow
            return DateInterval(start: startOfTomorrow, end: endOfTomorrow)
        case .week:
            var sundayFirstCalendar = calendar
            sundayFirstCalendar.firstWeekday = 1
            let startOfWeek = sundayFirstCalendar.dateInterval(of: .weekOfYear, for: startOfToday)?.start ?? startOfToday
            let endOfWeek = sundayFirstCalendar.date(byAdding: .day, value: 7, to: startOfWeek) ?? startOfToday
            return DateInterval(start: startOfToday, end: endOfWeek)
        }
    }

    func includesToDoItem(
        dueDate: Date?,
        status: ToDoStatus,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let dueDate else {
            return false
        }

        let interval = dateInterval(now: now, calendar: calendar)
        return (dueDate >= interval.start && dueDate < interval.end) ||
            (status == .open && dueDate < interval.start)
    }

    private static let tabDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM. d"
        return formatter
    }()
}

struct ToDoLocationSearchSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String

    var displayText: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}

struct ToDoTaskSection: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tone: ToDoTone
    let tasks: [ToDoTask]
}

struct ToDoTask: Identifiable {
    let id: Int
    let name: String
    let locationIds: [Int]?
    let date: Date?
    let recurring: ToDoRecurring?
    let createdBy: Int?
    let createdFor: [Int]
    let createdDate: Date
    let status: ToDoStatus
    let locationDisplayText: String
    let isLinkedToFamilyCalendar: Bool
    let notes: String?
    let subtasks: [JSONValue]

    var isCompleted: Bool {
        status == .completed
    }

    var isFamilyItem: Bool {
        Set(createdFor) == Set([1, 2])
    }

    var dueListDisplayText: String {
        "Due: \(Self.dueListDateText(for: date))"
    }

    var dateTone: ToDoTone {
        if status == .completed {
            return .success
        }

        guard let date else {
            return recurring == nil ? .neutral : .accent
        }

        if Calendar.current.isDateInToday(date) || date < Date() {
            return .warning
        }

        return .accent
    }

    private static func dueListDateText(for date: Date?) -> String {
        guard let date else {
            return "N/A"
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: date)

        if dueDay < startOfToday {
            return "\(shortWeekdayText(for: dueDay)), \(monthDayFormatter.string(from: dueDay))"
        }

        if calendar.isDate(dueDay, inSameDayAs: startOfToday) {
            return "Today"
        }

        if calendar.isDateInTomorrow(dueDay) {
            return "Tomorrow"
        }

        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: startOfToday)?.start ?? startOfToday
        let startOfWeekAfterNext = calendar.date(byAdding: .weekOfYear, value: 2, to: startOfWeek)
            ?? calendar.date(byAdding: .day, value: 14, to: startOfWeek)
            ?? startOfToday

        if dueDay < startOfWeekAfterNext {
            return "Next \(fullWeekdayFormatter.string(from: dueDay))"
        }

        return "\(shortWeekdayText(for: dueDay)), \(monthDayFormatter.string(from: dueDay))"
    }

    private static func shortWeekdayText(for date: Date) -> String {
        switch fullWeekdayFormatter.string(from: date) {
        case "Sunday":
            return "Sun"
        case "Monday":
            return "Mon"
        case "Tuesday":
            return "Tues"
        case "Wednesday":
            return "Wed"
        case "Thursday":
            return "Thurs"
        case "Friday":
            return "Fri"
        case "Saturday":
            return "Sat"
        default:
            return shortWeekdayFormatter.string(from: date)
        }
    }

    private static let fullWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

enum ToDoEditorMode: Identifiable {
    case add
    case edit(ToDoTask)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let task):
            return "edit-\(task.id)"
        }
    }

    func initialDraft(currentUserId: Int) -> ToDoDraft {
        switch self {
        case .add:
            return ToDoDraft(createdBy: currentUserId)
        case .edit(let task):
            return ToDoDraft(task: task, fallbackCreatedBy: currentUserId)
        }
    }
}

enum ToDoAudience: String, CaseIterable, Identifiable {
    case family
    case me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .family:
            return "Family"
        case .me:
            return "Me"
        }
    }

    var systemImage: String {
        switch self {
        case .family:
            return "person.2.fill"
        case .me:
            return "person.fill"
        }
    }

    func createdFor(creatorId: Int) -> [Int] {
        switch self {
        case .family:
            return [1, 2]
        case .me:
            return [creatorId]
        }
    }

    init(createdFor: [Int]) {
        self = Set(createdFor) == Set([1, 2]) ? .family : .me
    }
}

struct ToDoDraft {
    var name = ""
    var locationIds: [Int]?
    var date: Date? = ToDoDateDefaults.today
    var recurring: ToDoRecurring?
    var createdBy: Int
    var audience: ToDoAudience = .family
    var createdDate = Date()
    var status: ToDoStatus = .open
    var dueDateID = "today"
    var location = ""
    var notes = ""
    var saveLocation = true

    init(createdBy: Int = 1) {
        self.createdBy = createdBy
    }

    init(task: ToDoTask, fallbackCreatedBy: Int) {
        name = task.name
        locationIds = task.locationIds
        date = task.date
        recurring = task.recurring
        createdBy = task.createdBy ?? fallbackCreatedBy
        audience = ToDoAudience(createdFor: task.createdFor)
        createdDate = task.createdDate
        status = task.status
        dueDateID = Self.dueDateID(for: task.date)
        location = task.locationDisplayText == "No location" ? "" : task.locationDisplayText
        notes = task.notes ?? ""
        saveLocation = false
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLocation: String {
        location.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var createdFor: [Int] {
        audience.createdFor(creatorId: createdBy)
    }

    var isValid: Bool {
        !trimmedName.isEmpty
    }

    private static func dueDateID(for date: Date?) -> String {
        guard let date else {
            return "none"
        }

        if Calendar.current.isDateInToday(date) {
            return "today"
        }

        if Calendar.current.isDateInTomorrow(date) {
            return "tomorrow"
        }

        if let thisWeek = ToDoDateDefaults.thisWeek, Calendar.current.isDate(date, inSameDayAs: thisWeek) {
            return "this-week"
        }

        return "custom"
    }
}

struct ToDoDueDateOption: Identifiable {
    let id: String
    let title: String
    let tone: ToDoTone
    let date: Date?
}

enum ToDoStatus: String, CaseIterable, Identifiable {
    case open
    case completed
    case canceled

    var id: String { rawValue }
}

enum ToDoRecurring: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case quarterly

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .quarterly:
            return "Quarterly"
        }
    }
}

enum ToDoTone {
    case accent
    case success
    case warning
    case critical
    case neutral

    var foregroundColor: Color {
        switch self {
        case .accent:
            return AppColors.accent
        case .success:
            return AppColors.success
        case .warning:
            return AppColors.warning
        case .critical:
            return AppColors.critical
        case .neutral:
            return AppColors.mutedText
        }
    }

    var backgroundColor: Color {
        switch self {
        case .accent:
            return AppColors.accentSoft
        case .success:
            return AppColors.successSoft
        case .warning:
            return AppColors.warningSoft
        case .critical:
            return AppColors.criticalSoft
        case .neutral:
            return Color(uiColor: .tertiarySystemFill)
        }
    }
}

extension ToDoLocation {
    var displayTitle: String {
        mapkitTitle ?? name
    }

    var previewSystemImage: String {
        let normalizedName = name.lowercased()

        if normalizedName.contains("home") {
            return "house"
        }

        if normalizedName.contains("pediatric") || normalizedName.contains("doctor") {
            return "cross.case"
        }

        if normalizedName.contains("vet") {
            return "pawprint"
        }

        if normalizedName.contains("county") || normalizedName.contains("office") {
            return "building.columns"
        }

        return "mappin.and.ellipse"
    }
}
