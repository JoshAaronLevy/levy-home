import Foundation

struct GarageCompletionWatchPolicy: Equatable {
    let expectedState: GarageStatus.State
    let inProgressState: GarageStatus.State
    let maximumAttempts: Int
    let pollIntervalNanoseconds: UInt64
    let minimumAttemptsBeforeStableMismatch: Int

    init?(request: QuickActionRequest) {
        pollIntervalNanoseconds = 1_500_000_000
        minimumAttemptsBeforeStableMismatch = 3

        switch request {
        case .openGarage:
            expectedState = .open
            inProgressState = .opening
            maximumAttempts = 12
        case .closeGarage:
            expectedState = .closed
            inProgressState = .closing
            maximumAttempts = 24
        case .turnOffAllLights, .turnOnLightGroup, .turnOffLightGroup, .setThermostatTemperature:
            return nil
        }
    }
}

struct LightingCompletionWatchPolicy: Equatable {
    let expectedState: LightSummary.State
    let maximumAttempts: Int
    let pollIntervalNanoseconds: UInt64

    init(turnOn: Bool) {
        expectedState = turnOn ? .on : .off
        maximumAttempts = 8
        pollIntervalNanoseconds = 750_000_000
    }

    func isSatisfied(in overview: HomeOverview?, groupIds: [String]) -> Bool {
        guard let overview else {
            return false
        }

        let targetIds = Set(groupIds.filter { !$0.isEmpty })

        guard !targetIds.isEmpty else {
            return false
        }

        let groupsById = Dictionary(uniqueKeysWithValues: overview.lightSummary.groups.map { ($0.id, $0) })

        return targetIds.allSatisfy { groupId in
            groupsById[groupId]?.state == expectedState
        }
    }
}

extension GarageStatus.State {
    var displayText: String {
        switch self {
        case .open:
            return "open"
        case .closed:
            return "closed"
        case .opening:
            return "opening"
        case .closing:
            return "closing"
        case .unknown:
            return "unknown"
        case .unrecognized(let rawValue):
            return rawValue
        }
    }

    var isStableGarageState: Bool {
        switch self {
        case .open, .closed:
            return true
        case .opening, .closing, .unknown, .unrecognized:
            return false
        }
    }
}
