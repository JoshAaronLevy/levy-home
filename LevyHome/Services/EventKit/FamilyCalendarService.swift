import EventKit
import Foundation

@MainActor
final class FamilyCalendarService {
    static let shared = FamilyCalendarService()

    private let eventStore: EKEventStore
    private let calendar: Calendar
    private let familyCalendarName = "Family"

    init(eventStore: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    func loadTodaysFamilyEvents() async throws -> FamilyCalendarLoadResult {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            guard try await requestFullAccess() else {
                return FamilyCalendarLoadResult(state: .permissionNeeded, events: [])
            }

            return try readTodaysFamilyEvents()
        case .fullAccess:
            return try readTodaysFamilyEvents()
        case .denied:
            return FamilyCalendarLoadResult(state: .permissionNeeded, events: [])
        case .restricted:
            return FamilyCalendarLoadResult(state: .restricted, events: [])
        case .writeOnly:
            return FamilyCalendarLoadResult(state: .permissionNeeded, events: [])
        @unknown default:
            return FamilyCalendarLoadResult(state: .failed("Calendar access returned an unknown status."), events: [])
        }
    }

    private func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func readTodaysFamilyEvents() throws -> FamilyCalendarLoadResult {
        let familyCalendars = eventStore.calendars(for: .event).filter { calendar in
            calendar.title.trimmingCharacters(in: .whitespacesAndNewlines) == familyCalendarName
        }

        guard !familyCalendars.isEmpty else {
            return FamilyCalendarLoadResult(state: .calendarNotFound, events: [])
        }

        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return FamilyCalendarLoadResult(state: .failed("Unable to calculate today's Family Calendar window."), events: [])
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: familyCalendars
        )
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isDetached }
            .map(ToDoCalendarEvent.init(event:))

        return FamilyCalendarLoadResult(state: .synced, events: events)
    }
}
