import Foundation

struct SiriListCommand: Equatable {
    let list: SiriListKind
    let title: String
    let residentName: String
}

protocol SiriListCommandServicing {
    func execute(_ command: SiriListCommand) async -> SiriListCommandResult
}

protocol SiriShoppingListAPI {
    func fetchShoppingList() async throws -> ShoppingListResponse
    func lookupShoppingListItem(named name: String) async throws -> ShoppingListItemLookupResponse
    func createShoppingListItem(_ request: CreateShoppingListItemRequest) async throws -> ShoppingListMutationResponse
    func updateShoppingListItem(
        id itemId: Int,
        _ request: UpdateShoppingListItemRequest
    ) async throws -> ShoppingListMutationResponse
}

protocol SiriToDoListAPI {
    func fetchUsers() async throws -> UsersResponse
    func createToDoItem(_ request: CreateToDoItemRequest) async throws -> ToDoListMutationResponse
}

extension APIClient: SiriShoppingListAPI {}
extension APIClient: SiriToDoListAPI {}

final class SiriListCommandService: SiriListCommandServicing {
    private let shoppingAPI: SiriShoppingListAPI
    private let toDoAPI: SiriToDoListAPI?
    private let makeMutationID: () -> String

    init(
        shoppingAPI: SiriShoppingListAPI,
        toDoAPI: SiriToDoListAPI? = nil,
        makeMutationID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.shoppingAPI = shoppingAPI
        self.toDoAPI = toDoAPI
        self.makeMutationID = makeMutationID
    }

    func execute(_ command: SiriListCommand) async -> SiriListCommandResult {
        switch command.list {
        case .shopping:
            return await executeShopping(command)
        case .toDo:
            return await executeToDo(command)
        }
    }

    private func executeShopping(_ command: SiriListCommand) async -> SiriListCommandResult {
        let title = canonicalTitle(command.title)
        let normalizedCommandTitle = normalizedTitle(title)
        let residentName = command.residentName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedCommandTitle.isEmpty else {
            return .rejected
        }

        guard !residentName.isEmpty else {
            return .requiresDeviceOwner
        }

        do {
            let snapshot = try await shoppingAPI.fetchShoppingList()
            guard let miscellaneousCategory = snapshot.categories.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare("Miscellaneous") == .orderedSame
            }) else {
                return .failed
            }

            let snapshotMatch = snapshot.items.first(where: {
                normalizedTitle($0.name) == normalizedCommandTitle
            })
            let lookup = try await shoppingAPI.lookupShoppingListItem(named: title)

            if let existingItem = lookup.match ?? snapshotMatch {
                return try await resolveExistingItem(existingItem, residentName: residentName)
            }

            return try await createItem(
                title: title,
                categoryID: miscellaneousCategory.id,
                residentName: residentName
            )
        } catch {
            return .failed
        }
    }

    private func executeToDo(_ command: SiriListCommand) async -> SiriListCommandResult {
        guard let toDoAPI else {
            return .notImplemented
        }

        let title = canonicalTitle(command.title)
        let residentName = command.residentName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            return .rejected
        }

        guard !residentName.isEmpty else {
            return .requiresDeviceOwner
        }

        do {
            let users = try await toDoAPI.fetchUsers().users
            guard let resident = users.first(where: {
                namesMatch(residentName, $0.firstName) || namesMatch(residentName, $0.fullName)
            }) else {
                return .requiresDeviceOwner
            }

            let request = CreateToDoItemRequest(
                name: title,
                status: .open,
                locationIds: [],
                createdBy: resident.id,
                actor: residentName,
                mutationId: makeMutationID()
            )
            let response = try await toDoAPI.createToDoItem(request)
            return .added(SiriListCommandItem(item: response.item))
        } catch {
            return .failed
        }
    }

    private func resolveExistingItem(
        _ item: ShoppingListItem,
        residentName: String
    ) async throws -> SiriListCommandResult {
        guard item.purchased else {
            return .alreadyPresent(SiriListCommandItem(item: item))
        }

        let request = UpdateShoppingListItemRequest(
            quantity: item.quantity,
            notes: item.notes.map { .value($0) },
            purchased: false,
            categoryId: item.categoryId.map { .value($0) },
            image: item.image.map { .value($0) },
            storeListings: item.storeListings.isEmpty ? nil : item.storeListings,
            actor: residentName,
            mutationId: makeMutationID()
        )
        let response = try await shoppingAPI.updateShoppingListItem(id: item.id, request)
        return .restored(SiriListCommandItem(item: response.item))
    }

    private func createItem(
        title: String,
        categoryID: Int,
        residentName: String
    ) async throws -> SiriListCommandResult {
        let request = CreateShoppingListItemRequest(
            name: title,
            quantity: 1,
            purchased: false,
            categoryId: categoryID,
            actor: residentName,
            mutationId: makeMutationID()
        )

        do {
            let response = try await shoppingAPI.createShoppingListItem(request)
            return .added(SiriListCommandItem(item: response.item))
        } catch let error as APIError {
            guard isDuplicateConflict(error) else {
                throw error
            }

            let lookup = try await shoppingAPI.lookupShoppingListItem(named: title)
            guard let existingItem = lookup.match else {
                throw error
            }

            return try await resolveExistingItem(existingItem, residentName: residentName)
        }
    }

    private func normalizedTitle(_ value: String) -> String {
        canonicalTitle(value)
            .lowercased()
    }

    private func canonicalTitle(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func namesMatch(_ first: String, _ second: String) -> Bool {
        first.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(second.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private func isDuplicateConflict(_ error: APIError) -> Bool {
        switch error {
        case .server(let statusCode, _), .httpStatus(let statusCode):
            return statusCode == 409
        case .invalidBaseURL, .invalidURL, .transport, .decoding:
            return false
        }
    }
}
