import CoreLocation
import Foundation

private struct HomeWeatherProviderAttempt {
    let name: String
    let provider: CoordinateWeatherSnapshotLoading
    let startDelay: Duration?
}

private struct HomeWeatherProviderFailure {
    let providerName: String
    let error: Error
}

private enum HomeWeatherProviderAttemptResult {
    case success(providerName: String, snapshot: HomeWeatherSnapshot)
    case failure(HomeWeatherProviderFailure)
}

enum HomeWeatherServiceError: LocalizedError {
    case homeLocationUnavailable
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .homeLocationUnavailable:
            return "Home weather location is unavailable."
        case .requestTimedOut:
            return "Home weather request timed out."
        }
    }
}

final class HomeWeatherService: HomeWeatherServicing {
    private let homeLocationProvider: HomeLocationProviding
    private let primaryWeatherProvider: CoordinateWeatherSnapshotLoading
    private let fallbackWeatherProvider: CoordinateWeatherSnapshotLoading?
    private let tertiaryWeatherProvider: CoordinateWeatherSnapshotLoading?
    private let now: () -> Date
    private let providerTimeout: Duration
    private let fallbackStartDelay: Duration
    private let tertiaryStartDelay: Duration
    private let appLogStore: AppLogStore?

    init(
        homeLocationProvider: HomeLocationProviding = StaticHomeLocationProvider.levyHome,
        primaryWeatherProvider: CoordinateWeatherSnapshotLoading = WeatherKitHomeWeatherProvider(),
        fallbackWeatherProvider: CoordinateWeatherSnapshotLoading? = OpenMeteoHomeWeatherProvider(),
        tertiaryWeatherProvider: CoordinateWeatherSnapshotLoading? = NationalWeatherServiceHomeWeatherProvider(),
        now: @escaping () -> Date = Date.init,
        providerTimeout: Duration = .seconds(8),
        fallbackStartDelay: Duration = .seconds(1),
        tertiaryStartDelay: Duration = .seconds(3),
        appLogStore: AppLogStore? = nil
    ) {
        self.homeLocationProvider = homeLocationProvider
        self.primaryWeatherProvider = primaryWeatherProvider
        self.fallbackWeatherProvider = fallbackWeatherProvider
        self.tertiaryWeatherProvider = tertiaryWeatherProvider
        self.now = now
        self.providerTimeout = providerTimeout
        self.fallbackStartDelay = fallbackStartDelay
        self.tertiaryStartDelay = tertiaryStartDelay
        self.appLogStore = appLogStore
    }

    func fetchSnapshot() async throws -> HomeWeatherSnapshot {
        do {
            let location = try await homeLocationProvider.location()
            let fetchedAt = now()
            let attempts = weatherProviderAttempts

            appLogStore?.record(
                level: .info,
                category: "Weather",
                title: "Fetching Home weather",
                detail: "Providers: \(attempts.map(\.name).joined(separator: ", "))"
            )

            let result = try await fetchFirstSuccessfulSnapshot(
                attempts: attempts,
                for: location,
                fetchedAt: fetchedAt
            )

            appLogStore?.record(
                level: .success,
                category: "Weather",
                title: "Loaded Home weather",
                detail: "\(result.providerName): \(Self.temperatureText(result.snapshot.currentTemperature)), \(result.snapshot.conditionDescription)"
            )

            return result.snapshot
        } catch {
            if error.isTaskCancellation {
                appLogStore?.record(
                    level: .info,
                    category: "Weather",
                    title: "Cancelled Home weather refresh",
                    detail: nil
                )
                throw error
            }

            appLogStore?.record(
                level: .error,
                category: "Weather",
                title: "Home weather unavailable",
                detail: error.localizedDescription
            )
            throw error
        }
    }

    private var weatherProviderAttempts: [HomeWeatherProviderAttempt] {
        var attempts = [
            HomeWeatherProviderAttempt(
                name: "WeatherKit",
                provider: primaryWeatherProvider,
                startDelay: nil
            )
        ]

        if let fallbackWeatherProvider {
            attempts.append(
                HomeWeatherProviderAttempt(
                    name: "Open-Meteo",
                    provider: fallbackWeatherProvider,
                    startDelay: fallbackStartDelay
                )
            )
        }

        if let tertiaryWeatherProvider {
            attempts.append(
                HomeWeatherProviderAttempt(
                    name: "National Weather Service",
                    provider: tertiaryWeatherProvider,
                    startDelay: tertiaryStartDelay
                )
            )
        }

        return attempts
    }

    private func fetchFirstSuccessfulSnapshot(
        attempts: [HomeWeatherProviderAttempt],
        for location: CLLocation,
        fetchedAt: Date
    ) async throws -> (providerName: String, snapshot: HomeWeatherSnapshot) {
        let providerTimeout = providerTimeout
        var failures: [HomeWeatherProviderFailure] = []

        return try await withThrowingTaskGroup(of: HomeWeatherProviderAttemptResult.self) { group in
            defer { group.cancelAll() }

            for attempt in attempts {
                group.addTask {
                    do {
                        if let startDelay = attempt.startDelay {
                            try await Task.sleep(for: startDelay)
                        }

                        let snapshot = try await Self.fetchSnapshot(
                            using: attempt.provider,
                            for: location,
                            fetchedAt: fetchedAt,
                            timeout: providerTimeout
                        )

                        return .success(providerName: attempt.name, snapshot: snapshot)
                    } catch {
                        return .failure(
                            HomeWeatherProviderFailure(
                                providerName: attempt.name,
                                error: error
                            )
                        )
                    }
                }
            }

            while let result = try await group.next() {
                switch result {
                case .success(let providerName, let snapshot):
                    return (providerName, snapshot)
                case .failure(let failure):
                    if failure.error.isTaskCancellation {
                        throw failure.error
                    }

                    failures.append(failure)
                    recordProviderFailure(failure)
                }
            }

            throw failures.last?.error ?? HomeWeatherServiceError.requestTimedOut
        }
    }

    private func recordProviderFailure(_ failure: HomeWeatherProviderFailure) {
        appLogStore?.record(
            level: .warning,
            category: "Weather",
            title: "\(failure.providerName) weather failed",
            detail: failure.error.localizedDescription
        )
    }

    private static func fetchSnapshot(
        using provider: CoordinateWeatherSnapshotLoading,
        for location: CLLocation,
        fetchedAt: Date,
        timeout: Duration
    ) async throws -> HomeWeatherSnapshot {
        return try await withThrowingTaskGroup(of: HomeWeatherSnapshot.self) { group in
            defer { group.cancelAll() }

            group.addTask {
                try await provider.fetchSnapshot(
                    for: location,
                    fetchedAt: fetchedAt
                )
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw HomeWeatherServiceError.requestTimedOut
            }

            guard let snapshot = try await group.next() else {
                throw HomeWeatherServiceError.requestTimedOut
            }

            return snapshot
        }
    }

    private static func temperatureText(_ temperature: Measurement<UnitTemperature>) -> String {
        "\(Int(temperature.converted(to: .fahrenheit).value.rounded()))°"
    }
}
