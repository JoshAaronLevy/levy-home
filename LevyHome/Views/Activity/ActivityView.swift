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
                title: "No Activity in the Latest 24 Hours",
                subtitle: "Earlier Home Assistant activity may still be available.",
                systemImage: "clock"
            ) {
                PrimaryActionButton(
                    title: "Load Earlier Activity",
                    systemImage: "clock.arrow.circlepath",
                    isLoading: viewModel.isLoadingOlder
                ) {
                    Task {
                        await viewModel.loadOlder()
                    }
                }
            }
        } else {
            ForEach(viewModel.events) { event in
                EventCardView(event: event)
                    .task {
                        await viewModel.loadOlderIfNeeded(currentEvent: event)
                    }
            }

            olderActivityFooter
        }
    }

    @ViewBuilder
    private var olderActivityFooter: some View {
        if viewModel.isLoadingOlder {
            HStack(spacing: AppSpacing.medium) {
                ProgressView()

                Text("Loading earlier activity...")
                    .font(.body)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.medium)
        } else {
            PrimaryActionButton(
                title: "Load Earlier Activity",
                systemImage: "clock.arrow.circlepath"
            ) {
                Task {
                    await viewModel.loadOlder()
                }
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
            viewModel: ActivityViewModel { _, _, _ in
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
                        ),
                        LevyHomeEvent(
                            id: "event-2",
                            type: .phoneStateChanged,
                            entityId: "device_tracker.josh_iphone",
                            category: .phone,
                            severity: .normal,
                            source: "home_assistant",
                            occurredAt: "2026-06-15T17:00:00Z",
                            title: "Josh arrived home",
                            message: "Away -> Home",
                            receivedAt: "2026-06-15T17:00:01Z",
                            display: EventDisplayMetadata(
                                title: "Josh arrived home",
                                body: "Away -> Home",
                                severity: .info
                            ),
                            push: nil
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
            viewModel: ActivityViewModel { _, _, _ in
                EventsResponse(ok: true, events: [])
            }
        )
    }
}
