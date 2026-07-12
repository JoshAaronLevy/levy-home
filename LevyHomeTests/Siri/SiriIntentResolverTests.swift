import XCTest
@testable import LevyHome

final class SiriIntentResolverTests: XCTestCase {
    func testResolvesCanonicalListsAndEverySupportedAlias() {
        let examples: [(String, SiriListKind)] = [
            ("Shopping", .shopping),
            ("shopping list", .shopping),
            ("grocery list", .shopping),
            ("groceries", .shopping),
            ("To Do", .toDo),
            ("to-do list", .toDo),
            ("todo list", .toDo),
            ("task list", .toDo),
            ("tasks", .toDo)
        ]

        for (title, expectedList) in examples {
            XCTAssertEqual(
                SiriIntentResolver.resolveTargetTaskList(identifier: nil, title: "  \(title.uppercased())  "),
                .resolved(expectedList),
                title
            )
        }
    }

    func testResolvesStableTaskListIdentifiers() {
        XCTAssertEqual(
            SiriIntentResolver.resolveTargetTaskList(
                identifier: SiriListKind.shopping.siriTaskListIdentifier,
                title: "not the displayed name"
            ),
            .resolved(.shopping)
        )
        XCTAssertEqual(
            SiriIntentResolver.resolveTargetTaskList(
                identifier: SiriListKind.toDo.siriTaskListIdentifier,
                title: nil
            ),
            .resolved(.toDo)
        )
    }

    func testDisambiguatesMissingOrConflictingList() {
        XCTAssertEqual(
            SiriIntentResolver.resolveTargetTaskList(identifier: nil, title: nil),
            .disambiguationRequired
        )
        XCTAssertEqual(
            SiriIntentResolver.resolveTargetTaskList(
                identifier: SiriListKind.shopping.siriTaskListIdentifier,
                title: "To Do"
            ),
            .disambiguationRequired
        )
    }

    func testRejectsUnrelatedTaskList() {
        XCTAssertEqual(
            SiriIntentResolver.resolveTargetTaskList(identifier: "reminders", title: "Weekend"),
            .unsupported
        )
    }

    func testResolvesOneTrimmedTitleAndRejectsUnsupportedTitleShapes() {
        XCTAssertEqual(
            SiriIntentResolver.resolveTaskTitles(["  Paper plates  "]),
            .resolved("Paper plates")
        )
        XCTAssertEqual(SiriIntentResolver.resolveTaskTitles(nil), .needsValue)
        XCTAssertEqual(SiriIntentResolver.resolveTaskTitles([" \n "]), .needsValue)
        XCTAssertEqual(
            SiriIntentResolver.resolveTaskTitles(["Paper plates", "Dish soap"]),
            .unsupported
        )
    }
}
