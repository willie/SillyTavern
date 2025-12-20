import Foundation

/// Generic JSON value that can represent any valid JSON structure.
/// Used for preserving unknown fields during round-trip serialization.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

// MARK: - Convenience Accessors

extension JSONValue {
    /// Returns the string value if this is a string, nil otherwise.
    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Returns the number value if this is a number, nil otherwise.
    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// Returns the integer value if this is a number, nil otherwise.
    var int: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    /// Returns the boolean value if this is a bool, nil otherwise.
    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Returns the object value if this is an object, nil otherwise.
    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Returns the array value if this is an array, nil otherwise.
    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// Returns true if this is null.
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - Subscript Access

extension JSONValue {
    /// Access nested object properties by key.
    subscript(key: String) -> JSONValue? {
        get {
            guard case .object(let obj) = self else { return nil }
            return obj[key]
        }
        set {
            guard case .object(var obj) = self else { return }
            obj[key] = newValue
            self = .object(obj)
        }
    }

    /// Access array elements by index.
    subscript(index: Int) -> JSONValue? {
        get {
            guard case .array(let arr) = self, arr.indices.contains(index) else { return nil }
            return arr[index]
        }
        set {
            guard case .array(var arr) = self, arr.indices.contains(index), let newValue else { return }
            arr[index] = newValue
            self = .array(arr)
        }
    }
}

// MARK: - ExpressibleBy Protocols

extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    init(nilLiteral: ()) {
        self = .null
    }
}

// MARK: - JSON Serialization

extension JSONValue {
    /// Parse JSON data into a JSONValue.
    static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Parse a JSON string into a JSONValue.
    static func parse(_ string: String) throws -> JSONValue {
        guard let data = string.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid UTF-8 string"
                )
            )
        }
        return try parse(data)
    }

    /// Serialize to JSON data.
    func toData(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(self)
    }

    /// Serialize to JSON string.
    func toString(prettyPrinted: Bool = false) throws -> String {
        let data = try toData(prettyPrinted: prettyPrinted)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Could not encode as UTF-8 string"
                )
            )
        }
        return string
    }
}
