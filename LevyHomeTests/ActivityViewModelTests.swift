import XCTest
@testable import LevyHome

@MainActor
final class ActivityViewModelTests: XCTestCase {
    func testLoadIfNeededLoadsEventsSuccessfully() async {
        let expectedEvent = Self.event(id: "event-1", title: "Garage opened")
        let viewModel = ActivityViewModel { limit in
            XCTAssertEqual(limit, 50)
            return EventsResponse(ok: true, events: [expectedEvent])
        }

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.events, [expectedEvent])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testLoadIfNeededDoesNotReloadAfterFirstSuccess() async {
        var loadCount = 0
        let viewModel = ActivityViewModel { _ in
            loadCount += 1
            return EventsResponse(ok: true, events: [Self.event(id: "event-\(loadCount)")])
        }

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(viewModel.events.map(\.id), ["event-1"])
    }

    func testEmptyResponseShowsEmptyState() async {
        let viewModel = ActivityViewModel { _ in
            EventsResponse(ok: true, events: [])
        }

        await viewModel.loadIfNeeded()

        XCTAssertTrue(viewModel.events.isEmpty)
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFailureShowsErrorMessage() async {
        let viewModel = ActivityViewModel { _ in
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

        let viewModel = ActivityViewModel { _ in
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

        let viewModel = ActivityViewModel { _ in
            try responses.removeFirst().get()
        }

        await viewModel.loadIfNeeded()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.events.map(\.id), ["event-1"])
        XCTAssertEqual(viewModel.errorMessage, "The API returned HTTP 500.")
    }

    private static func event(id: String, title: String = "Garage opened") -> LevyHomeEvent {
        LevyHomeEvent(
            id: id,
            type: .garageOpened,
            entityId: "cover.main_garage_door",
            category: .garage,
            severity: .normal,
            source: "home_assistant",
            occurredAt: "2026-06-12T14:00:00Z",
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
}
