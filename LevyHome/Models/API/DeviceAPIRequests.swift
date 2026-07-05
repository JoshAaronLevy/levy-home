enum DevicePlatform: String, Codable, Equatable {
    case iOS = "ios"
}

enum PushProvider: String, Codable, Equatable {
    case apns
}

enum APNsEnvironment: String, Codable, Equatable {
    case sandbox
    case production
}

struct RegisterDeviceRequest: Codable, Equatable {
    let token: String
    let platform: DevicePlatform
    let provider: PushProvider
    let environment: APNsEnvironment
    let appVersion: String?
    let deviceName: String?
}

struct TestPushRequest: Codable, Equatable {
    let title: String?
    let body: String?
}
