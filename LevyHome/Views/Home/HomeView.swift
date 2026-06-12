import SwiftUI

struct HomeView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        HomeContentView(
            viewModel: HomeOverviewViewModel(service: appEnvironment.homeStatusService)
        )
    }
}

private struct HomeContentView: View {
    @StateObject private var viewModel: HomeOverviewViewModel

    init(viewModel: HomeOverviewViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                HStack {
                    Spacer(minLength: AppSpacing.medium)

                    StatusBadgeView(
                        label: viewModel.statusData.label,
                        systemImage: viewModel.statusData.systemImage,
                        tone: viewModel.statusData.tone
                    )
                }

                if viewModel.isLoading {
                    loadingView
                }

                if let errorMessage = viewModel.errorMessage, viewModel.overview == nil {
                    ErrorBannerView(message: errorMessage)

                    PrimaryActionButton(
                        title: "Retry",
                        systemImage: "arrow.clockwise"
                    ) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                } else {
                    if let statusMessage = viewModel.statusMessage {
                        ErrorBannerView(message: statusMessage, tone: .warning)
                    }

                    GarageStatusCard(data: viewModel.garageCardData)
                    LightSummaryCard(data: viewModel.lightSummaryCardData)
                    RecentImportantEventView(data: viewModel.recentImportantEventData)
                    QuickActionsView(actions: viewModel.quickActions)
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
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
            viewModel: HomeOverviewViewModel {
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
            }
        )
    }
}
