import SwiftUI

struct ActivityView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        ActivityContentView(
            viewModel: ActivityViewModel(apiClient: appEnvironment.apiClient)
        )
    }
}

private struct ActivityContentView: View {
    @StateObject private var viewModel: ActivityViewModel

    init(viewModel: ActivityViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                if viewModel.isLoading {
                    loadingView
                } else {
                    contentView
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Activity")
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if let errorMessage = viewModel.errorMessage {
            ErrorBannerView(message: errorMessage)

            PrimaryActionButton(
                title: "Retry",
                systemImage: "arrow.clockwise"
            ) {
                Task {
                    await viewModel.refresh()
                }
            }
        }

        if viewModel.isEmpty {
            InfoPanel(
                title: "No Activity Yet",
                subtitle: "Recent home events will appear here after Home Assistant sends them.",
                systemImage: "clock"
            ) {
                Text("Pull to refresh after sending a test event from the local API.")
                    .font(.body)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ForEach(viewModel.events) { event in
                EventCardView(event: event)
            }
        }
    }

    private var loadingView: some View {
        InfoPanel(
            title: "Loading Activity",
            subtitle: "Fetching recent home events.",
            systemImage: "clock.arrow.circlepath"
        ) {
            HStack(spacing: AppSpacing.medium) {
                ProgressView()

                Text("Checking the event timeline...")
                    .font(.body)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Loaded") {
    NavigationStack {
        ActivityContentView(
            viewModel: ActivityViewModel { _ in
                EventsResponse(
                    ok: true,
                    events: [
                        LevyHomeEvent(
                            id: "event-1",
                            type: .garageLeftOpen10Min,
                            entityId: "cover.main_garage_door",
                            category: .garage,
                            severity: .high,
                            source: "home_assistant",
                            occurredAt: "2026-06-12T14:00:00Z",
                            title: "Garage left open",
                            message: "The garage has been open for 10 minutes.",
                            receivedAt: "2026-06-12T14:00:01Z",
                            display: EventDisplayMetadata(
                                title: "Garage left open",
                                body: "The garage has been open for 10 minutes.",
                                severity: .warning
                            ),
                            push: EventPushStatus(
                                attempted: true,
                                skipped: false,
                                reason: nil,
                                ticketCount: 1,
                                invalidTokenCount: 0
                            )
                        )
                    ]
                )
            }
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        ActivityContentView(
            viewModel: ActivityViewModel { _ in
                EventsResponse(ok: true, events: [])
            }
        )
    }
}
