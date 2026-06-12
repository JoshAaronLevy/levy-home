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
        tone: .success
    )

    static let quickActions = [
        QuickActionDisplayData(
            title: "Close Garage",
            subtitle: "Available after live status and action support are connected.",
            systemImage: "door.garage.closed"
        ),
        QuickActionDisplayData(
            title: "Turn Off All Lights",
            subtitle: "Will turn off curated whole-home lighting groups.",
            systemImage: "lightbulb.slash"
        ),
        QuickActionDisplayData(
            title: "Turn Off Kitchen + Living Room",
            subtitle: "Will target selected family room lighting groups.",
            systemImage: "lightswitch.off"
        )
    ]
}
