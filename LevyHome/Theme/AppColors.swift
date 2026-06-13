import SwiftUI

enum AppColors {
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let panelBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let insetPanelBackground = Color(uiColor: .secondarySystemBackground)
    static let panelBorder = Color(uiColor: .separator).opacity(0.35)
    static let mutedText = Color.secondary

    static let accent = adaptive(
        light: UIColor(red: 0.05, green: 0.42, blue: 0.80, alpha: 1.0),
        dark: UIColor(red: 0.36, green: 0.68, blue: 1.0, alpha: 1.0)
    )
    static let success = adaptive(
        light: UIColor(red: 0.07, green: 0.50, blue: 0.31, alpha: 1.0),
        dark: UIColor(red: 0.28, green: 0.78, blue: 0.52, alpha: 1.0)
    )
    static let warning = adaptive(
        light: UIColor(red: 0.72, green: 0.43, blue: 0.08, alpha: 1.0),
        dark: UIColor(red: 1.0, green: 0.69, blue: 0.24, alpha: 1.0)
    )
    static let critical = adaptive(
        light: UIColor(red: 0.74, green: 0.16, blue: 0.16, alpha: 1.0),
        dark: UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0)
    )

    static let accentSoft = adaptive(
        light: UIColor(red: 0.05, green: 0.42, blue: 0.80, alpha: 0.12),
        dark: UIColor(red: 0.36, green: 0.68, blue: 1.0, alpha: 0.22)
    )
    static let successSoft = adaptive(
        light: UIColor(red: 0.07, green: 0.50, blue: 0.31, alpha: 0.12),
        dark: UIColor(red: 0.28, green: 0.78, blue: 0.52, alpha: 0.20)
    )
    static let warningSoft = adaptive(
        light: UIColor(red: 0.72, green: 0.43, blue: 0.08, alpha: 0.14),
        dark: UIColor(red: 1.0, green: 0.69, blue: 0.24, alpha: 0.20)
    )
    static let criticalSoft = adaptive(
        light: UIColor(red: 0.74, green: 0.16, blue: 0.16, alpha: 0.12),
        dark: UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 0.20)
    )
    static let disabledControl = Color(uiColor: .systemGray)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}
