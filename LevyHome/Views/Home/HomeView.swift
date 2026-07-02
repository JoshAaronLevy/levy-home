import SwiftUI

struct HomeView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        HomeContentView(
            homeViewModel: HomeOverviewViewModel(service: appEnvironment.homeStatusService),
            weatherViewModel: HomeWeatherViewModel(service: appEnvironment.homeWeatherService),
            quickActionsViewModel: QuickActionsViewModel(
                service: appEnvironment.quickActionService,
                appLogStore: appEnvironment.appLogStore
            )
        )
    }
}

private struct HomeContentView: View {
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
        quickActionsViewModel: QuickActionsViewModel
    ) {
        _homeViewModel = StateObject(wrappedValue: homeViewModel)
        _weatherViewModel = StateObject(wrappedValue: weatherViewModel)
        _quickActionsViewModel = StateObject(wrappedValue: quickActionsViewModel)
    }

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
            async let home: Void = homeViewModel.loadIfNeeded()
            async let weather: Void = weatherViewModel.loadIfNeeded()
            async let actions: Void = quickActionsViewModel.loadIfNeeded()
            _ = await (home, weather, actions)
        }
        .refreshable {
            async let home: Void = homeViewModel.refresh()
            async let weather: Void = weatherViewModel.refresh()
            async let actions: Void = quickActionsViewModel.refresh()
            _ = await (home, weather, actions)
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

private struct HomeHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Levy Home")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(HomePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: AppSpacing.medium)

                HStack(spacing: AppSpacing.medium) {
                    /*
                    TODO: Restore after alerts are fine-tuned and notifications are ready.
                    Button {} label: {
                        Image(systemName: "bell")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(HomePalette.ink)
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(HomePalette.coral)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 2, y: -2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Notifications")
                    */

                    HomeAvatarView()
                }
            }
        }
    }
}

private struct HomeAvatarView: View {
    var body: some View {
        Image("HomeAvatar")
            .resizable()
            .scaledToFill()
            .frame(width: 76, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.88), lineWidth: 3)
            }
            .shadow(color: HomePalette.shadow, radius: 11, y: 6)
            .accessibilityLabel("Home profile")
    }
}

private struct HomeWeatherSummaryCard: View {
    let data: HomeWeatherSummaryData
    let isLoading: Bool
    let expandAction: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(data.dateText)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(HomePalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let attributionURL = data.attributionURL {
                    Link("Weather", destination: attributionURL)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                } else {
                    Text("Weather")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppSpacing.small)

            if isLoading && data.isPlaceholder {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 34)
            } else {
                Image(systemName: data.systemImage)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(HomePalette.gold, Color(red: 0.72, green: 0.82, blue: 0.92))
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 34)
            }

            Text(data.currentTemperatureText)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(HomePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            Text(data.highLowTemperatureText)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(HomePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            if data.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomePalette.gold)
                    .accessibilityHidden(true)
            }

            WeatherPanelToggleButton(
                systemName: "chevron.down",
                accessibilityLabel: "Expand weather",
                action: expandAction
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.large)
        .frame(height: 58)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomePalette.hairline, lineWidth: 1)
        }
        .shadow(color: HomePalette.shadow.opacity(0.45), radius: 10, y: 5)
    }
}

private struct HomeWeatherExpandedCard: View {
    let data: HomeWeatherExpandedData
    let isLoading: Bool
    let collapseAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(data.summary.dateText)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(HomePalette.ink)
                        .lineLimit(1)

                    Text(data.summary.conditionText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.small)

                if isLoading && data.summary.isPlaceholder {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 34)
                } else {
                    Image(systemName: data.summary.systemImage)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(HomePalette.gold, Color(red: 0.72, green: 0.82, blue: 0.92))
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 34)
                }

                VStack(alignment: .trailing, spacing: 3) {
                    Text(data.summary.currentTemperatureText)
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(HomePalette.ink)
                        .lineLimit(1)

                    Text(data.summary.highLowTemperatureText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                }

                WeatherPanelToggleButton(
                    systemName: "chevron.up",
                    accessibilityLabel: "Collapse weather",
                    action: collapseAction
                )
            }

            HomeWeatherTemperatureChart(data: data.chart)

            Divider()
                .overlay(HomePalette.hairline)

            HomeWeatherPrecipitationRow(summary: data.precipitationSummary)

            Divider()
                .overlay(HomePalette.hairline)

            HomeWeatherTomorrowSection(data: data.tomorrow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomePalette.hairline, lineWidth: 1)
        }
        .shadow(color: HomePalette.shadow.opacity(0.45), radius: 12, y: 6)
    }
}

