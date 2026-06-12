import SwiftUI

struct HomeView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        HomeContentView(
            homeViewModel: HomeOverviewViewModel(service: appEnvironment.homeStatusService),
            quickActionsViewModel: QuickActionsViewModel(service: appEnvironment.quickActionService)
        )
    }
}

private struct HomeContentView: View {
    @StateObject private var homeViewModel: HomeOverviewViewModel
    @StateObject private var quickActionsViewModel: QuickActionsViewModel

    init(
        homeViewModel: HomeOverviewViewModel,
        quickActionsViewModel: QuickActionsViewModel
    ) {
        _homeViewModel = StateObject(wrappedValue: homeViewModel)
        _quickActionsViewModel = StateObject(wrappedValue: quickActionsViewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                HStack {
                    Spacer(minLength: AppSpacing.medium)

                    StatusBadgeView(
                        label: homeViewModel.statusData.label,
                        systemImage: homeViewModel.statusData.systemImage,
                        tone: homeViewModel.statusData.tone
                    )
                }

                if homeViewModel.isLoading {
                    loadingView
                }

                if let errorMessage = homeViewModel.errorMessage, homeViewModel.overview == nil {
                    ErrorBannerView(message: errorMessage)

                    PrimaryActionButton(
                        title: "Retry",
                        systemImage: "arrow.clockwise"
                    ) {
                        Task {
                            await homeViewModel.refresh()
                        }
                    }
                } else {
                    if let statusMessage = homeViewModel.statusMessage {
                        ErrorBannerView(message: statusMessage, tone: .warning)
                    }

                    GarageStatusCard(data: homeViewModel.garageCardData)
                    LightSummaryCard(data: homeViewModel.lightSummaryCardData)
                    RecentImportantEventView(data: homeViewModel.recentImportantEventData)
                    QuickActionsView(viewModel: quickActionsViewModel) { refreshedOverview in
                        homeViewModel.apply(overview: refreshedOverview)
                    }
                }
            }
            .padding(AppSpacing.screen)
            .padding(.bottom, AppSpacing.xLarge * 3)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .task {
            async let home: Void = homeViewModel.loadIfNeeded()
            async let actions: Void = quickActionsViewModel.loadIfNeeded()
            _ = await (home, actions)
        }
        .refreshable {
            async let home: Void = homeViewModel.refresh()
            async let actions: Void = quickActionsViewModel.refresh()
            _ = await (home, actions)
        }
    }

    private var loadingView: some View {
        InfoPanel(
            title: "Loading Home",
            subtitle: "Fetching garage and light status.",
            systemImage: "house"
        ) {
            HStack(spacing: AppSpacing.medium) {
                ProgressView()

                Text("Checking the latest home overview...")
                    .font(.body)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeContentView(
            homeViewModel: HomeOverviewViewModel {
                HomeOverview(
                    garageStatus: GarageStatus(
                        state: .closed,
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
                                lightsOnCount: 2,
                                totalLightCount: 5
                            )
                        ]
                    ),
                    recentImportantEvent: nil,
                    generatedAt: "2026-06-12T14:00:02Z",
                    isPartial: false
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
