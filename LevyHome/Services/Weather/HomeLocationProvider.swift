import CoreLocation

protocol HomeLocationProviding {
    func location() async throws -> CLLocation
}

struct StaticHomeLocationProvider: HomeLocationProviding {
    static let levyHome = StaticHomeLocationProvider(
        latitude: 39.5388289,
        longitude: -105.0305231
    )

    init(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees
    ) {
        self.location = CLLocation(latitude: latitude, longitude: longitude)
    }

    private let location: CLLocation

    func location() async throws -> CLLocation { location }
}
