import Foundation

// WordPress/ACF fields are loosely typed: an empty field comes back as `false`,
// numbers sometimes as strings, and empty PHP arrays as `[]` even where an object
// is expected. These wrappers decode whatever arrives without failing the whole
// response, and a missing key simply yields the empty value.

@propertyWrapper
struct LossyString: Decodable, Hashable {
    var wrappedValue: String?

    init(wrappedValue: String?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
        } else if let string = try? container.decode(String.self) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            wrappedValue = trimmed.isEmpty ? nil : trimmed
        } else if let int = try? container.decode(Int.self) {
            wrappedValue = String(int)
        } else if let double = try? container.decode(Double.self) {
            wrappedValue = String(double)
        } else {
            // `false` (empty ACF field), objects and arrays carry no text.
            wrappedValue = nil
        }
    }
}

@propertyWrapper
struct LossyInt: Decodable, Hashable {
    var wrappedValue: Int?

    init(wrappedValue: Int?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            wrappedValue = int
        } else if let double = try? container.decode(Double.self) {
            wrappedValue = Int(double)
        } else if let string = try? container.decode(String.self) {
            wrappedValue = Int(string.trimmingCharacters(in: .whitespaces))
                ?? Double(string.trimmingCharacters(in: .whitespaces)).map { Int($0) }
        } else {
            wrappedValue = nil
        }
    }
}

@propertyWrapper
struct LossyBool: Decodable, Hashable {
    var wrappedValue: Bool

    init(wrappedValue: Bool) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            wrappedValue = bool
        } else if let int = try? container.decode(Int.self) {
            wrappedValue = int != 0
        } else if let string = try? container.decode(String.self) {
            wrappedValue = ["1", "true", "yes", "on"].contains(string.lowercased())
        } else {
            wrappedValue = false
        }
    }
}

/// Decodes an array, dropping elements that fail. Anything that is not an
/// array (false, "", a PHP associative array) becomes empty.
@propertyWrapper
struct LossyArray<Element: Decodable & Hashable>: Decodable, Hashable {
    var wrappedValue: [Element]

    init(wrappedValue: [Element]) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        guard var container = try? decoder.unkeyedContainer() else {
            wrappedValue = []
            return
        }
        var items: [Element] = []
        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) {
                items.append(item)
            } else {
                // Advance past the element we could not read.
                _ = try? container.decode(Skip.self)
            }
        }
        wrappedValue = items
    }

    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

/// Decodes a nested object, or nil when it is absent or the wrong shape.
@propertyWrapper
struct LossyObject<Value: Decodable & Hashable>: Decodable, Hashable {
    var wrappedValue: Value?

    init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        wrappedValue = try? Value(from: decoder)
    }
}

// Missing keys fall back to the empty value instead of throwing keyNotFound.
extension KeyedDecodingContainer {
    func decode(_ type: LossyString.Type, forKey key: Key) throws -> LossyString {
        try decodeIfPresent(type, forKey: key) ?? LossyString(wrappedValue: nil)
    }

    func decode(_ type: LossyInt.Type, forKey key: Key) throws -> LossyInt {
        try decodeIfPresent(type, forKey: key) ?? LossyInt(wrappedValue: nil)
    }

    func decode(_ type: LossyBool.Type, forKey key: Key) throws -> LossyBool {
        try decodeIfPresent(type, forKey: key) ?? LossyBool(wrappedValue: false)
    }

    func decode<T>(_ type: LossyArray<T>.Type, forKey key: Key) throws -> LossyArray<T> {
        try decodeIfPresent(type, forKey: key) ?? LossyArray(wrappedValue: [])
    }

    func decode<T>(_ type: LossyObject<T>.Type, forKey key: Key) throws -> LossyObject<T> {
        try decodeIfPresent(type, forKey: key) ?? LossyObject(wrappedValue: nil)
    }
}
