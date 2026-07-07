import SwiftUI

struct HomeBlueprintView: View {
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
            let kitchenStatus = lightStatus(matching: ["kitchen"])
            let upstairsStatus = lightStatus(matching: ["upstairs", "hallway"])
            let studyStatus = lightStatus(matching: ["study"])
            let playroomStatus = lightStatus(matching: ["playroom"])
            let entryStatus = lightStatus(matching: ["foyer", "entry"])
            let garageStatus = lightStatus(matching: ["garage"])

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

                BlueprintConnectorLine(from: center, to: positions.entry)
                    .stroke(entryStatus.color, style: BlueprintConnectorLine.strokeStyle)
                    .shadow(color: .white.opacity(0.78), radius: 1.5)

                BlueprintConnectorLine(from: center, to: positions.playroom)
                    .stroke(playroomStatus.color, style: BlueprintConnectorLine.strokeStyle)
                    .shadow(color: .white.opacity(0.78), radius: 1.5)

                CenterHomeNode(size: centerSize)
                    .position(center)

                BlueprintNodeView(
                    title: "Kitchen",
                    subtitle: kitchenSubtitle,
                    systemImage: "lightbulb",
                    tone: .success,
                    size: nodeSize,
                    lightStatus: kitchenStatus
                )
                .position(positions.kitchen)

                BlueprintNodeView(
                    title: "Upstairs",
                    subtitle: "quiet",
                    systemImage: "stairs",
                    tone: .accent,
                    size: nodeSize,
                    lightStatus: upstairsStatus
                )
                .position(positions.upstairsHall)

                BlueprintNodeView(
                    title: "Study",
                    subtitle: "idle",
                    systemImage: "lamp.desk",
                    tone: .success,
                    size: nodeSize,
                    lightStatus: studyStatus
                )
                .position(positions.study)

                BlueprintNodeView(
                    title: "Playroom",
                    subtitle: "quiet",
                    systemImage: "teddybear",
                    tone: .accent,
                    size: nodeSize,
                    lightStatus: playroomStatus
                )
                .position(positions.playroom)

                BlueprintNodeView(
                    title: "Entry",
                    subtitle: "secure",
                    systemImage: "door.left.hand.closed",
                    tone: .success,
                    size: nodeSize,
                    lightStatus: entryStatus
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

    private func lightStatus(matching terms: [String]) -> BlueprintLightStatus {
        let groups = lightSummaryData.groups.filter { group in
            let searchableText = "\(group.id) \(group.name)".lowercased()
            return terms.contains { searchableText.contains($0.lowercased()) }
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

private struct BlueprintNodeView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tone: StatusBadgeTone
    let size: CGFloat
    let lightStatus: BlueprintLightStatus
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
                .overlay {
                    Circle()
                        .stroke(lightStatus.color, lineWidth: isPriority ? 3 : 2.5)
                }
                .shadow(color: HomePalette.shadow, radius: isPriority ? 16 : 12, y: isPriority ? 9 : 7)

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
