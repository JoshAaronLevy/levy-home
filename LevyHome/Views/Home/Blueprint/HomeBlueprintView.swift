import SwiftUI

struct HomeBlueprintView: View {
    let garageData: GarageStatusCardData
    let lightSummaryData: LightSummaryCardData
    let thermostatStatus: ThermostatStatus?
    let garageToggleAction: QuickActionDisplayData?
    let showsGarageWarning: Bool
    let performingActionID: String?
    let onLightingAreaTapped: (BlueprintLightingArea) -> Void
    let onGarageTapped: () -> Void
    let onThermostatTapped: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let cornerRadius: CGFloat = 26
            let center = CGPoint(x: width * 0.50, y: height * 0.48)
            let fullNodeSize = min(max(width * 0.225, 78), 92)
            let fullGarageSize = min(max(width * 0.305, 112), 134)
            let nodeSize = fullNodeSize * 0.85
            let garageSize = fullGarageSize * 0.85
            let centerSize = min(max(width * 0.185, 66), 80)
            let positions = BlueprintNodePositions(width: width, height: height)
            let kitchenStatus = lightStatus(for: .kitchen)
            let upstairsStatus = lightStatus(for: .upstairs)
            let studyStatus = lightStatus(for: .study)
            let playroomStatus = lightStatus(for: .playroom)
            let entryStatus = lightStatus(for: .entry)
            let garageStatus = BlueprintLightStatus(garageStatus: garageData.status)
            let thermostatOperation = BlueprintThermostatOperation(hvacAction: thermostatStatus?.hvacAction)

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

                BlueprintConnectorLine(from: center, to: positions.kitchen)
                    .stroke(kitchenStatus.color, style: BlueprintConnectorLine.strokeStyle)
                    .shadow(color: .white.opacity(0.78), radius: 1.5)

                BlueprintConnectorLine(from: center, to: positions.upstairsHall)
                    .stroke(upstairsStatus.color, style: BlueprintConnectorLine.strokeStyle)
                    .shadow(color: .white.opacity(0.78), radius: 1.5)

                BlueprintConnectorLine(from: center, to: positions.study)
                    .stroke(studyStatus.color, style: BlueprintConnectorLine.strokeStyle)
                    .shadow(color: .white.opacity(0.78), radius: 1.5)

                BlueprintConnectorLine(from: center, to: positions.garage)
                    .stroke(garageStatus.color, style: BlueprintConnectorLine.strokeStyle)
                    .shadow(color: .white.opacity(0.78), radius: 1.5)

                BlueprintConnectorLine(from: center, to: positions.thermostat)
                    .stroke(thermostatOperation.color, style: BlueprintConnectorLine.strokeStyle)
                    .shadow(color: .white.opacity(0.78), radius: 1.5)

                BlueprintConnectorLine(from: center, to: positions.entry)
                    .stroke(entryStatus.color, style: BlueprintConnectorLine.strokeStyle)
                    .shadow(color: .white.opacity(0.78), radius: 1.5)

                BlueprintConnectorLine(from: center, to: positions.playroom)
                    .stroke(playroomStatus.color, style: BlueprintConnectorLine.strokeStyle)
                    .shadow(color: .white.opacity(0.78), radius: 1.5)

                CenterHomeNode(size: centerSize)
                    .position(center)

