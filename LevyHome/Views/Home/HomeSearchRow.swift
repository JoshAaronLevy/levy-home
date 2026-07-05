import SwiftUI

struct HomeSearchRow: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(HomePalette.secondaryInk)

                TextField("Find devices, scenes, events", text: $searchText)
                    .font(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, AppSpacing.large)
            .frame(height: 58)
            .background(HomePalette.surface, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(HomePalette.hairline, lineWidth: 1)
            }

            Button {} label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(HomePalette.secondaryInk)
                    .frame(width: 58, height: 58)
                    .background(HomePalette.surface, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(HomePalette.hairline, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter search")
        }
    }
}