private struct WeatherPanelToggleButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(HomePalette.secondaryInk)
                .frame(width: 32, height: 32)
                .background(HomePalette.connector, in: Circle())
                .overlay {
                    Circle()
                        .stroke(HomePalette.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct HomeWeatherTemperatureChart: View {
    let data: HomeWeatherChartData

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                Label("Temperature", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomePalette.ink)

                Spacer()
            }

            HStack(alignment: .top, spacing: AppSpacing.small) {
                VStack(alignment: .trailing) {
                    ForEach(Array(data.yAxisValues.enumerated()), id: \.offset) { _, value in
                        Text("\(value)°")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HomePalette.secondaryInk)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 34, height: 136)

                VStack(spacing: AppSpacing.small) {
                    HomeWeatherChartPlot(data: data)
                        .frame(height: 136)

                    HomeWeatherChartXAxis(data: data)
                        .frame(height: 16)
                }
            }
        }
    }
}

private struct HomeWeatherChartPlot: View {
    let data: HomeWeatherChartData

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(data.yAxisValues.indices, id: \.self) { index in
                    Rectangle()
                        .fill(HomePalette.hairline)
                        .frame(height: 1)
                        .position(
                            x: proxy.size.width / 2,
                            y: yPosition(forIndex: index, count: data.yAxisValues.count, height: proxy.size.height)
                        )
                }

                if data.points.count > 1 {
                    Path { path in
                        guard let firstPoint = data.points.first else {
                            return
                        }

                        path.move(to: point(for: firstPoint, size: proxy.size))

                        for chartPoint in data.points.dropFirst() {
                            path.addLine(to: point(for: chartPoint, size: proxy.size))
                        }
                    }
                    .stroke(HomePalette.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                ForEach(data.points) { chartPoint in
                    Circle()
                        .fill(HomePalette.gold)
                        .frame(width: 7, height: 7)
                        .overlay {
                            Circle()
                                .stroke(HomePalette.surface, lineWidth: 2)
                        }
                        .position(point(for: chartPoint, size: proxy.size))
                }

                if data.points.isEmpty {
                    Text("Forecast unavailable")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HomePalette.secondaryInk)
                }
            }
        }
    }

    private func yPosition(forIndex index: Int, count: Int, height: CGFloat) -> CGFloat {
        guard count > 1 else {
            return height / 2
        }

        return CGFloat(index) / CGFloat(count - 1) * height
    }

    private func point(for chartPoint: HomeWeatherChartPoint, size: CGSize) -> CGPoint {
        let span = max(data.maximumTemperature - data.minimumTemperature, 1)
        let normalizedY = (data.maximumTemperature - chartPoint.temperature) / span

        return CGPoint(
            x: chartPoint.position * size.width,
            y: min(max(normalizedY, 0), 1) * size.height
        )
    }
}

private struct HomeWeatherChartXAxis: View {
    let data: HomeWeatherChartData

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(data.xAxisLabels) { label in
                    Text(label.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                        .position(
                            x: min(max(label.position * proxy.size.width, 22), proxy.size.width - 22),
                            y: 8
                        )
                }
            }
        }
    }
}

private struct HomeWeatherPrecipitationRow: View {
    let summary: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: "cloud.rain.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(HomePalette.blue, Color(red: 0.72, green: 0.82, blue: 0.92))
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("Precipitation")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HomePalette.secondaryInk)

                Text(summary)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomePalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }
        }
    }
}

private struct HomeWeatherTomorrowSection: View {
    let data: HomeWeatherTomorrowSummaryData

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Label("Tomorrow", systemImage: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HomePalette.ink)

