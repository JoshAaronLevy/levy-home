import XCTest
@testable import LevyHome

@MainActor
final class ActivityViewModelTests: XCTestCase {
    func testLoadIfNeededLoadsEventsSuccessfully() async {
        let expectedEvent = Self.event(id: "event-1", title: "Garage opened")
        let now = Self.date("2026-06-15T17:00:00Z")
        let viewModel = ActivityViewModel(now: { now }) { limit, start, end in
            XCTAssertEqual(limit, 500)
            XCTAssertEqual(start, Self.date("2026-06-14T17:00:00Z"))
            XCTAssertEqual(end, now)
            return EventsResponse(ok: true, events: [expectedEvent])
        }

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.events, [expectedEvent])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertFalse(viewModel.isLoadingOlder)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testLoadIfNeededDoesNotReloadAfterFirstSuccess() async {
        var loadCount = 0
        let viewModel = ActivityViewModel { _, _, _ in
            loadCount += 1
            return EventsResponse(ok: true, events: [Self.event(id: "event-\(loadCount)")])
        }

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(viewModel.events.map(\.id), ["event-1"])
    }

    func testEmptyResponseShowsEmptyState() async {
        let viewModel = ActivityViewModel { _, _, _ in
            EventsResponse(ok: true, events: [])
        }

        await viewModel.loadIfNeeded()

        XCTAssertTrue(viewModel.events.isEmpty)
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFailureShowsErrorMessage() async {
        let viewModel = ActivityViewModel { _, _, _ in
            throw APIError.server(statusCode: 503, message: "Events are unavailable.")
        }

        await viewModel.loadIfNeeded()

        XCTAssertTrue(viewModel.events.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Events are unavailable.")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testRefreshReplacesEventsAndClearsError() async {
        var responses: [Result<EventsResponse, Error>] = [
            .failure(APIError.transport("Offline")),
            .success(EventsResponse(ok: true, events: [Self.event(id: "event-2", title: "Garage closed")]))
        ]

        let viewModel = ActivityViewModel { _, _, _ in
            try responses.removeFirst().get()
        }

        await viewModel.loadIfNeeded()
        XCTAssertEqual(viewModel.errorMessage, "The network request failed.")

        await viewModel.refresh()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.events.map(\.id), ["event-2"])
    }

    func testFailedRefreshKeepsExistingEvents() async {
        var responses: [Result<EventsResponse, Error>] = [
            .success(EventsResponse(ok: true, events: [Self.event(id: "event-1")])),
            .failure(APIError.httpStatus(500))
        ]

        let viewModel = ActivityViewModel { _, _, _ in
            try responses.removeFirst().get()
        }

        await viewModel.loadIfNeeded()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.events.map(\.id), ["event-1"])
        XCTAssertEqual(viewModel.errorMessage, "The API returned HTTP 500.")
    }

    func testLoadOlderAppendsPreviousWindowWithoutDuplicatingEvents() async {
        let now = Self.date("2026-06-15T17:00:00Z")
        var requestedWindows: [(Date, Date)] = []
        let viewModel = ActivityViewModel(now: { now }) { _, start, end in
            requestedWindows.append((start, end))

            if requestedWindows.count == 1 {
                return EventsResponse(
                    ok: true,
                    events: [
                        Self.event(id: "latest", occurredAt: "2026-06-15T16:00:00Z"),
                        Self.event(id: "duplicate", occurredAt: "2026-06-14T18:00:00Z")
                    ]
                )
            }

            return EventsResponse(
                ok: true,
                events: [
                    Self.event(id: "older", occurredAt: "2026-06-14T10:00:00Z"),
                    Self.event(id: "duplicate", occurredAt: "2026-06-14T18:00:00Z")
                ]
            )
        }

        await viewModel.loadIfNeeded()
        await viewModel.loadOlder()

        XCTAssertEqual(requestedWindows.count, 2)
        XCTAssertEqual(requestedWindows[0].0, Self.date("2026-06-14T17:00:00Z"))
        XCTAssertEqual(requestedWindows[0].1, Self.date("2026-06-15T17:00:00Z"))
        XCTAssertEqual(requestedWindows[1].0, Self.date("2026-06-13T17:00:00Z"))
        XCTAssertEqual(requestedWindows[1].1, Self.date("2026-06-14T17:00:00Z"))
        XCTAssertEqual(viewModel.events.map(\.id), ["latest", "duplicate", "older"])
        XCTAssertFalse(viewModel.isLoadingOlder)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadOlderIfNeededOnlyRunsForLastVisibleEvent() async {
        let now = Self.date("2026-06-15T17:00:00Z")
        var loadCount = 0
        let viewModel = ActivityViewModel(now: { now }) { _, _, _ in
            loadCount += 1

            if loadCount == 1 {
                return EventsResponse(
                    ok: true,
                    events: [
                        Self.event(id: "newer", occurredAt: "2026-06-15T16:00:00Z"),
                        Self.event(id: "older-visible", occurredAt: "2026-06-15T15:00:00Z")
                    ]
                )
            }

            return EventsResponse(ok: true, events: [Self.event(id: "older-page", occurredAt: "2026-06-14T10:00:00Z")])
        }

        await viewModel.loadIfNeeded()
        await viewModel.loadOlderIfNeeded(currentEvent: viewModel.events[0])
        XCTAssertEqual(loadCount, 1)

        await viewModel.loadOlderIfNeeded(currentEvent: viewModel.events[1])
        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(viewModel.events.map(\.id), ["newer", "older-visible", "older-page"])
    }

    private static func event(
        id: String,
        title: String = "Garage opened",
        occurredAt: String = "2026-06-12T14:00:00Z"
    ) -> LevyHomeEvent {
        LevyHomeEvent(
            id: id,
            type: .garageOpened,
            entityId: "cover.main_garage_door",
            category: .garage,
            severity: .normal,
            source: "home_assistant",
            occurredAt: occurredAt,
            title: title,
            message: "\(title) message.",
            receivedAt: "2026-06-12T14:00:01Z",
            display: EventDisplayMetadata(
                title: title,
                body: "\(title) message.",
                severity: .info
            ),
            push: EventPushStatus(
                attempted: true,
                skipped: false,
                reason: nil,
                ticketCount: 1,
                invalidTokenCount: 0
            )
        )
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
