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

    func loadIncompleteReminders() async throws -> PersonalRemindersLoadResult {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            guard try await requestFullAccess() else {
                return PersonalRemindersLoadResult(state: .permissionNeeded, reminders: [])
            }

            return try await readIncompleteReminders()
        case .fullAccess:
            return try await readIncompleteReminders()
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

    private func readIncompleteReminders() async throws -> PersonalRemindersLoadResult {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        let reminders = await fetchReminders(matching: predicate)
            .filter { !$0.isCompleted }
            .map { ToDoReminder(reminder: $0, calendar: calendar) }

        return PersonalRemindersLoadResult(state: .synced, reminders: reminders)
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
