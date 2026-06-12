import Foundation

struct APIErrorResponse: Codable, Equatable {
    let error: String
    let code: String?
}

enum APIError: Error, Equatable, LocalizedError {
    case invalidBaseURL(String)
    case invalidURL(path: String)
    case transport(String)
    case server(statusCode: Int, message: String)
    case httpStatus(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The API base URL is invalid."
        case .invalidURL:
            return "The API request URL is invalid."
        case .transport:
            return "The network request failed."
        case .server(_, let message):
            return message
        case .httpStatus(let statusCode):
            return "The API returned HTTP \(statusCode)."
        case .decoding:
            return "The API returned an unexpected response."
        }
    }
}
