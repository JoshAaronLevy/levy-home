import XCTest
@testable import LevyHome

@MainActor
final class QuickActionsViewModelTests: XCTestCase {
    func testLoadsCuratedActionsAndExpandsLightGroups() async {
        let service = MockQuickActionService()
        service.catalog = Self.catalog()
        let viewModel = QuickActionsViewModel(service: service)

        await viewModel.loadIfNeeded()

        XCTAssertEqual(service.fetchCount, 1)
        XCTAssertEqual(
            viewModel.actions.map(\.id),
            [
                "open_garage",
                "close_garage",
                "turn_off_all_lights",
                "turn_off_light_group.upstairs_hallway",
                "turn_off_light_group.playroom_lamp"
            ]
        )
        XCTAssertEqual(viewModel.actions[0].request, .openGarage)
        XCTAssertEqual(viewModel.actions[1].request, .closeGarage)
        XCTAssertEqual(viewModel.actions[2].request, .turnOffAllLights)
        XCTAssertEqual(viewModel.actions[3].request, .turnOffLightGroup(groupId: "upstairs_hallway"))
        XCTAssertFalse(viewModel.actions[0].requiresConfirmation)
        XCTAssertTrue(viewModel.actions[1].requiresConfirmation)
        XCTAssertEqual(viewModel.subtitle, "Curated Home Assistant actions")
    }

    func testOpenGaragePerformsWithoutConfirmation() async {
        let refreshedOverview = Self.overview(garageState: .opening)
        let service = MockQuickActionService()
        service.catalog = Self.catalog()
        service.result = QuickActionResult(
            actionId: .openGarage,
            status: .success,
            message: "Garage open requested.",
            refreshedHomeOverview: refreshedOverview
        )
        let viewModel = QuickActionsViewModel(service: service)

        await viewModel.loadIfNeeded()
        let openGarage = try! XCTUnwrap(viewModel.actions.first { $0.request == .openGarage })
        let overview = await viewModel.select(openGarage)

        XCTAssertEqual(service.performedRequests, [.openGarage])
        XCTAssertEqual(overview, refreshedOverview)
        XCTAssertNil(viewModel.pendingConfirmationAction)
        XCTAssertNil(viewModel.message)
    }

    func testCloseGarageRequiresConfirmationAndCanBeCancelled() async {
        let service = MockQuickActionService()
        service.catalog = Self.catalog()
        let viewModel = QuickActionsViewModel(service: service)

        await viewModel.loadIfNeeded()
        let closeGarage = try! XCTUnwrap(viewModel.actions.first { $0.request == .closeGarage })

        let overview = await viewModel.select(closeGarage)

        XCTAssertNil(overview)
        XCTAssertEqual(viewModel.pendingConfirmationAction, closeGarage)
        XCTAssertTrue(service.performedRequests.isEmpty)

        viewModel.cancelPendingConfirmation()

        XCTAssertNil(viewModel.pendingConfirmationAction)
        XCTAssertTrue(service.performedRequests.isEmpty)
    }

    func testConfirmingGarageActionPerformsRequestAndReturnsRefreshedOverview() async {
        let refreshedOverview = Self.overview(garageState: .closing)
        let service = MockQuickActionService()
        service.catalog = Self.catalog()
        service.result = QuickActionResult(
            actionId: .closeGarage,
            status: .success,
            message: "Garage close requested.",
            refreshedHomeOverview: refreshedOverview
        )
        let viewModel = QuickActionsViewModel(service: service)

        await viewModel.loadIfNeeded()
        _ = await viewModel.select(try! XCTUnwrap(viewModel.actions.first { $0.request == .closeGarage }))
        let overview = await viewModel.confirmPendingAction()

        XCTAssertEqual(service.performedRequests, [.closeGarage])
        XCTAssertEqual(overview, refreshedOverview)
        XCTAssertNil(viewModel.pendingConfirmationAction)
        XCTAssertNil(viewModel.message)
        XCTAssertFalse(viewModel.isPerforming)
        XCTAssertNil(viewModel.performingActionID)
    }

    func testActionFailureShowsReadableMessage() async {
        let service = MockQuickActionService()
        service.catalog = Self.catalog()
        service.performHandler = { _ in
            throw APIError.server(statusCode: 503, message: "Action service is unavailable.")
        }
        let viewModel = QuickActionsViewModel(service: service)

        await viewModel.loadIfNeeded()
        let allLights = try! XCTUnwrap(viewModel.actions.first { $0.request == .turnOffAllLights })
        let overview = await viewModel.select(allLights)

        XCTAssertNil(overview)
        XCTAssertEqual(service.performedRequests, [.turnOffAllLights])
        XCTAssertEqual(viewModel.message, QuickActionMessage(text: "Action service is unavailable.", tone: .error))
        XCTAssertFalse(viewModel.isPerforming)
    }

