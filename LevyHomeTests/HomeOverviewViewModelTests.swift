import XCTest
@testable import LevyHome

@MainActor
final class HomeOverviewViewModelTests: XCTestCase {
    func testLoadIfNeededLoadsOverviewSuccessfully() async {
        let overview = Self.overview(
            garageStatus: GarageStatus(
                state: .closed,
                displayName: "Main garage",
                lastUpdatedAt: "2026-06-12T14:00:00Z",
                isStale: false
            ),
            lightSummary: LightSummary(
                state: .off,
                lightsOnCount: 0,
                totalLightCount: 12,
                groups: []
            )
        )

        let viewModel = HomeOverviewViewModel { overview }

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.overview, overview)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertEqual(viewModel.statusData.label, "Live")
        XCTAssertEqual(viewModel.garageCardData.status, "Closed")
        XCTAssertEqual(viewModel.lightSummaryCardData.state, "All lights off")
    }

    func testLoadIfNeededDoesNotReloadAfterFirstLoad() async {
        var loadCount = 0
        let viewModel = HomeOverviewViewModel {
            loadCount += 1
            return Self.overview(generatedAt: "2026-06-12T14:00:0\(loadCount)Z")
        }

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(viewModel.overview?.generatedAt, "2026-06-12T14:00:01Z")
    }

    func testRefreshReloadsTheLatestHomeOverviewAfterInitialLoad() async {
        var loadCount = 0
        let viewModel = HomeOverviewViewModel {
            loadCount += 1
            return Self.overview(generatedAt: "2026-06-12T14:00:0\(loadCount)Z")
        }

        await viewModel.loadIfNeeded()
        await viewModel.refresh()

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(viewModel.overview?.generatedAt, "2026-06-12T14:00:02Z")
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testPartialAndUnknownStatusRemainReadable() async {
        let viewModel = HomeOverviewViewModel {
            Self.overview(
                garageStatus: GarageStatus(
                    state: .unknown,
                    displayName: nil,
                    lastUpdatedAt: nil,
                    isStale: true
                ),
                lightSummary: LightSummary(
                    state: .unknown,
                    lightsOnCount: nil,
                    totalLightCount: nil,
                    groups: [
                        LightGroupStatus(
                            id: "upstairs_hallway",
                            name: "Downstairs",
                            state: .unknown,
                            lightsOnCount: nil,
                            totalLightCount: nil
                        )
                    ]
                ),
                isPartial: true
            )
        }

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.statusData.label, "Partial")
        XCTAssertEqual(viewModel.garageCardData.status, "Unknown")
        XCTAssertEqual(viewModel.garageCardData.location, "Main garage")
        XCTAssertTrue(viewModel.garageCardData.detail.contains("Garage status is unavailable."))
        XCTAssertEqual(viewModel.lightSummaryCardData.state, "Unknown")
        XCTAssertEqual(viewModel.lightSummaryCardData.groups.first?.count, "Unknown")
        XCTAssertEqual(
            viewModel.statusMessage,
            "Some home status could not be loaded. The available details are shown below."
        )
    }

    func testLoadsOnlyEventsFromTheCurrentMountainDay() async {
        let now = Self.date("2026-07-20T18:00:00Z") // Noon in Denver (MDT).
        var requestedRange: (Date, Date)?
        let currentEvent = Self.event(id: "doorbell", occurredAt: "2026-07-20T06:15:00Z")
        let priorDayEvent = Self.event(id: "prior-day", occurredAt: "2026-07-20T05:59:59Z")

        let viewModel = HomeOverviewViewModel(
            now: { now },
            loadTodayActivity: { _, start, end in
                requestedRange = (start, end)
                return EventsResponse(ok: true, events: [priorDayEvent, currentEvent])
            },
            loadOverview: { Self.overview() }
        )

        await viewModel.loadIfNeeded()

        XCTAssertEqual(requestedRange?.0, Self.date("2026-07-20T06:00:00Z"))
        XCTAssertEqual(requestedRange?.1, Self.date("2026-07-21T06:00:00Z"))
        XCTAssertEqual(viewModel.todayActivityEvents.map(\.id), ["doorbell"])
        XCTAssertTrue(viewModel.hasLoadedTodayActivity)
    }

    func testFailureWithoutOverviewShowsErrorAndOfflineStatus() async {
        let viewModel = HomeOverviewViewModel {
            throw APIError.server(statusCode: 503, message: "Home overview is unavailable.")
        }

        await viewModel.loadIfNeeded()

        XCTAssertNil(viewModel.overview)
        XCTAssertEqual(viewModel.errorMessage, "Home overview is unavailable.")
        XCTAssertEqual(viewModel.statusData.label, "Offline")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testFailedRefreshKeepsExistingOverviewAndMarksStale() async {
        var responses: [Result<HomeOverview, Error>] = [
            .success(Self.overview()),
            .failure(APIError.transport("Offline"))
        ]

        let viewModel = HomeOverviewViewModel {
            try responses.removeFirst().get()
        }

        await viewModel.loadIfNeeded()
        await viewModel.refresh()

        XCTAssertNotNil(viewModel.overview)
        XCTAssertEqual(viewModel.errorMessage, "The network request failed.")
        XCTAssertEqual(viewModel.statusData.label, "Stale")
        XCTAssertEqual(
            viewModel.statusMessage,
            "The network request failed. Showing the last loaded home status."
        )
    }

    func testCancelledRefreshKeepsExistingOverviewWithoutError() async {
        var responses: [Result<HomeOverview, Error>] = [
            .success(Self.overview()),
            .failure(URLError(.cancelled))
        ]

        let viewModel = HomeOverviewViewModel {
            try responses.removeFirst().get()
        }

        await viewModel.loadIfNeeded()
        await viewModel.refresh()

        XCTAssertNotNil(viewModel.overview)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.statusData.label, "Live")
        XCTAssertNil(viewModel.statusMessage)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    private static func overview(
        garageStatus: GarageStatus = GarageStatus(
            state: .closed,
            displayName: "Main garage",
            lastUpdatedAt: "2026-06-12T14:00:00Z",
            isStale: false
        ),
        lightSummary: LightSummary = LightSummary(
            state: .partiallyOn,
            lightsOnCount: 3,
            totalLightCount: 12,
            groups: [
                LightGroupStatus(
                    id: "kitchen",
                    name: "Kitchen",
                    state: .partiallyOn,
                    lightsOnCount: 2,
                    totalLightCount: 5
                )
            ]
        ),
        recentImportantEvent: LevyHomeEvent? = nil,
        generatedAt: String = "2026-06-12T14:00:02Z",
        isPartial: Bool = false
    ) -> HomeOverview {
        HomeOverview(
            garageStatus: garageStatus,
            lightSummary: lightSummary,
            presence: nil,
            recentImportantEvent: recentImportantEvent,
            generatedAt: generatedAt,
            isPartial: isPartial
        )
    }

    private static func event(id: String, occurredAt: String = "2026-06-12T14:00:00Z") -> LevyHomeEvent {
        let display = EventDisplayMetadata(
            title: "Doorbell pressed",
            body: "Someone pressed the doorbell.",
            severity: .critical
        )
        return LevyHomeEvent(
            id: id,
            type: .doorbellPressed,
            entityId: "binary_sensor.doorbell_ringing",
            category: .doorbell,
            severity: .high,
            source: "home_assistant",
            occurredAt: occurredAt,
            title: display.title,
            message: display.body,
            receivedAt: "2026-06-12T14:00:01Z",
            display: display,
            push: nil
        )
    }

    private static func date(_ rawValue: String) -> Date {
        ISO8601DateFormatter().date(from: rawValue)!
    }
}
