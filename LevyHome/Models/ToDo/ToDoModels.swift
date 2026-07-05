import Foundation
import SwiftUI

enum ToDoDateDefaults {
    static let today = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    static let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
    static let thisWeek = Calendar.current.date(byAdding: .day, value: 4, to: today)
    static let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: today)
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
    let createdDate: Date
    let status: ToDoStatus
    let locationDisplayText: String
    let isLinkedToFamilyCalendar: Bool
    let previewNote: String?

    var isCompleted: Bool {
        status == .completed
    }

    var dateDisplayText: String {
        if let date {
            if Calendar.current.isDateInToday(date) {
                return "Today"
            }

            if Calendar.current.isDateInTomorrow(date) {
                return "Tomorrow"
            }

            return Self.shortDateFormatter.string(from: date)
        }

        return recurring?.displayTitle ?? "No date"
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

    private static let shortDateFormatter: DateFormatter = {
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

struct ToDoDraft {
    var name = ""
    var locationIds: [Int]?
    var date: Date? = ToDoDateDefaults.today
    var recurring: ToDoRecurring?
    var createdBy: Int
    var createdDate = Date()
    var status: ToDoStatus = .open
    var dueDateID = "today"
    var location = ""
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
        createdDate = task.createdDate
        status = task.status
        dueDateID = Self.dueDateID(for: task.date)
        location = task.locationDisplayText == "No location" ? "" : task.locationDisplayText
        saveLocation = false
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLocation: String {
        location.trimmingCharacters(in: .whitespacesAndNewlines)
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
