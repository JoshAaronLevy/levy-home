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
    private var loadedDateInterval: DateInterval?

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

    func loadReminders(in dateInterval: DateInterval, force: Bool = false) async {
        if !force, state == .synced, loadedDateInterval == dateInterval {
            return
        }

        guard !isLoadingReminders else {
            return
        }

        isLoadingReminders = true
        let previousState = state
        let previousReminders = reminders
        let previousDateInterval = loadedDateInterval
        state = EKEventStore.authorizationStatus(for: .reminder) == .notDetermined ? .requestingPermission : .loading

        defer {
            isLoadingReminders = false
        }

        do {
            let result = try await service.loadIncompleteReminders(in: dateInterval)
            state = result.state
            reminders = result.reminders
            loadedDateInterval = dateInterval
        } catch {
            guard !error.isTaskCancellation else {
                state = previousState
                reminders = previousReminders
                loadedDateInterval = previousDateInterval
                return
            }

            state = .failed(error.localizedDescription)
            reminders = []
        }
    }

    #if targetEnvironment(simulator)
    func loadSimulatorPreviewData(in dateInterval: DateInterval) {
        state = .synced
        reminders = ToDoPreviewData.simulatorReminders.filter {
            PersonalRemindersService.isDue($0.dueDate, in: dateInterval)
        }
        loadedDateInterval = dateInterval
    }

    func completeSimulatorReminder(_ reminder: ToDoReminder) {
        reminders.removeAll { $0.id == reminder.id }
        state = .synced
    }
    #endif

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