            HStack(spacing: 0) {
                HomeWeatherMetricView(title: "High", value: data.highText)
                HomeWeatherMetricDivider()
                HomeWeatherMetricView(title: "Low", value: data.lowText)
                HomeWeatherMetricDivider()
                HomeWeatherMetricView(title: "Avg", value: data.averageText)
                HomeWeatherMetricDivider()
                HomeWeatherMetricView(title: "Rain", value: data.precipitationChanceText)
            }
        }
    }
}

private struct HomeWeatherMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HomePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HomePalette.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HomeWeatherMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(HomePalette.hairline)
            .frame(width: 1, height: 34)
    }
}

private struct HomeWeatherSummaryCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: AppSpacing.large) {
            HomeWeatherSummaryCard(
                data: HomeWeatherSummaryData(
                    dateText: "Wed. Jul 1",
                    attributionURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html"),
                    systemImage: "cloud.sun.fill",
                    currentTemperatureText: "74°",
                    highLowTemperatureText: "82°/58°",
                    conditionText: "Partly Cloudy",
                    isPlaceholder: false,
                    isStale: false
                ),
                isLoading: false,
                expandAction: {}
            )

            HomeWeatherExpandedCard(
                data: HomeWeatherExpandedData(
                    summary: HomeWeatherSummaryData(
                        dateText: "Wed. Jul 1",
                        attributionURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html"),
                        systemImage: "cloud.sun.fill",
                        currentTemperatureText: "74°",
                        highLowTemperatureText: "82°/58°",
                        conditionText: "Partly Cloudy",
                        isPlaceholder: false,
                        isStale: false
                    ),
                    chart: HomeWeatherChartData(
                        points: [
                            HomeWeatherChartPoint(id: 1, position: 0.12, temperature: 66),
                            HomeWeatherChartPoint(id: 2, position: 0.28, temperature: 73),
                            HomeWeatherChartPoint(id: 3, position: 0.42, temperature: 80),
                            HomeWeatherChartPoint(id: 4, position: 0.62, temperature: 84),
                            HomeWeatherChartPoint(id: 5, position: 0.82, temperature: 76)
                        ],
                        xAxisLabels: HomeWeatherChartData.standardXAxisLabels,
                        yAxisValues: [89, 82, 75, 68, 61],
                        minimumTemperature: 61,
                        maximumTemperature: 89
                    ),
                    precipitationSummary: "Chance of light rain in the afternoon.",
                    tomorrow: HomeWeatherTomorrowSummaryData(
                        highText: "79°",
                        lowText: "61°",
                        averageText: "73°",
                        precipitationChanceText: "35%"
                    )
                ),
                isLoading: false,
                collapseAction: {}
            )
        }
        .padding()
        .background(HomePalette.background)
    }
}
struct GarageCompletionWatchPolicy: Equatable {
    let expectedState: GarageStatus.State
    let inProgressState: GarageStatus.State
    let maximumAttempts: Int
    let pollIntervalNanoseconds: UInt64
    let minimumAttemptsBeforeStableMismatch: Int

    init?(request: QuickActionRequest) {
        pollIntervalNanoseconds = 1_500_000_000
        minimumAttemptsBeforeStableMismatch = 3

        switch request {
        case .openGarage:
            expectedState = .open
            inProgressState = .opening
            maximumAttempts = 12
        case .closeGarage:
            expectedState = .closed
            inProgressState = .closing
            maximumAttempts = 24
        case .turnOffAllLights, .turnOffLightGroup:
            return nil
        }
    }
}

private extension GarageStatus.State {
    var displayText: String {
        switch self {
        case .open:
            return "open"
        case .closed:
            return "closed"
        case .opening:
            return "opening"
        case .closing:
            return "closing"
        case .unknown:
            return "unknown"
        case .unrecognized(let rawValue):
            return rawValue
        }
    }

    var isStableGarageState: Bool {
        switch self {
        case .open, .closed:
            return true
        case .opening, .closing, .unknown, .unrecognized:
            return false
        }
    }
}

private struct HomeSearchRow: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(HomePalette.secondaryInk)

                TextField("Find devices, scenes, events", text: $searchText)
                    .font(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, AppSpacing.large)
            .frame(height: 58)
            .background(HomePalette.surface, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(HomePalette.hairline, lineWidth: 1)
            }

            Button {} label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(HomePalette.secondaryInk)
                    .frame(width: 58, height: 58)
                    .background(HomePalette.surface, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(HomePalette.hairline, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter search")
        }
    }
}

