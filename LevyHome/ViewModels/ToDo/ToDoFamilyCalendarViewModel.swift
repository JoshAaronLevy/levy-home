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
    private var isLoadingEvents = false
    private var loadedDateInterval: DateInterval?
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

    func load(in dateInterval: DateInterval, force: Bool = false) async {
        if !force, state == .synced, loadedDateInterval == dateInterval {
            return
        }

        guard !isLoadingEvents else {
            return
        }

        isLoadingEvents = true
        let previousState = state
        let previousEvents = events
        let previousDateInterval = loadedDateInterval
        state = EKEventStore.authorizationStatus(for: .event) == .notDetermined ? .requestingPermission : .loading

        defer {
            isLoadingEvents = false
        }

        do {
            let result = try await service.loadFamilyEvents(in: dateInterval)
            state = result.state
            events = result.events.map { event in
                event.withCompletion(completedEventIDs.contains(event.completionID))
            }
            loadedDateInterval = dateInterval
        } catch {
            guard !error.isTaskCancellation else {
                state = previousState
                events = previousEvents
                loadedDateInterval = previousDateInterval
                return
            }

            state = .failed(error.localizedDescription)
            events = []
        }
    }

    #if targetEnvironment(simulator)
    func loadSimulatorPreviewData(in dateInterval: DateInterval) {
        state = .synced
        events = ToDoPreviewData.simulatorCalendarEvents
            .filter { $0.startDate < dateInterval.end && $0.endDate > dateInterval.start }
            .map { event in
                event.withCompletion(completedEventIDs.contains(event.completionID))
            }
        loadedDateInterval = dateInterval
    }
    #endif

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