                Button {
                    onLightingAreaTapped(.kitchen)
                } label: {
                    BlueprintNodeView(
                        systemImage: "stove",
                        tone: .success,
                        size: nodeSize,
                        iconReferenceSize: fullNodeSize,
                        lightStatus: kitchenStatus,
                        iconScale: 1.12
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kitchen Lights")
                .accessibilityHint("Shows Kitchen lighting controls.")
                .position(positions.kitchen)

                Button {
                    onLightingAreaTapped(.upstairs)
                } label: {
                    BlueprintNodeView(
                        systemImage: "light.recessed.3.inverse",
                        tone: .accent,
                        size: nodeSize,
                        iconReferenceSize: fullNodeSize,
                        lightStatus: upstairsStatus
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Upstairs Lights")
                .accessibilityHint("Shows Upstairs lighting controls.")
                .position(positions.upstairsHall)

                Button {
                    onLightingAreaTapped(.study)
                } label: {
                    BlueprintNodeView(
                        systemImage: "lamp.desk",
                        tone: .success,
                        size: nodeSize,
                        iconReferenceSize: fullNodeSize,
                        lightStatus: studyStatus
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Study Lights")
                .accessibilityHint("Shows Study lighting controls.")
                .position(positions.study)

                Button {
                    onLightingAreaTapped(.playroom)
                } label: {
                    BlueprintNodeView(
                        systemImage: "teddybear",
                        tone: .accent,
                        size: nodeSize,
                        iconReferenceSize: fullNodeSize,
                        lightStatus: playroomStatus
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playroom Lights")
                .accessibilityHint("Shows Playroom lighting controls.")
                .position(positions.playroom)

                Button {
                    onLightingAreaTapped(.entry)
                } label: {
                    BlueprintNodeView(
                        systemImage: "door.left.hand.closed",
                        tone: .success,
                        size: nodeSize,
                        iconReferenceSize: fullNodeSize,
                        lightStatus: entryStatus,
                        iconScale: 1.12
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foyer Lights")
                .accessibilityHint("Shows Foyer lighting controls.")
                .position(positions.entry)

                Button {
                    onThermostatTapped()
                } label: {
                    BlueprintThermostatNode(size: garageSize, status: thermostatStatus, operation: thermostatOperation)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Thermostat controls")
                .accessibilityHint("Shows the current temperature and setpoint controls.")
                .position(positions.thermostat)

                Button {
                    onGarageTapped()
                } label: {
                    BlueprintNodeView(
                        systemImage: garageData.systemImage,
                        tone: garageData.tone,
                        size: garageSize,
                        iconReferenceSize: fullGarageSize,
                        lightStatus: garageStatus,
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

    private func lightStatus(for area: BlueprintLightingArea) -> BlueprintLightStatus {
        let groups = lightSummaryData.groups.filter { group in
            area.matches(id: group.id, name: group.name)
        }

        return BlueprintLightStatus(groups: groups)
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

enum HomeBlueprintMode: String, CaseIterable, Identifiable {
    case temperatures
    case lights

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .temperatures:
            return "Temps"
        case .lights:
            return "Lights"
        }
    }
}

struct HomeBlueprintModePicker: View {
    @Binding var selection: HomeBlueprintMode

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            ForEach(HomeBlueprintMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(selection == mode ? HomePalette.blue : HomePalette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.small + 2)
                        .background {
                            if selection == mode {
                                Capsule()
                                    .fill(HomePalette.nodeFill)
                                    .shadow(color: HomePalette.shadow.opacity(0.42), radius: 8, y: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(mode.title) blueprint")
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(AppSpacing.xSmall)
        .background(HomePalette.blueprintFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(HomePalette.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

struct TemperatureBlueprintView: View {
    let roomTemperatures: [RoomTemperatureReading]
    let thermostatStatus: ThermostatStatus?
    let onThermostatTapped: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let cornerRadius: CGFloat = 26
            let center = CGPoint(x: width * 0.50, y: height * 0.48)
            let sensorNodeSize = min(max(width * 0.22, 78), 88)
            let thermostatNodeSize = min(max(width * 0.32, 108), 118)
            let centerSize = min(max(width * 0.185, 66), 80)
            let positions = TemperatureBlueprintNodePositions(width: width, height: height)

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

                ForEach(TemperatureBlueprintNodeKind.allCases) { node in
                    BlueprintConnectorLine(from: center, to: positions.point(for: node))
                        .stroke(HomePalette.blue.opacity(0.28), style: BlueprintConnectorLine.strokeStyle)
                        .shadow(color: .white.opacity(0.78), radius: 1.5)
                }

                BlueprintConnectorLine(from: center, to: positions.thermostat)
                    .stroke(HomePalette.blue.opacity(0.42), style: BlueprintConnectorLine.strokeStyle)
                    .shadow(color: .white.opacity(0.78), radius: 1.5)

                CenterHomeNode(size: centerSize)
                    .position(center)

                ForEach(TemperatureBlueprintNodeKind.allCases) { node in
                    TemperatureBlueprintSensorNode(
                        node: node,
                        reading: roomTemperatures.first(where: { $0.id == node.id }),
                        size: sensorNodeSize
                    )
                    .position(positions.point(for: node))
                }

                Button {
                    onThermostatTapped()
                } label: {
                    TemperatureBlueprintThermostatNode(
                        size: thermostatNodeSize,
                        status: thermostatStatus,
                        operation: BlueprintThermostatOperation(hvacAction: thermostatStatus?.hvacAction)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Thermostat controls")
                .accessibilityHint("Shows the current temperature and setpoint controls.")
                .position(positions.thermostat)
            }
        }
        .frame(height: 350)
        .padding(.bottom, AppSpacing.large)
    }
}

private enum TemperatureBlueprintNodeKind: CaseIterable, Identifiable {
    case study
    case kitchenFamily
    case nursery
    case masterBedroom
    case playroom

    var id: String {
        switch self {
        case .study:
            return "study"
        case .kitchenFamily:
            return "kitchen_family"
        case .nursery:
            return "nursery"
        case .masterBedroom:
            return "master_bedroom"
        case .playroom:
            return "playroom"
        }
    }

    var name: String {
        switch self {
        case .study:
            return "Study"
        case .kitchenFamily:
            return "Kitchen and Family Room"
        case .nursery:
            return "Nursery"
        case .masterBedroom:
            return "Master Bedroom"
        case .playroom:
            return "Playroom"
        }
    }

    var systemImage: String {
        switch self {
        case .study:
            return "lamp.desk"
        case .kitchenFamily:
            return "tv"
        case .nursery:
            return "teddybear"
        case .masterBedroom:
            return "bed.double"
        case .playroom:
            return "gamecontroller"
        }
    }
}

private struct TemperatureBlueprintNodePositions {
    let study: CGPoint
    let kitchenFamily: CGPoint
    let nursery: CGPoint
    let masterBedroom: CGPoint
    let playroom: CGPoint
    let thermostat: CGPoint

    init(width: CGFloat, height: CGFloat) {
        study = CGPoint(x: width * 0.28, y: height * 0.25)
        kitchenFamily = CGPoint(x: width * 0.72, y: height * 0.25)
        nursery = CGPoint(x: width * 0.18, y: height * 0.50)
        masterBedroom = CGPoint(x: width * 0.82, y: height * 0.50)
        playroom = CGPoint(x: width * 0.20, y: height * 0.76)
        thermostat = CGPoint(x: width * 0.50, y: height * 0.80)
    }

    func point(for node: TemperatureBlueprintNodeKind) -> CGPoint {
        switch node {
        case .study:
            return study
        case .kitchenFamily:
            return kitchenFamily
        case .nursery:
            return nursery
        case .masterBedroom:
            return masterBedroom
        case .playroom:
            return playroom
        }
    }
}

private struct TemperatureBlueprintSensorNode: View {
    let node: TemperatureBlueprintNodeKind
    let reading: RoomTemperatureReading?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(HomePalette.nodeFill)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.88), lineWidth: 2)
                }
                .overlay {
                    Circle()
                        .stroke(HomePalette.inactiveLightStatus.opacity(0.78), lineWidth: 2.5)
                }
                .shadow(color: HomePalette.shadow, radius: 12, y: 7)

            VStack(spacing: size * 0.05) {
                Text(temperatureText)
                    .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(reading?.temperature?.isFinite == true ? HomePalette.blue : HomePalette.secondaryInk)

                Image(systemName: node.systemImage)
                    .font(.system(size: size * 0.26, weight: .medium))
                    .foregroundStyle(HomePalette.iconInk.opacity(0.62))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(reading?.name ?? node.name), \(temperatureText)")
    }

    private var temperatureText: String {
        guard let temperature = reading?.temperature, temperature.isFinite else {
            return "—"
        }

        return "\(Int(temperature.rounded()))°"
    }
}

private struct TemperatureBlueprintThermostatNode: View {
    let size: CGFloat
    let status: ThermostatStatus?
    let operation: BlueprintThermostatOperation

    var body: some View {
        ZStack {
            Circle()
                .fill(HomePalette.nodeFill)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                }
                .overlay {
                    Circle()
                        .stroke(operation.color.opacity(0.8), lineWidth: 3)
                }
                .shadow(color: HomePalette.shadow, radius: 18, y: 9)

            VStack(spacing: size * 0.025) {
                Text(temperatureText(status?.currentTemperature, includesDegreeSymbol: true))
                    .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(HomePalette.blue)

                Text("\(temperatureText(status?.targetTemperatureLow)) / \(temperatureText(status?.targetTemperatureHigh))")
                    .font(.system(size: size * 0.16, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(HomePalette.secondaryInk)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityLabel)
    }

    private func temperatureText(_ temperature: Double?, includesDegreeSymbol: Bool = false) -> String {
        guard let temperature, temperature.isFinite else {
            return "—"
        }

        let value = "\(Int(temperature.rounded()))"
        return includesDegreeSymbol ? "\(value)°" : value
    }

    private var accessibilityLabel: String {
        "Thermostat, current \(temperatureText(status?.currentTemperature)), low \(temperatureText(status?.targetTemperatureLow)), high \(temperatureText(status?.targetTemperatureHigh))"
    }
}

enum BlueprintLightingArea: String, CaseIterable, Identifiable {
    case entry
    case kitchen
    case playroom
    case upstairs
    case study

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .entry:
            return "Foyer"
        case .kitchen:
            return "Kitchen"
        case .playroom:
            return "Playroom"
        case .upstairs:
            return "Upstairs"
        case .study:
            return "Study"
        }
    }

    var dialogTitle: String {
        "\(title) Lights"
    }

    private var matchingTerms: [String] {
        switch self {
        case .entry:
            return ["foyer", "entry"]
        case .kitchen:
            return ["kitchen"]
        case .playroom:
            return ["playroom"]
        case .upstairs:
            return ["upstairs", "hallway"]
        case .study:
            return ["study"]
        }
    }

    func matches(id: String, name: String) -> Bool {
        let searchableText = "\(id) \(name)".lowercased()
        return matchingTerms.contains { searchableText.contains($0.lowercased()) }
    }
}

private struct BlueprintNodePositions {
    let kitchen: CGPoint
    let upstairsHall: CGPoint
    let study: CGPoint
    let garage: CGPoint
    let thermostat: CGPoint
    let entry: CGPoint
    let playroom: CGPoint

    init(width: CGFloat, height: CGFloat) {
        kitchen = CGPoint(x: width * 0.48, y: height * 0.25)
        upstairsHall = CGPoint(x: width * 0.72, y: height * 0.26)
        study = CGPoint(x: width * 0.82, y: height * 0.50)
        garage = CGPoint(x: width * 0.75, y: height * 0.78)
        thermostat = CGPoint(x: width * 0.47, y: height * 0.75)
        entry = CGPoint(x: width * 0.18, y: height * 0.75)
        playroom = CGPoint(x: width * 0.19, y: height * 0.50)
    }
}

private enum BlueprintLightStatus {
    case active
    case inactive
    case unavailable
    case unknown

    init(groups: [LightGroupSummary]) {
        guard !groups.isEmpty else {
            self = .inactive
            return
        }

        if groups.contains(where: { $0.state.isUnavailable }) {
            self = .unavailable
            return
        }

        if groups.contains(where: { $0.state.isActive }) {
            self = .active
            return
        }

        if groups.allSatisfy({ $0.state == .off }) {
            self = .inactive
            return
        }

        self = .unknown
    }

    init(garageStatus: String) {
        switch garageStatus.lowercased() {
        case "open", "opening", "closing":
            self = .active
        default:
            self = .inactive
        }
    }

    var color: Color {
        switch self {
        case .active:
            return HomePalette.gold
        case .inactive, .unknown:
            return HomePalette.inactiveLightStatus
        case .unavailable:
            return HomePalette.coral
        }
    }
}

private extension LightSummary.State {
    var isActive: Bool {
        switch self {
        case .on, .partiallyOn:
            return true
        case .off, .unavailable, .unknown, .unrecognized:
            return false
        }
    }

    var isUnavailable: Bool {
        switch self {
        case .unavailable:
            return true
        case .off, .on, .partiallyOn, .unknown, .unrecognized:
            return false
        }
    }
}

private enum BlueprintThermostatOperation {
    case cooling
    case heating
    case neutral

    init(hvacAction: String?) {
        switch hvacAction?.lowercased() {
        case "cooling":
            self = .cooling
        case "heating":
            self = .heating
        default:
            self = .neutral
        }
    }

    var color: Color {
        switch self {
        case .cooling:
            return HomePalette.blue
        case .heating:
            return HomePalette.coral
        case .neutral:
            return HomePalette.inactiveLightStatus
        }
    }
}

private struct BlueprintThermostatNode: View {
    let size: CGFloat
    let status: ThermostatStatus?
    let operation: BlueprintThermostatOperation

    var body: some View {
        ZStack {
            Circle()
                .fill(HomePalette.nodeFill)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.88), lineWidth: 2)
                }
                .overlay {
                    Circle()
                        .stroke(operation.color, lineWidth: 3)
                }
                .shadow(color: HomePalette.shadow, radius: 16, y: 9)

            VStack(spacing: size * 0.02) {
                Text(temperatureText(status?.currentTemperature, includesDegreeSymbol: true))
                    .font(.system(size: size * 0.30, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text("\(temperatureText(status?.targetTemperatureLow)) / \(temperatureText(status?.targetTemperatureHigh))")
                    .font(.system(size: size * 0.17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(HomePalette.iconInk)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityLabel)
    }

    private func temperatureText(_ temperature: Double?, includesDegreeSymbol: Bool = false) -> String {
        guard let temperature, temperature.isFinite else {
            return "—"
        }

        let value = "\(Int(temperature.rounded()))"
        return includesDegreeSymbol ? "\(value)°" : value
    }

    private var accessibilityLabel: String {
        "Thermostat, current \(temperatureText(status?.currentTemperature)), low \(temperatureText(status?.targetTemperatureLow)), high \(temperatureText(status?.targetTemperatureHigh))"
    }
}

private struct BlueprintNodeView: View {
    let systemImage: String
    let tone: StatusBadgeTone
    let size: CGFloat
    let iconReferenceSize: CGFloat
    let lightStatus: BlueprintLightStatus
    var isPriority = false
    var showsWarningBadge = false
    var isPerforming = false
    var iconScale: CGFloat = 1

    var body: some View {
        ZStack {
            Circle()
                .fill(HomePalette.nodeFill)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.88), lineWidth: 2)
                }
                .overlay {
                    Circle()
                        .stroke(lightStatus.color, lineWidth: isPriority ? 3 : 2.5)
                }
                .shadow(color: HomePalette.shadow, radius: isPriority ? 16 : 12, y: isPriority ? 9 : 7)

            Group {
                if isPerforming {
                    ProgressView()
                        .tint(tone == .warning ? HomePalette.amber : HomePalette.iconInk)
                        .scaleEffect(isPriority ? 1.35 : 1.15)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: baseIconSize * iconScale, weight: .medium))
                        .foregroundStyle(tone == .warning ? HomePalette.amber : HomePalette.iconInk)
                }
            }
            .frame(
                width: iconReferenceSize * 0.72,
                height: iconReferenceSize * 0.72,
                alignment: .center
            )

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

    private var baseIconSize: CGFloat {
        isPriority ? iconReferenceSize * 0.38 : iconReferenceSize * 0.36
    }
}

private struct BlueprintConnectorLine: Shape {
    static let strokeStyle = StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)

    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
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
