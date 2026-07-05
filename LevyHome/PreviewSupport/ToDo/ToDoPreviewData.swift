import Foundation

enum ToDoPreviewData {
    static let today = ToDoDateDefaults.today
    static let tomorrow = ToDoDateDefaults.tomorrow
    static let thisWeek = ToDoDateDefaults.thisWeek
    static let nextMonth = ToDoDateDefaults.nextMonth

    static let users = [
        LevyHomeUser(
            id: 1,
            firstName: "Josh",
            lastName: "Levy",
            email: "josh@example.com",
            mobileDevice: nil,
            lastLogin: nil
        ),
        LevyHomeUser(
            id: 2,
            firstName: "Mallory",
            lastName: "Levy",
            email: "mallory@example.com",
            mobileDevice: nil,
            lastLogin: nil
        )
    ]

    static let dueDateOptions = [
        ToDoDueDateOption(id: "today", title: "Today", tone: .warning, date: today),
        ToDoDueDateOption(id: "tomorrow", title: "Tomorrow", tone: .accent, date: tomorrow),
        ToDoDueDateOption(id: "this-week", title: "This week", tone: .accent, date: thisWeek),
        ToDoDueDateOption(id: "none", title: "No date", tone: .neutral, date: nil)
    ]

    static let recentLocations = [
        ToDoLocation(
            id: 1,
            name: "Home",
            address: nil,
            mapkitTitle: "Home",
            mapkitSubtitle: nil,
            latitude: nil,
            longitude: nil,
            createdBy: 1,
            createdDate: "2026-06-28T15:30:00.000Z",
            lastUsedDate: "2026-06-29T12:00:00.000Z",
            useCount: 8,
            isActive: true,
            favoritedBy: [1, 2]
        ),
        ToDoLocation(
            id: 2,
            name: "Denver Pediatrics",
            address: "123 Wellness Way, Denver, CO",
            mapkitTitle: "Denver Pediatrics",
            mapkitSubtitle: "123 Wellness Way",
            latitude: 39.7392,
            longitude: -104.9903,
            createdBy: 1,
            createdDate: "2026-06-28T15:30:00.000Z",
            lastUsedDate: "2026-06-29T12:00:00.000Z",
            useCount: 3,
            isActive: true,
            favoritedBy: [1, 2]
        ),
        ToDoLocation(
            id: 3,
            name: "Maple Vet Clinic",
            address: "456 Maple St, Denver, CO",
            mapkitTitle: "Maple Vet Clinic",
            mapkitSubtitle: "456 Maple St",
            latitude: 39.75,
            longitude: -104.98,
            createdBy: 2,
            createdDate: "2026-06-28T15:30:00.000Z",
            lastUsedDate: nil,
            useCount: 1,
            isActive: true,
            favoritedBy: [2]
        ),
        ToDoLocation(
            id: 4,
            name: "County office",
            address: nil,
            mapkitTitle: "County office",
            mapkitSubtitle: nil,
            latitude: nil,
            longitude: nil,
            createdBy: 1,
            createdDate: "2026-06-28T15:30:00.000Z",
            lastUsedDate: nil,
            useCount: 1,
            isActive: true,
            favoritedBy: []
        )
    ]

    static let taskSections = [
        ToDoTaskSection(
            id: "appointments",
            title: "Appointments",
            systemImage: "calendar",
            tone: .accent,
            tasks: [
                ToDoTask(
                    id: 1,
                    name: "Schedule dentist",
                    locationIds: nil,
                    date: today,
                    recurring: nil,
                    createdBy: 1,
                    createdDate: today,
                    status: .open,
                    locationDisplayText: "Cherry Creek Dental",
                    isLinkedToFamilyCalendar: false,
                    previewNote: "Find a morning opening next week."
                ),
                ToDoTask(
                    id: 2,
                    name: "Confirm pediatrician paperwork",
                    locationIds: [2],
                    date: today,
                    recurring: nil,
                    createdBy: 2,
                    createdDate: today,
                    status: .open,
                    locationDisplayText: "Denver Pediatrics",
                    isLinkedToFamilyCalendar: true,
                    previewNote: "Bring insurance card and forms."
                )
            ]
        ),
        ToDoTaskSection(
            id: "house-projects",
            title: "House Projects",
            systemImage: "wrench.and.screwdriver",
            tone: .warning,
            tasks: [
                ToDoTask(
                    id: 3,
                    name: "Fix gate latch",
                    locationIds: [1],
                    date: thisWeek,
                    recurring: nil,
                    createdBy: 1,
                    createdDate: today,
                    status: .open,
                    locationDisplayText: "Home",
                    isLinkedToFamilyCalendar: false,
                    previewNote: "Measure latch before hardware store run."
                )
            ]
        ),
        ToDoTaskSection(
            id: "family",
            title: "Family",
            systemImage: "person.2",
            tone: .success,
            tasks: [
                ToDoTask(
                    id: 4,
                    name: "Book summer camp",
                    locationIds: nil,
                    date: thisWeek,
                    recurring: nil,
                    createdBy: 2,
                    createdDate: today,
                    status: .open,
                    locationDisplayText: "Rec center",
                    isLinkedToFamilyCalendar: false,
                    previewNote: "Check weekly availability."
                )
            ]
        ),
        ToDoTaskSection(
            id: "admin",
            title: "Admin",
            systemImage: "doc.text",
            tone: .neutral,
            tasks: [
                ToDoTask(
                    id: 5,
                    name: "Renew passport",
                    locationIds: [4],
                    date: nextMonth,
                    recurring: .quarterly,
                    createdBy: 1,
                    createdDate: today,
                    status: .open,
                    locationDisplayText: "County office",
                    isLinkedToFamilyCalendar: false,
                    previewNote: "Make appointment and print forms."
                )
            ]
        )
    ]
}
