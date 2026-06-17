import Foundation
import XCTest
@testable import LevyHome

final class APIClientTests: XCTestCase {
    private var client: APIClient!
    private var capturedRequests: [URLRequest] = []

    override func setUp() {
        super.setUp()

        capturedRequests = []
        MockURLProtocol.requestHandler = nil

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        client = APIClient(
            baseURL: URL(string: "http://localhost:4000/api-base")!,
            session: session
        )
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        client = nil
        capturedRequests = []

        super.tearDown()
    }

    func testFetchRecentEventsBuildsCurrentEventsRequest() async throws {
        MockURLProtocol.requestHandler = { request in
            self.capturedRequests.append(request)
            return Self.response(
                for: request,
                json: """
                {
                  "ok": true,
                  "events": [
                    \(Self.eventJSON(type: "garage_opened", displaySeverity: "info"))
                  ]
                }
                """
            )
        }

        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "2026-06-14T17:00:00Z")!
        let end = formatter.date(from: "2026-06-15T17:00:00Z")!
        let response = try await client.fetchRecentEvents(limit: 25, start: start, end: end)
        let queryItems = Dictionary(
            uniqueKeysWithValues: (URLComponents(
                url: try XCTUnwrap(capturedRequests.first?.url),
                resolvingAgainstBaseURL: false
            )?.queryItems ?? []).map { ($0.name, $0.value) }
        )

