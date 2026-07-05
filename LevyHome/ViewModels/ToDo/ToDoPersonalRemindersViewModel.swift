import Combine
import EventKit
import Foundation

@MainActor
final class ToDoPersonalRemindersViewModel: ObservableObject {
    @Published private(set) var state: ToDoPersonalRemindersState = .idle
    @Published private(set) var reminders: [ToDoReminder] = []

    private let service: PersonalRemindersService
    private var isLoadingReminders = false
    private var completingReminderIDs = Set<String>()

    init(service: PersonalRemindersService? = nil) {
        self.service = service ?? PersonalRemindersService.shared
    }

    var reminderCount: Int {
        reminders.count
    }

    var displayReminders: [ToDoReminder] {
        reminders.sorted { first, second in
            if first.sortDate != second.sortDate {
                return first.sortDate < second.sortDate
            }

            if first.listTitle.localizedCaseInsensitiveCompare(second.listTitle) != .orderedSame {
                return first.listTitle.localizedCaseInsensitiveCompare(second.listTitle) == .orderedAscending
            }

            return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
        }
    }

    func loadReminders(force: Bool = false) async {
        if !force, state == .synced {
            return
        }

        guard !isLoadingReminders else {
            return
        }

        isLoadingReminders = true
        let previousState = state
        let previousReminders = reminders
        state = EKEventStore.authorizationStatus(for: .reminder) == .notDetermined ? .requestingPermission : .loading

        defer {
            isLoadingReminders = false
        }

        do {
            let result = try await service.loadIncompleteReminders()
            state = result.state
            reminders = result.reminders
        } catch {
            guard !error.isTaskCancellation else {
                state = previousState
                reminders = previousReminders
                return
            }

            state = .failed(error.localizedDescription)
            reminders = []
        }
    }

    func complete(_ reminder: ToDoReminder) async {
        guard !completingReminderIDs.contains(reminder.id) else {
            return
        }

        completingReminderIDs.insert(reminder.id)

        defer {
            completingReminderIDs.remove(reminder.id)
        }

        do {
            try await service.completeReminder(reminder)
            reminders.removeAll { $0.id == reminder.id }
            state = .synced
        } catch {
            guard !error.isTaskCancellation else {
                return
            }

            state = .failed(error.localizedDescription)
        }
    }
}
