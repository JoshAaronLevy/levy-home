import SwiftUI

struct SeverityBadgeView: View {
    let severity: DisplaySeverity

    var body: some View {
        StatusBadgeView(
            label: label,
            systemImage: systemImage,
            tone: tone
        )
    }

    private var label: String {
        switch severity {
        case .info:
            return "Info"
        case .warning:
            return "Warning"
        case .critical:
            return "Critical"
        case .unknown(let rawValue):
            return rawValue.capitalized
        }
    }

    private var systemImage: String {
        switch severity {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var tone: StatusBadgeTone {
        switch severity {
        case .info:
            return .accent
        case .warning:
            return .warning
        case .critical:
            return .critical
        case .unknown:
            return .neutral
        }
    }
}

#Preview {
    HStack {
        SeverityBadgeView(severity: .info)
        SeverityBadgeView(severity: .warning)
        SeverityBadgeView(severity: .critical)
    }
    .padding()
}
