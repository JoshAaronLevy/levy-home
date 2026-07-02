import SwiftUI

struct NotificationDeliveryStatusView: View {
    @ObservedObject var viewModel: PushRegistrationViewModel
    @ObservedObject var preferencesViewModel: NotificationPreferencesViewModel
    let deviceName: String?

    init(
        viewModel: PushRegistrationViewModel,
        preferencesViewModel: NotificationPreferencesViewModel,
        deviceName: String? = nil
    ) {
        self.viewModel = viewModel
        self.preferencesViewModel = preferencesViewModel
        self.deviceName = deviceName
    }

    var body: some View {
        InfoPanel(
            title: "Notifications",
            subtitle: nil,
            systemImage: "bell.badge"
        ) {
            NavigationLink {
                NotificationDeliveryStatusDetailView(
                    viewModel: viewModel,
                    preferencesViewModel: preferencesViewModel
                )
            } label: {
                HStack(spacing: AppSpacing.medium) {
                    Image(systemName: deliveryStatusIcon)
                        .font(.title3)
                        .foregroundStyle(deliveryStatusColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        HStack(spacing: AppSpacing.xSmall) {
                            Text("Delivery Status")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if needsAttention {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.warning)
                                    .accessibilityLabel("Needs attention")
                            }
                        }

                        Text(deliveryStatusSummary)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.mutedText)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.mutedText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .task(id: deviceName ?? "") {
            viewModel.updateDeviceName(deviceName)
            await viewModel.refreshStatus()
        }
    }

    private var deliveryStatusIcon: String {
        needsAttention ? "bell.badge" : "checkmark.circle"
    }

    private var deliveryStatusColor: Color {
        needsAttention ? AppColors.warning : AppColors.success
    }

    private var deliveryStatusSummary: String {
        needsAttention ? "Setup needed" : "Ready"
    }

    private var needsAttention: Bool {
        deliveryRows.contains { row in
            switch row.tone {
            case .success:
                return false
            case .neutral, .accent, .warning, .critical:
                return row.requiresAttention
            }
        }
    }

    private var deliveryRows: [DeliveryStatusRow] {
        [
            DeliveryStatusRow(
                title: "Notifications",
                detail: viewModel.permissionDetail,
                badgeLabel: viewModel.permissionLabel,
                badgeImage: viewModel.permissionSystemImage,
                tone: viewModel.permissionTone,
                requiresAttention: viewModel.permissionTone != .success
            ),
            DeliveryStatusRow(
                title: "APNs token",
                detail: viewModel.registrationDetail,
                badgeLabel: viewModel.registrationLabel,
                badgeImage: viewModel.registrationSystemImage,
                tone: viewModel.registrationTone,
                requiresAttention: viewModel.registrationTone != .success
            ),
            DeliveryStatusRow(
                title: "API sync",
                detail: viewModel.apiRegistrationDetail,
                badgeLabel: viewModel.apiRegistrationLabel,
                badgeImage: viewModel.apiRegistrationSystemImage,
                tone: productSafeAPITone,
                requiresAttention: productSafeAPITone != .success
            ),
            DeliveryStatusRow(
                title: "Preferences",
                detail: preferencesViewModel.syncDetail,
                badgeLabel: preferencesViewModel.syncLabel,
                badgeImage: preferencesViewModel.syncSystemImage,
                tone: preferencesViewModel.syncTone,
                requiresAttention: preferencesViewModel.syncTone == .warning || preferencesViewModel.syncTone == .critical
            )
        ]
    }

    private var productSafeAPITone: StatusBadgeTone {
        viewModel.apiRegistrationTone == .critical ? .warning : viewModel.apiRegistrationTone
    }
}

private struct NotificationDeliveryStatusDetailView: View {
    @ObservedObject var viewModel: PushRegistrationViewModel
    @ObservedObject var preferencesViewModel: NotificationPreferencesViewModel

    var body: some View {
        ScrollView {
            InfoPanel(
                title: "Delivery Status",
                subtitle: "Current notification readiness for this device.",
                systemImage: "bell.badge"
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    deliveryRow(
                        title: "Notifications",
                        detail: viewModel.permissionDetail,
                        badge: StatusBadgeView(
                            label: viewModel.permissionLabel,
                            systemImage: viewModel.permissionSystemImage,
                            tone: viewModel.permissionTone
                        )
                    )

                    deliveryRow(
                        title: "APNs token",
                        detail: viewModel.registrationDetail,
                        badge: StatusBadgeView(
                            label: viewModel.registrationLabel,
                            systemImage: viewModel.registrationSystemImage,
                            tone: viewModel.registrationTone
                        )
                    )

                    deliveryRow(
                        title: "API sync",
                        detail: viewModel.apiRegistrationDetail,
                        badge: StatusBadgeView(
                            label: viewModel.apiRegistrationLabel,
                            systemImage: viewModel.apiRegistrationSystemImage,
                            tone: productSafeAPITone
                        )
                    )

                    deliveryRow(
                        title: "Preferences",
                        detail: preferencesViewModel.syncDetail,
                        badge: StatusBadgeView(
                            label: preferencesViewModel.syncLabel,
                            systemImage: preferencesViewModel.syncSystemImage,
                            tone: preferencesViewModel.syncTone
                        )
                    )
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Delivery Status")
        .task {
            await viewModel.refreshStatus()
        }
    }

    private var productSafeAPITone: StatusBadgeTone {
        viewModel.apiRegistrationTone == .critical ? .warning : viewModel.apiRegistrationTone
    }

    private func deliveryRow<Badge: View>(
        title: String,
        detail: String,
        badge: Badge
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.medium)

            badge
        }
    }
}

private struct DeliveryStatusRow {
    let title: String
    let detail: String
    let badgeLabel: String
    let badgeImage: String
    let tone: StatusBadgeTone
    let requiresAttention: Bool
}

#Preview {
    NotificationDeliveryStatusView(
        viewModel: PushRegistrationViewModel(service: PreviewDeliveryNotificationService()),
        preferencesViewModel: NotificationPreferencesViewModel(
            service: NotificationPreferencesService(
                userDefaults: UserDefaults(suiteName: "DeliveryStatusPreview") ?? .standard
            )
        )
    )
        .padding()
        .background(AppColors.pageBackground)
}

private struct PreviewDeliveryNotificationService: NotificationServicing {
    func currentSnapshot() async -> PushRegistrationSnapshot {
        PushRegistrationSnapshot(
            permissionStatus: .notDetermined,
            availability: .simulatorUnavailable,
            deviceToken: nil,
            errorMessage: nil
        )
    }

    func requestAuthorizationAndRegister() async -> PushRegistrationSnapshot {
        await currentSnapshot()
    }
}
