import SwiftUI

struct QuickActionsView: View {
    @ObservedObject var viewModel: QuickActionsViewModel
    let onOverviewRefreshed: (HomeOverview) -> Void

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingConfirmationAction != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelPendingConfirmation()
                }
            }
        )
    }

    var body: some View {
        InfoPanel(
            title: "Quick Actions",
            subtitle: viewModel.subtitle,
            systemImage: "bolt"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                if viewModel.isLoading {
                    HStack(spacing: AppSpacing.medium) {
                        ProgressView()

                        Text("Loading available actions...")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.mutedText)
                    }
                }

                if let message = viewModel.message {
                    ErrorBannerView(message: message.text, tone: message.tone)
                }

                if viewModel.actions.isEmpty && !viewModel.isLoading {
                    Text("Configured actions will appear here once the API is reachable.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: AppSpacing.small)],
                    alignment: .leading,
                    spacing: AppSpacing.small
                ) {
                    ForEach(viewModel.actions) { action in
                        actionButton(action)
                    }
                }
            }
        }
        .confirmationDialog(
            viewModel.pendingConfirmationAction?.title ?? "Confirm Action",
            isPresented: confirmationBinding,
            titleVisibility: .visible,
            presenting: viewModel.pendingConfirmationAction
        ) { action in
            Button(action.title) {
                Task {
                    await performConfirmedAction()
                }
            }

            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingConfirmation()
            }
        } message: { action in
            Text("\(action.subtitle) This will send a command through the Levy Home API.")
        }
    }

    private func actionButton(_ action: QuickActionDisplayData) -> some View {
        Button {
            Task {
                await select(action)
            }
        } label: {
            HStack(spacing: AppSpacing.medium) {
                icon(for: action)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppColors.mutedText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.small)
            .background(actionBackground(for: action))
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy || !action.isEnabled)
        .accessibilityLabel(accessibilityLabel(for: action))
    }

    private func icon(for action: QuickActionDisplayData) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                .fill(iconBackground(for: action))
                .frame(width: 36, height: 36)

            if viewModel.performingActionID == action.id {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: action.systemImage)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }

    private func select(_ action: QuickActionDisplayData) async {
        if let refreshedOverview = await viewModel.select(action) {
            onOverviewRefreshed(refreshedOverview)
        }
    }

    private func performConfirmedAction() async {
        if let refreshedOverview = await viewModel.confirmPendingAction() {
            onOverviewRefreshed(refreshedOverview)
        }
    }

    private func actionBackground(for action: QuickActionDisplayData) -> Color {
        if viewModel.isBusy || !action.isEnabled {
            return Color(uiColor: .tertiarySystemFill)
        }

        return AppColors.accentSoft
    }

    private func iconBackground(for action: QuickActionDisplayData) -> Color {
        if viewModel.isBusy || !action.isEnabled {
            return AppColors.disabledControl
        }

        return AppColors.accent
    }

    private func accessibilityLabel(for action: QuickActionDisplayData) -> String {
        if !action.isEnabled {
            return "\(action.title), unavailable"
        }

        if viewModel.performingActionID == action.id {
            return "\(action.title), in progress"
        }

        return action.requiresConfirmation ? "\(action.title), requires confirmation" : action.title
    }
}

#Preview {
    QuickActionsView(
        viewModel: QuickActionsViewModel(service: QuickActionsPreviewService())
    ) { _ in }
    .padding()
    .background(AppColors.pageBackground)
}

private struct QuickActionsPreviewService: QuickActionServicing {
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
                LightActionGroup(id: "upstairs_hallway", name: "Upstairs Hallway")
            ]
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
