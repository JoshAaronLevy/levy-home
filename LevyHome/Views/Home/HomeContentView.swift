import SwiftUI

struct HomeContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var homeViewModel: HomeOverviewViewModel
    @StateObject private var weatherViewModel: HomeWeatherViewModel
    @StateObject private var quickActionsViewModel: QuickActionsViewModel
    @State private var searchText = ""
    @State private var isShowingConfirmationDialog = false
    @State private var isWeatherExpanded = false
    @AppStorage(ResidentPreference.storageKey) private var currentResidentName = ResidentPreference.defaultName

    init(
        homeViewModel: HomeOverviewViewModel,
        weatherViewModel: HomeWeatherViewModel,
        quickActionsViewModel: QuickActionsViewModel,
        isSelected: Bool = true
    ) {
        _homeViewModel = StateObject(wrappedValue: homeViewModel)
        _weatherViewModel = StateObject(wrappedValue: weatherViewModel)
        _quickActionsViewModel = StateObject(wrappedValue: quickActionsViewModel)
        self.isSelected = isSelected
    }

    private let isSelected: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                HomeHeaderView()

                if isWeatherExpanded {
                    HomeWeatherExpandedCard(
                        data: weatherViewModel.expandedData,
                        isLoading: weatherViewModel.isLoading || weatherViewModel.isRefreshing
                    ) {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                            isWeatherExpanded = false
                        }
                    }
                } else {
                    HomeWeatherSummaryCard(
                        data: weatherViewModel.displayData,
                        isLoading: weatherViewModel.isLoading || weatherViewModel.isRefreshing
                    ) {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                            isWeatherExpanded = true
                        }
                    }
                }

                HomeSearchRow(searchText: $searchText)

                statusMessages

                HomeBlueprintView(
                    garageData: homeViewModel.garageCardData,
                    lightSummaryData: homeViewModel.lightSummaryCardData,
                    garageToggleAction: garageToggleAction,
                    showsGarageWarning: showsGarageAwayWarning,
                    performingActionID: quickActionsViewModel.performingActionID
                ) {
                    Task {
                        await selectGarageToggle()
                    }
                }

                AutomationShortcutStrip(
                    shortcuts: automationShortcuts,
                    isBusy: quickActionsViewModel.isBusy,
                    performingActionID: quickActionsViewModel.performingActionID
                ) { action in
                    Task {
                        await select(action)
                    }
                }

                RecentActivityRibbon(
                    recentEventData: homeViewModel.recentImportantEventData,
                    garageData: homeViewModel.garageCardData
                )
            }
            .padding(.horizontal, AppSpacing.screen)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, AppSpacing.xLarge * 3)
        }
        .background(HomePalette.background.ignoresSafeArea())
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadHomeContentIfNeeded()
        }
        .onChange(of: isSelected) { _, newValue in
            guard newValue else {
                return
            }

            Task {
                await refreshWeatherForHomeVisit()
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active, isSelected else {
                return
            }

            Task {
                await refreshWeatherForHomeVisit()
            }
        }
        .refreshable {
            await refreshHomeContent()
        }
        .confirmationDialog(
            quickActionsViewModel.pendingConfirmationAction?.title ?? "Confirm Action",
            isPresented: $isShowingConfirmationDialog,
            titleVisibility: .visible,
            presenting: quickActionsViewModel.pendingConfirmationAction
        ) { action in
            Button(action.title) {
                Task {
                    await performConfirmedAction(action)
                }
            }

            Button("Cancel", role: .cancel) {
                quickActionsViewModel.cancelPendingConfirmation()
            }
        } message: { action in
            Text("\(action.subtitle) This will send a command through the Levy Home API.")
        }
    }

    private func loadHomeContentIfNeeded() async {
        await runHomeContentOperation {
            async let home: Void = homeViewModel.loadIfNeeded()
            async let weather: Void = weatherViewModel.refreshForHomeVisit()
            async let actions: Void = quickActionsViewModel.loadIfNeeded()
            _ = await (home, weather, actions)
        }
    }

    private func refreshHomeContent() async {
        await runHomeContentOperation {
            async let home: Void = homeViewModel.refresh()
            async let weather: Void = weatherViewModel.refresh()
            async let actions: Void = quickActionsViewModel.refresh()
            _ = await (home, weather, actions)
        }
    }

    private func refreshWeatherForHomeVisit() async {
        await runHomeContentOperation {
            await weatherViewModel.refreshForHomeVisit()
        }
    }

    private func runHomeContentOperation(
        _ operation: @escaping @MainActor () async -> Void
    ) async {
        let task = Task { @MainActor in
            await operation()
        }

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            // SwiftUI may cancel view tasks around refresh gestures; keep the requested load alive.
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if homeViewModel.isLoading {
            InlineStatusView(
                title: "Checking home status",
                message: "Fetching garage, lighting, and activity data.",
                systemImage: "arrow.clockwise"
            )
        }

        if let errorMessage = homeViewModel.errorMessage, homeViewModel.overview == nil {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                ErrorBannerView(message: errorMessage)

                Button {
                    Task {
                        await homeViewModel.refresh()
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(HomeCapsuleButtonStyle(tone: .accent))
            }
        } else if let statusMessage = homeViewModel.statusMessage {
            ErrorBannerView(message: statusMessage, tone: .warning)
        }

        if let message = quickActionsViewModel.message {
            ErrorBannerView(message: message.text, tone: message.tone)
        }
    }

    private var openGarageAction: QuickActionDisplayData? {
        quickActionsViewModel.actions.first { $0.request.actionId == .openGarage }
    }

    private var closeGarageAction: QuickActionDisplayData? {
        quickActionsViewModel.actions.first { $0.request.actionId == .closeGarage }
    }

    private var garageToggleAction: QuickActionDisplayData? {
        guard let state = homeViewModel.overview?.garageStatus.state else {
            return nil
        }

        switch state {
        case .open:
            return closeGarageAction
        case .closed:
            return openGarageAction
        case .opening, .closing, .unknown, .unrecognized:
            return nil
        }
    }

    private var showsGarageAwayWarning: Bool {
        guard
            homeViewModel.overview?.garageStatus.state == .open,
            !currentResidentName.isEmpty,
            let currentPresence = homeViewModel.overview?.presence?.first(where: {
                $0.person.localizedCaseInsensitiveCompare(currentResidentName) == .orderedSame
            })
        else {
            return false
        }

        return currentPresence.state == .away
    }

    private var allLightsAction: QuickActionDisplayData? {
        quickActionsViewModel.actions.first { $0.request.actionId == .turnOffAllLights }
    }

    private var automationShortcuts: [AutomationShortcut] {
        [
            AutomationShortcut(
                title: "Good Night",
                subtitle: "Scene",
                systemImage: "moon.stars.fill",
                tone: .indigo,
                action: nil,
                isAvailable: false
            ),
            AutomationShortcut(
                title: "Lights",
                subtitle: lightsShortcutSubtitle,
                systemImage: "lightbulb.led",
                tone: .gold,
                action: allLightsAction,
                isAvailable: allLightsAction?.isEnabled == true
            ),
            AutomationShortcut(
                title: "Arrive Home",
                subtitle: "Presence",
                systemImage: "house.fill",
                tone: .green,
                action: nil,
                isAvailable: false
            ),
            AutomationShortcut(
                title: "Quiet Mode",
                subtitle: "Scene",
                systemImage: "bell.slash.fill",
                tone: .blue,
                action: nil,
                isAvailable: false
            )
        ]
    }

    private var lightsShortcutSubtitle: String {
        guard let lightSummary = homeViewModel.overview?.lightSummary else {
            return "Loading"
        }

        if let lightsOnCount = lightSummary.lightsOnCount,
           let totalLightCount = lightSummary.totalLightCount {
            return "\(lightsOnCount)/\(totalLightCount)"
        }

        if let lightsOnCount = lightSummary.lightsOnCount {
            return lightsOnCount == 1 ? "1 on" : "\(lightsOnCount) on"
        }

        switch lightSummary.state {
        case .off:
            return "0 on"
        case .on, .partiallyOn:
            return "On"
        case .unknown, .unrecognized:
            return "Unknown"
        }
    }

    private func select(_ action: QuickActionDisplayData) async {
        if let refreshedOverview = await quickActionsViewModel.select(action) {
            homeViewModel.apply(overview: refreshedOverview)
            await watchGarageCompletionIfNeeded(for: action)
        } else if quickActionsViewModel.pendingConfirmationAction != nil {
            isShowingConfirmationDialog = true
        }
    }

    private func selectGarageToggle() async {
        guard let garageToggleAction else {
            quickActionsViewModel.reportUnavailableSelection(
                title: "Garage",
                reason: garageUnavailableReason
            )

            if quickActionsViewModel.actions.isEmpty {
                await quickActionsViewModel.refresh()
            }
            return
        }

        if let refreshedOverview = await quickActionsViewModel.performImmediately(garageToggleAction) {
            homeViewModel.apply(overview: refreshedOverview)
            await watchGarageCompletionIfNeeded(for: garageToggleAction)
        }
    }

    private func performConfirmedAction(_ action: QuickActionDisplayData) async {
        isShowingConfirmationDialog = false

        if let refreshedOverview = await quickActionsViewModel.confirm(action) {
            homeViewModel.apply(overview: refreshedOverview)
            await watchGarageCompletionIfNeeded(for: action)
        }
    }

    private func watchGarageCompletionIfNeeded(for action: QuickActionDisplayData) async {
        guard let watchPolicy = GarageCompletionWatchPolicy(request: action.request) else {
            return
        }

        if homeViewModel.overview?.garageStatus.state == watchPolicy.expectedState {
            return
        }

        for attempt in 1...watchPolicy.maximumAttempts {
            try? await Task.sleep(nanoseconds: watchPolicy.pollIntervalNanoseconds)
            await homeViewModel.refresh()

            guard let currentState = homeViewModel.overview?.garageStatus.state else {
                continue
            }

            if currentState == watchPolicy.expectedState {
                return
            }

            if currentState == watchPolicy.inProgressState {
                continue
            }

            if attempt >= watchPolicy.minimumAttemptsBeforeStableMismatch && currentState.isStableGarageState {
                break
            }
        }

        let currentState = homeViewModel.overview?.garageStatus.state.displayText ?? "unknown"
        quickActionsViewModel.reportActionIssue(
            title: action.title,
            reason: "\(action.title) was sent, but Garage still reports \(currentState). Pull to refresh or check Home Assistant."
        )
    }

    private var garageUnavailableReason: String {
        guard let overview = homeViewModel.overview else {
            return "Home overview has not loaded yet. Wait for GET /api/home/overview to finish, then try again."
        }

        switch overview.garageStatus.state {
        case .closed:
            return "Open Garage is missing from the quick-action catalog. Check GET /api/home/actions in Logs."
        case .open:
            return "Close Garage is missing from the quick-action catalog. Check GET /api/home/actions in Logs."
        case .opening:
            return "Garage is already opening. Wait for the next status refresh before sending another command."
        case .closing:
            return "Garage is already closing. Wait for the next status refresh before sending another command."
        case .unknown, .unrecognized:
            return "Garage status is unknown, so the app is waiting for a stable open or closed state."
        }
    }
}
