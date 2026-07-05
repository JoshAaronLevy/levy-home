protocol ShoppingListLiveServicing {
    func messages() -> AsyncStream<ShoppingListLiveMessage>
    func connectionStates() -> AsyncStream<ShoppingListLiveConnectionState>
    func disconnect()
}