    func testDuplicateTapsAreIgnoredWhileActionIsInProgress() async throws {
        let service = MockQuickActionService()
        service.catalog = QuickActionCatalog(
            actions: [
                QuickAction(
                    id: .turnOffAllLights,
                    title: "Turn Off All Lights",
                    subtitle: "Turn off the configured all-lights group.",
                    isEnabled: true,
                    requiresConfirmation: false,
                    targetName: "All lights"
                )
            ],
            lightGroups: []
        )

        service.performHandler = { request in
            try await Task.sleep(nanoseconds: 100_000_000)
            return QuickActionResult(
                actionId: request.actionId,
                status: .success,
                message: "All configured lights were turned off.",
                refreshedHomeOverview: Self.overview()
            )
        }

        let viewModel = QuickActionsViewModel(service: service)
        await viewModel.loadIfNeeded()
        let action = try XCTUnwrap(viewModel.actions.first)

        let firstAction = Task {
            await viewModel.select(action)
        }

        for _ in 0..<10 where !viewModel.isPerforming {
            await Task.yield()
        }

        XCTAssertTrue(viewModel.isPerforming)
        XCTAssertEqual(viewModel.performingActionID, action.id)

        let duplicateOverview = await viewModel.select(action)

        XCTAssertNil(duplicateOverview)
        XCTAssertEqual(service.performedRequests, [.turnOffAllLights])

        let firstOverview = await firstAction.value

        XCTAssertNotNil(firstOverview)
        XCTAssertEqual(service.performedRequests, [.turnOffAllLights])
        XCTAssertFalse(viewModel.isPerforming)
    }

    private static func catalog() -> QuickActionCatalog {
        QuickActionCatalog(
            actions: [
                QuickAction(
                    id: .openGarage,
                    title: "Open Garage",
                    subtitle: "Open the main garage door.",
                    isEnabled: true,
                    requiresConfirmation: true,
                    targetName: "Main garage"
                ),
                QuickAction(
                    id: .closeGarage,
                    title: "Close Garage",
                    subtitle: "Close the main garage door.",
                    isEnabled: true,
                    requiresConfirmation: true,
                    targetName: "Main garage"
                ),
                QuickAction(
                    id: .turnOffAllLights,
                    title: "Turn Off All Lights",
                    subtitle: "Turn off the configured all-lights group.",
                    isEnabled: true,
                    requiresConfirmation: false,
                    targetName: "All lights"
                ),
                QuickAction(
                    id: .turnOffLightGroup,
                    title: "Turn Off Light Group",
                    subtitle: "Turn off one configured light group.",
                    isEnabled: true,
                    requiresConfirmation: false,
                    targetName: "Curated light groups"
                )
            ],
            lightGroups: [
                LightActionGroup(id: "upstairs_hallway", name: "Upstairs Hallway"),
                LightActionGroup(id: "playroom_lamp", name: "Playroom")
            ]
        )
    }

    private static func overview(garageState: GarageStatus.State = .closed) -> HomeOverview {
        HomeOverview(
            garageStatus: GarageStatus(
                state: garageState,
                displayName: "Main garage",
                lastUpdatedAt: "2026-06-12T14:00:00Z",
                isStale: false
            ),
            lightSummary: LightSummary(
                state: .off,
                lightsOnCount: 0,
                totalLightCount: 12,
                groups: []
            ),
            presence: nil,
            recentImportantEvent: nil,
            generatedAt: "2026-06-12T14:00:02Z",
            isPartial: false
        )
    }
}

private final class MockQuickActionService: QuickActionServicing {
    var catalog = QuickActionCatalog(actions: [], lightGroups: [])
    var fetchCount = 0
    var performedRequests: [QuickActionRequest] = []
    var result = QuickActionResult(
        actionId: .turnOffAllLights,
        status: .success,
        message: "Action completed.",
        refreshedHomeOverview: nil
    )
    var performHandler: ((QuickActionRequest) async throws -> QuickActionResult)?

    func fetchCatalog() async throws -> QuickActionCatalog {
        fetchCount += 1
        return catalog
    }

    func perform(_ request: QuickActionRequest) async throws -> QuickActionResult {
        performedRequests.append(request)

        if let performHandler {
            return try await performHandler(request)
        }

        return result
    }
}
