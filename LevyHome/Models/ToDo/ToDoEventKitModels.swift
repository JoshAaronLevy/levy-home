import EventKit
import Foundation

struct FamilyCalendarLoadResult {
    let state: ToDoFamilyCalendarState
    let events: [ToDoCalendarEvent]
}

enum ToDoFamilyCalendarState: Equatable {
    case idle
    case requestingPermission
    case loading
    case synced
    case permissionNeeded
    case restricted
    case calendarNotFound
    case failed(String)

    func statusText(eventCount: Int) -> String {
        switch self {
        case .idle, .requestingPermission, .loading:
            return "Syncing"
        case .synced:
            return eventCount == 1 ? "1 event today" : "\(eventCount) events today"
        case .permissionNeeded:
            return "Permission Needed"
        case .restricted:
            return "Restricted"
        case .calendarNotFound:
            return "Missing"
        case .failed:
            return "Error"
        }
    }

    func statusSystemImage(eventCount: Int) -> String {
        switch self {
        case .idle, .requestingPermission, .loading:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "calendar"
        case .permissionNeeded, .restricted:
            return "lock.circle"
        case .calendarNotFound:
            return "calendar.badge.exclamationmark"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var statusTone: ToDoTone {
        switch self {
        case .idle, .requestingPermission, .loading:
            return .accent
        case .synced:
            return .success
        case .permissionNeeded, .restricted, .calendarNotFound:
            return .warning
        case .failed:
            return .critical
        }
    }
}

struct PersonalRemindersLoadResult {
    let state: ToDoPersonalRemindersState
    let reminders: [ToDoReminder]
}

enum ToDoPersonalRemindersState: Equatable {
    case idle
    case requestingPermission
    case loading
    case synced
    case permissionNeeded
    case restricted
    case failed(String)

    func statusText(reminderCount: Int) -> String {
        switch self {
        case .idle, .requestingPermission, .loading:
            return "Syncing"
        case .synced:
            return reminderCount == 1 ? "1 reminder" : "\(reminderCount) reminders"
        case .permissionNeeded:
            return "Permission Needed"
        case .restricted:
            return "Restricted"
        case .failed:
            return "Error"
        }
    }

    func statusSystemImage(reminderCount: Int) -> String {
        switch self {
        case .idle, .requestingPermission, .loading:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checklist"
        case .permissionNeeded, .restricted:
            return "lock.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var statusTone: ToDoTone {
        switch self {
        case .idle, .requestingPermission, .loading:
            return .accent
        case .synced:
            return .success
        case .permissionNeeded, .restricted:
            return .warning
        case .failed:
            return .critical
        }
    }
}

struct ToDoReminder: Identifiable {
    let id: String
    let calendarItemIdentifier: String
    let title: String
    let listTitle: String
    let dueDate: Date?
    let hasDueTime: Bool
    let notes: String?
    let url: URL?
    let priority: Int

    init(
        id: String,
        calendarItemIdentifier: String? = nil,
        title: String,
        listTitle: String = "Reminders",
        dueDate: Date?,
        hasDueTime: Bool,
        notes: String? = nil,
        url: URL? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.calendarItemIdentifier = calendarItemIdentifier ?? id
        self.title = Self.normalizedOptionalText(title) ?? "Untitled reminder"
        self.listTitle = Self.normalizedOptionalText(listTitle) ?? "Reminders"
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.notes = Self.normalizedOptionalText(notes)
        self.url = url
        self.priority = priority
    }

    init(reminder: EKReminder, calendar: Calendar = .current) {
        let identifier = reminder.calendarItemIdentifier
        let dueDateComponents = reminder.dueDateComponents

        id = identifier
        calendarItemIdentifier = identifier
        title = Self.normalizedOptionalText(reminder.title) ?? "Untitled reminder"
        listTitle = reminder.calendar?.title ?? "Reminders"
        dueDate = Self.date(from: dueDateComponents, fallbackCalendar: calendar)
        hasDueTime = Self.hasTime(in: dueDateComponents)
        notes = Self.normalizedOptionalText(reminder.notes)
        url = reminder.url
        priority = reminder.priority
    }

    var sortDate: Date {
        dueDate ?? .distantFuture
    }

    var dueBadgeTitle: String {
        guard let dueDate else {
            return "No"
        }

        if hasDueTime {
            return Self.timeFormatter.string(from: dueDate)
        }

        if Calendar.current.isDateInToday(dueDate) {
            return "Today"
        }

        if Calendar.current.isDateInTomorrow(dueDate) {
            return "Tmrw"
        }

        if dueDate < Calendar.current.startOfDay(for: Date()) {
            return Self.monthFormatter.string(from: dueDate)
        }

        return Self.monthFormatter.string(from: dueDate)
    }

    var dueBadgeSubtitle: String {
        guard let dueDate else {
            return "Date"
        }

        if hasDueTime {
            return Self.periodFormatter.string(from: dueDate)
        }

        if Calendar.current.isDateInToday(dueDate) || Calendar.current.isDateInTomorrow(dueDate) {
            return "Due"
        }

        return Self.dayFormatter.string(from: dueDate)
    }

    var dueDetailText: String {
        guard let dueDate else {
            return "No due date"
        }

        let dateText: String
        if Calendar.current.isDateInToday(dueDate) {
            dateText = "today"
        } else if Calendar.current.isDateInTomorrow(dueDate) {
            dateText = "tomorrow"
        } else {
            dateText = Self.detailDateFormatter.string(from: dueDate)
        }

        if hasDueTime {
            return "Due \(dateText) at \(Self.detailTimeFormatter.string(from: dueDate))"
        }

        return "Due \(dateText)"
    }

    var metadataText: String {
        "\(listTitle) - \(dueDetailText)"
    }

    var priorityText: String {
        switch priority {
        case 1...4:
            return "High"
        case 5:
            return "Medium"
        case 6...9:
            return "Low"
        default:
            return "No priority"
        }
    }

    var priorityBadgeText: String? {
        priorityText == "High" ? "High" : nil
    }

    var dueTone: ToDoTone {
        guard let dueDate else {
            return .neutral
        }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        if dueDate < startOfToday || Calendar.current.isDateInToday(dueDate) {
            return .warning
        }

        return .accent
    }

    private static func date(from components: DateComponents?, fallbackCalendar: Calendar) -> Date? {
        guard let components else {
            return nil
        }

        let calendar = components.calendar ?? fallbackCalendar
        return calendar.date(from: components)
    }

    private static func hasTime(in components: DateComponents?) -> Bool {
        guard let components else {
            return false
        }

        return components.hour != nil || components.minute != nil || components.second != nil
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let detailTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct ToDoCalendarEvent: Identifiable {
    let id: String
    let completionID: String
    let title: String
    let calendarTitle: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: URL?
    let isCompleted: Bool

    init(
        id: String,
        completionID: String,
        title: String,
        calendarTitle: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        url: URL?,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.completionID = completionID
        self.title = title
        self.calendarTitle = calendarTitle
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = Self.normalizedOptionalText(location)
        self.notes = Self.normalizedOptionalText(notes)
        self.url = url
        self.isCompleted = isCompleted
    }

    init(event: EKEvent) {
        let eventIdentifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let startTimestamp = Int(event.startDate.timeIntervalSince1970)
        let completionID = "\(eventIdentifier)-\(startTimestamp)"

        self.init(
            id: completionID,
            completionID: completionID,
            title: Self.normalizedOptionalText(event.title) ?? "Untitled event",
            calendarTitle: event.calendar?.title ?? "Family",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            url: event.url
        )
    }

    var time: String {
        guard !isAllDay else {
            return "All"
        }

        return Self.timeFormatter.string(from: startDate)
    }

    var period: String {
        guard !isAllDay else {
            return "Day"
        }

        return Self.periodFormatter.string(from: startDate)
    }

    var timeRangeText: String {
        if isAllDay {
            return "All day, \(Self.detailDateFormatter.string(from: startDate))"
        }

        return "\(Self.detailDateFormatter.string(from: startDate)), \(Self.detailTimeFormatter.string(from: startDate)) - \(Self.detailTimeFormatter.string(from: endDate))"
    }

    var locationDisplayText: String {
        location ?? "No location"
    }

    func withCompletion(_ isCompleted: Bool) -> ToDoCalendarEvent {
        ToDoCalendarEvent(
            id: id,
            completionID: completionID,
            title: title,
            calendarTitle: calendarTitle,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location,
            notes: notes,
            url: url,
            isCompleted: isCompleted
        )
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    private static let detailTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
