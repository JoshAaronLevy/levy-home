import SwiftUI

struct ThemePreferenceRowView: View {
    @ObservedObject var viewModel: ThemePreferenceViewModel

    var body: some View {
        InfoPanel(
            title: "Appearance",
            subtitle: nil,
            systemImage: "circle.lefthalf.filled"
        ) {
            NavigationLink {
                ThemePreferenceView(viewModel: viewModel)
            } label: {
                HStack(spacing: AppSpacing.medium) {
                    Image(systemName: viewModel.preference.systemImage)
                        .font(.title3)
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text("Theme")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(viewModel.selectedTitle)
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
}

struct ThemePreferenceView: View {
    @ObservedObject var viewModel: ThemePreferenceViewModel

    var body: some View {
        ScrollView {
            InfoPanel(
                title: "Theme",
                subtitle: nil,
                systemImage: "paintbrush"
            ) {
                VStack(spacing: 0) {
                    ForEach(viewModel.options) { option in
                        optionButton(option)

                        if option != viewModel.options.last {
                            Divider()
                                .padding(.vertical, AppSpacing.medium)
                        }
                    }
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Theme")
    }

    private func optionButton(_ option: ThemePreference) -> some View {
        Button {
            viewModel.select(option)
        } label: {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: option.systemImage)
                    .font(.title3)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(option.detail)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                }

                Spacer()

                if viewModel.preference == option {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
    }
}

#Preview {
    NavigationStack {
        ThemePreferenceView(
            viewModel: ThemePreferenceViewModel(
                service: ThemePreferenceService(
                    userDefaults: UserDefaults(suiteName: "ThemePreferencePreview") ?? .standard
                )
            )
        )
    }
}
