import SwiftUI

struct AutomationShortcut: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tone: ShortcutTone
    let action: QuickActionDisplayData?
    let isAvailable: Bool
}

enum ShortcutTone {
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
