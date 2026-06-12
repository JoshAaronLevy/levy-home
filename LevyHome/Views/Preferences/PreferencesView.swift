import SwiftUI

struct PreferencesView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        PreferencesContentView(
            viewModel: NotificationPreferencesViewModel(
                service: appEnvironment.notificationPreferencesService
            )
        )
    }
}

private struct PreferencesContentView: View {
    @StateObject private var viewModel: NotificationPreferencesViewModel

    init(viewModel: NotificationPreferencesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                NotificationDeliveryStatusView()

                NotificationPreferencesView(viewModel: viewModel)
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Preferences")
    }
}

#Preview {
    NavigationStack {
        PreferencesContentView(
            viewModel: NotificationPreferencesViewModel(
                service: NotificationPreferencesService(
                    userDefaults: UserDefaults(suiteName: "PreferencesPreview") ?? .standard
                )
            )
        )
    }
}
