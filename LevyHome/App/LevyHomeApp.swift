import SwiftUI

@main
struct LevyHomeApp: App {
    var body: some Scene {
        WindowGroup {
            BaselineView()
        }
    }
}

private struct BaselineView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Levy Home")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("SwiftUI baseline")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    BaselineView()
}
