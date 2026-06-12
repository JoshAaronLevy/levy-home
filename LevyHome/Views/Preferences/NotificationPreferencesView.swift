import SwiftUI

struct NotificationPreferencesView: View {
    @ObservedObject var viewModel: NotificationPreferencesViewModel

    var body: some View {
        InfoPanel(
            title: "Notification Preferences",
            subtitle: "Categories configured for this device.",
            systemImage: "slider.horizontal.3"
        ) {
            NavigationLink {
                GarageNotificationPreferencesView(viewModel: viewModel)
            } label: {
                HStack(spacing: AppSpacing.medium) {
                    Image(systemName: "door.garage.closed")
                        .font(.title3)
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text("Garage")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(preferenceSummary)
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
    }

    private var preferenceSummary: String {
        let enabledCount = viewModel.preferences.filter { $0.isEnabled }.count
        let totalCount = viewModel.preferences.count
        return "\(enabledCount) of \(totalCount) enabled"
    }
}

private struct GarageNotificationPreferencesView: View {
    @ObservedObject var viewModel: NotificationPreferencesViewModel

    var body: some View {
        ScrollView {
            InfoPanel(
                title: "Garage Notifications",
                subtitle: "Choose which garage notifications this device should receive.",
                systemImage: "door.garage.closed"
            ) {
                VStack(spacing: 0) {
                    ForEach(viewModel.preferences) { preference in
                        preferenceToggle(preference)

                        if preference.id != viewModel.preferences.last?.id {
                            Divider()
                                .padding(.vertical, AppSpacing.medium)
                        }
                    }
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Garage")
    }

    private func preferenceToggle(_ preference: NotificationPreference) -> some View {
        Toggle(
            isOn: Binding(
                get: { preference.isEnabled },
                set: { viewModel.setPreference(preference, isEnabled: $0) }
            )
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(preference.title ?? preference.category.rawValue)
                    .font(.subheadline.weight(.semibold))

                if let detail = preference.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(AppColors.accent)
    }
}

#Preview {
    NotificationPreferencesView(
        viewModel: NotificationPreferencesViewModel(
            service: NotificationPreferencesService(
                userDefaults: UserDefaults(suiteName: "NotificationPreferencesPreview") ?? .standard
            )
        )
    )
    .padding()
    .background(AppColors.pageBackground)
}