private struct HomeBlueprintView: View {
    let garageData: GarageStatusCardData
    let lightSummaryData: LightSummaryCardData
    let garageToggleAction: QuickActionDisplayData?
    let showsGarageWarning: Bool
    let performingActionID: String?
    let onGarageTapped: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let cornerRadius: CGFloat = 26
            let center = CGPoint(x: width * 0.50, y: height * 0.54)
            let nodeSize = min(max(width * 0.225, 78), 92)
            let garageSize = min(max(width * 0.305, 112), 134)
            let centerSize = min(max(width * 0.185, 66), 80)
            let positions = BlueprintNodePositions(width: width, height: height)

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(HomePalette.blueprintFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.75), lineWidth: 2)
                    }
                    .shadow(color: HomePalette.shadow.opacity(0.8), radius: 18, y: 10)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HomePalette.hairline, lineWidth: 1)

                FloorPlanLines()
                    .stroke(HomePalette.floorLine, lineWidth: 1)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                ConnectorLines(
                    center: center,
                    points: [
                        positions.kitchen,
                        positions.upstairsHall,
                        positions.study,
                        positions.garage,
                        positions.entry,
                        positions.playroom
                    ]
                )
                .stroke(
                    HomePalette.connector,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: .white.opacity(0.9), radius: 2)

                BlueprintDecorations(width: width, height: height)

                CenterHomeNode(size: centerSize)
                    .position(center)

                BlueprintNodeView(
                    title: "Kitchen",
                    subtitle: kitchenSubtitle,
                    systemImage: "lightbulb",
                    tone: .success,
                    size: nodeSize
                )
                .position(positions.kitchen)

                BlueprintNodeView(
                    title: "Upstairs",
                    subtitle: "quiet",
                    systemImage: "stairs",
                    tone: .accent,
                    size: nodeSize
                )
                .position(positions.upstairsHall)

                BlueprintNodeView(
                    title: "Study",
                    subtitle: "idle",
                    systemImage: "lamp.desk",
                    tone: .success,
                    size: nodeSize
                )
                .position(positions.study)

                BlueprintNodeView(
                    title: "Playroom",
                    subtitle: "quiet",
                    systemImage: "teddybear",
                    tone: .accent,
                    size: nodeSize
                )
                .position(positions.playroom)

                BlueprintNodeView(
                    title: "Entry",
                    subtitle: "secure",
                    systemImage: "door.left.hand.closed",
                    tone: .success,
                    size: nodeSize
                )
                .position(positions.entry)

                Button {
                    onGarageTapped()
                } label: {
                    BlueprintNodeView(
                        title: "Garage",
                        subtitle: garageSubtitle,
                        systemImage: garageData.systemImage,
                        tone: garageData.tone,
                        size: garageSize,
                        isPriority: true,
                        showsWarningBadge: showsGarageWarning,
                        isPerforming: garageToggleAction?.id == performingActionID
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(garageAccessibilityLabel)
                .accessibilityHint(garageAccessibilityHint)
                .position(positions.garage)
            }
        }
        .frame(height: 350)
        .padding(.bottom, AppSpacing.large)
    }

    private var kitchenSubtitle: String {
        if let group = lightSummaryData.groups.first(where: { $0.name.localizedCaseInsensitiveContains("kitchen") }) {
            return group.count
        }

        if lightSummaryData.state.localizedCaseInsensitiveContains("light") {
            return lightSummaryData.state.replacingOccurrences(of: " on", with: "")
        }

        return "quiet"
    }

    private var garageSubtitle: String {
        garageData.status.lowercased()
    }

    private var garageAccessibilityLabel: String {
        let warning = showsGarageWarning ? ", open while you are away" : ""
        return "Garage, \(garageData.status.lowercased())\(warning)"
    }

    private var garageAccessibilityHint: String {
        guard let garageToggleAction else {
            return "Garage control is unavailable."
        }

        if garageToggleAction.id == performingActionID {
            return "\(garageToggleAction.title) is in progress."
        }

        return "Double tap to \(garageToggleAction.title.lowercased())."
    }

}

