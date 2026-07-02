import SwiftUI

enum AppColors {
    static let pageBackground = adaptive(
        light: UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1.0),
        dark: UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)
    )
    static let panelBackground = adaptive(
        light: UIColor(red: 1.0, green: 0.995, blue: 0.98, alpha: 0.96),
        dark: UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 0.96)
    )
    static let insetPanelBackground = adaptive(
        light: UIColor(red: 0.97, green: 0.965, blue: 0.94, alpha: 0.92),
        dark: UIColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 0.92)
    )
    static let panelBorder = adaptive(
        light: UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 0.09),
        dark: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.11)
    )
    static let text = adaptive(
        light: UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1.0),
        dark: UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
    )
    static let mutedText = adaptive(
        light: UIColor(red: 0.42, green: 0.45, blue: 0.50, alpha: 1.0),
        dark: UIColor(red: 0.64, green: 0.66, blue: 0.70, alpha: 1.0)
    )
    static let surfaceShadow = Color.black.opacity(0.10)

    static let accent = adaptive(
        light: UIColor(red: 0.18, green: 0.43, blue: 0.80, alpha: 1.0),
        dark: UIColor(red: 0.36, green: 0.68, blue: 1.0, alpha: 1.0)
    )
    static let success = adaptive(
        light: UIColor(red: 0.34, green: 0.62, blue: 0.38, alpha: 1.0),
        dark: UIColor(red: 0.28, green: 0.78, blue: 0.52, alpha: 1.0)
    )
    static let warning = adaptive(
        light: UIColor(red: 0.72, green: 0.43, blue: 0.08, alpha: 1.0),
        dark: UIColor(red: 1.0, green: 0.69, blue: 0.24, alpha: 1.0)
    )
    static let critical = adaptive(
        light: UIColor(red: 0.96, green: 0.34, blue: 0.16, alpha: 1.0),
        dark: UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0)
    )

    static let accentSoft = adaptive(
        light: UIColor(red: 0.18, green: 0.43, blue: 0.80, alpha: 0.12),
        dark: UIColor(red: 0.36, green: 0.68, blue: 1.0, alpha: 0.22)
    )
    static let successSoft = adaptive(
        light: UIColor(red: 0.34, green: 0.62, blue: 0.38, alpha: 0.12),
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
