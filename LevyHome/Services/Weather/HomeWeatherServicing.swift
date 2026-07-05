import CoreLocation
import Foundation

protocol HomeWeatherServicing {
    func fetchSnapshot() async throws -> HomeWeatherSnapshot
}

protocol CoordinateWeatherSnapshotLoading {
    func fetchSnapshot(
        for location: CLLocation,
        fetchedAt: Date
    ) async throws -> HomeWeatherSnapshot
}
