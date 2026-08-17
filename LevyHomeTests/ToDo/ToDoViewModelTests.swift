import Foundation
import XCTest
@testable import LevyHome

@MainActor
final class ToDoViewModelTests: XCTestCase {
    private var client: APIClient!
    private var capturedRequests: CapturedRequestStore!

    override func setUp() {
        super.setUp()

        capturedRequests = CapturedRequestStore()
        ToDoMockURLProtocol.requestHandler = nil

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ToDoMockURLProtocol.self]
        client = APIClient(
            baseURL: URL(string: "http://localhost:4000")!,
            session: URLSession(configuration: configuration)
        )
    }

    override func tearDown() {
        ToDoMockURLProtocol.requestHandler = nil
        capturedRequests = nil
        client = nil

        super.tearDown()
    }

    func testLoadPopulatesSharedListUsersAndSections() async {
        ToDoMockURLProtocol.requestHandler = { request in
            self.capturedRequests.append(request)

            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/todo-list"):
                return Self.response(for: request, json: Self.toDoListJSON(status: "open"))
            case ("GET", "/api/users"):
                return Self.response(for: request, json: Self.usersJSON)
            default:
                return Self.response(for: request, statusCode: 404, json: #"{"error":"Unhandled"}"#)
            }
        }

        let viewModel = ToDoViewModel()
        await viewModel.load(apiClient: client)

        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.items.map(\.id), [1])
        XCTAssertEqual(viewModel.users.map(\.firstName), ["Josh", "Mallory"])
        XCTAssertEqual(viewModel.sections.first?.tasks.first?.name, "Schedule dentist")
        XCTAssertEqual(viewModel.sections.first?.tasks.first?.locationIds, [2])
        XCTAssertEqual(viewModel.sections.first?.tasks.first?.notes, "Bring insurance card.")
        XCTAssertEqual(viewModel.sections.first?.tasks.first?.subtasks, [])
        XCTAssertEqual(viewModel.items.first?.createdFor, [1, 2])
        XCTAssertEqual(viewModel.sections.map(\.title), ["Family"])
        XCTAssertEqual(Set(capturedRequests.requests.map { $0.url?.path }), ["/api/todo-list", "/api/users"])
    }

    func testSectionsSeparateFamilyAndPersonalToDos() async {
        let viewModel = ToDoViewModel()

        await viewModel.applyLiveMessage(
            .itemCreated(
                item: Self.liveItem(id: 41, name: "Schedule dentist", createdFor: [1, 2]),
                mutationId: "family-41",
                serverTime: "2026-08-08T18:00:00Z"
            )
        )
        await viewModel.applyLiveMessage(
            .itemCreated(
                item: Self.liveItem(id: 42, name: "Renew passport", createdFor: [1]),
                mutationId: "personal-42",
                serverTime: "2026-08-08T18:00:01Z"
            )
        )

        XCTAssertEqual(viewModel.sections.map(\.title), ["Family", "Me"])
        XCTAssertEqual(viewModel.sections[0].tasks.map(\.id), [41])
        XCTAssertEqual(viewModel.sections[1].tasks.map(\.id), [42])
    }

    func testLiveItemsOutsideCurrentResidentAudienceAreIgnored() async {
        let viewModel = ToDoViewModel()
        let liveService = ToDoListLiveServiceStub()

        viewModel.startLiveUpdatesIfNeeded(
            liveService: liveService,
            currentViewerId: "mallory",
            loadSnapshot: { fatalError("No snapshot expected.") }
        )

        await viewModel.applyLiveMessage(
            .itemCreated(
                item: Self.liveItem(id: 43, name: "Josh only", createdFor: [1]),
                mutationId: "josh-only",
                serverTime: "2026-08-08T18:00:00Z"
            )
        )
        await viewModel.applyLiveMessage(
            .itemCreated(
                item: Self.liveItem(id: 44, name: "Mallory only", createdFor: [2]),
                mutationId: "mallory-only",
                serverTime: "2026-08-08T18:00:01Z"
            )
        )

        XCTAssertEqual(viewModel.items.map(\.id), [44])
        viewModel.stopLiveUpdates()
    }

    func testLoadSortsToDoItemsByDueDateThenCreatedDate() async {
        ToDoMockURLProtocol.requestHandler = { request in
            self.capturedRequests.append(request)

            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/todo-list"):
                return Self.response(for: request, json: Self.unsortedToDoListJSON)
            case ("GET", "/api/users"):
                return Self.response(for: request, json: Self.usersJSON)
            default:
                return Self.response(for: request, statusCode: 404, json: #"{"error":"Unhandled"}"#)
            }
        }

        let viewModel = ToDoViewModel()
        await viewModel.load(apiClient: client)

        XCTAssertEqual(viewModel.sections.first?.tasks.map(\.id), [4, 3, 2, 1])
    }

    func testCancelledReloadKeepsExistingSnapshotWithoutError() async {
        ToDoMockURLProtocol.requestHandler = { request in
            self.capturedRequests.append(request)
            return Self.response(
                for: request,
                json: request.url?.path == "/api/users" ? Self.usersJSON : Self.toDoListJSON(status: "open")
            )
        }

        let viewModel = ToDoViewModel()
        await viewModel.load(apiClient: client)

        ToDoMockURLProtocol.requestHandler = { _ in
            throw URLError(.cancelled)
        }

        await viewModel.load(apiClient: client, force: true)

        XCTAssertEqual(viewModel.items.map(\.id), [1])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testToggleCompletionMapsPatchRequestAndUpdatesItem() async throws {
        ToDoMockURLProtocol.requestHandler = { request in
            self.capturedRequests.append(request)

            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/todo-list"):
                return Self.response(for: request, json: Self.toDoListJSON(status: "open"))
            case ("GET", "/api/users"):
                return Self.response(for: request, json: Self.usersJSON)
            case ("PATCH", "/api/todo-list/items/1"):
                return Self.response(for: request, json: Self.toDoMutationJSON(status: "completed"))
            default:
                return Self.response(for: request, statusCode: 404, json: #"{"error":"Unhandled"}"#)
            }
        }

        let viewModel = ToDoViewModel()
        await viewModel.load(apiClient: client)
        let task = try XCTUnwrap(viewModel.sections.first?.tasks.first)

        await viewModel.toggleCompletion(task, apiClient: client, actor: "Josh")

        let patchRequest = try XCTUnwrap(capturedRequests.requests.first { $0.httpMethod == "PATCH" })
        XCTAssertEqual(patchRequest.url?.path, "/api/todo-list/items/1")
        XCTAssertEqual(patchRequest.jsonBody["status"] as? String, "completed")
        XCTAssertEqual(patchRequest.jsonBody["actor"] as? String, "Josh")
        XCTAssertEqual(viewModel.items.first?.status, .completed)
        XCTAssertTrue(viewModel.mutatingItemIDs.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateTaskSendsPersonalAudienceForMe() async throws {
        ToDoMockURLProtocol.requestHandler = { request in
            self.capturedRequests.append(request)

            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/todo-list/items"):
                return Self.response(for: request, json: Self.toDoMutationJSON(status: "open"))
            default:
                return Self.response(for: request, statusCode: 404, json: #"{"error":"Unhandled"}"#)
            }
        }

        var draft = ToDoDraft(createdBy: 1)
        draft.name = "Renew passport"
        draft.audience = .me

        let viewModel = ToDoViewModel()
        try await viewModel.createTask(from: draft, apiClient: client, actor: "Josh")

        let createRequest = try XCTUnwrap(capturedRequests.requests.first { $0.httpMethod == "POST" })
        XCTAssertEqual(createRequest.jsonBody["createdBy"] as? Int, 1)
        XCTAssertEqual(createRequest.jsonBody["createdFor"] as? [Int], [1])
    }

    func testUpdateTaskSendsEditedAudience() async throws {
        ToDoMockURLProtocol.requestHandler = { request in
            self.capturedRequests.append(request)

            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/todo-list"):
                return Self.response(for: request, json: Self.toDoListJSON(status: "open"))
            case ("GET", "/api/users"):
                return Self.response(for: request, json: Self.usersJSON)
            case ("PATCH", "/api/todo-list/items/1"):
                return Self.response(for: request, json: Self.toDoMutationJSON(status: "open"))
            default:
                return Self.response(for: request, statusCode: 404, json: #"{"error":"Unhandled"}"#)
            }
        }

        let viewModel = ToDoViewModel()
        await viewModel.load(apiClient: client)
        let task = try XCTUnwrap(viewModel.sections.first?.tasks.first)
        var draft = ToDoDraft(task: task, fallbackCreatedBy: 1)
        draft.audience = .me

        try await viewModel.updateTask(task, from: draft, apiClient: client, actor: "Josh")

        let patchRequest = try XCTUnwrap(capturedRequests.requests.first { $0.httpMethod == "PATCH" })
        XCTAssertEqual(patchRequest.jsonBody["createdFor"] as? [Int], [1])
    }

    func testLoadFailureShowsErrorAndMarksLoaded() async {
        ToDoMockURLProtocol.requestHandler = { request in
            self.capturedRequests.append(request)

            if request.url?.path == "/api/users" {
                return Self.response(for: request, json: Self.usersJSON)
            }

            return Self.response(for: request, statusCode: 503, json: #"{"error":"To Do unavailable"}"#)
        }

        let viewModel = ToDoViewModel()
        await viewModel.load(apiClient: client)

        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.items, [])
        XCTAssertEqual(viewModel.errorMessage, "To Do unavailable")
    }

    func testLiveItemEventsUpsertAndDeleteByBackendID() async {
        let viewModel = ToDoViewModel()
        let created = Self.liveItem(id: 41, name: "Call plumber")

        await viewModel.applyLiveMessage(
            .itemCreated(item: created, mutationId: "created-41", serverTime: "2026-07-11T20:00:00Z")
        )
        await viewModel.applyLiveMessage(
            .itemUpdated(
                item: Self.liveItem(id: 41, name: "Call plumber", status: .completed),
                mutationId: "updated-41",
                serverTime: "2026-07-11T20:01:00Z"
            )
        )

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.items.first?.id, 41)
        XCTAssertEqual(viewModel.items.first?.status, .completed)

        await viewModel.applyLiveMessage(
            .itemDeleted(itemId: 41, mutationId: "deleted-41", serverTime: "2026-07-11T20:02:00Z")
        )

        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testLiveMessagesDecodeSnapshotAndItemMutationPayloads() throws {
        let snapshotMessage = try JSONDecoder().decode(
            ToDoListLiveMessage.self,
            from: Data(#"{"type":"snapshot_required","reason":"connected","serverTime":"2026-07-11T20:00:00Z"}"#.utf8)
        )
        let itemMessage = try JSONDecoder().decode(
            ToDoListLiveMessage.self,
            from: Data(
                #"{"type":"item_created","item":{"id":41,"name":"Call plumber","status":"open","locationIds":[],"locationDisplayText":"No location","alerts":[],"subtasks":[]},"mutationId":"created-41","serverTime":"2026-07-11T20:00:01Z"}"#.utf8
            )
        )

        XCTAssertEqual(
            snapshotMessage,
            .snapshotRequired(reason: .connected, serverTime: "2026-07-11T20:00:00Z")
        )
        XCTAssertEqual(
            itemMessage,
            .itemCreated(
                item: Self.liveItem(id: 41, name: "Call plumber", createdBy: nil),
                mutationId: "created-41",
                serverTime: "2026-07-11T20:00:01Z"
            )
        )
    }

    func testLateLiveSnapshotCannotOverwriteNewerItemEvent() async {
        let viewModel = ToDoViewModel()
        let liveService = ToDoListLiveServiceStub()
        let snapshotGate = ToDoSnapshotGate()
        let staleSnapshot = ToDoListResponse(
            ok: true,
            items: [Self.liveItem(id: 7, name: "Stale task")],
            categories: [],
            locations: [],
            generatedAt: nil
        )

        viewModel.startLiveUpdatesIfNeeded(
            liveService: liveService,
            currentViewerId: "josh",
            loadSnapshot: {
                await snapshotGate.load()
            }
        )

        let snapshotTask = Task { @MainActor in
            await viewModel.applyLiveMessage(
                .snapshotRequired(reason: .connected, serverTime: "2026-07-11T20:00:00Z")
            )
        }
        await snapshotGate.waitUntilLoadStarts()

        await viewModel.applyLiveMessage(
            .itemCreated(
                item: Self.liveItem(id: 8, name: "Added while snapshot loaded"),
                mutationId: "created-8",
                serverTime: "2026-07-11T20:00:01Z"
            )
        )
        await snapshotGate.resolve(with: staleSnapshot)
        await snapshotGate.waitUntilLoadStarts(number: 2)
        await snapshotGate.resolve(
            with: ToDoListResponse(
                ok: true,
                items: [Self.liveItem(id: 8, name: "Added while snapshot loaded")],
                categories: [],
                locations: [],
                generatedAt: nil
            )
        )
        await snapshotTask.value

        XCTAssertEqual(viewModel.items.map(\.id), [8])
        viewModel.stopLiveUpdates()
    }

    func testDateScopesUseExpectedLabelsAndDateWindows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let sunday = Self.date(calendar: calendar, year: 2026, month: 8, day: 16, hour: 12)
        let todayInterval = ToDoDateScope.today.dateInterval(now: sunday, calendar: calendar)
        let tomorrowInterval = ToDoDateScope.tomorrow.dateInterval(now: sunday, calendar: calendar)
        let weekInterval = ToDoDateScope.week.dateInterval(now: sunday, calendar: calendar)

        XCTAssertEqual(ToDoDateScope.today.title(now: sunday, calendar: calendar), "Aug. 16")
        XCTAssertEqual(ToDoDateScope.tomorrow.title(now: sunday, calendar: calendar), "Aug. 17")
        XCTAssertEqual(ToDoDateScope.week.title(now: sunday, calendar: calendar), "Week")
        XCTAssertEqual(todayInterval.start, Self.date(calendar: calendar, year: 2026, month: 8, day: 16))
        XCTAssertEqual(todayInterval.end, Self.date(calendar: calendar, year: 2026, month: 8, day: 17))
        XCTAssertEqual(tomorrowInterval.start, Self.date(calendar: calendar, year: 2026, month: 8, day: 17))
        XCTAssertEqual(tomorrowInterval.end, Self.date(calendar: calendar, year: 2026, month: 8, day: 18))
        XCTAssertEqual(weekInterval.start, Self.date(calendar: calendar, year: 2026, month: 8, day: 16))
        XCTAssertEqual(weekInterval.end, Self.date(calendar: calendar, year: 2026, month: 8, day: 23))
    }

    func testDateScopesIncludeOnlyScheduledRemindersAndOpenOverdueToDoItems() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let thursday = Self.date(calendar: calendar, year: 2026, month: 8, day: 20, hour: 12)
        let overdueWednesday = Self.date(calendar: calendar, year: 2026, month: 8, day: 19, hour: 7)
        let thursdayMorning = Self.date(calendar: calendar, year: 2026, month: 8, day: 20, hour: 7)
        let friday = Self.date(calendar: calendar, year: 2026, month: 8, day: 21, hour: 7)
        let saturday = Self.date(calendar: calendar, year: 2026, month: 8, day: 22, hour: 7)
        let sunday = Self.date(calendar: calendar, year: 2026, month: 8, day: 23, hour: 7)
        let todayInterval = ToDoDateScope.today.dateInterval(now: thursday, calendar: calendar)

        XCTAssertFalse(PersonalRemindersService.isDue(overdueWednesday, in: todayInterval))
        XCTAssertTrue(PersonalRemindersService.isDue(thursdayMorning, in: todayInterval))
        XCTAssertFalse(PersonalRemindersService.isDue(friday, in: todayInterval))
        XCTAssertFalse(PersonalRemindersService.isDue(nil, in: todayInterval))

        XCTAssertTrue(ToDoDateScope.today.includesToDoItem(dueDate: overdueWednesday, status: .open, now: thursday, calendar: calendar))
        XCTAssertFalse(ToDoDateScope.today.includesToDoItem(dueDate: overdueWednesday, status: .completed, now: thursday, calendar: calendar))
        XCTAssertTrue(ToDoDateScope.tomorrow.includesToDoItem(dueDate: thursdayMorning, status: .open, now: thursday, calendar: calendar))
        XCTAssertTrue(ToDoDateScope.tomorrow.includesToDoItem(dueDate: friday, status: .completed, now: thursday, calendar: calendar))
        XCTAssertTrue(ToDoDateScope.week.includesToDoItem(dueDate: saturday, status: .open, now: thursday, calendar: calendar))
        XCTAssertFalse(ToDoDateScope.week.includesToDoItem(dueDate: sunday, status: .open, now: thursday, calendar: calendar))
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

    private static func liveItem(
        id: Int,
        name: String,
        status: ToDoItemStatus = .open,
        createdBy: Int? = 1,
        createdFor: [Int] = [1, 2]
    ) -> ToDoItem {
        ToDoItem(
            id: id,
            name: name,
            status: status,
            locationIds: [],
            locationDisplayText: "No location",
            createdBy: createdBy,
            createdFor: createdFor
        )
    }

    private static func toDoListJSON(status: String) -> String {
        """
        {
          "ok": true,
          "generatedAt": "2026-07-05T18:00:00.000Z",
          "items": [
            {
              "id": 1,
              "name": "Schedule dentist",
              "status": "\(status)",
              "locationIds": [2],
              "locationDisplayText": "Denver Pediatrics",
              "date": "2026-07-06T17:00:00.000Z",
              "recurring": null,
              "notes": "Bring insurance card.",
              "subtasks": [],
              "createdBy": 1,
              "createdFor": [1, 2],
              "createdDate": "2026-07-05T17:00:00.000Z"
            }
          ],
          "categories": [
            {
              "id": 1,
              "name": "Family",
              "updatedAt": "2026-07-05T17:00:00.000Z"
            }
          ],
          "locations": [
            {
              "id": 2,
              "name": "Denver Pediatrics",
              "address": "123 Wellness Way",
              "mapkitTitle": "Denver Pediatrics",
              "mapkitSubtitle": "123 Wellness Way",
              "latitude": 39.7,
              "longitude": -104.9,
              "createdBy": 1,
              "createdDate": "2026-07-05T17:00:00.000Z",
              "lastUsedDate": "2026-07-05T17:00:00.000Z",
              "useCount": 2,
              "isActive": true,
              "favoritedBy": [1]
            }
          ]
        }
        """
    }

    private static func toDoMutationJSON(status: String) -> String {
        """
        {
          "ok": true,
          "mutationId": "mutation-1",
          "generatedAt": "2026-07-05T18:01:00.000Z",
          "push": null,
          "item": {
            "id": 1,
            "name": "Schedule dentist",
            "status": "\(status)",
            "locationIds": [2],
            "locationDisplayText": "Denver Pediatrics",
            "date": "2026-07-06T17:00:00.000Z",
            "recurring": null,
            "createdBy": 1,
            "createdDate": "2026-07-05T17:00:00.000Z"
          }
        }
        """
    }

    private static let unsortedToDoListJSON = """
    {
      "ok": true,
      "generatedAt": "2026-07-05T18:00:00.000Z",
      "items": [
        {
          "id": 2,
          "name": "Newest undated",
          "status": "open",
          "locationIds": [],
          "locationDisplayText": "No location",
          "date": null,
          "recurring": null,
          "createdBy": 1,
          "createdDate": "2026-07-06T18:00:00.000Z"
        },
        {
          "id": 3,
          "name": "Later dated",
          "status": "open",
          "locationIds": [],
          "locationDisplayText": "No location",
          "date": "2026-07-08T17:00:00.000Z",
          "recurring": null,
          "createdBy": 1,
          "createdDate": "2026-07-01T17:00:00.000Z"
        },
        {
          "id": 1,
          "name": "Older undated",
          "status": "open",
          "locationIds": [],
          "locationDisplayText": "No location",
          "date": null,
          "recurring": null,
          "createdBy": 2,
          "createdDate": "2026-07-05T18:00:00.000Z"
        },
        {
          "id": 4,
          "name": "Soonest dated",
          "status": "completed",
          "locationIds": [],
          "locationDisplayText": "No location",
          "date": "2026-07-06T17:00:00.000Z",
          "recurring": null,
          "createdBy": 2,
          "createdDate": "2026-07-03T17:00:00.000Z"
        }
      ],
      "categories": [],
      "locations": []
    }
    """

    private static func date(
        calendar: Calendar,
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private static let usersJSON = """
    {
      "ok": true,
      "generatedAt": "2026-07-05T18:00:00.000Z",
      "users": [
        {
          "id": 1,
          "firstName": "Josh",
          "lastName": "Levy",
          "email": "josh@example.com"
        },
        {
          "id": 2,
          "firstName": "Mallory",
          "lastName": "Levy",
          "email": "mallory@example.com"
        }
      ]
    }
    """
}

private final class CapturedRequestStore {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock {
            storedRequests
        }
    }

    func append(_ request: URLRequest) {
        lock.withLock {
            storedRequests.append(request)
        }
    }
}

private final class ToDoListLiveServiceStub: ToDoListLiveServicing {
    func messages() -> AsyncStream<ToDoListLiveMessage> {
        AsyncStream { _ in }
    }

    func disconnect() {}
}

private actor ToDoSnapshotGate {
    private var loadCount = 0
    private var startContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var responseContinuation: CheckedContinuation<ToDoListResponse, Never>?

    func load() async -> ToDoListResponse {
        loadCount += 1
        let currentLoadCount = loadCount
        let readyContinuations = startContinuations
            .filter { $0.key <= currentLoadCount }
            .map(\.value)
        startContinuations = startContinuations.filter { $0.key > currentLoadCount }
        readyContinuations.forEach { $0.resume() }

        return await withCheckedContinuation { continuation in
            responseContinuation = continuation
        }
    }

    func waitUntilLoadStarts(number: Int = 1) async {
        guard loadCount < number else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations[number] = continuation
        }
    }

    func resolve(with response: ToDoListResponse) {
        responseContinuation?.resume(returning: response)
        responseContinuation = nil
    }
}

private final class ToDoMockURLProtocol: URLProtocol {
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

        return (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
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
