import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                ActivityView()
            }
            .tabItem {
                Label("Activity", systemImage: "clock")
            }

            NavigationStack {
                NotificationHubView()
            }
            .tabItem {
                Label("Notifications", systemImage: "bell")
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.appEnvironment, AppEnvironment.live())
}