private struct BlueprintNodePositions {
    let kitchen: CGPoint
    let upstairsHall: CGPoint
    let study: CGPoint
    let garage: CGPoint
    let entry: CGPoint
    let playroom: CGPoint

    init(width: CGFloat, height: CGFloat) {
        kitchen = CGPoint(x: width * 0.48, y: height * 0.31)
        upstairsHall = CGPoint(x: width * 0.72, y: height * 0.32)
        study = CGPoint(x: width * 0.82, y: height * 0.56)
        garage = CGPoint(x: width * 0.77, y: height * 0.84)
        entry = CGPoint(x: width * 0.29, y: height * 0.76)
        playroom = CGPoint(x: width * 0.19, y: height * 0.52)
    }
}

private struct BlueprintNodeView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tone: StatusBadgeTone
    let size: CGFloat
    var isPriority = false
    var showsWarningBadge = false
    var isPerforming = false

    var body: some View {
        ZStack {
            Circle()
                .fill(HomePalette.nodeFill)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.88), lineWidth: 2)
                }
                .shadow(color: HomePalette.shadow, radius: isPriority ? 16 : 12, y: isPriority ? 9 : 7)

            Circle()
                .trim(from: 0.62, to: 0.94)
                .stroke(
                    tone.foregroundColor,
                    style: StrokeStyle(lineWidth: isPriority ? 4 : 3, lineCap: .round)
                )
                .rotationEffect(.degrees(28))
                .padding(isPriority ? 8 : 6)

            VStack(spacing: isPriority ? AppSpacing.small : AppSpacing.xSmall) {
                if isPerforming {
                    ProgressView()
                        .tint(tone == .warning ? HomePalette.amber : HomePalette.iconInk)
                        .frame(height: isPriority ? 34 : 28)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: isPriority ? 32 : 22, weight: .medium))
                        .foregroundStyle(tone == .warning ? HomePalette.amber : HomePalette.iconInk)
                        .frame(height: isPriority ? 34 : 28)
                }

                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: isPriority ? 20 : 16, weight: .semibold))
                        .foregroundStyle(HomePalette.ink)
                        .lineLimit(title == "Upstairs" ? 2 : 1)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.76)

                    Text(subtitle)
                        .font(.system(size: isPriority ? 14 : 12, weight: .medium))
                        .foregroundStyle(tone.foregroundColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(.horizontal, AppSpacing.small)

            if showsWarningBadge {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: isPriority ? 18 : 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: isPriority ? 34 : 28, height: isPriority ? 34 : 28)
                    .background(HomePalette.coral, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.88), lineWidth: 2)
                    }
                    .shadow(color: HomePalette.coral.opacity(0.34), radius: 8, y: 3)
                    .offset(x: size * 0.32, y: -size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

private struct CenterHomeNode: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(HomePalette.centerFill)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.95), lineWidth: 2)
                }
                .shadow(color: HomePalette.green.opacity(0.22), radius: 18, y: 8)

            Image(systemName: "house.fill")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(HomePalette.iconInk.opacity(0.62))
                .overlay(alignment: .bottom) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: size * 0.18, weight: .medium))
                        .foregroundStyle(HomePalette.gold)
                        .offset(y: -size * 0.02)
                }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Home center")
    }
}

