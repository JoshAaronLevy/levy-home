import ActivityKit
import Foundation

struct ShoppingTripActivityAttributes: ActivityAttributes, Codable, Hashable, Sendable {
    typealias ContentState = ShoppingTripActivityState

    let tripID: String
    let startedByName: String
    let startedAtEpochSeconds: Int
}

struct ShoppingTripActivityState: Codable, Hashable, Sendable {
    let status: String
    let pickedUpCount: Int
    let remainingCount: Int
    let totalItemCount: Int
    let estimatedTotalCents: Int
    let pricedPickedItemCount: Int
    let unpricedPickedItemCount: Int
    let currencyCode: String
    let stateVersion: Int
    let updatedAtEpochSeconds: Int

    var isCompleted: Bool {
        switch status.lowercased() {
        case "completed", "ended":
            return true
        default:
            return false
        }
    }
}
