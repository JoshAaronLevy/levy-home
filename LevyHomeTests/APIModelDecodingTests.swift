import XCTest
@testable import LevyHome

final class APIModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func testDecodesEventsResponse() throws {
        let response = try decode(
            EventsResponse.self,
            from: """
            {
              "ok": true,
              "events": [
                \(eventJSON(type: "garage_opened", displaySeverity: "info")),
                \(eventJSON(type: "garage_left_open_10_min", displaySeverity: "warning"))
              ]
            }
            """
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.events.map(\.type), [.garageOpened, .garageLeftOpen10Min])
    }

    func testDecodesHomeOverviewResponse() throws {
        let response = try decode(
            HomeOverviewResponse.self,
            from: """
            {
              "ok": true,
              "overview": {
                "garageStatus": {
                  "state": "open",
                  "displayName": "Main garage",
                  "lastUpdatedAt": "2026-06-12T14:00:00Z",
                  "isStale": false
                },
                "lightSummary": {
                  "state": "partially_on",
                  "lightsOnCount": 4,
                  "totalLightCount": 12,
                  "groups": []
                },
                "recentImportantEvent": null,
                "generatedAt": "2026-06-12T14:00:02Z",
                "isPartial": false
              }
            }
            """
        )

        XCTAssertEqual(response.overview.garageStatus.state, .open)
        XCTAssertEqual(response.overview.lightSummary.state, .partiallyOn)
    }

    func testDecodesQuickActionResponse() throws {
        let response = try decode(
            QuickActionResponse.self,
            from: """
            {
              "ok": true,
              "result": {
                "actionId": "close_garage",
                "status": "success",
                "message": "Garage close requested.",
                "refreshedHomeOverview": null
              }
            }
            """
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.result.actionId, .closeGarage)
        XCTAssertEqual(response.result.status, .success)
    }

    func testDecodesNotificationPreferencesResponse() throws {
        let response = try decode(
            NotificationPreferencesResponse.self,
            from: """
            {
              "ok": true,
              "syncedAt": "2026-06-12T14:00:03Z",
              "preferences": [
                {
                  "category": "garage_opened",
                  "isEnabled": true,
                  "title": "Garage opened",
                  "detail": "Notify when the garage opens."
                },
                {
                  "category": "garage_left_open",
                  "isEnabled": false,
                  "title": null,
                  "detail": null
                }
              ]
            }
            """
        )

        XCTAssertEqual(response.preferences.map(\.category), [.garageOpened, .garageLeftOpen])
        XCTAssertEqual(response.preferences.map(\.isEnabled), [true, false])
        XCTAssertEqual(response.syncedAt, "2026-06-12T14:00:03Z")
    }

    func testDecodesRegisterDeviceResponse() throws {
        let response = try decode(
            RegisterDeviceResponse.self,
            from: """
            {
              "ok": true,
              "registeredDeviceCount": 2,
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
        )

        XCTAssertEqual(response.registeredDeviceCount, 2)
        XCTAssertEqual(response.device?.platform, .iOS)
        XCTAssertEqual(response.device?.provider, .apns)
        XCTAssertEqual(response.device?.environment, .sandbox)
    }

    func testDecodesTestPushResponse() throws {
        let response = try decode(
            TestPushResponse.self,
            from: """
            {
              "ok": true,
              "message": "Sent test push.",
              "registeredDeviceCount": 2,
              "sentNotificationCount": 1,
              "sentTicketCount": 1,
              "invalidTokenCount": 0,
              "provider": "apns"
            }
            """
        )

        XCTAssertEqual(response.message, "Sent test push.")
        XCTAssertEqual(response.sentNotificationCount, 1)
        XCTAssertEqual(response.sentTicketCount, 1)
        XCTAssertEqual(response.provider, .apns)
    }

    func testDecodesAPIErrorResponse() throws {
        let response = try decode(
            APIErrorResponse.self,
            from: """
            {
              "error": "Home overview is unavailable.",
              "code": "home_unavailable"
            }
            """
        )

        XCTAssertEqual(response.error, "Home overview is unavailable.")
        XCTAssertEqual(response.code, "home_unavailable")
    }

    func testEncodesCuratedQuickActionRequestsOnly() throws {
        let closeGarage = try encodeJSON(QuickActionRequest.closeGarage)
        let turnOffAllLights = try encodeJSON(QuickActionRequest.turnOffAllLights)
        let turnOffLightGroup = try encodeJSON(QuickActionRequest.turnOffLightGroup(groupId: "upstairs_hallway"))

        XCTAssertEqual(closeGarage["actionId"] as? String, "close_garage")
        XCTAssertNil(closeGarage["groupId"])
        XCTAssertEqual(turnOffAllLights["actionId"] as? String, "turn_off_all_lights")
        XCTAssertNil(turnOffAllLights["groupId"])
        XCTAssertEqual(turnOffLightGroup["actionId"] as? String, "turn_off_light_group")
        XCTAssertEqual(turnOffLightGroup["groupId"] as? String, "upstairs_hallway")
    }

    func testEncodesProviderAwareRegisterDeviceRequest() throws {
        let request = RegisterDeviceRequest(
            token: "sample-apns-token",
            platform: .iOS,
            provider: .apns,
            environment: .sandbox,
            appVersion: "0.1.0",
            deviceName: "Joshs iPhone"
        )

        let json = try encodeJSON(request)

        XCTAssertEqual(json["token"] as? String, "sample-apns-token")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(json["provider"] as? String, "apns")
        XCTAssertEqual(json["environment"] as? String, "sandbox")
    }

    func testEncodesProviderAwareNotificationPreferenceSyncRequest() throws {
        let request = NotificationPreferencesUpdateRequest(
            preferences: [
                NotificationPreferenceUpdate(category: .garageOpened, isEnabled: true),
                NotificationPreferenceUpdate(category: .garageLeftOpen, isEnabled: false)
            ],
            deviceToken: "sample-apns-token",
            provider: .apns,
            environment: .sandbox
        )

        let json = try encodeJSON(request)
        let preferences = try XCTUnwrap(json["preferences"] as? [[String: Any]])

        XCTAssertEqual(json["deviceToken"] as? String, "sample-apns-token")
        XCTAssertEqual(json["provider"] as? String, "apns")
        XCTAssertEqual(json["environment"] as? String, "sandbox")
        XCTAssertEqual(preferences[0]["category"] as? String, "garage_opened")
        XCTAssertEqual(preferences[0]["isEnabled"] as? Bool, true)
        XCTAssertEqual(preferences[1]["category"] as? String, "garage_left_open")
        XCTAssertEqual(preferences[1]["isEnabled"] as? Bool, false)
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func eventJSON(type: String, displaySeverity: String) -> String {
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
