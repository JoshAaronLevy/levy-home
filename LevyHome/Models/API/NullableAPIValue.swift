enum ShoppingListNullableValue<Value: Encodable & Equatable>: Encodable, Equatable {
    case value(Value)
    case null

    func encode(to encoder: Encoder) throws {
        switch self {
        case .value(let value):
            try value.encode(to: encoder)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}