private struct FloorPlanLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        let lines: [[CGPoint]] = [
            [point(0.05, 0.22), point(0.28, 0.22), point(0.28, 0.08)],
            [point(0.28, 0.08), point(0.49, 0.08), point(0.49, 0.30)],
            [point(0.62, 0.09), point(0.84, 0.09), point(0.84, 0.30)],
            [point(0.74, 0.31), point(0.94, 0.31), point(0.94, 0.57)],
            [point(0.08, 0.43), point(0.33, 0.43), point(0.33, 0.67)],
            [point(0.09, 0.67), point(0.32, 0.67), point(0.32, 0.91)],
            [point(0.41, 0.75), point(0.62, 0.75), point(0.62, 0.91)],
            [point(0.62, 0.67), point(0.86, 0.67), point(0.86, 0.90)]
        ]

        for line in lines {
            guard let first = line.first else {
                continue
            }

            path.move(to: first)
            for point in line.dropFirst() {
                path.addLine(to: point)
            }
        }

        let rooms = [
            CGRect(x: rect.width * 0.13, y: rect.height * 0.58, width: rect.width * 0.08, height: rect.height * 0.10),
            CGRect(x: rect.width * 0.19, y: rect.height * 0.14, width: rect.width * 0.10, height: rect.height * 0.09),
            CGRect(x: rect.width * 0.63, y: rect.height * 0.12, width: rect.width * 0.08, height: rect.height * 0.07),
            CGRect(x: rect.width * 0.79, y: rect.height * 0.58, width: rect.width * 0.11, height: rect.height * 0.13),
            CGRect(x: rect.width * 0.44, y: rect.height * 0.72, width: rect.width * 0.10, height: rect.height * 0.10)
        ]

        for room in rooms {
            path.addRoundedRect(
                in: CGRect(
                    x: rect.minX + room.minX,
                    y: rect.minY + room.minY,
                    width: room.width,
                    height: room.height
                ),
                cornerSize: CGSize(width: 6, height: 6)
            )
        }

        return path
    }
}

private struct ConnectorLines: Shape {
    let center: CGPoint
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for point in points {
            path.move(to: center)
            let control = CGPoint(
                x: (center.x + point.x) / 2,
                y: (center.y + point.y) / 2
            )
            path.addQuadCurve(to: point, control: control)
        }

        return path
    }
}

private struct BlueprintDecorations: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            decorativeSpark(at: CGPoint(x: width * 0.12, y: height * 0.16))
            decorativeSpark(at: CGPoint(x: width * 0.92, y: height * 0.14))
            decorativeSpark(at: CGPoint(x: width * 0.92, y: height * 0.63))
            decorativeSpark(at: CGPoint(x: width * 0.49, y: height * 0.75))
        }
    }

    private func decorativeSpark(at point: CGPoint) -> some View {
        Image(systemName: "asterisk")
            .font(.title3.weight(.medium))
            .foregroundStyle(HomePalette.green.opacity(0.34))
            .position(point)
            .accessibilityHidden(true)
    }
}

private struct AutomationShortcutStrip: View {
    let shortcuts: [AutomationShortcut]
    let isBusy: Bool
    let performingActionID: String?
    let onActionSelected: (QuickActionDisplayData) -> Void

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.small),
                    GridItem(.flexible(), spacing: AppSpacing.small),
                    GridItem(.flexible(), spacing: AppSpacing.small),
                    GridItem(.flexible(), spacing: AppSpacing.small)
                ],
                spacing: AppSpacing.small
            ) {
                ForEach(shortcuts) { shortcut in
                    ShortcutButton(
                        shortcut: shortcut,
                        isBusy: isBusy,
                        isPerforming: isPerforming(shortcut)
                    ) {
                        if let action = shortcut.action {
                            onActionSelected(action)
                        }
                    }
                }
            }

            HStack(spacing: AppSpacing.xSmall) {
                Circle()
                    .fill(HomePalette.blue)
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(HomePalette.hairline)
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(HomePalette.hairline)
                    .frame(width: 8, height: 8)
            }
            .accessibilityHidden(true)
        }
    }

    private func isPerforming(_ shortcut: AutomationShortcut) -> Bool {
        guard let action = shortcut.action, let performingActionID else {
            return false
        }

        return action.id == performingActionID
    }
}

private struct ShortcutButton: View {
    let shortcut: AutomationShortcut
    let isBusy: Bool
    let isPerforming: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.small) {
                if isPerforming {
                    ProgressView()
                        .tint(shortcut.tone.color)
                        .frame(height: 30)
                } else {
                    Image(systemName: shortcut.systemImage)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(shortcut.tone.color)
                        .frame(height: 30)
                }

                Text(shortcut.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomePalette.ink)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, minHeight: 18)

                Text(shortcut.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(shortcut.tone.color.opacity(shortcut.isAvailable ? 0.95 : 0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .padding(.horizontal, AppSpacing.xSmall)
            .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(HomePalette.hairline, lineWidth: 1)
            }
            .shadow(color: HomePalette.shadow.opacity(0.72), radius: 14, y: 8)
            .opacity(shortcut.isAvailable ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!shortcut.isAvailable || isBusy)
        .accessibilityLabel(
            shortcut.isAvailable
                ? "\(shortcut.title), \(shortcut.subtitle)"
                : "\(shortcut.title), \(shortcut.subtitle), unavailable"
        )
    }
}

