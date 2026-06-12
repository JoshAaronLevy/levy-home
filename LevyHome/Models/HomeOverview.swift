import Foundation

struct HomeOverview: Codable, Equatable {
    let garageStatus: GarageStatus
    let lightSummary: LightSummary
    let recentImportantEvent: LevyHomeEvent?
    let generatedAt: String?
    let isPartial: Bool?
}
