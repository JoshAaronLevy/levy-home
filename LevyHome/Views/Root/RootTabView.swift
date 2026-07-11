import SwiftUI

struct RootTabView: View {
    @State private var selectedTab: RootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(isSelected: selectedTab == .home)
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(RootTab.home)

            NavigationStack {
                ShoppingListView(isSelected: selectedTab == .list)
            }
            .tabItem {
                Label("List", systemImage: "cart")
            }
            .tag(RootTab.list)

            NavigationStack {
                ToDoView(isSelected: selectedTab == .todo)
            }
            .tabItem {
                Label("To Do", systemImage: "checkmark.circle")
            }
            .tag(RootTab.todo)

            NavigationStack {
                PreferencesView()
            }
            .tabItem {
                Label("Preferences", systemImage: "gearshape")
            }
            .tag(RootTab.preferences)
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "levyhome" else { return }

            if url.host?.lowercased() == "shopping" {
                selectedTab = .list
            }
        }
    }
}

enum RootTab: Hashable {
    case home
    case list
    case todo
    case preferences
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
        .environmentObject(ShoppingLiveActivityCoordinator())
        .environmentObject(PushRegistrationViewModel(service: NotificationService.shared))
}