private struct RecentActivityRibbon: View {
    let recentEventData: RecentImportantEventData
    let garageData: GarageStatusCardData

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .foregroundStyle(HomePalette.ink)

                Spacer()

                Button("See all") {}
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomePalette.blue)
                    .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ActivityRibbonRow(
                    icon: recentIcon,
                    tone: recentEventData.tone,
                    title: recentEventData.title,
                    detail: recentEventData.timestamp
                )

                ActivityRibbonRow(
                    icon: garageData.systemImage,
                    tone: garageData.tone,
                    title: "Garage \(garageData.status.lowercased())",
                    detail: garageData.location
                )
            }
        }
        .padding(AppSpacing.large)
        .background(HomePalette.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(HomePalette.hairline, lineWidth: 1)
        }
    }

    private var recentIcon: String {
        switch recentEventData.tone {
        case .success:
            return "person.fill"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        case .accent:
            return "sparkles"
        case .neutral:
            return "clock"
        }
    }
}

private struct ActivityRibbonRow: View {
    let icon: String
    let tone: StatusBadgeTone
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            ZStack {
                Circle()
                    .fill(tone.backgroundColor)
                    .frame(width: 46, height: 46)

                Image(systemName: icon)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(tone.foregroundColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(HomePalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(HomePalette.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HomePalette.secondaryInk.opacity(0.45))
        }
        .padding(.vertical, AppSpacing.small)
    }
}

private struct InlineStatusView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            ProgressView()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomePalette.ink)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(HomePalette.secondaryInk)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.medium)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomePalette.hairline, lineWidth: 1)
        }
    }
}

private struct AutomationShortcut: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tone: ShortcutTone
    let action: QuickActionDisplayData?
    let isAvailable: Bool
}

private enum ShortcutTone {
    case indigo
    case gold
    case green
    case blue

    var color: Color {
        switch self {
        case .indigo:
            return HomePalette.indigo
        case .gold:
            return HomePalette.gold
        case .green:
            return HomePalette.green
        case .blue:
            return HomePalette.blue
        }
    }
}

private struct HomeCapsuleButtonStyle: ButtonStyle {
    let tone: StatusBadgeTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, AppSpacing.large)
            .frame(height: 42)
            .foregroundStyle(tone.foregroundColor)
            .background(tone.backgroundColor, in: Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private enum HomePalette {
    static let background = adaptive(
        light: UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1.0),
        dark: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)
    )
    static let surface = adaptive(
        light: UIColor(red: 1.0, green: 0.995, blue: 0.98, alpha: 0.96),
        dark: UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 0.96)
    )
    static let nodeFill = adaptive(
        light: UIColor(red: 1.0, green: 0.995, blue: 0.98, alpha: 0.96),
        dark: UIColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 0.96)
    )
    static let centerFill = adaptive(
        light: UIColor(red: 0.96, green: 0.98, blue: 0.91, alpha: 0.96),
        dark: UIColor(red: 0.17, green: 0.21, blue: 0.16, alpha: 0.96)
    )
    static let blueprintFill = LinearGradient(
        colors: [
            adaptive(
                light: UIColor(red: 0.94, green: 0.93, blue: 0.88, alpha: 0.92),
                dark: UIColor(red: 0.13, green: 0.14, blue: 0.14, alpha: 0.92)
            ),
            adaptive(
                light: UIColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 0.86),
                dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 0.86)
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let garageGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.46, blue: 0.18),
            Color(red: 0.87, green: 0.27, blue: 0.12)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let ink = adaptive(
        light: UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1.0),
        dark: UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
    )
    static let iconInk = adaptive(
        light: UIColor(red: 0.36, green: 0.37, blue: 0.38, alpha: 1.0),
        dark: UIColor(red: 0.78, green: 0.80, blue: 0.82, alpha: 1.0)
    )
    static let secondaryInk = adaptive(
        light: UIColor(red: 0.42, green: 0.45, blue: 0.50, alpha: 1.0),
        dark: UIColor(red: 0.64, green: 0.66, blue: 0.70, alpha: 1.0)
    )
    static let hairline = adaptive(
        light: UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 0.09),
        dark: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.11)
    )
    static let floorLine = adaptive(
        light: UIColor(red: 0.51, green: 0.52, blue: 0.50, alpha: 0.14),
        dark: UIColor(red: 0.80, green: 0.82, blue: 0.78, alpha: 0.13)
    )
    static let connector = adaptive(
        light: UIColor(red: 1.0, green: 1.0, blue: 0.96, alpha: 0.82),
        dark: UIColor(red: 0.30, green: 0.32, blue: 0.30, alpha: 0.82)
    )
    static let shadow = Color.black.opacity(0.10)
    static let blue = Color(red: 0.18, green: 0.43, blue: 0.80)
    static let green = Color(red: 0.34, green: 0.62, blue: 0.38)
    static let amber = Color(red: 0.72, green: 0.43, blue: 0.17)
    static let gold = Color(red: 0.86, green: 0.63, blue: 0.10)
    static let coral = Color(red: 0.96, green: 0.34, blue: 0.16)
    static let indigo = Color(red: 0.31, green: 0.35, blue: 0.85)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

