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
                "presence": [
                  {
                    "person": "Josh",
                    "state": "away",
                    "entityId": "device_tracker.josh_iphone",
                    "deviceName": "Joshs iPhone",
                    "lastUpdatedAt": "2026-06-12T13:59:00Z",
                    "isStale": false
                  }
                ],
                "recentImportantEvent": null,
                "generatedAt": "2026-06-12T14:00:02Z",
                "isPartial": false
              }
            }
            """
        )

        XCTAssertEqual(response.overview.garageStatus.state, .open)
        XCTAssertEqual(response.overview.lightSummary.state, .partiallyOn)
        XCTAssertEqual(response.overview.presence?.first?.person, "Josh")
        XCTAssertEqual(response.overview.presence?.first?.state, .away)
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

    func testDecodesUsersResponse() throws {
        let response = try decode(
            UsersResponse.self,
            from: """
            {
              "ok": true,
              "generatedAt": "2026-06-28T15:30:00.000Z",
              "users": [
                {
                  "id": 1,
                  "firstName": "Josh",
                  "lastName": "Levy",
                  "email": "josh@example.com",
                  "mobileDevice": null,
                  "lastLogin": null
                },
                {
                  "id": 2,
                  "firstName": "Mallory",
                  "lastName": "Levy",
                  "email": "mallory@example.com",
                  "mobileDevice": "Mallory iPhone",
                  "lastLogin": "2026-06-28T15:29:00.000Z"
                }
              ]
            }
            """
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.users.map(\.id), [1, 2])
        XCTAssertEqual(response.users.first?.fullName, "Josh Levy")
        XCTAssertEqual(response.users.first?.initials, "JL")
        XCTAssertEqual(response.users.last?.mobileDevice, "Mallory iPhone")
        XCTAssertEqual(response.users.last?.lastLogin, "2026-06-28T15:29:00.000Z")
    }

    func testDecodesToDoLocationsResponse() throws {
        let response = try decode(
            ToDoLocationsResponse.self,
            from: """
            {
              "ok": true,
              "generatedAt": "2026-06-28T15:30:00.000Z",
              "locations": [
                {
                  "id": 2,
                  "name": "Denver Pediatrics",
                  "address": "123 Wellness Way, Denver, CO",
                  "mapkitTitle": "Denver Pediatrics",
                  "mapkitSubtitle": "123 Wellness Way",
                  "latitude": 39.7392,
                  "longitude": -104.9903,
                  "createdBy": 1,
                  "createdDate": "2026-06-28T15:30:00.000Z",
                  "lastUsedDate": "2026-06-29T12:00:00.000Z",
                  "useCount": 3,
                  "isActive": true,
                  "favoritedBy": [1, 2]
                }
              ]
            }
            """
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.locations.first?.id, 2)
        XCTAssertEqual(response.locations.first?.mapkitTitle, "Denver Pediatrics")
        XCTAssertEqual(response.locations.first?.latitude, 39.7392)
        XCTAssertEqual(response.locations.first?.favoritedBy, [1, 2])
    }

    func testDecodesShoppingListResponse() throws {
        let response = try decode(
            ShoppingListResponse.self,
            from: """
            {
              "ok": true,
              "generatedAt": "2026-06-22T12:31:00.000Z",
              "items": [
                {
                  "id": 1,
                  "name": "Whole milk",
                  "brand": "Horizon",
                  "quantity": 2,
                  "notes": "Half gallon",
                  "purchased": false,
                  "created": "2026-06-22T12:00:00.000Z",
                  "updated": "2026-06-22T12:30:00.000Z",
                  "categoryId": 3,
                  "image": "https://example.test/milk.png",
                  "storeListings": [
                    {
                      "storeId": 1,
                      "storeName": "Target",
                      "source": "manual",
                      "availability": {
                        "status": "unknown"
                      }
                    },
                    {
                      "storeId": 2,
                      "storeName": "King Soopers",
                      "krogerLocationId": "62000008",
                      "aisle": {
                        "display": "13:2"
                      },
                      "inventory": {
                        "stockLevel": "LOW"
                      }
                    }
                  ]
                }
              ],
              "stores": [
                {
                  "id": 1,
                  "name": "Target",
                  "logo": "target"
                }
              ],
              "categories": [
                {
                  "id": 3,
                  "name": "Dairy"
                }
              ]
            }
            """
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.items.first?.name, "Whole milk")
        XCTAssertEqual(response.items.first?.storeListings.map(\.storeId), [1, 2])
        XCTAssertEqual(response.items.first?.storeListings.last?.aisle?.display, "13:2")
        XCTAssertEqual(response.items.first?.storeListings.last?.inventory?["stockLevel"]?.stringValue, "LOW")
        XCTAssertEqual(response.items.first?.categoryId, 3)
        XCTAssertEqual(response.stores.first?.name, "Target")
        XCTAssertEqual(response.categories.first?.name, "Dairy")
    }

    func testDecodesShoppingTripLiveMessagesAndPreservesUnknownTypes() throws {
        let decoder = JSONDecoder()
        let tripJSON = #"""
        {
          "id": "fca7f84a-8527-4a58-90b5-a78e4cde5b16",
          "status": "active",
          "startedBy": "Josh",
          "startedAt": "2026-07-11T18:00:00.000Z",
          "endedBy": null,
          "endedAt": null,
          "pickedUpCount": 1,
          "remainingCount": 2,
          "totalItemCount": 3,
          "estimatedTotalCents": 1275,
          "pricedPickedItemCount": 1,
          "unpricedPickedItemCount": 0,
          "currencyCode": "USD",
          "version": 4
        }
        """#

        for (type, expected) in [
            ("trip_started", "started"),
            ("trip_updated", "updated"),
            ("trip_ended", "ended")
        ] {
            let message = try decoder.decode(
                ShoppingListLiveMessage.self,
                from: Data("""
                {"type":"\(type)","trip":\(tripJSON),"mutationId":"7dfadc16-69a0-448e-a5a9-c4eaf79d2e44","serverTime":"2026-07-11T18:01:00.000Z"}
                """.utf8)
            )

            switch (expected, message) {
            case ("started", .tripStarted(let trip, let mutationId, _)),
                 ("updated", .tripUpdated(let trip, let mutationId, _)),
                 ("ended", .tripEnded(let trip, let mutationId, _)):
                XCTAssertEqual(trip.id, "fca7f84a-8527-4a58-90b5-a78e4cde5b16")
                XCTAssertEqual(trip.estimatedTotalCents, 1275)
                XCTAssertEqual(mutationId, "7dfadc16-69a0-448e-a5a9-c4eaf79d2e44")
            default:
                XCTFail("Expected \(expected) shopping trip message.")
            }
        }

        let unknown = try decoder.decode(
            ShoppingListLiveMessage.self,
            from: Data(#"{"type":"future_trip_event"}"#.utf8)
        )
        XCTAssertEqual(unknown, .unknown(type: "future_trip_event"))
    }

    func testDecodesKrogerProductDiagnosticResponse() throws {
        let response = try decode(
            KrogerProductDiagnosticResponse.self,
            from: """
            {
              "ok": false,
              "query": "Soy Milk",
              "generatedAt": "2026-06-23T12:31:00.000Z",
              "stage": "token",
              "outputFilePath": "/tmp/kroger-product-response.json",
              "normalizedOutputFilePath": "/tmp/kroger-products-normalized.json",
              "tokenStatusCode": 401,
              "productStatusCode": null,
              "products": [
                {
                  "productId": "0003700008411",
                  "upc": "0003700008411",
                  "productPageURI": "/p/luvs-diapers/0003700008411",
                  "aisles": [
                    {
                      "bayNumber": 2,
                      "description": "Baby",
                      "number": "8"
                    }
                  ],
                  "brand": "Luvs",
                  "name": "Luvs Disposable Baby Diapers",
                  "description": "Luvs Disposable Baby Diapers",
                  "image": "https://www.kroger.com/product/images/large/front/0003700008411",
                  "storeListings": [
                    {
                      "storeId": 2,
                      "storeName": "King Soopers",
                      "krogerLocationId": "62000008",
                      "aisle": {
                        "display": "8:2"
                      },
                      "price": {
                        "regular": 9.29,
                        "promo": 6.99
                      },
                      "inventory": {
                        "stockLevel": "LOW"
                      }
                    }
                  ]
                }
              ],
              "error": "Kroger token request returned HTTP 401."
            }
            """
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.query, "Soy Milk")
        XCTAssertEqual(response.stage, "token")
        XCTAssertEqual(response.tokenStatusCode, 401)
        XCTAssertNil(response.productStatusCode)
        XCTAssertEqual(response.normalizedOutputFilePath, "/tmp/kroger-products-normalized.json")
        XCTAssertEqual(response.products.first?.brand, "Luvs")
        XCTAssertEqual(response.products.first?.name, "Luvs Disposable Baby Diapers")
        XCTAssertEqual(response.products.first?.aisles.first?.bayNumber, "2")
        XCTAssertEqual(response.products.first?.image, "https://www.kroger.com/product/images/large/front/0003700008411")
        XCTAssertEqual(response.products.first?.storeListings.first?.price?.promo, 6.99)
        XCTAssertEqual(response.products.first?.storeListings.first?.inventory?["stockLevel"]?.stringValue, "LOW")
        XCTAssertEqual(response.error, "Kroger token request returned HTTP 401.")
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
        let openGarage = try encodeJSON(QuickActionRequest.openGarage)
        let closeGarage = try encodeJSON(QuickActionRequest.closeGarage)
        let turnOffAllLights = try encodeJSON(QuickActionRequest.turnOffAllLights)
        let turnOnLightGroup = try encodeJSON(QuickActionRequest.turnOnLightGroup(groupId: "upstairs_hallway"))
        let turnOffLightGroup = try encodeJSON(QuickActionRequest.turnOffLightGroup(groupId: "upstairs_hallway"))

        XCTAssertEqual(openGarage["actionId"] as? String, "open_garage")
        XCTAssertNil(openGarage["groupId"])
        XCTAssertEqual(closeGarage["actionId"] as? String, "close_garage")
        XCTAssertNil(closeGarage["groupId"])
        XCTAssertEqual(turnOffAllLights["actionId"] as? String, "turn_off_all_lights")
        XCTAssertNil(turnOffAllLights["groupId"])
        XCTAssertEqual(turnOnLightGroup["actionId"] as? String, "turn_on_light_group")
        XCTAssertEqual(turnOnLightGroup["groupId"] as? String, "upstairs_hallway")
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
