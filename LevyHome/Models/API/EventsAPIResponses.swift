struct EventsResponse: Codable, Equatable {
    let ok: Bool
    let events: [LevyHomeEvent]
}