#Preview {
    NavigationStack {
        HomeContentView(
            homeViewModel: HomeOverviewViewModel {
                HomeOverview(
                    garageStatus: GarageStatus(
                        state: .open,
                        displayName: "Main garage",
                        lastUpdatedAt: "2026-06-12T14:00:00Z",
                        isStale: false
                    ),
                    lightSummary: LightSummary(
                        state: .partiallyOn,
                        lightsOnCount: 3,
                        totalLightCount: 12,
                        groups: [
                            LightGroupStatus(
                                id: "kitchen",
                                name: "Kitchen",
                                state: .partiallyOn,
                                lightsOnCount: 3,
                                totalLightCount: 5
                            )
                        ]
                    ),
                    presence: [
                        HomePresenceStatus(
                            person: "Josh",
                            state: .away,
                            entityId: "device_tracker.josh_iphone",
                            deviceName: "Joshs iPhone",
                            lastUpdatedAt: "2026-06-12T13:55:00Z",
                            isStale: false
                        )
                    ],
                    recentImportantEvent: nil,
                    generatedAt: "2026-06-12T14:00:02Z",
                    isPartial: false
                )
            },
            weatherViewModel: HomeWeatherViewModel {
                HomeWeatherSnapshot(
                    currentTemperature: Measurement(value: 74, unit: UnitTemperature.fahrenheit),
                    highTemperature: Measurement(value: 82, unit: UnitTemperature.fahrenheit),
                    lowTemperature: Measurement(value: 58, unit: UnitTemperature.fahrenheit),
                    conditionDescription: "Partly Cloudy",
                    symbolName: "cloud.sun.fill",
                    attributionURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html"),
                    fetchedAt: Date()
                )
            },
            quickActionsViewModel: QuickActionsViewModel(
                service: PreviewQuickActionService()
            )
        )
    }
}

private struct PreviewQuickActionService: QuickActionServicing {
    func fetchCatalog() async throws -> QuickActionCatalog {
        QuickActionCatalog(
            actions: [
                QuickAction(
                    id: .openGarage,
                    title: "Open Garage",
                    subtitle: "Open the main garage door.",
                    isEnabled: true,
                    requiresConfirmation: true,
                    targetName: "Main garage"
                ),
                QuickAction(
                    id: .closeGarage,
                    title: "Close Garage",
                    subtitle: "Close the main garage door.",
                    isEnabled: true,
                    requiresConfirmation: true,
                    targetName: "Main garage"
                ),
                QuickAction(
                    id: .turnOffAllLights,
                    title: "Turn Off All Lights",
                    subtitle: "Turn off the configured all-lights group.",
                    isEnabled: true,
                    requiresConfirmation: false,
                    targetName: "All lights"
                )
            ],
            lightGroups: []
        )
    }

    func perform(_ request: QuickActionRequest) async throws -> QuickActionResult {
        QuickActionResult(
            actionId: request.actionId,
            status: .success,
            message: "Preview action completed.",
            refreshedHomeOverview: nil
        )
    }
}
