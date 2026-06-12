import SwiftUI

struct HomeView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Home",
            systemImage: "house",
            message: "Garage status, light status, recent activity, and quick actions will land here."
        )
        .navigationTitle("Home")
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
