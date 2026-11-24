import Foundation

/// Opaque JSON used for rule-pack parts that native code never interprets
/// (DOM rules, network predicates). They're forwarded to the engine untouched.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue {
    /// The string at a key path through nested objects, if present.
    public func stringValue(at path: String...) -> String? {
        var current = self
        for key in path {
            guard case .object(let o) = current, let next = o[key] else { return nil }
            current = next
        }
        if case .string(let s) = current { return s }
        return nil
    }
}

/// Reads object keys in document order. JSONDecoder dictionaries are unordered,
/// but the settings UI should list features in the order the rule pack declares them.
enum JSONKeyOrder {
    /// Keys of the object reached by following `path` (object keys from the root).
    static func keys(atPath path: [String], in data: Data) -> [String]? {
        var parser = Parser(bytes: [UInt8](data), target: path)
        do {
            try parser.parseValue(path: [])
            return parser.found
        } catch {
            return nil
        }
    }

    private struct ParseError: Error {}

    private struct Parser {
        let bytes: [UInt8]
        let target: [String]
        var i = 0
        var found: [String]?

        init(bytes: [UInt8], target: [String]) {
            self.bytes = bytes
            self.target = target
        }

        mutating func skipWS() {
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        }

        mutating func expect(_ b: UInt8) throws {
            skipWS()
            guard i < bytes.count, bytes[i] == b else { throw ParseError() }
            i += 1
        }

        mutating func parseValue(path: [String]) throws {
            skipWS()
            guard i < bytes.count else { throw ParseError() }
            switch bytes[i] {
            case UInt8(ascii: "{"): try parseObject(path: path)
            case UInt8(ascii: "["): try parseArray(path: path)
            case UInt8(ascii: "\""): _ = try parseString()
            default: try skipScalar()
            }
        }

        mutating func parseObject(path: [String]) throws {
            try expect(UInt8(ascii: "{"))
            var keys: [String] = []
            skipWS()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") {
                i += 1
            } else {
                while true {
                    skipWS()
                    let key = try parseString()
                    keys.append(key)
                    try expect(UInt8(ascii: ":"))
                    try parseValue(path: path + [key])
                    skipWS()
                    guard i < bytes.count else { throw ParseError() }
                    if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    if bytes[i] == UInt8(ascii: "}") { i += 1; break }
                    throw ParseError()
                }
            }
            if path == target, found == nil { found = keys }
        }

        mutating func parseArray(path: [String]) throws {
            try expect(UInt8(ascii: "["))
            skipWS()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return }
            while true {
                // Array elements are not addressable by `path`; use an impossible segment.
                try parseValue(path: path + ["\u{0}[]"])
                skipWS()
                guard i < bytes.count else { throw ParseError() }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return }
                throw ParseError()
            }
        }

        mutating func parseString() throws -> String {
            skipWS()
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw ParseError() }
            let start = i
            i += 1
            while i < bytes.count {
                if bytes[i] == UInt8(ascii: "\\") { i += 2; continue }
                if bytes[i] == UInt8(ascii: "\"") { i += 1; break }
                i += 1
            }
            guard i <= bytes.count else { throw ParseError() }
            let slice = Data(bytes[start..<i])
            guard let s = try JSONSerialization.jsonObject(with: slice, options: .fragmentsAllowed) as? String else {
                throw ParseError()
            }
            return s
        }

        mutating func skipScalar() throws {
            let start = i
            while i < bytes.count {
                let b = bytes[i]
                if b == UInt8(ascii: ",") || b == UInt8(ascii: "}") || b == UInt8(ascii: "]")
                    || [0x20, 0x09, 0x0A, 0x0D].contains(b) { break }
                i += 1
            }
            if i == start { throw ParseError() }
        }
    }
}
