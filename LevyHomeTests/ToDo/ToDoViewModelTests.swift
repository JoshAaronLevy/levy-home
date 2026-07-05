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
        XCTAssertEqual(Set(capturedRequests.requests.map { $0.url?.path }), ["/api/todo-list", "/api/users"])
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
              "createdBy": 1,
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
