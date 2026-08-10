import SwiftUI

enum HomePalette {
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
    static let inactiveLightStatus = adaptive(
        light: UIColor(red: 0.72, green: 0.73, blue: 0.70, alpha: 0.88),
        dark: UIColor(red: 0.66, green: 0.68, blue: 0.68, alpha: 0.86)
    )
    static let shadow = Color.black.opacity(0.10)
    static let blue = Color(red: 0.18, green: 0.43, blue: 0.80)
    static let green = Color(red: 0.34, green: 0.62, blue: 0.38)
    static let amber = Color(red: 0.72, green: 0.43, blue: 0.17)
    static let gold = Color(red: 0.86, green: 0.63, blue: 0.10)
    static let coral = Color(red: 0.96, green: 0.34, blue: 0.16)
    static let indigo = Color(red: 0.31, green: 0.35, blue: 0.85)
    static let temperatureNeutral = Color(red: 0.18, green: 0.19, blue: 0.20)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}
