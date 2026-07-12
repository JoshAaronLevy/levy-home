import UIKit

enum ResidentDeviceOwnerDefaults {
    static var defaultName: String {
        ResidentIdentity.inferred(from: UIDevice.current.name)?.rawValue ?? ""
    }
}

extension ResidentIdentity {
    static func inferred(from deviceName: String) -> ResidentIdentity? {
        let normalizedName = deviceName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)

        if normalizedName.contains("josh") {
            return .josh
        }

        if normalizedName.contains("mallory") {
            return .mallory
        }

        return nil
    }
}
