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

    func loadFamilyEvents(in dateInterval: DateInterval) async throws -> FamilyCalendarLoadResult {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            guard try await requestFullAccess() else {
                return FamilyCalendarLoadResult(state: .permissionNeeded, events: [])
            }

            return try readFamilyEvents(in: dateInterval)
        case .fullAccess:
            return try readFamilyEvents(in: dateInterval)
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

    /// Reads a local calendar day without prompting for permission, so background
    /// notification scheduling never unexpectedly presents the Calendar dialog.
    func familyEventCount(on date: Date) -> Int? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return nil
        }

        let familyCalendars = eventStore.calendars(for: .event).filter { calendar in
            calendar.title.trimmingCharacters(in: .whitespacesAndNewlines) == familyCalendarName
        }

        let startOfDay = calendar.startOfDay(for: date)
        guard
            !familyCalendars.isEmpty,
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
        else {
            return nil
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: familyCalendars
        )

        return eventStore.events(matching: predicate)
            .filter { !$0.isDetached }
            .count
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

    private func readFamilyEvents(in dateInterval: DateInterval) throws -> FamilyCalendarLoadResult {
        let familyCalendars = eventStore.calendars(for: .event).filter { calendar in
            calendar.title.trimmingCharacters(in: .whitespacesAndNewlines) == familyCalendarName
        }

        guard !familyCalendars.isEmpty else {
            return FamilyCalendarLoadResult(state: .calendarNotFound, events: [])
        }

        let predicate = eventStore.predicateForEvents(
            withStart: dateInterval.start,
            end: dateInterval.end,
            calendars: familyCalendars
        )
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isDetached }
            .map(ToDoCalendarEvent.init(event:))

        return FamilyCalendarLoadResult(state: .synced, events: events)
    }
}
