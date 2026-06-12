import SwiftUI

struct ActivityView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Activity",
            systemImage: "clock",
            message: "Recent home events will appear here."
        )
        .navigationTitle("Activity")
    }
}

#Preview {
    NavigationStack {
        ActivityView()
    }
}
