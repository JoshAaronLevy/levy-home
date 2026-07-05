extension Optional where Wrapped: Collection, Wrapped.Index == Int {
    subscript(safe index: Int) -> Wrapped.Element? {
        guard let collection = self, collection.indices.contains(index) else {
            return nil
        }

        return collection[index]
    }
}
