import SwiftUI

struct WeatherPanelToggleButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(HomePalette.secondaryInk)
                .frame(width: 32, height: 32)
                .background(HomePalette.connector, in: Circle())
                .overlay {
                    Circle()
                        .stroke(HomePalette.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
