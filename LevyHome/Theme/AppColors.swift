import SwiftUI

enum AppColors {
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let panelBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let panelBorder = Color(uiColor: .separator).opacity(0.35)
    static let mutedText = Color.secondary

    static let accent = Color(red: 0.05, green: 0.42, blue: 0.80)
    static let success = Color(red: 0.07, green: 0.50, blue: 0.31)
    static let warning = Color(red: 0.72, green: 0.43, blue: 0.08)
    static let critical = Color(red: 0.74, green: 0.16, blue: 0.16)

    static let accentSoft = accent.opacity(0.12)
    static let successSoft = success.opacity(0.12)
    static let warningSoft = warning.opacity(0.14)
    static let criticalSoft = critical.opacity(0.12)
}
