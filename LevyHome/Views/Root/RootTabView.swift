import SwiftUI

struct RootTabView: View {
    @State private var selectedTab: RootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(isSelected: selectedTab == .home)
            }
            .tabItem {
                Label(RootTab.home.title, systemImage: RootTab.home.systemImage)
            }
            .tag(RootTab.home)

            NavigationStack {
                ShoppingListView(isSelected: selectedTab == .list)
            }
            .tabItem {
                Label(RootTab.list.title, systemImage: RootTab.list.systemImage)
            }
            .tag(RootTab.list)

            NavigationStack {
                ToDoView(isSelected: selectedTab == .todo)
            }
            .tabItem {
                Label(RootTab.todo.title, systemImage: RootTab.todo.systemImage)
            }
            .tag(RootTab.todo)

            NavigationStack {
                CameraView()
            }
            .tabItem {
                Label(RootTab.camera.title, systemImage: RootTab.camera.systemImage)
            }
            .tag(RootTab.camera)

            NavigationStack {
                PreferencesView()
            }
            .tabItem {
                Label(RootTab.settings.title, systemImage: RootTab.settings.systemImage)
            }
            .tag(RootTab.settings)
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "levyhome" else { return }

            if url.host?.lowercased() == "shopping" {
                selectedTab = .list
            }
        }
        .onAppear {
            openPendingDestination()
        }
        .onReceive(NotificationCenter.default.publisher(for: .levyHomeOpenShopping)) { _ in
            openPendingDestination()
        }
        .onReceive(NotificationCenter.default.publisher(for: .levyHomeOpenToDo)) { _ in
            openPendingDestination()
        }
    }

    private func openPendingDestination() {
        switch AppNavigationDestination.consumePendingDestination() {
        case "shopping":
            selectedTab = .list
        case "todo":
            selectedTab = .todo
        default:
            return
        }
    }
}

enum RootTab: Hashable, CaseIterable {
    case home
    case list
    case todo
    case camera
    case settings

    var title: String {
        switch self {
        case .home:
            "Home"
        case .list:
            "List"
        case .todo:
            "To Do"
        case .camera:
            "Camera"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house"
        case .list:
            "cart"
        case .todo:
            "checkmark.circle"
        case .camera:
            "video"
        case .settings:
            "gearshape"
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
        .environmentObject(ShoppingLiveActivityCoordinator())
        .environmentObject(PushRegistrationViewModel(service: NotificationService.shared))
}
