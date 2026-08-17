import EventKit
import Foundation

@MainActor
final class PersonalRemindersService {
    static let shared = PersonalRemindersService()

    private let eventStore: EKEventStore
    private let calendar: Calendar

    init(eventStore: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    func loadIncompleteReminders(in dateInterval: DateInterval) async throws -> PersonalRemindersLoadResult {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            guard try await requestFullAccess() else {
                return PersonalRemindersLoadResult(state: .permissionNeeded, reminders: [])
            }

            return try await readIncompleteReminders(in: dateInterval)
        case .fullAccess:
            return try await readIncompleteReminders(in: dateInterval)
        case .denied:
            return PersonalRemindersLoadResult(state: .permissionNeeded, reminders: [])
        case .restricted:
            return PersonalRemindersLoadResult(state: .restricted, reminders: [])
        case .writeOnly:
            return PersonalRemindersLoadResult(state: .permissionNeeded, reminders: [])
        @unknown default:
            return PersonalRemindersLoadResult(state: .failed("Reminders access returned an unknown status."), reminders: [])
        }
    }

    func completeReminder(_ reminder: ToDoReminder) async throws {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder else {
            throw PersonalRemindersServiceError.reminderNotFound
        }

        ekReminder.isCompleted = true
        try eventStore.save(ekReminder, commit: true)
    }

    private func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func readIncompleteReminders(in dateInterval: DateInterval) async throws -> PersonalRemindersLoadResult {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: dateInterval.start,
            ending: dateInterval.end,
            calendars: nil
        )
        let reminders = await fetchReminders(matching: predicate)
            .filter { !$0.isCompleted }
            .map { ToDoReminder(reminder: $0, calendar: calendar) }
            .filter { Self.isDue($0.dueDate, in: dateInterval) }

        return PersonalRemindersLoadResult(state: .synced, reminders: reminders)
    }

    static func isDue(
        _ dueDate: Date?,
        in dateInterval: DateInterval
    ) -> Bool {
        guard let dueDate else {
            return false
        }

        return dueDate >= dateInterval.start && dueDate < dateInterval.end
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
}

private enum PersonalRemindersServiceError: LocalizedError {
    case reminderNotFound

    var errorDescription: String? {
        switch self {
        case .reminderNotFound:
            return "The reminder could not be found."
        }
    }
}
