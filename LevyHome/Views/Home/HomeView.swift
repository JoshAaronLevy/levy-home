import SwiftUI

struct HomeView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    let isSelected: Bool

    init(isSelected: Bool = true) {
        self.isSelected = isSelected
    }

    var body: some View {
        HomeContentView(
            homeViewModel: HomeOverviewViewModel(service: appEnvironment.homeStatusService),
            weatherViewModel: HomeWeatherViewModel(service: appEnvironment.homeWeatherService),
            quickActionsViewModel: QuickActionsViewModel(
                service: appEnvironment.quickActionService,
                appLogStore: appEnvironment.appLogStore
            ),
            isSelected: isSelected
        )
    }
}

#Preview {
    NavigationStack {
        HomeContentView(
            homeViewModel: HomeOverviewViewModel {
                HomeOverview(
                    garageStatus: GarageStatus(
                        state: .open,
                        displayName: "Main garage",
                        lastUpdatedAt: "2026-06-12T14:00:00Z",
                        isStale: false
                    ),
                    lightSummary: LightSummary(
                        state: .partiallyOn,
                        lightsOnCount: 3,
                        totalLightCount: 12,
                        groups: [
                            LightGroupStatus(
                                id: "kitchen",
                                name: "Kitchen",
                                state: .partiallyOn,
                                lightsOnCount: 3,
                                totalLightCount: 5
                            )
                        ]
                    ),
                    presence: [
                        HomePresenceStatus(
                            person: "Josh",
                            state: .away,
                            entityId: "device_tracker.josh_iphone",
                            deviceName: "Joshs iPhone",
                            lastUpdatedAt: "2026-06-12T13:55:00Z",
                            isStale: false
                        )
                    ],
                    recentImportantEvent: nil,
                    generatedAt: "2026-06-12T14:00:02Z",
                    isPartial: false
                )
            },
            weatherViewModel: HomeWeatherViewModel {
                HomeWeatherSnapshot(
                    currentTemperature: Measurement(value: 74, unit: UnitTemperature.fahrenheit),
                    highTemperature: Measurement(value: 82, unit: UnitTemperature.fahrenheit),
                    lowTemperature: Measurement(value: 58, unit: UnitTemperature.fahrenheit),
                    conditionDescription: "Partly Cloudy",
                    symbolName: "cloud.sun.fill",
                    attributionURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html"),
                    fetchedAt: Date()
                )
            },
            quickActionsViewModel: QuickActionsViewModel(
                service: PreviewQuickActionService()
            )
        )
    }
}

private struct PreviewQuickActionService: QuickActionServicing {
    func fetchCatalog() async throws -> QuickActionCatalog {
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
                )
            ],
            lightGroups: []
        )
    }

    func perform(_ request: QuickActionRequest) async throws -> QuickActionResult {
        QuickActionResult(
            actionId: request.actionId,
            status: .success,
            message: "Preview action completed.",
            refreshedHomeOverview: nil
        )
    }
}
