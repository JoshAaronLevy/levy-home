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
                ShoppingListView()
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
    }
}

private enum RootTab: Hashable {
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
}
