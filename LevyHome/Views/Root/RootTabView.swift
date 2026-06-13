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

            NavigationStack {
                PreferencesView()
            }
            .tabItem {
                Label("Preferences", systemImage: "gearshape")
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.appEnvironment, AppEnvironment.live())
        .environmentObject(
            ThemePreferenceViewModel(
                service: ThemePreferenceService(
                    userDefaults: UserDefaults(suiteName: "RootTabPreview") ?? .standard
                )
            )
        )
}
