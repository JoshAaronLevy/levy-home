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
    let includeDeviceCount: Bool?

    init(
        token: String,
        platform: DevicePlatform,
        provider: PushProvider,
        environment: APNsEnvironment,
        appVersion: String?,
        deviceName: String?,
        includeDeviceCount: Bool? = nil
    ) {
        self.token = token
        self.platform = platform
        self.provider = provider
        self.environment = environment
        self.appVersion = appVersion
        self.deviceName = deviceName
        self.includeDeviceCount = includeDeviceCount
    }
}

struct TestPushRequest: Codable, Equatable {
    let title: String?
    let body: String?
}
