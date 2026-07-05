struct UsersResponse: Codable, Equatable {
    let ok: Bool
    let users: [LevyHomeUser]
    let generatedAt: String?
}

struct LevyHomeUser: Codable, Equatable, Hashable, Identifiable {
    let id: Int
    let firstName: String
    let lastName: String
    let email: String
    let mobileDevice: String?
    let lastLogin: String?

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    var initials: String {
        let firstInitial = firstName.first.map(String.init) ?? ""
        let lastInitial = lastName.first.map(String.init) ?? ""

        return "\(firstInitial)\(lastInitial)".uppercased()
    }
}
