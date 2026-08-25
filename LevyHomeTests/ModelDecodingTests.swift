import XCTest
@testable import LevyHome

final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodesAllGarageEventTypes() throws {
        let cases: [(String, EventType, DisplaySeverity)] = [
            ("garage_opened", .garageOpened, .info),
            ("garage_closed", .garageClosed, .info),
            ("garage_left_open_10_min", .garageLeftOpen10Min, .warning),
            ("garage_opened_after_hours", .garageOpenedAfterHours, .warning),
            ("garage_still_open_at_10pm", .garageStillOpenAt10PM, .critical)
        ]

        for (rawType, expectedType, expectedSeverity) in cases {
            let event = try decodeEvent(type: rawType, displaySeverity: expectedSeverity.rawValue)

            XCTAssertEqual(event.type, expectedType)
            XCTAssertEqual(event.category, .garage)
            XCTAssertEqual(event.display.severity, expectedSeverity)
            XCTAssertEqual(event.push?.attempted, true)
            XCTAssertEqual(event.entityId, "cover.sample_garage_door")
        }
    }

    func testDecodesDoorbellPlaceholderEvent() throws {
        let event = try decodeEvent(
            type: "doorbell_person_detected",
            displaySeverity: "warning",
            category: "doorbell"
        )

        XCTAssertEqual(event.type, .doorbellPersonDetected)
        XCTAssertEqual(event.category, .doorbell)
        XCTAssertEqual(event.display.severity, .warning)
    }

    func testDecodesLaundryEvents() throws {
        let cases: [(String, EventType)] = [
            ("washer_cycle_finished", .washerCycleFinished),
            ("dryer_cycle_finished", .dryerCycleFinished),
            ("washer_transfer_reminder", .washerTransferReminder)
        ]

        for (rawType, expectedType) in cases {
            let event = try decodeEvent(
                type: rawType,
                displaySeverity: "info",
                category: "laundry"
            )

            XCTAssertEqual(event.type, expectedType)
            XCTAssertEqual(event.category, .laundry)
            XCTAssertEqual(event.display.severity, .info)
            XCTAssertEqual(event.push?.attempted, true)
        }
    }

    func testDecodesRefrigeratorAndFreezerDoorEvents() throws {
        let cases: [(String, EventType, HomeAssistantCategory)] = [
            ("freezer_door_left_open_5_min", .freezerDoorLeftOpen5Min, .freezer),
            ("refrigerator_door_left_open_5_min", .refrigeratorDoorLeftOpen5Min, .refrigerator)
        ]

        for (rawType, expectedType, expectedCategory) in cases {
            let event = try decodeEvent(
                type: rawType,
                displaySeverity: "warning",
                category: expectedCategory.rawValue
            )

            XCTAssertEqual(event.type, expectedType)
            XCTAssertEqual(event.category, expectedCategory)
            XCTAssertEqual(event.display.severity, .warning)
            XCTAssertEqual(event.push?.attempted, true)
        }
    }

    func testDecodesPartnerPresenceEvent() throws {
        let event = try decodeEvent(
            type: "partner_left_home",
            displaySeverity: "info",
            category: "presence"
        )

        XCTAssertEqual(event.type, .partnerLeftHome)
        XCTAssertEqual(event.category, .presence)
        XCTAssertEqual(event.display.severity, .info)
        XCTAssertEqual(event.push?.attempted, true)
    }

    func testDecodesLightingAutomationEvent() throws {
        let event = try decodeEvent(
            type: "study_lights_on",
            displaySeverity: "info",
            category: "lighting"
        )

        XCTAssertEqual(event.type, .studyLightsOn)
        XCTAssertEqual(event.category, .lighting)
        XCTAssertEqual(event.display.severity, .info)
        XCTAssertEqual(event.push?.attempted, true)
    }

    func testDecodesThermostatHighSetpointEvent() throws {
        let event = try decodeEvent(
            type: "thermostat_setpoint_high",
            displaySeverity: "warning",
            category: "thermostat"
        )

        XCTAssertEqual(event.type, .thermostatSetpointHigh)
        XCTAssertEqual(event.category, .thermostat)
        XCTAssertEqual(event.display.severity, .warning)
        XCTAssertEqual(event.push?.attempted, true)
    }

    func testDecodesPhoneActivityEventWithoutPushMetadata() throws {
        let json = """
        {
          "id": "event-phone",
          "type": "phone_state_changed",
          "entityId": "sensor.josh_iphone_battery_level",
          "category": "phone",
          "severity": "normal",
          "source": "home_assistant",
          "occurredAt": "2026-06-15T17:00:00Z",
          "title": "Joshs iPhone changed",
          "message": "82 -> 81",
          "receivedAt": "2026-06-15T17:00:01Z",
          "display": {
            "title": "Joshs iPhone changed",
            "body": "82 -> 81",
            "severity": "info"
          }
        }
        """

        let event = try decode(LevyHomeEvent.self, from: json)

        XCTAssertEqual(event.type, .phoneStateChanged)
        XCTAssertEqual(event.category, .phone)
        XCTAssertEqual(event.entityId, "sensor.josh_iphone_battery_level")
        XCTAssertEqual(event.display.title, "Joshs iPhone changed")
        XCTAssertEqual(event.display.body, "82 -> 81")
        XCTAssertNil(event.push)
    }

    func testUnknownEventAndSeverityFallbacksPreserveRawValues() throws {
        let event = try decodeEvent(
            type: "future_water_leak",
            displaySeverity: "urgent",
            category: "future_category",
            payloadSeverity: "medium"
        )

        XCTAssertEqual(event.type, .unknown("future_water_leak"))
        XCTAssertEqual(event.display.severity, .unknown("urgent"))
        XCTAssertEqual(event.category, .unknown("future_category"))
        XCTAssertEqual(event.severity, .unknown("medium"))
    }

    func testDecodesEventWithOptionalFieldsMissing() throws {
        let json = """
        {
          "id": "event-optional",
          "type": "garage_closed",
          "entityId": "cover.sample_garage_door",
          "occurredAt": "2026-06-12T14:00:00Z",
          "receivedAt": "2026-06-12T14:00:01Z",
          "display": {
            "title": "Garage closed",
            "body": "The garage closed.",
            "severity": "info"
          }
        }
        """

        let event = try decode(LevyHomeEvent.self, from: json)

        XCTAssertNil(event.category)
        XCTAssertNil(event.severity)
        XCTAssertNil(event.source)
        XCTAssertNil(event.title)
        XCTAssertNil(event.message)
        XCTAssertNil(event.push)
    }

    func testDecodesGarageStatusVariants() throws {
        let variants: [(String, GarageStatus.State)] = [
            ("open", .open),
            ("closed", .closed),
            ("opening", .opening),
            ("closing", .closing),
            ("unknown", .unknown)
        ]

        for (rawState, expectedState) in variants {
            let status = try decode(
                GarageStatus.self,
                from: """
                {
                  "state": "\(rawState)",
                  "displayName": "Main garage",
                  "lastUpdatedAt": "2026-06-12T14:00:00Z",
                  "isStale": false
                }
                """
            )

            XCTAssertEqual(status.state, expectedState)
            XCTAssertEqual(status.displayName, "Main garage")
        }
    }

    func testDecodesLightSummaryWithGroups() throws {
        let summary = try decode(
            LightSummary.self,
            from: """
            {
              "state": "partially_on",
              "lightsOnCount": 3,
              "totalLightCount": 12,
              "groups": [
                {
                  "id": "kitchen",
                  "name": "Kitchen",
                  "state": "on",
                  "lightsOnCount": 2,
                  "totalLightCount": 4
                },
                {
                  "id": "living_room",
                  "name": "Living Room",
                  "state": "off",
                  "lightsOnCount": 0,
                  "totalLightCount": 3
                }
              ]
            }
            """
        )

        XCTAssertEqual(summary.state, .partiallyOn)
        XCTAssertEqual(summary.lightsOnCount, 3)
        XCTAssertEqual(summary.groups.map(\.state), [.on, .off])
    }

    func testDecodesHomeOverviewWithRecentImportantEvent() throws {
        let overview = try decode(
            HomeOverview.self,
            from: """
            {
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
              "thermostatStatus": {
                "currentTemperature": 74.2,
                "targetTemperatureLow": 65,
                "targetTemperatureHigh": 70,
                "minimumTemperature": 45,
                "maximumTemperature": 95,
                "temperatureStep": 1,
                "hvacAction": "cooling"
              },
              "roomTemperatures": [
                {
                  "id": "study",
                  "name": "Study",
                  "temperature": 73.94,
                  "isOccupied": true,
                  "lastUpdatedAt": "2026-08-10T02:43:30Z",
                  "isStale": false
                }
              ],
              "occupiedMeanTemperature": 73.8,
              "recentImportantEvent": \(eventJSON(type: "garage_closed", displaySeverity: "info")),
              "generatedAt": "2026-06-12T14:00:02Z",
              "isPartial": false
            }
            """
        )

        XCTAssertEqual(overview.garageStatus.state, .closed)
        XCTAssertEqual(overview.lightSummary.state, .off)
        XCTAssertEqual(overview.thermostatStatus?.currentTemperature, 74.2)
        XCTAssertEqual(overview.thermostatStatus?.targetTemperatureLow, 65)
        XCTAssertEqual(overview.thermostatStatus?.targetTemperatureHigh, 70)
        XCTAssertEqual(overview.thermostatStatus?.minimumTemperature, 45)
        XCTAssertEqual(overview.thermostatStatus?.maximumTemperature, 95)
        XCTAssertEqual(overview.thermostatStatus?.temperatureStep, 1)
        XCTAssertEqual(overview.thermostatStatus?.hvacAction, "cooling")
        XCTAssertEqual(overview.roomTemperatures?.first?.id, "study")
        XCTAssertEqual(overview.roomTemperatures?.first?.temperature, 73.94)
        XCTAssertEqual(overview.roomTemperatures?.first?.isOccupied, true)
        XCTAssertEqual(overview.occupiedMeanTemperature, 73.8)
        XCTAssertEqual(overview.recentImportantEvent?.type, .garageClosed)
        XCTAssertEqual(overview.isPartial, false)
    }

    func testOccupiedMeanTemperatureDifferenceUsesTheDisplayedWholeDegreeThresholds() throws {
        let neutralCooler = try XCTUnwrap(
            OccupiedMeanTemperatureDifference(occupiedMeanTemperature: 68, thermostatTemperature: 70)
        )
        let blueCooler = try XCTUnwrap(
            OccupiedMeanTemperatureDifference(occupiedMeanTemperature: 67, thermostatTemperature: 70)
        )
        let neutralWarmer = try XCTUnwrap(
            OccupiedMeanTemperatureDifference(occupiedMeanTemperature: 72, thermostatTemperature: 70)
        )
        let yellowWarmer = try XCTUnwrap(
            OccupiedMeanTemperatureDifference(occupiedMeanTemperature: 73, thermostatTemperature: 70)
        )
        let redWarmer = try XCTUnwrap(
            OccupiedMeanTemperatureDifference(occupiedMeanTemperature: 75, thermostatTemperature: 70)
        )

        XCTAssertEqual(neutralCooler.degrees, -2)
        XCTAssertEqual(neutralCooler.tone, .neutral)
        XCTAssertEqual(blueCooler.tone, .cooler)
        XCTAssertEqual(neutralWarmer.displayText, "+2°")
        XCTAssertEqual(neutralWarmer.tone, .neutral)
        XCTAssertEqual(yellowWarmer.tone, .warmer)
        XCTAssertEqual(redWarmer.tone, .muchWarmer)
        XCTAssertNil(OccupiedMeanTemperatureDifference(occupiedMeanTemperature: nil, thermostatTemperature: 70))
    }

    func testTemperatureBlueprintMeanDisplayUsesEveryRoomOnlyWhenAllAreExplicitlyUnoccupied() {
        let occupiedDisplay = TemperatureBlueprintMeanDisplay(
            occupiedMeanTemperature: 73.8,
            roomTemperatures: [
                roomTemperature(id: "study", temperature: 70, isOccupied: true),
                roomTemperature(id: "nursery", temperature: 74, isOccupied: false)
            ]
        )
        let fallbackDisplay = TemperatureBlueprintMeanDisplay(
            occupiedMeanTemperature: 99,
            roomTemperatures: [
                roomTemperature(id: "study", temperature: 70, isOccupied: false),
                roomTemperature(id: "kitchen_family", temperature: 72, isOccupied: false),
                roomTemperature(id: "nursery", temperature: 74, isOccupied: false)
            ]
        )

        XCTAssertEqual(occupiedDisplay.temperature, 73.8)
        XCTAssertFalse(occupiedDisplay.usesAllRoomsFallback)
        XCTAssertEqual(fallbackDisplay.temperature, 72)
        XCTAssertTrue(fallbackDisplay.usesAllRoomsFallback)
    }

    func testTemperatureBlueprintMeanDisplayDoesNotUseAPartialOrUnknownOccupancyFallback() {
        let partialDisplay = TemperatureBlueprintMeanDisplay(
            occupiedMeanTemperature: 73.8,
            roomTemperatures: [
                roomTemperature(id: "study", temperature: 70, isOccupied: false),
                roomTemperature(id: "nursery", temperature: nil, isOccupied: false)
            ]
        )
        let unknownOccupancyDisplay = TemperatureBlueprintMeanDisplay(
            occupiedMeanTemperature: 73.8,
            roomTemperatures: [
                roomTemperature(id: "study", temperature: 70, isOccupied: nil),
                roomTemperature(id: "nursery", temperature: 74, isOccupied: false)
            ]
        )

        XCTAssertEqual(partialDisplay.temperature, 73.8)
        XCTAssertFalse(partialDisplay.usesAllRoomsFallback)
        XCTAssertEqual(unknownOccupancyDisplay.temperature, 73.8)
        XCTAssertFalse(unknownOccupancyDisplay.usesAllRoomsFallback)
    }

    func testThermostatSetpointDraftAdjustsOnlyTheOppositeSetpointNeededForTheMinimumDelta() throws {
        let status = ThermostatStatus(
            currentTemperature: 72,
            targetTemperatureLow: 65,
            targetTemperatureHigh: 74,
            minimumTemperature: 45,
            maximumTemperature: 95,
            temperatureStep: 0.5,
            hvacAction: "idle",
            lastUpdatedAt: nil,
            isStale: false
        )
        var draft = try XCTUnwrap(ThermostatSetpointDraft(status: status))
        XCTAssertEqual(ThermostatSetpointDraft.minimumDelta, 6)
        XCTAssertEqual(draft.step, 1)
        XCTAssertEqual(draft.availableMinSetpoints.first, 45)
        XCTAssertEqual(draft.availableMinSetpoints.last, 89)
        XCTAssertEqual(draft.availableMaxSetpoints.first, 51)
        XCTAssertEqual(draft.availableMaxSetpoints.last, 95)

        draft.setHigh(72)
        XCTAssertEqual(draft.low, 65)
        XCTAssertEqual(draft.high, 72)

        draft.setHigh(71)
        XCTAssertEqual(draft.low, 65)
        XCTAssertEqual(draft.high, 71)

        draft.setHigh(70)
        XCTAssertEqual(draft.low, 64)
        XCTAssertEqual(draft.high, 70)

        draft.setLow(66)
        XCTAssertEqual(draft.low, 66)
        XCTAssertEqual(draft.high, 72)
        XCTAssertTrue(draft.isValid)
    }

    func testDecodesQuickActionsAndResults() throws {
        let action = try decode(
            QuickAction.self,
            from: """
            {
              "id": "close_garage",
              "title": "Close Garage",
              "subtitle": "Close the main garage door.",
              "isEnabled": true,
              "requiresConfirmation": true,
              "targetName": "Main garage"
            }
            """
        )

        XCTAssertEqual(action.id, .closeGarage)
        XCTAssertEqual(action.requiresConfirmation, true)

        let result = try decode(
            QuickActionResult.self,
            from: """
            {
              "actionId": "turn_off_all_lights",
              "status": "success",
              "message": "All selected lights were turned off.",
              "refreshedHomeOverview": null
            }
            """
        )

        XCTAssertEqual(result.actionId, .turnOffAllLights)
        XCTAssertEqual(result.status, .success)
        XCTAssertNil(result.refreshedHomeOverview)
    }

    func testDecodesNotificationPreferences() throws {
        let preferences = try decode(
            [NotificationPreference].self,
            from: """
            [
              {
                "category": "garage_opened",
                "isEnabled": true,
                "title": "Garage opened",
                "detail": "Notify when the garage opens."
              },
              {
                "category": "garage_closed",
                "isEnabled": true
              },
              {
                "category": "garage_left_open",
                "isEnabled": true
              },
              {
                "category": "garage_after_hours",
                "isEnabled": true
              },
              {
                "category": "garage_still_open_at_10pm",
                "isEnabled": true
              },
              {
                "category": "partner_presence",
                "isEnabled": true,
                "title": "Partner presence",
                "detail": "Notify when your partner leaves or arrives home."
              },
              {
                "category": "doorbell",
                "isEnabled": true
              },
              {
                "category": "laundry",
                "isEnabled": true,
                "title": "Laundry",
                "detail": "Notify when the washer or dryer cycle finishes."
              },
              {
                "category": "freezer",
                "isEnabled": true,
                "title": "Freezer door",
                "detail": "Notify when the freezer door has been left open."
              },
              {
                "category": "refrigerator",
                "isEnabled": true,
                "title": "Refrigerator door",
                "detail": "Notify when the refrigerator door has been left open."
              },
              {
                "category": "thermostat_setpoint_high",
                "isEnabled": true,
                "title": "Thermostat high setpoint",
                "detail": "Notify when the thermostat high setpoint is raised above 72°."
              },
              {
                "category": "weather_alerts",
                "isEnabled": true,
                "title": "Weather alerts",
                "detail": "Notify before precipitation."
              },
              {
                "category": "lighting_automation",
                "isEnabled": true,
                "title": "Lighting automations",
                "detail": "Notify when selected lighting automations finish."
              }
            ]
            """
        )

        XCTAssertEqual(
            preferences.map(\.category),
            [
                .garageOpened,
                .garageClosed,
                .garageLeftOpen,
                .garageAfterHours,
                .garageStillOpenAt10PM,
                .laundry,
                .freezer,
                .refrigerator,
                .partnerPresence,
                .doorbell,
                .thermostatSetpointHigh,
                .weatherAlerts,
                .lightingAutomation
            ]
        )
        XCTAssertTrue(preferences.allSatisfy(\.isEnabled))
        XCTAssertNil(preferences[1].title)
        XCTAssertNil(preferences[1].detail)
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }

    private func roomTemperature(id: String, temperature: Double?, isOccupied: Bool?) -> RoomTemperatureReading {
        RoomTemperatureReading(
            id: id,
            name: id,
            temperature: temperature,
            isOccupied: isOccupied,
            lastUpdatedAt: nil,
            isStale: false
        )
    }

    private func decodeEvent(
        type: String,
        displaySeverity: String,
        category: String = "garage",
        payloadSeverity: String = "normal"
    ) throws -> LevyHomeEvent {
        try decode(
            LevyHomeEvent.self,
            from: eventJSON(
                type: type,
                displaySeverity: displaySeverity,
                category: category,
                payloadSeverity: payloadSeverity
            )
        )
    }

    private func eventJSON(
        type: String,
        displaySeverity: String,
        category: String = "garage",
        payloadSeverity: String = "normal"
    ) -> String {
        """
        {
          "id": "event-\(type)",
          "type": "\(type)",
          "entityId": "cover.sample_garage_door",
          "category": "\(category)",
          "severity": "\(payloadSeverity)",
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
