import Combine
import EventKit
import Foundation

@MainActor
final class ToDoFamilyCalendarViewModel: ObservableObject {
    @Published private(set) var state: ToDoFamilyCalendarState = .idle
    @Published private(set) var events: [ToDoCalendarEvent] = []

    private let service: FamilyCalendarService
    private let userDefaults: UserDefaults
    private let completionStorageKey = "familyCalendarCompletedEventIDs"
    private var isLoadingToday = false
    private var completedEventIDs: Set<String>

    init(service: FamilyCalendarService? = nil, userDefaults: UserDefaults = .standard) {
        self.service = service ?? FamilyCalendarService.shared
        self.userDefaults = userDefaults
        completedEventIDs = Set(userDefaults.stringArray(forKey: completionStorageKey) ?? [])
    }

    var eventCount: Int {
        events.count
    }

    var displayEvents: [ToDoCalendarEvent] {
        events.sorted { first, second in
            if first.isCompleted != second.isCompleted {
                return !first.isCompleted && second.isCompleted
            }

            if first.startDate != second.startDate {
                return first.startDate < second.startDate
            }

            return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
        }
    }

    func loadToday(force: Bool = false) async {
        if !force, state == .synced {
            return
        }

        guard !isLoadingToday else {
            return
        }

        isLoadingToday = true
        let previousState = state
        let previousEvents = events
        state = EKEventStore.authorizationStatus(for: .event) == .notDetermined ? .requestingPermission : .loading

        defer {
            isLoadingToday = false
        }

        do {
            let result = try await service.loadTodaysFamilyEvents()
            state = result.state
            events = result.events.map { event in
                event.withCompletion(completedEventIDs.contains(event.completionID))
            }
        } catch {
            guard !error.isTaskCancellation else {
                state = previousState
                events = previousEvents
                return
            }

            state = .failed(error.localizedDescription)
            events = []
        }
    }

    func toggleCompletion(for event: ToDoCalendarEvent) {
        if completedEventIDs.contains(event.completionID) {
            completedEventIDs.remove(event.completionID)
        } else {
            completedEventIDs.insert(event.completionID)
        }

        persistCompletionIDs()
        events = events.map { existingEvent in
            guard existingEvent.completionID == event.completionID else {
                return existingEvent
            }

            return existingEvent.withCompletion(completedEventIDs.contains(event.completionID))
        }
    }

    private func persistCompletionIDs() {
        userDefaults.set(Array(completedEventIDs).sorted(), forKey: completionStorageKey)
    }
}
