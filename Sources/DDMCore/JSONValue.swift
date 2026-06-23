import Foundation

/// A minimal, ordered-agnostic JSON value used to build DDM declaration
/// payloads. We keep `int` and `double` distinct so a profile's `42` doesn't
/// become `42.0` in the output, and we carry `bool` separately so booleans
/// never collapse into numbers.
///
/// Property-list inputs can contain `Date` and `Data`, which JSON cannot
/// represent natively. We convert `Date` -> ISO8601 string and `Data` ->
/// base64 string at the boundary (see `init(plist:)`), and record that this
/// happened nowhere silently — the migration report notes any such payload.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    // MARK: Build from a parsed property list value

    /// Convert an `Any` produced by `PropertyListSerialization` into a
    /// JSON-safe value. Returns the value plus whether a lossy conversion
    /// (Date/Data -> String) occurred anywhere in the tree.
    public static func fromPlist(_ value: Any) -> (value: JSONValue, lossy: Bool) {
        var lossy = false
        let v = convert(value, lossy: &lossy)
        return (v, lossy)
    }

    private static func convert(_ value: Any, lossy: inout Bool) -> JSONValue {
        switch value {
        case let s as String:
            return .string(s)
        case let num as NSNumber:
            // Distinguish Bool from numeric NSNumber.
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            }
            let objCType = String(cString: num.objCType)
            if objCType == "d" || objCType == "f" {
                return .double(num.doubleValue)
            }
            return .int(num.intValue)
        case let d as Date:
            lossy = true
            return .string(JSONValue.iso8601.string(from: d))
        case let data as Data:
            lossy = true
            return .string(data.base64EncodedString())
        case let arr as [Any]:
            return .array(arr.map { convert($0, lossy: &lossy) })
        case let dict as [String: Any]:
            var out: [String: JSONValue] = [:]
            for (k, v) in dict { out[k] = convert(v, lossy: &lossy) }
            return .object(out)
        case is NSNull:
            return .null
        default:
            // Last resort: stringify so we never crash or silently drop.
            return .string(String(describing: value))
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: Convenience accessors

    public var objectValue: [String: JSONValue]? {
        if case let .object(o) = self { return o }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(a) = self { return a }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    // MARK: Serialization

    /// Convert to a Foundation object suitable for `JSONSerialization`.
    public func foundationObject() -> Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return NSNumber(value: i)
        case .double(let d): return NSNumber(value: d)
        case .bool(let b): return NSNumber(value: b)
        case .array(let a): return a.map { $0.foundationObject() }
        case .object(let o):
            var out: [String: Any] = [:]
            for (k, v) in o { out[k] = v.foundationObject() }
            return out
        case .null: return NSNull()
        }
    }

    /// Stable, pretty-printed JSON. Sorted keys keep output deterministic so
    /// declarations diff cleanly and tests are reproducible.
    public func prettyPrintedData() throws -> Data {
        let obj = foundationObject()
        return try JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    public func prettyPrintedString() -> String {
        (try? prettyPrintedData()).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
}
