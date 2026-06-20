enum PreviewData {
    static let garageStatus = GarageStatusCardData(
        status: "Closed",
        location: "Main garage",
        detail: "Last checked 2 minutes ago",
        systemImage: "door.garage.closed",
        tone: .success
    )

    static let lightSummary = LightSummaryCardData(
        state: "3 lights on",
        detail: "Kitchen and living room lights are still on.",
        groups: [
            LightGroupSummary(name: "Kitchen", count: "2 on"),
            LightGroupSummary(name: "Living Room", count: "1 on")
        ]
    )

    static let recentImportantEvent = RecentImportantEventData(
        title: "Garage closed",
        detail: "The main garage was closed from the driveway remote.",
        timestamp: "Today at 8:42 AM",
        badgeLabel: "Info",
        tone: .success
    )

    static let quickActions = [
        QuickActionDisplayData(
            id: QuickActionID.openGarage.rawValue,
            request: .openGarage,
            title: "Open Garage",
            subtitle: "Open the main garage door.",
            systemImage: "door.garage.open",
            isEnabled: true,
            requiresConfirmation: true
        ),
        QuickActionDisplayData(
            id: QuickActionID.closeGarage.rawValue,
            request: .closeGarage,
            title: "Close Garage",
            subtitle: "Close the main garage door.",
            systemImage: "door.garage.closed",
            isEnabled: true,
            requiresConfirmation: true
        ),
        QuickActionDisplayData(
            id: QuickActionID.turnOffAllLights.rawValue,
            request: .turnOffAllLights,
            title: "Turn Off All Lights",
            subtitle: "Turn off configured whole-home lighting groups.",
            systemImage: "lightbulb.slash",
            isEnabled: true,
            requiresConfirmation: false
        ),
        QuickActionDisplayData(
            id: "\(QuickActionID.turnOffLightGroup.rawValue).upstairs_hallway",
            request: .turnOffLightGroup(groupId: "upstairs_hallway"),
            title: "Turn Off Kitchen + Living Room",
            subtitle: "Turn off this curated light group.",
            systemImage: "lightswitch.off",
            isEnabled: true,
            requiresConfirmation: false
        )
    ]
}