        XCTAssertEqual(response.events.map(\.type), [.garageOpened])
        XCTAssertEqual(capturedRequests.first?.httpMethod, "GET")
        XCTAssertEqual(capturedRequests.first?.url?.path, "/api-base/api/events")
        XCTAssertEqual(queryItems["limit"] ?? nil, "25")
        XCTAssertEqual(queryItems["start"] ?? nil, "2026-06-14T17:00:00.000Z")
        XCTAssertEqual(queryItems["end"] ?? nil, "2026-06-15T17:00:00.000Z")
        XCTAssertEqual(capturedRequests.first?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(capturedRequests.first?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(capturedRequests.first?.value(forHTTPHeaderField: "Pragma"), "no-cache")
        XCTAssertNil(capturedRequests.first?.httpBody)
    }

    func testSupportsExpandedEndpointSurface() async throws {
        MockURLProtocol.requestHandler = { request in
            self.capturedRequests.append(request)

            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api-base/api/home/overview"):
                return Self.response(for: request, json: Self.homeOverviewResponseJSON)
            case ("GET", "/api-base/api/home/actions"):
                return Self.response(for: request, json: Self.quickActionsResponseJSON)
            case ("POST", "/api-base/api/home/actions"):
                return Self.response(for: request, json: Self.quickActionResponseJSON)
            case ("GET", "/api-base/api/notification-preferences"):
                return Self.response(for: request, json: Self.notificationPreferencesResponseJSON)
            case ("PUT", "/api-base/api/notification-preferences"):
                return Self.response(for: request, json: Self.notificationPreferencesResponseJSON)
            case ("POST", "/api-base/api/devices/register"):
                return Self.response(for: request, json: Self.registerDeviceResponseJSON)
            case ("POST", "/api-base/api/debug/send-test-push"):
                return Self.response(for: request, json: Self.testPushResponseJSON)
            case ("GET", "/api-base/health"):
                return Self.response(for: request, json: Self.healthResponseJSON)
            default:
                return Self.response(for: request, statusCode: 404, json: #"{"error":"Unhandled test path"}"#)
            }
        }

        _ = try await client.fetchHomeOverview()
        _ = try await client.fetchQuickActions()
        _ = try await client.performQuickAction(.turnOffLightGroup(groupId: "upstairs_hallway"))
        _ = try await client.fetchNotificationPreferences()
        _ = try await client.updateNotificationPreferences(
            NotificationPreferencesUpdateRequest(
                preferences: [
                    NotificationPreferenceUpdate(category: .garageLeftOpen, isEnabled: true)
                ]
            )
        )
        _ = try await client.registerDevice(
            RegisterDeviceRequest(
                token: "sample-apns-token",
                platform: .iOS,
                provider: .apns,
                environment: .sandbox,
                appVersion: "0.1.0",
                deviceName: "Joshs iPhone"
            )
        )
        _ = try await client.sendTestPush(TestPushRequest(title: "Test", body: "Body"))
        _ = try await client.fetchHealth()

        XCTAssertEqual(capturedRequests.count, 8)
        let quickActions = try await client.fetchQuickActions()
        XCTAssertEqual(quickActions.lightGroups?.map(\.id), ["upstairs_hallway"])
        XCTAssertEqual(capturedRequests[2].jsonBody["actionId"] as? String, "turn_off_light_group")
        XCTAssertEqual(capturedRequests[2].jsonBody["groupId"] as? String, "upstairs_hallway")
        XCTAssertEqual(capturedRequests[4].jsonBody["preferences"] as? [[String: Any]] != nil, true)
        XCTAssertEqual(capturedRequests[5].jsonBody["provider"] as? String, "apns")
        XCTAssertEqual(capturedRequests[6].jsonBody["title"] as? String, "Test")
    }

    func testDecodesServerErrorEnvelope() async {
        MockURLProtocol.requestHandler = { request in
            Self.response(
                for: request,
                statusCode: 400,
                json: #"{"error":"Garage action is unavailable.","code":"action_unavailable"}"#
            )
        }

        await XCTAssertThrowsAPIError(
            try await client.fetchHomeOverview(),
            matches: .server(statusCode: 400, message: "Garage action is unavailable.")
        )
    }

    func testMapsHTTPErrorWithoutEnvelope() async {
        MockURLProtocol.requestHandler = { request in
            Self.response(for: request, statusCode: 503, json: #"{"message":"Down"}"#)
        }

        await XCTAssertThrowsAPIError(
            try await client.fetchHomeOverview(),
            matches: .httpStatus(503)
        )
    }

    func testMapsTransportFailure() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        await XCTAssertThrowsAPIError(try await client.fetchHomeOverview()) { error in
            guard case .transport = error else {
                return false
            }

            return true
        }
    }

    func testRejectsInvalidBaseURLBeforeNetwork() async {
        let client = APIClient(baseURL: URL(string: "ftp://example.com")!)

        await XCTAssertThrowsAPIError(try await client.fetchHomeOverview()) { error in
            guard case .invalidBaseURL("ftp://example.com") = error else {
                return false
            }

            return true
        }
    }

    func testMapsDecodingFailure() async {
        MockURLProtocol.requestHandler = { request in
            Self.response(for: request, json: #"{"ok":true}"#)
        }

        await XCTAssertThrowsAPIError(try await client.fetchRecentEvents()) { error in
            guard case .decoding = error else {
                return false
            }

            return true
        }
    }

    private func XCTAssertThrowsAPIError<T>(
        _ expression: @autoclosure () async throws -> T,
        matches expectedError: APIError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await XCTAssertThrowsAPIError(
            try await expression(),
            file: file,
            line: line
        ) { error in
            error == expectedError
        }
    }

    private func XCTAssertThrowsAPIError<T>(
        _ expression: @autoclosure () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line,
        matches predicate: (APIError) -> Bool
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected APIError", file: file, line: line)
        } catch let error as APIError {
            XCTAssertTrue(predicate(error), "Unexpected APIError: \(error)", file: file, line: line)
        } catch {
            XCTFail("Expected APIError, got \(error)", file: file, line: line)
        }
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        json: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        return (response, Data(json.utf8))
    }

    private static var homeOverviewResponseJSON: String {
        """
        {
          "ok": true,
          "overview": {
            "garageStatus": {
              "state": "closed",
              "displayName": "Main garage",
              "lastUpdatedAt": "2026-06-12T14:00:00Z",
              "isStale": false
            },
            "lightSummary": {
              "state": "off",
              "lightsOnCount": 0,
              "totalLightCount": 12,
              "groups": []
            },
            "recentImportantEvent": null,
            "generatedAt": "2026-06-12T14:00:02Z",
            "isPartial": false
          }
        }
        """
    }

    private static var quickActionsResponseJSON: String {
        """
        {
          "ok": true,
          "actions": [
            {
              "id": "close_garage",
              "title": "Close Garage",
              "subtitle": "Close the main garage door.",
              "isEnabled": true,
              "requiresConfirmation": true,
              "targetName": "Main garage"
            }
          ],
          "lightGroups": [
            {
              "id": "upstairs_hallway",
              "name": "Upstairs Hallway"
            }
          ]
        }
        """
    }

    private static var quickActionResponseJSON: String {
        """
        {
          "ok": true,
          "result": {
            "actionId": "turn_off_light_group",
            "status": "success",
            "message": "The selected lights were turned off.",
            "refreshedHomeOverview": null
          }
        }
        """
    }

    private static var notificationPreferencesResponseJSON: String {
        """
        {
          "ok": true,
          "syncedAt": "2026-06-12T14:00:03Z",
          "preferences": [
            {
              "category": "garage_left_open",
              "isEnabled": true,
              "title": "Garage left open",
              "detail": "Notify when the garage has been open for a while."
            }
          ]
        }
        """
    }

    private static var registerDeviceResponseJSON: String {
        """
        {
          "ok": true,
          "registeredDeviceCount": 1,
          "device": {
            "id": "device-1",
            "platform": "ios",
            "provider": "apns",
            "environment": "sandbox",
            "registeredAt": "2026-06-12T14:00:04Z",
            "lastSeenAt": "2026-06-12T14:00:05Z"
          }
        }
        """
    }

    private static var testPushResponseJSON: String {
        """
        {
          "ok": true,
          "message": "Sent test push.",
          "registeredDeviceCount": 1,
          "sentNotificationCount": 1,
          "sentTicketCount": null,
          "invalidTokenCount": 0,
          "provider": "apns"
        }
        """
    }

    private static var healthResponseJSON: String {
        """
        {
          "ok": true,
          "service": "levy-home-api",
          "registeredDeviceCount": 1,
          "recentEventCount": 2,
          "uptimeSeconds": 12.5
        }
        """
    }

    private static func eventJSON(type: String, displaySeverity: String) -> String {
        """
        {
          "id": "event-\(type)",
          "type": "\(type)",
          "entityId": "cover.sample_garage_door",
          "category": "garage",
          "severity": "normal",
          "source": "home_assistant",
          "occurredAt": "2026-06-12T14:00:00Z",
          "title": "Sample event",
          "message": "Sample event body.",
          "receivedAt": "2026-06-12T14:00:01Z",
          "display": {
            "title": "Sample event",
            "body": "Sample event body.",
            "severity": "\(displaySeverity)"
          },
          "push": {
            "attempted": true,
            "skipped": false,
            "reason": null,
            "ticketCount": 1,
            "invalidTokenCount": 0
          }
        }
        """
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var jsonBody: [String: Any] {
        guard let bodyData else {
            return [:]
        }

        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            return [:]
        }

        return json
    }

    var bodyData: Data? {
        if let httpBody {
            return httpBody
        }

        guard let httpBodyStream else {
            return nil
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while httpBodyStream.hasBytesAvailable {
            let readCount = httpBodyStream.read(buffer, maxLength: bufferSize)

            if readCount < 0 {
                return nil
            }

            if readCount == 0 {
                break
            }

            data.append(buffer, count: readCount)
        }

        return data
    }
}
