import Combine
import Foundation
import MapKit

final class ToDoLocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [ToDoLocationSearchSuggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var selectedQuery: String?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedQuery.count >= 2 else {
            clearResults()
            completer.queryFragment = ""
            selectedQuery = nil
            return
        }

        if normalizedQuery == selectedQuery {
            clearResults()
            return
        }

        selectedQuery = nil
        errorMessage = nil

        guard completer.queryFragment != normalizedQuery else {
            return
        }

        isSearching = true
        completer.queryFragment = normalizedQuery
    }

    func select(query: String) {
        selectedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        clearResults()
        completer.queryFragment = ""
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let nextSuggestions = Self.suggestions(from: completer.results)

        DispatchQueue.main.async {
            self.suggestions = nextSuggestions
            self.isSearching = false
            self.errorMessage = nil
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.suggestions = []
            self.isSearching = false
            self.errorMessage = "Location search unavailable"
        }
    }

    private func clearResults() {
        suggestions = []
        isSearching = false
        errorMessage = nil
    }

    private static func suggestions(from completions: [MKLocalSearchCompletion]) -> [ToDoLocationSearchSuggestion] {
        var seenIDs = Set<String>()

        return completions.compactMap { completion in
            let title = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty else {
                return nil
            }

            let id = "\(title)|\(subtitle)".lowercased()

            guard !seenIDs.contains(id) else {
                return nil
            }

            seenIDs.insert(id)
            return ToDoLocationSearchSuggestion(id: id, title: title, subtitle: subtitle)
        }
    }
}
