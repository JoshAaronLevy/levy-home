import SwiftUI

@main
struct LevyHomeApp: App {
    private let appEnvironment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            BaselineView()
                .environment(\.appEnvironment, appEnvironment)
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
