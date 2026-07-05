struct QuickActionsResponse: Codable, Equatable {
    let ok: Bool
    let actions: [QuickAction]
    let lightGroups: [LightActionGroup]?
}

struct QuickActionResponse: Codable, Equatable {
    let ok: Bool
    let result: QuickActionResult
}
